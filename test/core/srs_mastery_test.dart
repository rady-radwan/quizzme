import 'package:flutter_test/flutter_test.dart';
import 'package:quiz_me/core/dates.dart';
import 'package:quiz_me/core/mastery.dart';
import 'package:quiz_me/core/models.dart';
import 'package:quiz_me/core/srs.dart';

void main() {
  const s = SrsScheduler();
  final t0 = DateTime(2026, 3, 10, 14, 30);

  group('Spaced repetition scheduling', () {
    test('consistent "good" answers follow 1, 3, then ×ease days', () {
      var st = s.initial();
      final intervals = <int>[];
      var now = t0;
      for (var i = 0; i < 5; i++) {
        st = s.review(st, ReviewGrade.good, now);
        intervals.add(st.intervalDays);
        now = st.dueAt!;
      }
      expect(intervals.take(2).toList(), [1, 3]);
      expect(intervals[2], 8); // 3 × 2.5 = 7.5 → 8
      expect(intervals[3], 20); // 8 × 2.5
      expect(intervals[4], 50);
      expect(st.repetitions, 5);
      expect(st.lapses, 0);
    });

    test('due date is local midnight N days after the review day', () {
      final st = s.review(s.initial(), ReviewGrade.good, t0);
      expect(st.dueAt, DateTime(2026, 3, 11));
    });

    test('wrong answer resets repetitions, counts a lapse, lowers ease', () {
      var st = s.initial();
      st = s.review(st, ReviewGrade.good, t0);
      st = s.review(st, ReviewGrade.good, t0);
      final ease = st.ease;
      st = s.review(st, ReviewGrade.again, t0);
      expect(st.repetitions, 0);
      expect(st.lapses, 1);
      expect(st.intervalDays, 1);
      expect(st.ease, closeTo(ease - 0.2, 1e-9));
    });

    test('ease never drops below the minimum', () {
      var st = s.initial();
      for (var i = 0; i < 30; i++) {
        st = s.review(st, ReviewGrade.again, t0);
      }
      expect(st.ease, greaterThanOrEqualTo(1.3));
    });

    test('interval is capped at the maximum', () {
      const capped = SrsScheduler(SrsSettings(maxIntervalDays: 60));
      var st = capped.initial();
      var now = t0;
      for (var i = 0; i < 15; i++) {
        st = capped.review(st, ReviewGrade.easy, now);
        now = st.dueAt!;
      }
      expect(st.intervalDays, 60);
    });

    test('easy grows faster than good, hard slower', () {
      SrsState run(ReviewGrade g) {
        var st = s.initial();
        for (var i = 0; i < 4; i++) {
          st = s.review(st, g, t0);
        }
        return st;
      }

      expect(run(ReviewGrade.easy).intervalDays, greaterThan(run(ReviewGrade.good).intervalDays));
      expect(run(ReviewGrade.hard).intervalDays, lessThan(run(ReviewGrade.good).intervalDays));
    });

    test('successful reviews never shrink the interval', () {
      var st = s.initial();
      var prev = 0;
      for (final g in [ReviewGrade.good, ReviewGrade.hard, ReviewGrade.hard, ReviewGrade.hard, ReviewGrade.good]) {
        st = s.review(st, g, t0);
        expect(st.intervalDays, greaterThanOrEqualTo(prev));
        prev = st.intervalDays;
      }
    });

    test('grade mapping uses correctness and confidence', () {
      expect(SrsScheduler.gradeFor(correct: false, confidence: Confidence.easy), ReviewGrade.again);
      expect(SrsScheduler.gradeFor(correct: true, confidence: Confidence.didntKnow), ReviewGrade.again);
      expect(SrsScheduler.gradeFor(correct: true, confidence: Confidence.hard), ReviewGrade.hard);
      expect(SrsScheduler.gradeFor(correct: true), ReviewGrade.good);
      expect(SrsScheduler.gradeFor(correct: true, confidence: Confidence.easy), ReviewGrade.easy);
    });
  });

  group('Mastery levels', () {
    const m = MasteryCalculator();
    QuestionProgress p({
      int attempts = 0,
      int correct = 0,
      int incorrect = 0,
      int reps = 0,
      int interval = 0,
      int lapses = 0,
      AttemptResult? last,
      DateTime? due,
    }) =>
        QuestionProgress(
          questionId: 'q',
          attemptCount: attempts,
          correctCount: correct,
          incorrectCount: incorrect,
          repetitions: reps,
          intervalDays: interval,
          lapses: lapses,
          lastResult: last,
          dueAt: due,
        );

    test('never answered is Not Learned', () {
      expect(m.evaluate(p(), t0).level, MasteryLevel.notLearned);
    });

    test('a wrong last answer moves back to Learning', () {
      final r = m.evaluate(p(attempts: 5, correct: 4, incorrect: 1, last: AttemptResult.incorrect), t0);
      expect(r.level, MasteryLevel.learning);
      expect(r.reason, isNotEmpty);
    });

    test('repeated mistakes give Needs Practice', () {
      final r = m.evaluate(p(attempts: 3, correct: 1, incorrect: 2, last: AttemptResult.incorrect), t0);
      expect(r.level, MasteryLevel.needsPractice);
    });

    test('long streak with long interval is Mastered', () {
      final r = m.evaluate(
          p(attempts: 5, correct: 5, reps: 5, interval: 30, last: AttemptResult.correct, due: addDays(t0, 30)), t0);
      expect(r.level, MasteryLevel.mastered);
    });

    test('two successful reviews and a week interval is Well Learned', () {
      final r = m.evaluate(
          p(attempts: 2, correct: 2, reps: 2, interval: 8, last: AttemptResult.correct, due: addDays(t0, 8)), t0);
      expect(r.level, MasteryLevel.wellLearned);
    });

    test('overdue reviews decay one level (retention fading)', () {
      final due = addDays(t0, -60);
      final r = m.evaluate(p(attempts: 5, correct: 5, reps: 5, interval: 30, last: AttemptResult.correct, due: due), t0);
      expect(r.level, MasteryLevel.wellLearned);
      expect(r.reason, contains('Overdue'));
    });

    test('difficulty does not affect mastery', () {
      // Mastery is computed only from learning history, never from difficulty.
      final r = m.evaluate(p(attempts: 1, correct: 1, reps: 1, interval: 1, last: AttemptResult.correct), t0);
      expect(r.level, MasteryLevel.learning);
    });
  });

  group('Dates', () {
    test('calendar day difference ignores time of day', () {
      expect(calendarDaysBetween(DateTime(2026, 1, 1, 23, 59), DateTime(2026, 1, 2, 0, 1)), 1);
      expect(calendarDaysBetween(DateTime(2026, 1, 5), DateTime(2026, 1, 1)), -4);
    });

    test('day keys round trip', () {
      expect(dayKey(DateTime(2026, 7, 4, 10)), '2026-07-04');
      expect(parseDayKey('2026-07-04'), DateTime(2026, 7, 4));
    });

    test('week starts on Monday', () {
      expect(startOfWeek(DateTime(2026, 11, 22)), DateTime(2026, 11, 16)); // Sunday -> Monday
    });
  });
}
