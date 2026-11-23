import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../data/media_store.dart';
import '../data/settings_repository.dart';
import 'drive_client.dart';
import 'google_auth.dart';
import 'sync_store.dart';

/// What to do the first time a device connects while both the device and
/// Google Drive already hold data.
enum FirstSyncChoice {
  /// Combine both; nothing is lost.
  merge,

  /// This device takes the Google Drive copy (its own data is replaced).
  useCloud,

  /// Google Drive (and then every other device) takes this device's data.
  useDevice,
}

/// The situation found when connecting.
enum ConnectState { cloudEmpty, deviceEmpty, bothHaveData }

/// Two-way sync of the learning data through the app's private folder in
/// the user's Google Drive. Every device downloads the shared copy, merges it
/// with its own changes (per row, the latest change wins; deletions travel
/// too) and uploads the result. Settings (theme, font, …) stay per device.
class SyncService extends ChangeNotifier {
  SyncService({
    required this.store,
    required this.settings,
    required this.media,
    required this.auth,
    required this.onDataChanged,
  });

  final SyncStore store;
  final SettingsRepository settings;
  final MediaStore media;
  final GoogleAuth auth;

  /// Called after changes from another device were applied here.
  final VoidCallback onDataChanged;

  static const fileName = 'quizme-sync.json.gz';
  static const generationFileName = 'quizme-sync-generation.txt';
  static const mediaPrefix = 'media-';

  static const _kEnabled = 'sync.enabled';
  static const _kLast = 'sync.last';
  static const _kGeneration = 'sync.generation';

  bool enabled = false;
  bool busy = false;
  DateTime? lastSync;
  String? error;

  /// Set when the user must sign in again (shown on the Sync screen).
  bool needsSignIn = false;

  Timer? _periodic;
  Timer? _soon;
  bool _applyingOwnChange = false;
  Future<void>? _running;

  bool get available => auth.configured;
  String? get email => auth.email;

  DriveClient get _drive => DriveClient(() => auth.accessToken());

  String get deviceName {
    try {
      return '${Platform.operatingSystem} ${Platform.localHostname}';
    } catch (_) {
      return Platform.operatingSystem;
    }
  }

