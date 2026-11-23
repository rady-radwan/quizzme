import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../core/dates.dart';
import '../data/settings_repository.dart';

/// Information used to word each day's reminder.
class ReminderContext {
  ReminderContext({
    required this.dueByDay,
    required this.dailyGoal,
    required this.answeredToday,
    this.subjectName,
  });

  /// Number of reviews due on or before each of the next days (index 0 = today).
  final List<int> dueByDay;
  final int dailyGoal;
  final int answeredToday;
  final String? subjectName;
}

/// Optional study reminders. At most one notification per day, only on the
/// days and at the time the user chose. Reminders are scheduled for the next
/// 14 days and re-planned whenever the app opens or a quiz finishes, so the
/// wording ("You have 20 questions due for review") stays accurate. The app is
/// fully functional when notifications are off or the permission is denied.
class NotificationService {
  final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();
  bool _ready = false;

  static bool get supported => !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  Future<void> init() async {
    if (!supported || _ready) return;
    try {
      tzdata.initializeTimeZones();
      const settings = InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: DarwinInitializationSettings(
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
        ),
      );
      await _plugin.initialize(settings);
      _ready = true;
    } catch (e) {
      debugPrint('Notifications unavailable: $e');
    }
  }

  /// Asks the OS for permission (Android 13+, iOS). Returns true if granted.
  Future<bool> requestPermission() async {
    await init();
    if (!_ready) return false;
    try {
      if (Platform.isAndroid) {
        final android = _plugin.resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
        return await android?.requestNotificationsPermission() ?? false;
      }
      if (Platform.isIOS) {
        final ios = _plugin.resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin>();
        return await ios?.requestPermissions(alert: true, badge: true, sound: true) ?? false;
      }
    } catch (e) {
      debugPrint('Notification permission request failed: $e');
    }
    return false;
  }

  static const _details = NotificationDetails(
    android: AndroidNotificationDetails(
      'study_reminders',
      'Study reminders',
      channelDescription: 'Daily reminders about reviews and study goals',
      importance: Importance.defaultImportance,
      priority: Priority.defaultPriority,
    ),
    iOS: DarwinNotificationDetails(),
  );

  /// Pure function: the reminder text for day [i] (0 = today), or null when
  /// there is nothing worth notifying about.
  static (String, String)? messageFor(int i, AppSettings s, ReminderContext c) {
    final due = i < c.dueByDay.length ? c.dueByDay[i] : 0;
    if (s.dueReminders && due > 0) {
      return ('Time to review', 'You have $due ${due == 1 ? 'question' : 'questions'} due for review.');
    }
    if (s.goalReminders && c.dailyGoal > 0) {
      if (i == 0 && c.answeredToday > 0 && c.answeredToday < c.dailyGoal) {
        return ('Daily goal', "You have completed ${c.answeredToday} of today's ${c.dailyGoal} questions.");
      }
      if (i > 0 || c.answeredToday == 0) {
        final what = c.subjectName == null ? 'Your revision' : 'Your ${c.subjectName} revision';
        return ('Quiz me', '$what is waiting — today\'s goal is ${c.dailyGoal} questions.');
      }
    }
    return null;
  }

  Future<void> reschedule(AppSettings s, ReminderContext c, {DateTime? now}) async {
    if (!supported) return;
    await init();
    if (!_ready) return;
    try {
      await _plugin.cancelAll();
      if (!s.notificationsEnabled) return;
      final t = now ?? DateTime.now();
      for (var i = 0; i < 14; i++) {
        final day = addDays(startOfDay(t), i);
        if (!s.reminderDays.contains(day.weekday)) continue;
        final at = DateTime(day.year, day.month, day.day, s.reminderHour, s.reminderMinute);
        if (!at.isAfter(t)) continue;
        final msg = messageFor(i, s, c);
        if (msg == null) continue;
        await _plugin.zonedSchedule(
          1000 + i,
          msg.$1,
          msg.$2,
          tz.TZDateTime.from(at.toUtc(), tz.UTC),
          _details,
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        );
      }
    } catch (e) {
      debugPrint('Could not schedule reminders: $e');
    }
  }
}
