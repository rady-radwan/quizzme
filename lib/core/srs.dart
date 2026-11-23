import 'dart:math' as math;

import 'dates.dart';
import 'models.dart';

/// The four review grades used by the scheduler.
enum ReviewGrade { again, hard, good, easy }

/// Tunable parameters of the spaced repetition algorithm (Settings →
/// Learning preferences). Defaults reproduce the 1 → 3 → ~7 → ~18 → ~45 day
/// progression for a question that is consistently answered "Medium".
class SrsSettings {
  const SrsSettings({
    this.firstIntervalDays = 1,
    this.secondIntervalDays = 3,
    this.maxIntervalDays = 1095,
    this.startingEase = 2.5,
    this.minEase = 1.3,
    this.easyBonus = 1.3,
    this.hardFactor = 1.2,
  });

  final int firstIntervalDays;
  final int secondIntervalDays;
  final int maxIntervalDays;
  final double startingEase;
  final double minEase;
  final double easyBonus;
  final double hardFactor;
}

/// The scheduling state of one question.
class SrsState {
  const SrsState({
    this.ease = 2.5,
    this.intervalDays = 0,
    this.repetitions = 0,
    this.lapses = 0,
    this.dueAt,
    this.lastReviewAt,
  });

  final double ease;
  final int intervalDays;

  /// Consecutive successful reviews since the last lapse.
  final int repetitions;

  /// Number of times a learned question was forgotten.
  final int lapses;
  final DateTime? dueAt;
  final DateTime? lastReviewAt;

  bool get isScheduled => dueAt != null;
}

/// A modified SM-2 scheduler (the algorithm used by SuperMemo 2 and, in a
/// similar four-button form, by Anki).
///
/// * **again** (wrong answer, or "Didn't know"): the question goes back to the
///   start — repetitions = 0, lapses + 1, ease − 0.20, due in
///   [SrsSettings.firstIntervalDays].
/// * **hard**: counts as a success but grows slowly — interval × hardFactor,
///   ease − 0.15.
/// * **good** ("Medium" or no rating): classic SM-2 — 1st review
///   firstInterval, 2nd secondInterval, then previous interval × ease.
/// * **easy**: interval × ease × easyBonus, ease + 0.15.
///
/// Intervals are whole days, never shrink on a success, are capped at
/// [SrsSettings.maxIntervalDays], and ease never drops below
/// [SrsSettings.minEase]. The due date is local midnight `interval` days after
/// the review day, so "due today" is stable through the whole day.
class SrsScheduler {
  const SrsScheduler([this.settings = const SrsSettings()]);

  final SrsSettings settings;

  /// Maps an answer to a grade. A correct answer rated "Didn't know" is
  /// treated as a lucky guess and reviewed again soon.
  static ReviewGrade gradeFor({required bool correct, Confidence? confidence}) {
    if (!correct) return ReviewGrade.again;
    switch (confidence) {
      case Confidence.didntKnow:
        return ReviewGrade.again;
      case Confidence.hard:
        return ReviewGrade.hard;
      case Confidence.easy:
        return ReviewGrade.easy;
      case Confidence.medium:
      case null:
        return ReviewGrade.good;
    }
  }

  SrsState initial() => SrsState(ease: settings.startingEase);

  SrsState review(SrsState s, ReviewGrade grade, DateTime now) {
    final prev = s.intervalDays;
    var ease = s.ease <= 0 ? settings.startingEase : s.ease;
    var reps = s.repetitions;
    var lapses = s.lapses;
    int interval;

    switch (grade) {
      case ReviewGrade.again:
        if (reps > 0 || prev > 0) lapses += 1;
        reps = 0;
        ease = ease - 0.20;
        interval = settings.firstIntervalDays;
        break;
      case ReviewGrade.hard:
        reps += 1;
        ease = ease - 0.15;
        if (reps == 1) {
          interval = settings.firstIntervalDays;
        } else if (reps == 2) {
          interval = math.max(settings.firstIntervalDays,
              (settings.secondIntervalDays * 0.8).round());
        } else {
          interval = math.max(prev + 1, (prev * settings.hardFactor).round());
        }
        break;
      case ReviewGrade.good:
        reps += 1;
        if (reps == 1) {
          interval = settings.firstIntervalDays;
        } else if (reps == 2) {
          interval = settings.secondIntervalDays;
        } else {
          interval = math.max(prev + 1, (prev * ease).round());
        }
        break;
      case ReviewGrade.easy:
        reps += 1;
        ease = ease + 0.15;
        if (reps == 1) {
          interval = settings.secondIntervalDays;
        } else if (reps == 2) {
          interval = (settings.secondIntervalDays * settings.easyBonus * 1.5).round();
        } else {
          interval = math.max(prev + 1, (prev * ease * settings.easyBonus).round());
        }
        break;
    }

    ease = ease.clamp(settings.minEase, 5.0).toDouble();
    interval = interval.clamp(1, settings.maxIntervalDays).toInt();
    return SrsState(
      ease: double.parse(ease.toStringAsFixed(3)),
      intervalDays: interval,
      repetitions: reps,
      lapses: lapses,
      dueAt: addDays(startOfDay(now), interval),
      lastReviewAt: now,
    );
  }
}