  Future<void> init() async {
    enabled = await settings.getValue(_kEnabled) == '1';
    final last = int.tryParse(await settings.getValue(_kLast) ?? '');
    lastSync = last == null ? null : DateTime.fromMillisecondsSinceEpoch(last);
    if (!enabled || !available) return;
    await auth.restore();
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

  // ---------------- Connect / disconnect ----------------

  /// Signs in and looks at what is already in Google Drive.
  Future<ConnectState> connect() async {
    error = null;
    needsSignIn = false;
    await auth.signIn();
    notifyListeners();
    final remote = await _drive.find(fileName);
    if (remote == null) return ConnectState.cloudEmpty;
    if (!await store.hasLocalData()) return ConnectState.deviceEmpty;
    return ConnectState.bothHaveData;
  }

  /// Completes the first connection and turns sync on.
  Future<void> finishConnect(FirstSyncChoice choice) => _exclusive(() async {
        final drive = _drive;
        final file = await drive.find(fileName);
        if (file == null || choice == FirstSyncChoice.useDevice) {
          // This device's data becomes the shared copy (new generation, so
          // other devices replace their data with it on their next sync).
          final snap = await store.snapshot(deviceName: deviceName);
          if (file == null) {
            await drive.create(fileName, snap.encode());
          } else {
            await drive.update(file.id, snap.encode());
          }
          await _writeGeneration(drive, _newGeneration());
        } else {
          final remote = SyncSnapshot.decode(await drive.download(file.id));
          if (choice == FirstSyncChoice.useCloud) {
            await store.replaceWith(remote);
          } else {
            await store.merge(remote);
          }
          _notifyData();
          await settings.setValue(_kGeneration, await _readGeneration(drive));
        }
        await settings.setValue(_kEnabled, '1');
        enabled = true;
        _startTimer();
        await _syncOnce(drive);
      });

  /// Turns sync off on this device (data stays on the device and in Drive).
  Future<void> disconnect({bool deleteCloudData = false}) async {
    await _running;
    if (deleteCloudData) {
      final drive = _drive;
      for (final f in await drive.list()) {
        await drive.delete(f.id);
      }
    }
    await auth.signOut();
    _periodic?.cancel();
    _soon?.cancel();
    enabled = false;
    lastSync = null;
    error = null;
    needsSignIn = false;
    await settings.setValue(_kEnabled, '0');
    await settings.setValue(_kGeneration, null);
    await settings.setValue(_kLast, null);
    notifyListeners();
  }

  /// Signs in again after access expired.
  Future<void> reauthenticate() async {
    await auth.signIn();
    needsSignIn = false;
    error = null;
    notifyListeners();
    await syncNow();
  }

  // ---------------- Sync ----------------

  /// Syncs now. Errors are kept in [error] (never thrown) unless [rethrowErrors].
  Future<void> syncNow({bool rethrowErrors = false}) async {
    if (!enabled || !available) return;
    try {
      await _exclusive(() async {
        if (!auth.signedIn) await auth.restore();
        await _syncOnce(_drive);
      });
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
    } on SocketException {
      error = 'No internet connection. Your changes are kept and will sync later.';
      rethrow;
    } on HttpException catch (e) {
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

  Future<void> _syncOnce(DriveClient drive) async {
    for (var attempt = 0; attempt < 4; attempt++) {
      final file = await drive.find(fileName);
      if (file == null) {
        // The shared copy was deleted (e.g. from another device): recreate.
        final snap = await store.snapshot(deviceName: deviceName);
        await drive.create(fileName, snap.encode());
        await _writeGeneration(drive, _newGeneration());
        break;
      }
      final remote = SyncSnapshot.decode(await drive.download(file.id));
      final generation = await _readGeneration(drive);
      final known = await settings.getValue(_kGeneration);
      if (generation != null && known != null && generation != known) {
        // Another device chose "use this device's data": follow it.
        await store.replaceWith(remote);
        await settings.setValue(_kGeneration, generation);
        _notifyData();
      } else {
        final r = await store.merge(remote);
        if (generation != null && known == null) await settings.setValue(_kGeneration, generation);
        if (r.changedLocal) _notifyData();
      }
      final local = await store.snapshot(deviceName: deviceName);
      if (local.canonical() != remote.canonical()) {
        // Upload only if nobody else uploaded in the meantime; otherwise
        // merge their newer copy first.
        final now = await drive.metadata(file.id);
        if (now.version != file.version) continue;
        await drive.update(file.id, local.encode());
      }
      break;
    }
    await _syncMedia(drive);
    lastSync = DateTime.now();
    await settings.setValue(_kLast, '${lastSync!.millisecondsSinceEpoch}');
  }

  /// Images and audio of questions: each file once in Drive (names are
  /// unique and files never change), copied to devices that lack them.
  Future<void> _syncMedia(DriveClient drive) async {
    final remote = {for (final f in await drive.list(prefix: mediaPrefix)) f.name.substring(mediaPrefix.length): f};
    final local = await media.all();
    for (final e in local.entries) {
      if (!remote.containsKey(e.key)) {
        await drive.create('$mediaPrefix${e.key}', await e.value.readAsBytes());
      }
    }
    for (final e in remote.entries) {
      final name = e.key;
      if (local.containsKey(name) || name.isEmpty || name.contains('/') || name.contains('\\') || name.contains('..')) {
        continue;
      }
      await media.ensure();
      final bytes = await drive.download(e.value.id);
      await File(p.join(media.root.path, name)).writeAsBytes(bytes, flush: true);
    }
  }

  Future<String?> _readGeneration(DriveClient drive) async {
    final f = await drive.find(generationFileName);
    if (f == null) return null;
    return String.fromCharCodes(await drive.download(f.id)).trim();
  }

  Future<void> _writeGeneration(DriveClient drive, String g) async {
    final f = await drive.find(generationFileName);
    final bytes = g.codeUnits;
    if (f == null) {
      await drive.create(generationFileName, bytes, mime: 'text/plain');
    } else {
      await drive.update(f.id, bytes, mime: 'text/plain');
    }
    await settings.setValue(_kGeneration, g);
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
