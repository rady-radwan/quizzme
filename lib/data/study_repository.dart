import 'package:sqflite_common/sqlite_api.dart';

import '../core/dates.dart';
import '../core/ids.dart';
import '../core/mastery.dart';
import '../core/models.dart';
import '../core/srs.dart';
import 'db.dart';

class AttemptOutcome {
  AttemptOutcome(this.progress, this.masteryBefore, this.wasDue);
  final QuestionProgress progress;
  final MasteryLevel masteryBefore;
  final bool wasDue;
  MasteryLevel get masteryAfter => progress.mastery;
  bool get newlyMastered =>
      masteryAfter == MasteryLevel.mastered && masteryBefore != MasteryLevel.mastered;
}

/// An entry of the Mistakes Notebook.
class MistakeEntry {
  MistakeEntry({
    required this.progress,
    required this.lastWrongResponse,
    required this.lastWrongAt,
    required this.bookmarked,
  });
  final QuestionProgress progress;
  final QuestionResponse lastWrongResponse;
  final DateTime? lastWrongAt;
  final bool bookmarked;
}

/// Records what the learner did and maintains each question's learning state:
/// presentation history (New Questions mode), attempts, spaced repetition
/// schedule and mastery level.
class StudyRepository {
  StudyRepository(this.db, {SrsSettings srs = const SrsSettings()})
      : scheduler = SrsScheduler(srs);

  final Database db;
  SrsScheduler scheduler;
  static const MasteryCalculator mastery = MasteryCalculator();

  /// Study time per answer is capped so an idle screen does not inflate totals.
  static const int maxCountedDurationMs = 5 * 60 * 1000;

  void updateSrsSettings(SrsSettings s) => scheduler = SrsScheduler(s);

  Future<QuestionProgress> progressOf(String questionId, [DatabaseExecutor? ex]) async {
    final rows = await (ex ?? db)
        .query('progress', where: 'question_id = ?', whereArgs: [questionId]);
    return rows.isEmpty
        ? QuestionProgress(questionId: questionId, ease: scheduler.settings.startingEase)
        : QuestionProgress.fromRow(rows.first);
  }

  Future<Map<String, QuestionProgress>> progressFor(List<String> ids) async {
    final out = <String, QuestionProgress>{};
    for (var i = 0; i < ids.length; i += 500) {
      final chunk = ids.sublist(i, i + 500 > ids.length ? ids.length : i + 500);
      final rows = await db.rawQuery(
          'SELECT * FROM progress WHERE question_id IN ${sqlInList(chunk)}');
      for (final r in rows) {
        final p = QuestionProgress.fromRow(r);
        out[p.questionId] = p;
      }
    }
    return out;
  }

  Future<void> _save(DatabaseExecutor ex, QuestionProgress p) =>
      ex.insert('progress', p.toRow(), conflictAlgorithm: ConflictAlgorithm.replace);

  /// Marks a question as presented. After this it is no longer "new" and will
  /// not be selected again by New Questions mode (until the user resets it).
  Future<void> markPresented(String questionId,
      {String? sessionId, DatabaseExecutor? ex, DateTime? now}) async {
    final e = ex ?? db;
    final t = now ?? DateTime.now();
    final p = await progressOf(questionId, e);
    await _save(
      e,
      p.copyWith(
        seen: true,
        presentedCount: p.presentedCount + 1,
        firstPresentedAt: p.firstPresentedAt ?? t,
        lastPresentedAt: t,
      ),
    );
    await e.insert('presentations', {
      'id': newId(),
      'question_id': questionId,
      'session_id': sessionId,
      'presented_at': toMs(t),
    });
  }

