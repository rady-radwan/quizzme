import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

import 'dpapi.dart';
import 'firebase_config.dart';

/// A sign-in problem with a message that can be shown to the user.
class AuthException implements Exception {
  const AuthException(this.message, {this.code});
  final String message;
  final String? code;
  @override
  String toString() => message;
}

/// The user must sign in again (session expired, account disabled or deleted).
class SignInRequired extends AuthException {
  const SignInRequired([super.message = 'Please sign in again to keep syncing.']);
}

/// Firebase Authentication (email + password) through its REST API, so the
/// same code works on Android and Windows. The session (refresh token) is
/// saved in the app's private folder; on Windows it is also encrypted with
/// DPAPI so only this Windows user can read it.
class FirebaseAuthClient {
  FirebaseAuthClient(this._dir, {http.Client? client}) : _http = client ?? http.Client();
  final Directory _dir;
  final http.Client _http;

  String? uid;
  String? email;
  String? _idToken;
  String? _refreshToken;
  DateTime _expiry = DateTime.fromMillisecondsSinceEpoch(0);

  bool get configured => FirebaseConfig.configured;
  bool get signedIn => uid != null && _refreshToken != null;

  File get _file => File(p.join(_dir.path, 'account.bin'));

  static const _idp = 'https://identitytoolkit.googleapis.com/v1/accounts';

  Future<void> restore() async {
    try {
      if (!await _file.exists()) return;
      List<int> bytes = await _file.readAsBytes();
      if (Dpapi.available) bytes = Dpapi.unprotect(bytes);
      final j = jsonDecode(utf8.decode(bytes)) as Map<String, Object?>;
      uid = j['uid'] as String?;
      email = j['email'] as String?;
      _refreshToken = j['refresh_token'] as String?;
    } catch (_) {
      uid = null;
      _refreshToken = null;
    }
  }

  Future<void> _save() async {
    await _dir.create(recursive: true);
    List<int> bytes = utf8.encode(jsonEncode({'uid': uid, 'email': email, 'refresh_token': _refreshToken}));
    if (Dpapi.available) bytes = Dpapi.protect(bytes);
    await _file.writeAsBytes(bytes, flush: true);
  }

  Future<Map<String, Object?>> _post(String url, Map<String, Object?> body) async {
    if (!configured) throw const AuthException('Accounts are not set up in this version of the app.');
    final http.Response r;
    try {
      r = await _http.post(Uri.parse('$url?key=${FirebaseConfig.apiKey}'),
          headers: {'Content-Type': 'application/json'}, body: jsonEncode(body));
    } on SocketException {
      throw const AuthException('No internet connection.');
    }
    final j = (r.body.isEmpty ? <String, Object?>{} : jsonDecode(r.body)) as Map<String, Object?>;
    if (r.statusCode != 200) {
      final code = ((j['error'] as Map?)?['message'] as String?) ?? 'HTTP ${r.statusCode}';
      throw AuthException(friendlyError(code), code: code);
    }
    return j;
  }

  static String friendlyError(String code) {
    final c = code.split(' ').first.split(':').first.trim();
    switch (c) {
      case 'EMAIL_EXISTS':
        return 'An account with this email already exists. Sign in instead.';
      case 'EMAIL_NOT_FOUND':
      case 'INVALID_PASSWORD':
      case 'INVALID_LOGIN_CREDENTIALS':
        return 'Wrong email or password.';
      case 'INVALID_EMAIL':
        return 'Please enter a valid email address.';
      case 'WEAK_PASSWORD':
        return 'Please choose a password with at least 6 characters.';
      case 'MISSING_PASSWORD':
        return 'Please enter your password.';
      case 'TOO_MANY_ATTEMPTS_TRY_LATER':
        return 'Too many attempts. Please wait a few minutes and try again.';
      case 'USER_DISABLED':
        return 'This account has been disabled.';
      case 'OPERATION_NOT_ALLOWED':
        return 'Email sign-in is not enabled for this app yet (Firebase console → Authentication).';
      case 'CREDENTIAL_TOO_OLD_LOGIN_AGAIN':
        return 'For your security, sign out and sign in again, then retry.';
      case 'TOKEN_EXPIRED':
      case 'INVALID_REFRESH_TOKEN':
      case 'USER_NOT_FOUND':
        return 'Your session has ended. Please sign in again.';
      default:
        return 'Sign-in failed ($code).';
    }
  }

  void _setSession(Map<String, Object?> j) {
    uid = (j['localId'] ?? j['user_id']) as String?;
    email = (j['email'] as String?) ?? email;
    _idToken = (j['idToken'] ?? j['id_token']) as String?;
    _refreshToken = (j['refreshToken'] ?? j['refresh_token']) as String?;
    final secs = int.tryParse('${j['expiresIn'] ?? j['expires_in'] ?? '3600'}') ?? 3600;
    _expiry = DateTime.now().add(Duration(seconds: secs - 120));
  }

  Future<void> signUp(String email, String password) async {
    _setSession(await _post('$_idp:signUp', {'email': email.trim(), 'password': password, 'returnSecureToken': true}));
    await _save();
  }

  Future<void> signIn(String email, String password) async {
    _setSession(await _post(
        '$_idp:signInWithPassword', {'email': email.trim(), 'password': password, 'returnSecureToken': true}));
    await _save();
  }

  Future<void> sendPasswordReset(String email) =>
      _post('$_idp:sendOobCode', {'requestType': 'PASSWORD_RESET', 'email': email.trim()});

  /// A valid Firebase ID token (refreshed when needed).
  Future<String> idToken() async {
    if (_idToken != null && DateTime.now().isBefore(_expiry)) return _idToken!;
    final refresh = _refreshToken;
    if (refresh == null) throw const SignInRequired();
    final http.Response r;
    try {
      r = await _http.post(Uri.parse('https://securetoken.googleapis.com/v1/token?key=${FirebaseConfig.apiKey}'),
          body: {'grant_type': 'refresh_token', 'refresh_token': refresh});
    } on SocketException {
      throw const AuthException('No internet connection.');
    }
    if (r.statusCode == 400 || r.statusCode == 401 || r.statusCode == 403) {
      await signOut();
      throw const SignInRequired();
    }
    if (r.statusCode != 200) throw AuthException('Sign-in service error (HTTP ${r.statusCode}).');
    _setSession(jsonDecode(r.body) as Map<String, Object?>);
    await _save();
    return _idToken!;
  }

  Future<void> signOut() async {
    uid = null;
    email = null;
    _idToken = null;
    _refreshToken = null;
    try {
      if (await _file.exists()) await _file.delete();
    } catch (_) {}
  }

  /// Permanently deletes the account (call after deleting its data).
  Future<void> deleteAccount() async {
    await _post('$_idp:delete', {'idToken': await idToken()});
    await signOut();
  }
}
