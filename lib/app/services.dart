import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart' as sqflite;
import 'package:sqflite_common/sqlite_api.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart' as ffi;

import '../data/backup_service.dart';
import '../data/catalog_repository.dart';
import '../data/db.dart';
import '../data/export_service.dart';
import '../data/import_service.dart';
import '../data/media_store.dart';
import '../data/question_repository.dart';
import '../data/session_repository.dart';
import '../data/settings_repository.dart';
import '../data/stats_repository.dart';
import '../data/study_repository.dart';
import '../services/notification_service.dart';
import '../services/speech_service.dart';
import '../sync/firebase_auth.dart';
import '../sync/sync_service.dart';
import '../sync/sync_store.dart';

const String appVersion = '1.0.0';

/// Holds the user's settings and notifies the UI when they change.
class SettingsController extends ChangeNotifier {
  SettingsController(this._repo, this._value);
  final SettingsRepository _repo;
  AppSettings _value;
  void Function(AppSettings)? onChanged;

  AppSettings get value => _value;

  Future<void> update(AppSettings s) async {
    _value = s;
    notifyListeners();
    onChanged?.call(s);
    await _repo.save(s);
  }
}

/// Composition root: opens the database and wires every repository/service.
class AppServices {
  AppServices._({
    required this.db,
    required this.media,
    required this.settingsRepo,
    required this.settings,
  }) {
    catalog = CatalogRepository(db);
    questions = QuestionRepository(db);
    study = StudyRepository(db, srs: settings.value.srs);
    sessions = SessionRepository(db, catalog, questions, study);
    stats = StatsRepository(db, catalog);
    imports = ImportService(db, catalog, questions, media);
    exports = ExportService(catalog, questions, media);
    backups = BackupService(db, media, appVersion: appVersion);
    speech.rate = settings.value.ttsRate;
    settings.onChanged = (s) {
      study.updateSrsSettings(s.srs);
      speech.rate = s.ttsRate;
    };
  }

  static late AppServices I;

  final Database db;
  final MediaStore media;
  final SettingsRepository settingsRepo;
  final SettingsController settings;
  late final CatalogRepository catalog;
  late final QuestionRepository questions;
  late final StudyRepository study;
  late final SessionRepository sessions;
  late final StatsRepository stats;
  late final ImportService imports;
  late final ExportService exports;
  late final BackupService backups;
  final NotificationService notifications = NotificationService();
  final SpeechService speech = SpeechService();

  /// Incremented whenever questions, banks or progress change, so open
  /// screens can refresh their numbers.
  final ValueNotifier<int> dataVersion = ValueNotifier<int>(0);
  void dataChanged() {
    dataVersion.value++;
    sync?.dataChanged();
  }

  /// Quiz me account and sync between devices (null in tests).
  SyncService? sync;

  static DatabaseFactory platformDatabaseFactory() {
    if (!kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
      ffi.sqfliteFfiInit();
      return ffi.databaseFactoryFfi;
    }
    return sqflite.databaseFactory;
  }

  static Future<AppServices> init() async {
    final dir = await getApplicationSupportDirectory();
    final db = await AppDatabase.open(
        platformDatabaseFactory(), p.join(dir.path, AppDatabase.fileName));
    final s = await forDatabase(db, mediaDir: Directory(p.join(dir.path, 'media')));
    s.sync = SyncService(
      store: SyncStore(db),
      settings: s.settingsRepo,
      media: s.media,
      auth: FirebaseAuthClient(dir),
      onDataChanged: s.dataChanged,
    );
    await s.imports.markInterruptedImports();
    // Retention decay and achievements are best-effort background chores.
    s.study.refreshDecay().catchError((Object e) {
      debugPrint('Decay refresh failed: $e');
      return 0;
    });
    return s;
  }

  static Future<AppServices> forDatabase(Database db, {required Directory mediaDir}) async {
    final repo = SettingsRepository(db);
    final settings = SettingsController(repo, await repo.load());
    final media = MediaStore(mediaDir);
    return AppServices._(db: db, media: media, settingsRepo: repo, settings: settings);
  }

  /// Re-plans study reminders with up-to-date numbers.
  Future<void> refreshReminders() async {
    final s = settings.value;
    if (!NotificationService.supported) return;
    try {
      final dash = await stats.dashboard();
      final upcoming = await stats.upcomingReviews(days: 14);
      final dueByDay = <int>[dash.dueToday];
      var running = dash.dueToday;
      for (final n in upcoming) {
        running += n;
        dueByDay.add(running);
      }
      await notifications.reschedule(
        s,
        ReminderContext(
          dueByDay: dueByDay,
          dailyGoal: s.dailyQuestionGoal,
          answeredToday: dash.today.answered,
        ),
      );
    } catch (e) {
      debugPrint('Reminder refresh failed: $e');
    }
  }
}