  /// Applies one answer to the learning state and stores it in the attempt
  /// history. Must be called inside a transaction together with the session
  /// update so the two can never disagree.
  ///
  /// Scheduling rules:
  /// * a wrong answer always resets the schedule (review again tomorrow);
  /// * a correct answer to a question that is not scheduled yet starts the
  ///   schedule; to a question that is due (or overdue) it advances it;
  /// * a correct answer *before* the due date is recorded but does not push
  ///   the schedule further (prevents cramming from inflating intervals);
  /// * using a hint caps the grade at "Hard";
  /// * skipping is recorded but does not change the schedule.
  Future<AttemptOutcome> applyAttempt({
    required DatabaseExecutor ex,
    required Question question,
    required AttemptResult result,
    QuestionResponse? response,
    bool hintUsed = false,
    Confidence? confidence,
    int durationMs = 0,
    String? sessionId,
    String mode = 'quiz',
    DateTime? now,
  }) async {
    final t = now ?? DateTime.now();
    final p = await progressOf(question.id, ex);
    final before = p.mastery;
    final wasDue = p.dueAt != null && !p.dueAt!.isAfter(endOfDay(t));
    var next = p.copyWith(seen: true, firstPresentedAt: p.firstPresentedAt ?? t);

    if (result == AttemptResult.skipped) {
      next = next.copyWith(skippedCount: p.skippedCount + 1);
    } else if (result == AttemptResult.correct || result == AttemptResult.incorrect) {
      final correct = result == AttemptResult.correct;
      next = next.copyWith(
        attemptCount: p.attemptCount + 1,
        correctCount: p.correctCount + (correct ? 1 : 0),
        incorrectCount: p.incorrectCount + (correct ? 0 : 1),
        hintCount: p.hintCount + (hintUsed ? 1 : 0),
        consecutiveCorrect: correct ? p.consecutiveCorrect + 1 : 0,
        lastResult: result,
        lastAttemptAt: t,
        understood: correct ? p.understood : false,
      );

      var grade = SrsScheduler.gradeFor(correct: correct, confidence: confidence);
      if (hintUsed && (grade == ReviewGrade.good || grade == ReviewGrade.easy)) {
        grade = ReviewGrade.hard;
      }
      final scheduledEarly = p.dueAt != null && !wasDue;
      if (!(correct && scheduledEarly && grade != ReviewGrade.again)) {
        final s = scheduler.review(
          SrsState(
            ease: p.ease,
            intervalDays: p.intervalDays,
            repetitions: p.repetitions,
            lapses: p.lapses,
            dueAt: p.dueAt,
            lastReviewAt: p.lastReviewAt,
          ),
          grade,
          t,
        );
        next = next.copyWith(
          ease: s.ease,
          intervalDays: s.intervalDays,
          repetitions: s.repetitions,
          lapses: s.lapses,
          dueAt: s.dueAt,
          lastReviewAt: s.lastReviewAt,
        );
      }
    }

    final m = mastery.evaluate(next, t);
    next = next.copyWith(mastery: m.level, masteryReason: m.reason);
    await _save(ex, next);

    await ex.insert('attempts', {
      'id': newId(),
      'question_id': question.id,
      'session_id': sessionId,
      'answered_at': toMs(t),
      'result': result.key,
      'response': response?.encode(),
      'hint_used': hintUsed ? 1 : 0,
      'confidence': confidence?.index,
      'duration_ms': durationMs.clamp(0, maxCountedDurationMs),
      'mode': mode,
      'was_due': wasDue ? 1 : 0,
      'mastery_before': before.index,
      'mastery_after': next.mastery.index,
      'content_version': question.contentVersion,
    });
    return AttemptOutcome(next, before, wasDue);
  }

  /// Makes every question in [bankIds] eligible for New Questions mode again.
  /// Attempt history, statistics and schedules are untouched.
  Future<int> resetNewProgress(List<String> bankIds) => db.rawUpdate(
      'UPDATE progress SET seen = 0 WHERE question_id IN '
      '(SELECT id FROM questions WHERE bank_id IN ${sqlInList(bankIds)})');

  /// Erases learning progress (schedules, mastery, attempts, presentation
  /// history) for [bankIds], or for everything when null. Questions remain.
  Future<void> clearLearningProgress(List<String>? bankIds) async {
    final scope = bankIds == null
        ? ''
        : ' WHERE question_id IN (SELECT id FROM questions WHERE bank_id IN ${sqlInList(bankIds)})';
    await db.transaction((txn) async {
      await txn.rawDelete('DELETE FROM progress$scope');
      await txn.rawDelete('DELETE FROM attempts$scope');
      await txn.rawDelete('DELETE FROM presentations$scope');
    });
  }

