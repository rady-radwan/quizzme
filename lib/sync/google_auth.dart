import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

import 'dpapi.dart';
import 'sync_config.dart';

/// Thrown when Google sign-in is needed again (signed out, access revoked or
/// expired). Background sync stops quietly; the Sync screen asks to sign in.
class SignInRequired implements Exception {
  const SignInRequired([this.message = 'Sign in to Google again to keep syncing.']);
  final String message;
  @override
  String toString() => message;
}

/// Google account access limited to the app's Drive folder.
abstract class GoogleAuth {
  /// Whether this build has the OAuth client ids it needs.
  bool get configured;
  String? get email;
  bool get signedIn;

  /// Restores a previous sign-in without showing anything.
  Future<void> restore();

  /// Interactive sign-in (account picker / browser).
  Future<void> signIn();

  /// A valid access token. With [interactive] false it never shows UI and
  /// throws [SignInRequired] when the user has to act.
  Future<String> accessToken({bool interactive = false});
  Future<void> signOut();

  static GoogleAuth forPlatform(Directory dataDir) =>
      (Platform.isAndroid || Platform.isIOS) ? MobileGoogleAuth() : DesktopGoogleAuth(dataDir);
}

/// Android/iOS: the system Google account picker (google_sign_in).
class MobileGoogleAuth implements GoogleAuth {
  GoogleSignInAccount? _account;
  bool _initialized = false;
  String? _email;

  @override
  bool get configured => SyncConfig.webClientId.isNotEmpty;
  @override
  String? get email => _email ?? _account?.email;
  @override
  bool get signedIn => _account != null;

  Future<void> _init() async {
    if (_initialized) return;
    await GoogleSignIn.instance.initialize(serverClientId: SyncConfig.webClientId);
    _initialized = true;
  }

  @override
  Future<void> restore() async {
    if (!configured) return;
    await _init();
    try {
      final f = GoogleSignIn.instance.attemptLightweightAuthentication();
      _account = await f;
    } catch (_) {
      _account = null;
    }
  }

  @override
  Future<void> signIn() async {
    if (!configured) throw StateError('Google sign-in is not set up in this build.');
    await _init();
    try {
      _account = await GoogleSignIn.instance.authenticate(scopeHint: const [SyncConfig.driveScope]);
    } on GoogleSignInException catch (e) {
      if (e.code == GoogleSignInExceptionCode.canceled) throw const SignInRequired('Sign-in was cancelled.');
      rethrow;
    }
    _email = _account!.email;
    await accessToken(interactive: true);
  }

  @override
  Future<String> accessToken({bool interactive = false}) async {
    final a = _account;
    if (a == null) throw const SignInRequired();
    final client = a.authorizationClient;
    var authz = await client.authorizationForScopes(const [SyncConfig.driveScope]);
    if (authz == null) {
      if (!interactive) throw const SignInRequired('Allow Quiz me to use Google Drive to keep syncing.');
      authz = await client.authorizeScopes(const [SyncConfig.driveScope]);
    }
    return authz.accessToken;
  }

  @override
  Future<void> signOut() async {
    await _init();
    await GoogleSignIn.instance.signOut();
    _account = null;
    _email = null;
  }
}

/// Windows/macOS/Linux: OAuth 2.0 for installed apps — the browser opens
/// Google's sign-in page and returns to a temporary local address
/// (loopback + PKCE). The refresh token is stored encrypted with Windows
/// DPAPI (only this Windows user can read it).
class DesktopGoogleAuth implements GoogleAuth {
  DesktopGoogleAuth(this._dir);
  final Directory _dir;

  String? _refreshToken;
  String? _accessToken;
  DateTime _expiry = DateTime.fromMillisecondsSinceEpoch(0);
  String? _email;

  File get _file => File(p.join(_dir.path, 'google_account.bin'));

  @override
  bool get configured => SyncConfig.desktopClientId.isNotEmpty && SyncConfig.desktopClientSecret.isNotEmpty;
  @override
  String? get email => _email;
  @override
  bool get signedIn => _refreshToken != null;

  @override
  Future<void> restore() async {
    try {
      if (!await _file.exists()) return;
      List<int> bytes = await _file.readAsBytes();
      if (Dpapi.available) bytes = Dpapi.unprotect(bytes);
      final j = jsonDecode(utf8.decode(bytes)) as Map<String, Object?>;
      _refreshToken = j['refresh_token'] as String?;
      _email = j['email'] as String?;
    } catch (_) {
      _refreshToken = null;
    }
  }

  Future<void> _save() async {
    await _dir.create(recursive: true);
    List<int> bytes = utf8.encode(jsonEncode({'refresh_token': _refreshToken, 'email': _email}));
    if (Dpapi.available) bytes = Dpapi.protect(bytes);
    await _file.writeAsBytes(bytes, flush: true);
  }

  static String _random(int length) {
    const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~';
    final r = Random.secure();
    return List.generate(length, (_) => chars[r.nextInt(chars.length)]).join();
  }

