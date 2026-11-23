import 'dart:convert';

import 'package:sqflite_common/sqlite_api.dart';

import '../core/models.dart';
import '../core/srs.dart';

enum AppTheme {
  system('system', 'System default'),
  light('light', 'Light'),
  dark('dark', 'Dark'),
  amoled('amoled', 'AMOLED Black'),
  minimal('minimal', 'Minimal White'),
  sepia('sepia', 'Sepia');

  const AppTheme(this.key, this.label);
  final String key;
  final String label;

  static AppTheme fromKey(String? k) =>
      values.firstWhere((t) => t.key == k, orElse: () => AppTheme.system);
}

enum AppFont {
  system('system', 'Default (Roboto)', null),
  serif('serif', 'Serif', 'serif'),
  mono('mono', 'Monospace', 'monospace');

  const AppFont(this.key, this.label, this.family);
  final String key;
  final String label;
  final String? family;

  static AppFont fromKey(String? k) =>
      values.firstWhere((t) => t.key == k, orElse: () => AppFont.system);
}

enum LayoutDirectionPref {
  auto('auto', 'Automatic'),
  ltr('ltr', 'Left to right'),
  rtl('rtl', 'Right to left');

  const LayoutDirectionPref(this.key, this.label);
  final String key;
  final String label;

  static LayoutDirectionPref fromKey(String? k) =>
      values.firstWhere((t) => t.key == k, orElse: () => LayoutDirectionPref.auto);
}

/// All user preferences. Stored as key/value rows so new settings never need a
/// schema migration; unknown or missing keys fall back to defaults.
class AppSettings {
  const AppSettings({
    this.theme = AppTheme.system,
    this.accentColor = 0xFF1E5BD6,
    this.useCustomAccent = false,
    this.font = AppFont.system,
    this.textScale = 1.0,
    this.lineHeight = 1.4,
    this.highContrast = false,
    this.reduceMotion = false,
    this.layoutDirection = LayoutDirectionPref.auto,
    this.defaultQuestionCount = 10,
    this.defaultSelection = SelectionMode.random,
    this.defaultFeedback = FeedbackTiming.immediate,
    this.shuffleQuestions = true,
    this.shuffleAnswers = true,
    this.hintsEnabled = true,
    this.timerMinutes = 0,
    this.confidenceRatings = true,
    this.adaptiveDifficulty = false,
    this.dailyQuestionGoal = 25,
    this.srsFirstInterval = 1,
    this.srsSecondInterval = 3,
    this.srsMaxInterval = 1095,
    this.srsEasyBonus = 1.3,
    this.notificationsEnabled = false,
    this.reminderHour = 19,
    this.reminderMinute = 0,
    this.reminderDays = const [1, 2, 3, 4, 5, 6, 7],
    this.dueReminders = true,
    this.goalReminders = true,
    this.gamification = true,
    this.ttsRate = 0.5,
    this.onboardingDone = false,
  });

  final AppTheme theme;
  final int accentColor;
  final bool useCustomAccent;
  final AppFont font;
  final double textScale;
  final double lineHeight;
  final bool highContrast;
  final bool reduceMotion;
  final LayoutDirectionPref layoutDirection;

  final int defaultQuestionCount;
  final SelectionMode defaultSelection;
  final FeedbackTiming defaultFeedback;
  final bool shuffleQuestions;
  final bool shuffleAnswers;
  final bool hintsEnabled;
  final int timerMinutes;

  final bool confidenceRatings;
  final bool adaptiveDifficulty;
  final int dailyQuestionGoal;
  final int srsFirstInterval;
  final int srsSecondInterval;
  final int srsMaxInterval;
  final double srsEasyBonus;

  final bool notificationsEnabled;
  final int reminderHour;
  final int reminderMinute;

  /// ISO weekdays (1 = Monday ... 7 = Sunday).
  final List<int> reminderDays;
  final bool dueReminders;
  final bool goalReminders;

  final bool gamification;
  final double ttsRate;
  final bool onboardingDone;

  SrsSettings get srs => SrsSettings(
        firstIntervalDays: srsFirstInterval,
        secondIntervalDays: srsSecondInterval,
        maxIntervalDays: srsMaxInterval,
        easyBonus: srsEasyBonus,
      );

