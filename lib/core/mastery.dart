import 'dart:math' as math;

import 'dates.dart';
import 'models.dart';

class MasteryResult {
  const MasteryResult(this.level, this.reason);
  final MasteryLevel level;

  /// Plain-language explanation shown to the learner ("why this status?").
  final String reason;
}

/// Transparent, rule-based mastery levels. Rules are evaluated in order:
///
/// 1. Never answered → **Not Learned**.
/// 2. Last answer wrong → **Learning** (or **Needs Practice** if it has been
///    answered wrong at least twice). This is how a question moves backwards.
/// 3. Otherwise, from the spaced-repetition state:
///    * ≥ 4 successful reviews in a row, interval ≥ 21 days and accuracy
///      ≥ 80% → **Mastered**
///    * ≥ 2 successful reviews in a row and interval ≥ 7 days → **Well Learned**
///      (unless accuracy is below 60% → Needs Practice)
///    * accuracy below 70% or forgotten at least twice → **Needs Practice**
///    * otherwise → **Learning**
/// 4. Retention decay: if a review is overdue by more than
///    max(interval, 3) days, the level drops one step (not below Learning),
///    because the memory may be fading.
class MasteryCalculator {
  const MasteryCalculator();

  MasteryResult evaluate(QuestionProgress p, DateTime now) {
    if (p.attemptCount == 0 || (p.correctCount + p.incorrectCount) == 0) {
      return const MasteryResult(MasteryLevel.notLearned, 'Not answered yet.');
    }
    final acc = p.accuracy ?? 0;
    final pct = (acc * 100).round();

    if (p.lastResult == AttemptResult.incorrect) {
      if (p.incorrectCount >= 2) {
        return MasteryResult(MasteryLevel.needsPractice,
            'Answered incorrectly ${p.incorrectCount} times, including the last attempt.');
      }
      return const MasteryResult(
          MasteryLevel.learning, 'Your last answer was incorrect.');
    }

    MasteryLevel level;
    String reason;
    if (p.repetitions >= 4 && p.intervalDays >= 21 && acc >= 0.8) {
      level = MasteryLevel.mastered;
      reason = 'Recalled ${p.repetitions} times in a row; next review in '
          '${p.intervalDays} days; $pct% accuracy.';
    } else if (p.repetitions >= 2 && p.intervalDays >= 7) {
      if (acc < 0.6) {
        level = MasteryLevel.needsPractice;
        reason = 'Recent reviews went well, but overall accuracy is only $pct%.';
      } else {
        level = MasteryLevel.wellLearned;
        reason = 'Recalled ${p.repetitions} times in a row; review interval '
            '${p.intervalDays} days.';
      }
    } else if (acc < 0.7 || p.lapses >= 2) {
      level = MasteryLevel.needsPractice;
      reason = p.lapses >= 2
          ? 'Forgotten ${p.lapses} times after being learned.'
          : 'Accuracy is $pct% — keep practising.';
    } else {
      level = MasteryLevel.learning;
      reason = p.repetitions <= 1
          ? 'Answered correctly — a few more successful reviews are needed.'
          : 'Getting there: ${p.repetitions} successful reviews in a row.';
    }

    final due = p.dueAt;
    if (due != null && level.index > MasteryLevel.learning.index) {
      final overdueDays = calendarDaysBetween(due, now);
      final grace = math.max(p.intervalDays, 3);
      if (overdueDays > grace) {
        level = MasteryLevel.values[level.index - 1];
        reason = '$reason Overdue for review by $overdueDays days, so '
            'retention may be fading.';
      }
    }
    return MasteryResult(level, reason);
  }
}