  /// Resets the schedule/mastery of one question while keeping its history.
  Future<void> resetQuestionSchedule(String questionId) async {
    final p = await progressOf(questionId);
    final reset = p.copyWith(
      ease: scheduler.settings.startingEase,
      intervalDays: 0,
      repetitions: 0,
      lapses: 0,
      clearDue: true,
    );
    final m = mastery.evaluate(reset, DateTime.now());
    await _save(db, reset.copyWith(mastery: m.level, masteryReason: m.reason));
  }

  Future<void> setUnderstood(String questionId, bool value) async {
    await db.rawUpdate('UPDATE progress SET understood = ? WHERE question_id = ?',
        [value ? 1 : 0, questionId]);
  }

  /// Re-evaluates mastery for questions whose review is overdue so that levels
  /// move backwards when retention may be declining. Run on app start.
  Future<int> refreshDecay({DateTime? now}) async {
    final t = now ?? DateTime.now();
    final rows = await db.rawQuery(
        'SELECT * FROM progress WHERE due_at IS NOT NULL AND due_at < ? AND mastery >= 2 LIMIT 5000',
        [toMs(addDays(startOfDay(t), -3))]);
    var changed = 0;
    await db.transaction((txn) async {
      for (final r in rows) {
        final p = QuestionProgress.fromRow(r);
        final m = mastery.evaluate(p, t);
        if (m.level != p.mastery || m.reason != p.masteryReason) {
          await txn.update('progress', {'mastery': m.level.index, 'mastery_reason': m.reason},
              where: 'question_id = ?', whereArgs: [p.questionId]);
          changed++;
        }
      }
    });
    return changed;
  }

  /// Mistakes Notebook entries.
  Future<List<MistakeEntry>> mistakes({
    List<String>? bankIds,
    bool repeatedOnly = false,
    bool includeUnderstood = false,
    bool bookmarkedOnly = false,
    bool lastAttemptWrongOnly = false,
    int limit = 100,
    int offset = 0,
  }) async {
    final where = <String>['p.incorrect_count > 0', 'q.archived = 0'];
    if (bankIds != null) where.add('q.bank_id IN ${sqlInList(bankIds)}');
    if (repeatedOnly) where.add('p.incorrect_count >= 2');
    if (!includeUnderstood) where.add('p.understood = 0');
    if (bookmarkedOnly) where.add('bm.question_id IS NOT NULL');
    if (lastAttemptWrongOnly) where.add("p.last_result = 'incorrect'");
    final rows = await db.rawQuery('''
SELECT p.*, CASE WHEN bm.question_id IS NULL THEN 0 ELSE 1 END AS bookmarked,
  (SELECT a.response FROM attempts a WHERE a.question_id = p.question_id AND a.result = 'incorrect'
     ORDER BY a.answered_at DESC LIMIT 1) AS wrong_response,
  (SELECT MAX(a.answered_at) FROM attempts a WHERE a.question_id = p.question_id AND a.result = 'incorrect') AS wrong_at
FROM progress p
JOIN questions q ON q.id = p.question_id
LEFT JOIN bookmarks bm ON bm.question_id = p.question_id
WHERE ${where.join(' AND ')}
ORDER BY wrong_at DESC
LIMIT ? OFFSET ?''', [limit, offset]);
    return rows
        .map((r) => MistakeEntry(
              progress: QuestionProgress.fromRow(r),
              lastWrongResponse: QuestionResponse.decode(r['wrong_response'] as String?),
              lastWrongAt: fromMs(r['wrong_at']),
              bookmarked: intOf(r['bookmarked']) == 1,
            ))
        .toList();
  }

  Future<int> mistakeCount({List<String>? bankIds, bool repeatedOnly = false}) async {
    final rows = await db.rawQuery('''
SELECT COUNT(*) AS n FROM progress p JOIN questions q ON q.id = p.question_id
WHERE p.incorrect_count > 0 AND p.understood = 0 AND q.archived = 0
${repeatedOnly ? 'AND p.incorrect_count >= 2' : ''}
${bankIds != null ? 'AND q.bank_id IN ${sqlInList(bankIds)}' : ''}''');
    return intOf(rows.first['n']);
  }

  /// Attempt history of one question, newest first.
  Future<List<Map<String, Object?>>> attemptsOf(String questionId, {int limit = 50}) =>
      db.query('attempts',
          where: 'question_id = ?',
          whereArgs: [questionId],
          orderBy: 'answered_at DESC',
          limit: limit);
}