  Map<String, String> toMap() => {
        'theme': theme.key,
        'accentColor': '$accentColor',
        'useCustomAccent': '$useCustomAccent',
        'font': font.key,
        'textScale': '$textScale',
        'lineHeight': '$lineHeight',
        'highContrast': '$highContrast',
        'reduceMotion': '$reduceMotion',
        'layoutDirection': layoutDirection.key,
        'defaultQuestionCount': '$defaultQuestionCount',
        'defaultSelection': defaultSelection.key,
        'defaultFeedback': defaultFeedback.key,
        'shuffleQuestions': '$shuffleQuestions',
        'shuffleAnswers': '$shuffleAnswers',
        'hintsEnabled': '$hintsEnabled',
        'timerMinutes': '$timerMinutes',
        'confidenceRatings': '$confidenceRatings',
        'adaptiveDifficulty': '$adaptiveDifficulty',
        'dailyQuestionGoal': '$dailyQuestionGoal',
        'srsFirstInterval': '$srsFirstInterval',
        'srsSecondInterval': '$srsSecondInterval',
        'srsMaxInterval': '$srsMaxInterval',
        'srsEasyBonus': '$srsEasyBonus',
        'notificationsEnabled': '$notificationsEnabled',
        'reminderHour': '$reminderHour',
        'reminderMinute': '$reminderMinute',
        'reminderDays': jsonEncode(reminderDays),
        'dueReminders': '$dueReminders',
        'goalReminders': '$goalReminders',
        'gamification': '$gamification',
        'ttsRate': '$ttsRate',
        'onboardingDone': '$onboardingDone',
      };

  factory AppSettings.fromMap(Map<String, String?> m) {
    const d = AppSettings();
    bool b(String k, bool def) => m[k] == null ? def : m[k] == 'true';
    int i(String k, int def) => int.tryParse(m[k] ?? '') ?? def;
    double f(String k, double def) => double.tryParse(m[k] ?? '') ?? def;
    List<int> days() {
      try {
        final v = jsonDecode(m['reminderDays'] ?? '') as List;
        return v.map((e) => (e as num).toInt()).where((e) => e >= 1 && e <= 7).toList();
      } catch (_) {
        return d.reminderDays;
      }
    }

    return AppSettings(
      theme: AppTheme.fromKey(m['theme']),
      accentColor: i('accentColor', d.accentColor),
      useCustomAccent: b('useCustomAccent', d.useCustomAccent),
      font: AppFont.fromKey(m['font']),
      textScale: f('textScale', d.textScale).clamp(0.8, 2.0).toDouble(),
      lineHeight: f('lineHeight', d.lineHeight).clamp(1.0, 2.2).toDouble(),
      highContrast: b('highContrast', d.highContrast),
      reduceMotion: b('reduceMotion', d.reduceMotion),
      layoutDirection: LayoutDirectionPref.fromKey(m['layoutDirection']),
      defaultQuestionCount: i('defaultQuestionCount', d.defaultQuestionCount).clamp(1, 1000).toInt(),
      defaultSelection: m['defaultSelection'] == null
          ? d.defaultSelection
          : SelectionMode.fromKey(m['defaultSelection']),
      defaultFeedback: FeedbackTiming.fromKey(m['defaultFeedback']),
      shuffleQuestions: b('shuffleQuestions', d.shuffleQuestions),
      shuffleAnswers: b('shuffleAnswers', d.shuffleAnswers),
      hintsEnabled: b('hintsEnabled', d.hintsEnabled),
      timerMinutes: i('timerMinutes', d.timerMinutes).clamp(0, 600).toInt(),
      confidenceRatings: b('confidenceRatings', d.confidenceRatings),
      adaptiveDifficulty: b('adaptiveDifficulty', d.adaptiveDifficulty),
      dailyQuestionGoal: i('dailyQuestionGoal', d.dailyQuestionGoal),
      srsFirstInterval: i('srsFirstInterval', d.srsFirstInterval).clamp(1, 30).toInt(),
      srsSecondInterval: i('srsSecondInterval', d.srsSecondInterval).clamp(1, 60).toInt(),
      srsMaxInterval: i('srsMaxInterval', d.srsMaxInterval).clamp(30, 3650).toInt(),
      srsEasyBonus: f('srsEasyBonus', d.srsEasyBonus).clamp(1.0, 2.0).toDouble(),
      notificationsEnabled: b('notificationsEnabled', d.notificationsEnabled),
      reminderHour: i('reminderHour', d.reminderHour).clamp(0, 23).toInt(),
      reminderMinute: i('reminderMinute', d.reminderMinute).clamp(0, 59).toInt(),
      reminderDays: days(),
      dueReminders: b('dueReminders', d.dueReminders),
      goalReminders: b('goalReminders', d.goalReminders),
      gamification: b('gamification', d.gamification),
      ttsRate: f('ttsRate', d.ttsRate).clamp(0.1, 1.0).toDouble(),
      onboardingDone: b('onboardingDone', d.onboardingDone),
    );
  }

