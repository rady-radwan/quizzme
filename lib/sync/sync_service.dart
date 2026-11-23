import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../data/media_store.dart';
import '../data/settings_repository.dart';
import 'firebase_auth.dart';
import 'firestore_backend.dart';
import 'sync_store.dart';

/// What to do the first time a device connects while both the device and
/// the account already hold data.
enum FirstSyncChoice {
  /// Combine both; nothing is lost.
  merge,

  /// This device takes the account's data (its own data is replaced).
  useCloud,

  /// The account (and then every other device) takes this device's data.
  useDevice,
}

/// What was found when signing in.
enum ConnectState { cloudEmpty, deviceEmpty, bothHaveData }

/// Quiz me accounts (Firebase Authentication, email + password) and
/// two-way sync of the learning data through Cloud Firestore. Each user's
/// data is private to them. Every device downloads the account's copy when
/// it changed, merges it with its own changes (per row, the latest change
/// wins; deletions travel too) and uploads the result. Settings (theme,
/// font, …) stay per device.
class SyncService extends ChangeNotifier {
  SyncService({
    required this.store,
    required this.settings,
    required this.media,
    required this.auth,
    required this.onDataChanged,
  }) : cloud = FirestoreBackend(auth);

  final SyncStore store;
  final SettingsRepository settings;
  final MediaStore media;
  final FirebaseAuthClient auth;
  final FirestoreBackend cloud;

  /// Called after changes from another device were applied here.
  final VoidCallback onDataChanged;

  static const _kEnabled = 'sync.enabled';
  static const _kLast = 'sync.last';
  static const _kGeneration = 'sync.generation';
  static const _kVersion = 'sync.version';
  static const _kHash = 'sync.hash';

  bool enabled = false;
  bool busy = false;
  DateTime? lastSync;
  String? error;

  /// The session ended: the user has to sign in again.
  bool needsSignIn = false;

  Timer? _periodic;
  Timer? _soon;
  bool _applyingOwnChange = false;
  Future<void>? _running;

  bool get available => auth.configured;
  bool get signedIn => auth.signedIn;
  String? get email => auth.email;

  String get deviceName {
    try {
      return '${Platform.operatingSystem} ${Platform.localHostname}';
    } catch (_) {
      return Platform.operatingSystem;
    }
  }

  Future<void> init() async {
    final last = int.tryParse(await settings.getValue(_kLast) ?? '');
    lastSync = last == null ? null : DateTime.fromMillisecondsSinceEpoch(last);
    if (!available) return;
    await auth.restore();
    enabled = auth.signedIn && await settings.getValue(_kEnabled) == '1';
    notifyListeners();
    if (!enabled) return;
    _startTimer();
    unawaited(syncNow());
  }

  void _startTimer() {
    _periodic?.cancel();
    _periodic = Timer.periodic(const Duration(minutes: 3), (_) => syncNow());
  }

  /// Local data changed: sync shortly (changes are batched).
  void dataChanged() {
    if (!enabled || _applyingOwnChange) return;
    _soon?.cancel();
    _soon = Timer(const Duration(seconds: 15), () => syncNow());
  }

  void appResumed() {
    if (enabled) unawaited(syncNow());
  }

  void appPaused() {
    if (enabled && _soon?.isActive == true) {
      _soon!.cancel();
      unawaited(syncNow());
    }
  }

  // ---------------- Account ----------------

  Future<ConnectState> signIn(String email, String password) async {
    await auth.signIn(email, password);
    return _afterSignIn();
  }

  Future<ConnectState> createAccount(String email, String password) async {
    await auth.signUp(email, password);
    return _afterSignIn();
  }

  Future<void> sendPasswordReset(String email) => auth.sendPasswordReset(email);

  Future<ConnectState> _afterSignIn() async {
    error = null;
    needsSignIn = false;
    notifyListeners();
    final m = await cloud.manifest();
    if (m == null) return ConnectState.cloudEmpty;
    if (!await store.hasLocalData()) return ConnectState.deviceEmpty;
    return ConnectState.bothHaveData;
  }

  /// Completes the first sign-in on this device and turns sync on.
  Future<void> finishConnect(FirstSyncChoice choice) => _exclusive(() async {
        final m = await cloud.manifest();
        if (m == null || choice == FirstSyncChoice.useDevice) {
          // This device's data becomes the account's copy. A new generation
          // tells other devices to switch to it instead of merging.
          final snap = await store.snapshot(deviceName: deviceName);
          final generation = _newGeneration();
          final version = (m?.version ?? 0) + 1;
          final ok = await cloud.upload(snap.encode(),
              version: version, generation: generation, device: deviceName, expected: m);
          if (!ok) throw CloudException('Another device was syncing at the same time. Please try again.');
          await _remember(version, generation, _hash(snap));
        } else {
          final remote = SyncSnapshot.decode(await cloud.download(m));
          if (choice == FirstSyncChoice.useCloud) {
            await store.replaceWith(remote);
          } else {
            await store.merge(remote);
          }
          await _remember(m.version, m.generation, _hash(remote));
          _notifyData();
        }
        await settings.setValue(_kEnabled, '1');
        enabled = true;
        _startTimer();
        await _syncOnce(forceMedia: true);
      });

  /// Signs out on this device. The data stays on the device and in the account.
  Future<void> signOut() async {
    await _running;
    await auth.signOut();
    await _stop();
  }