  @override
  Future<void> signIn() async {
    if (!configured) throw StateError('Google sign-in is not set up in this build.');
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    try {
      final redirect = 'http://127.0.0.1:${server.port}';
      final verifier = _random(64);
      final challenge = base64Url.encode(sha256.convert(ascii.encode(verifier)).bytes).replaceAll('=', '');
      final state = _random(24);
      final url = Uri.https('accounts.google.com', '/o/oauth2/v2/auth', {
        'client_id': SyncConfig.desktopClientId,
        'redirect_uri': redirect,
        'response_type': 'code',
        'scope': 'openid email ${SyncConfig.driveScope}',
        'code_challenge': challenge,
        'code_challenge_method': 'S256',
        'state': state,
        'access_type': 'offline',
        'prompt': 'consent',
      });
      await _openBrowser(url.toString());

      final req = await server.first.timeout(const Duration(minutes: 5),
          onTimeout: () => throw const SignInRequired('Sign-in timed out. Try again.'));
      final q = req.uri.queryParameters;
      final ok = q['state'] == state && q['code'] != null;
      req.response
        ..statusCode = 200
        ..headers.contentType = ContentType.html
        ..write('<!doctype html><html><body style="font-family:Segoe UI,sans-serif;text-align:center;padding-top:80px">'
            '<h2>${ok ? 'Signed in to Quiz me' : 'Sign-in was not completed'}</h2>'
            '<p>You can close this tab and return to Quiz me.</p></body></html>');
      await req.response.close();
      if (!ok) throw SignInRequired(q['error'] == 'access_denied' ? 'Sign-in was cancelled.' : 'Sign-in failed.');

      final r = await http.post(Uri.parse('https://oauth2.googleapis.com/token'), body: {
        'code': q['code']!,
        'client_id': SyncConfig.desktopClientId,
        'client_secret': SyncConfig.desktopClientSecret,
        'redirect_uri': redirect,
        'grant_type': 'authorization_code',
        'code_verifier': verifier,
      });
      if (r.statusCode != 200) throw SignInRequired('Google sign-in failed (${_errorOf(r)}).');
      final j = jsonDecode(r.body) as Map<String, Object?>;
      _refreshToken = j['refresh_token'] as String?;
      if (_refreshToken == null) throw const SignInRequired('Google did not allow offline access. Try again.');
      _setAccess(j);
      _email = _emailFromIdToken(j['id_token'] as String?);
      await _save();
    } finally {
      await server.close(force: true);
    }
  }

  void _setAccess(Map<String, Object?> j) {
    _accessToken = j['access_token'] as String?;
    final secs = (j['expires_in'] as num?)?.toInt() ?? 3600;
    _expiry = DateTime.now().add(Duration(seconds: secs - 60));
  }

  static String _errorOf(http.Response r) {
    try {
      final j = jsonDecode(r.body) as Map;
      return '${j['error_description'] ?? j['error'] ?? r.statusCode}';
    } catch (_) {
      return 'HTTP ${r.statusCode}';
    }
  }

  static String? _emailFromIdToken(String? idToken) {
    if (idToken == null) return null;
    try {
      final part = idToken.split('.')[1];
      final payload = utf8.decode(base64Url.decode(base64Url.normalize(part)));
      return (jsonDecode(payload) as Map)['email'] as String?;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<String> accessToken({bool interactive = false}) async {
    if (_accessToken != null && DateTime.now().isBefore(_expiry)) return _accessToken!;
    final refresh = _refreshToken;
    if (refresh == null) throw const SignInRequired();
    final r = await http.post(Uri.parse('https://oauth2.googleapis.com/token'), body: {
      'client_id': SyncConfig.desktopClientId,
      'client_secret': SyncConfig.desktopClientSecret,
      'refresh_token': refresh,
      'grant_type': 'refresh_token',
    });
    if (r.statusCode == 400 || r.statusCode == 401) {
      _refreshToken = null;
      _accessToken = null;
      try {
        await _file.delete();
      } catch (_) {}
      throw const SignInRequired();
    }
    if (r.statusCode != 200) throw HttpException('Google sign-in service error (${_errorOf(r)}).');
    _setAccess(jsonDecode(r.body) as Map<String, Object?>);
    return _accessToken!;
  }

  @override
  Future<void> signOut() async {
    final t = _refreshToken;
    _refreshToken = null;
    _accessToken = null;
    _email = null;
    try {
      if (await _file.exists()) await _file.delete();
    } catch (_) {}
    if (t != null) {
      // Best effort: also revoke the app's access in the Google account.
      try {
        await http.post(Uri.parse('https://oauth2.googleapis.com/revoke'), body: {'token': t});
      } catch (_) {}
    }
  }

  static Future<void> _openBrowser(String url) async {
    if (Platform.isWindows) {
      await Process.run('rundll32', ['url.dll,FileProtocolHandler', url]);
    } else if (Platform.isMacOS) {
      await Process.run('open', [url]);
    } else {
      await Process.run('xdg-open', [url]);
    }
  }
}