  AppSettings copyWith({
    AppTheme? theme,
    int? accentColor,
    bool? useCustomAccent,
    AppFont? font,
    double? textScale,
    double? lineHeight,
    bool? highContrast,
    bool? reduceMotion,
    LayoutDirectionPref? layoutDirection,
    int? defaultQuestionCount,
    SelectionMode? defaultSelection,
    FeedbackTiming? defaultFeedback,
    bool? shuffleQuestions,
    bool? shuffleAnswers,
    bool? hintsEnabled,
    int? timerMinutes,
    bool? confidenceRatings,
    bool? adaptiveDifficulty,
    int? dailyQuestionGoal,
    int? srsFirstInterval,
    int? srsSecondInterval,
    int? srsMaxInterval,
    double? srsEasyBonus,
    bool? notificationsEnabled,
    int? reminderHour,
    int? reminderMinute,
    List<int>? reminderDays,
    bool? dueReminders,
    bool? goalReminders,
    bool? gamification,
    double? ttsRate,
    bool? onboardingDone,
  }) =>
      AppSettings(
        theme: theme ?? this.theme,
        accentColor: accentColor ?? this.accentColor,
        useCustomAccent: useCustomAccent ?? this.useCustomAccent,
        font: font ?? this.font,
        textScale: textScale ?? this.textScale,
        lineHeight: lineHeight ?? this.lineHeight,
        highContrast: highContrast ?? this.highContrast,
        reduceMotion: reduceMotion ?? this.reduceMotion,
        layoutDirection: layoutDirection ?? this.layoutDirection,
        defaultQuestionCount: defaultQuestionCount ?? this.defaultQuestionCount,
        defaultSelection: defaultSelection ?? this.defaultSelection,
        defaultFeedback: defaultFeedback ?? this.defaultFeedback,
        shuffleQuestions: shuffleQuestions ?? this.shuffleQuestions,
        shuffleAnswers: shuffleAnswers ?? this.shuffleAnswers,
        hintsEnabled: hintsEnabled ?? this.hintsEnabled,
        timerMinutes: timerMinutes ?? this.timerMinutes,
        confidenceRatings: confidenceRatings ?? this.confidenceRatings,
        adaptiveDifficulty: adaptiveDifficulty ?? this.adaptiveDifficulty,
        dailyQuestionGoal: dailyQuestionGoal ?? this.dailyQuestionGoal,
        srsFirstInterval: srsFirstInterval ?? this.srsFirstInterval,
        srsSecondInterval: srsSecondInterval ?? this.srsSecondInterval,
        srsMaxInterval: srsMaxInterval ?? this.srsMaxInterval,
        srsEasyBonus: srsEasyBonus ?? this.srsEasyBonus,
        notificationsEnabled: notificationsEnabled ?? this.notificationsEnabled,
        reminderHour: reminderHour ?? this.reminderHour,
        reminderMinute: reminderMinute ?? this.reminderMinute,
        reminderDays: reminderDays ?? this.reminderDays,
        dueReminders: dueReminders ?? this.dueReminders,
        goalReminders: goalReminders ?? this.goalReminders,
        gamification: gamification ?? this.gamification,
        ttsRate: ttsRate ?? this.ttsRate,
        onboardingDone: onboardingDone ?? this.onboardingDone,
      );
}

class SettingsRepository {
  SettingsRepository(this.db);
  final Database db;

  Future<AppSettings> load() async {
    final rows = await db.query('settings');
    return AppSettings.fromMap({for (final r in rows) r['key'] as String: r['value'] as String?});
  }

  Future<void> save(AppSettings s) async {
    final batch = db.batch();
    s.toMap().forEach((k, v) {
      batch.insert('settings', {'key': k, 'value': v}, conflictAlgorithm: ConflictAlgorithm.replace);
    });
    await batch.commit(noResult: true);
  }

  Future<String?> getValue(String key) async {
    final r = await db.query('settings', where: 'key = ?', whereArgs: [key]);
    return r.isEmpty ? null : r.first['value'] as String?;
  }

  Future<void> setValue(String key, String? value) => db.insert(
      'settings', {'key': key, 'value': value},
      conflictAlgorithm: ConflictAlgorithm.replace);
}