  /// Deletes the account and all of its cloud data. Data on this device stays.
  Future<void> deleteAccount() async {
    await _running;
    await cloud.deleteAll();
    await auth.deleteAccount();
    await _stop();
  }

  Future<void> _stop() async {
    _periodic?.cancel();
    _soon?.cancel();
    enabled = false;
    lastSync = null;
    error = null;
    needsSignIn = false;
    for (final k in [_kEnabled, _kGeneration, _kVersion, _kHash, _kLast]) {
      await settings.setValue(k, null);
    }
    notifyListeners();
  }

  /// Signs in again after the session ended.
  Future<void> signInAgain(String password) async {
    final mail = auth.email;
    if (mail == null) throw const SignInRequired();
    await auth.signIn(mail, password);
    needsSignIn = false;
    error = null;
    notifyListeners();
    await syncNow();
  }

  // ---------------- Sync ----------------

  /// Syncs now. Errors are kept in [error] unless [rethrowErrors].
  Future<void> syncNow({bool rethrowErrors = false, bool includeMedia = false}) async {
    if (!enabled || !available) return;
    try {
      await _exclusive(() => _syncOnce(forceMedia: includeMedia));
    } catch (e) {
      if (rethrowErrors) rethrow;
    }
  }

  Future<void> _exclusive(Future<void> Function() body) async {
    while (_running != null) {
      await _running;
    }
    final c = Completer<void>();
    _running = c.future;
    busy = true;
    error = null;
    notifyListeners();
    try {
      await body();
      needsSignIn = false;
    } on SignInRequired catch (e) {
      needsSignIn = true;
      error = e.message;
      rethrow;
    } catch (e) {
      error = '$e';
      rethrow;
    } finally {
      busy = false;
      _running = null;
      c.complete();
      notifyListeners();
    }
  }

  static String _hash(SyncSnapshot s) => sha1.convert(utf8.encode(s.canonical())).toString();

  Future<void> _remember(int version, String generation, String hash) async {
    await settings.setValue(_kVersion, '$version');
    await settings.setValue(_kGeneration, generation);
    await settings.setValue(_kHash, hash);
  }

  Future<void> _syncOnce({bool forceMedia = false}) async {
    var mediaNeeded = forceMedia;
    for (var attempt = 0; attempt < 4; attempt++) {
      final m = await cloud.manifest();
      if (m == null) {
        // Nothing in the account (e.g. deleted from another device): upload.
        final snap = await store.snapshot(deviceName: deviceName);
        final g = _newGeneration();
        if (!await cloud.upload(snap.encode(), version: 1, generation: g, device: deviceName)) continue;
        await _remember(1, g, _hash(snap));
        mediaNeeded = true;
        break;
      }
      final knownVersion = int.tryParse(await settings.getValue(_kVersion) ?? '');
      final knownGeneration = await settings.getValue(_kGeneration);
      String remoteHash;
      if (m.version != knownVersion || m.generation != knownGeneration) {
        final remote = SyncSnapshot.decode(await cloud.download(m));
        if (knownGeneration != null && knownGeneration != m.generation) {
          // Another device chose "use this device's data": follow it.
          await store.replaceWith(remote);
          _notifyData();
        } else {
          final r = await store.merge(remote);
          if (r.changedLocal) _notifyData();
        }
        remoteHash = _hash(remote);
        mediaNeeded = true;
      } else {
        remoteHash = await settings.getValue(_kHash) ?? '';
      }
      final local = await store.snapshot(deviceName: deviceName);
      final localHash = _hash(local);
      if (localHash != remoteHash) {
        final ok = await cloud.upload(local.encode(),
            version: m.version + 1, generation: m.generation, device: deviceName, expected: m);
        if (!ok) continue; // Another device uploaded first: merge theirs, then retry.
        await _remember(m.version + 1, m.generation, localHash);
        mediaNeeded = true;
      } else {
        await _remember(m.version, m.generation, remoteHash);
      }
      break;
    }
    if (mediaNeeded) await _syncMedia();
    lastSync = DateTime.now();
    await settings.setValue(_kLast, '${lastSync!.millisecondsSinceEpoch}');
  }

  /// Images and audio of questions: each file stored once in the account
  /// (names are unique and files never change), copied to devices that lack them.
  Future<void> _syncMedia() async {
    final remote = await cloud.mediaNames();
    final local = await media.all();
    for (final e in local.entries) {
      if (!remote.contains(e.key)) await cloud.uploadMedia(e.key, await e.value.readAsBytes());
    }
    for (final name in remote) {
      if (local.containsKey(name) || name.isEmpty || name.contains('/') || name.contains('\\') || name.contains('..')) {
        continue;
      }
      final bytes = await cloud.downloadMedia(name);
      if (bytes == null) continue;
      await media.ensure();
      await File(p.join(media.root.path, name)).writeAsBytes(bytes, flush: true);
    }
  }

  String _newGeneration() {
    final r = Random.secure();
    return '${DateTime.now().millisecondsSinceEpoch}-${r.nextInt(1 << 32).toRadixString(36)}';
  }

  void _notifyData() {
    _applyingOwnChange = true;
    try {
      onDataChanged();
    } finally {
      _applyingOwnChange = false;
    }
  }

  @override
  void dispose() {
    _periodic?.cancel();
    _soon?.cancel();
    super.dispose();
  }
}
