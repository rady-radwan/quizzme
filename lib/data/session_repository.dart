import 'dart:convert';
import 'dart:math';

import 'package:sqflite_common/sqlite_api.dart';

import '../core/dates.dart';
import '../core/distribution.dart';
import '../core/grading.dart';
import '../core/ids.dart';
import '../core/models.dart';
import '../core/shuffle.dart';
import 'catalog_repository.dart';
import 'db.dart';
import 'question_repository.dart';
import 'study_repository.dart';

class QuizSession {
  QuizSession.fromRow(Map<String, Object?> r)
      : id = r['id'] as String,
        title = r['title'] as String,
        config = QuizConfig.decode(r['config'] as String?),
        status = SessionStatus.fromKey(r['status'] as String?),
        createdAt = fromMs(r['created_at']) ?? DateTime.now(),
        completedAt = fromMs(r['completed_at']),
        currentIndex = intOf(r['current_index']),
        elapsedMs = intOf(r['elapsed_ms']),
        total = intOf(r['total']),
        correct = intOf(r['correct']),
        incorrect = intOf(r['incorrect']),
        unanswered = intOf(r['unanswered']),
        score = r['score'] == null ? null : doubleOf(r['score']),
        scopeLabel = r['scope_label'] as String?;

  final String id;
  final String title;
  final QuizConfig config;
  final SessionStatus status;
  final DateTime createdAt;
  final DateTime? completedAt;
  final int currentIndex;
  final int elapsedMs;
  final int total;
  final int correct;
  final int incorrect;
  final int unanswered;

  /// Percentage of all questions answered correctly (0–100).
  final double? score;
  final String? scopeLabel;

  /// Correct among answered questions.
  double? get accuracy =>
      correct + incorrect == 0 ? null : correct / (correct + incorrect);
}

class SessionItem {
  SessionItem.fromRow(Map<String, Object?> r)
      : sessionId = r['session_id'] as String,
        position = intOf(r['position']),
        questionId = r['question_id'] as String,
        optionOrder = decodeStringList(r['option_order']),
        response = QuestionResponse.decode(r['response'] as String?),
        result = AttemptResult.fromKey(r['result'] as String?),
        applied = intOf(r['applied']) == 1,
        hintUsed = intOf(r['hint_used']) == 1,
        confidence = Confidence.fromIndex(r['confidence'] == null ? null : intOf(r['confidence'])),
        presentedAt = fromMs(r['presented_at']),
        answeredAt = fromMs(r['answered_at']),
        durationMs = intOf(r['duration_ms']),
        masteryAfter = r['mastery_after'] == null
            ? null
            : MasteryLevel.fromIndex(intOf(r['mastery_after']));

  final String sessionId;
  final int position;
  final String questionId;
  final List<String> optionOrder;
  final QuestionResponse response;
  final AttemptResult? result;
  final bool applied;
  final bool hintUsed;
  final Confidence? confidence;
  final DateTime? presentedAt;
  final DateTime? answeredAt;
  final int durationMs;
  final MasteryLevel? masteryAfter;

  bool get answered => result != null && result != AttemptResult.skipped;
}

/// What a quiz configuration would select, shown before starting.
class SelectionPreview {
  SelectionPreview({
    required this.bankIds,
    required this.availableByBank,
    required this.plan,
    this.adaptiveTarget,
  });
  final List<String> bankIds;
  final Map<String, int> availableByBank;
  final DistributionPlan plan;

  /// Preferred difficulty indexes when adaptive difficulty is on.
  final List<int>? adaptiveTarget;

  int get available => availableByBank.values.fold(0, (a, b) => a + b);
}

class InsufficientQuestionsException implements Exception {
  InsufficientQuestionsException(this.available, this.requested);
  final int available;
  final int requested;
  @override
  String toString() => available == 0
      ? 'No questions match your selected criteria.'
      : 'Only $available questions match your selected criteria.';
}

class SessionRepository {
  SessionRepository(this.db, this.catalog, this.questions, this.study, {Random? random})
      : _random = random ?? Random();

  final Database db;
  final CatalogRepository catalog;
  final QuestionRepository questions;
  final StudyRepository study;
  final Random _random;

  // ---------------- Selection ----------------

  static const _from = '''
FROM questions q
JOIN banks b ON b.id = q.bank_id
LEFT JOIN progress p ON p.question_id = q.id''';

  /// WHERE clause for questions eligible under [c].
  (String, List<Object?>) _eligible(QuizConfig c, List<String> bankIds, DateTime now) {
    final w = <String>['q.archived = 0', 'b.archived = 0'];
    final args = <Object?>[];
    if (c.fixedQuestionIds.isNotEmpty) {
      w.add('q.id IN ${sqlInList(c.fixedQuestionIds)}');
      return (w.join(' AND '), args);
    }
    w.add('q.bank_id IN ${sqlInList(bankIds)}');
    final endToday = toMs(endOfDay(now));
    switch (c.selection) {
      case SelectionMode.newQuestions:
        w.add('COALESCE(p.seen, 0) = 0');
        // Questions waiting in another unfinished quiz are not "new" either.
        w.add("q.id NOT IN (SELECT sq.question_id FROM session_questions sq "
            "JOIN sessions s ON s.id = sq.session_id WHERE s.status = 'active')");
        break;
      case SelectionMode.review:
        w.add('COALESCE(p.attempt_count, 0) > 0');
        break;
      case SelectionMode.mistakes:
        w.add(c.mistakesLastOnly
            ? "p.last_result = 'incorrect'"
            : 'COALESCE(p.incorrect_count, 0) > 0');
        w.add('COALESCE(p.understood, 0) = 0');
        break;
      case SelectionMode.spaced:
        w.add('p.due_at IS NOT NULL AND p.due_at <= $endToday');
        break;
      case SelectionMode.random:
        if (!c.includeAttempted) w.add('COALESCE(p.attempt_count, 0) = 0');
        break;
      case SelectionMode.mastery:
        w.add("(p.last_result = 'correct' OR COALESCE(p.mastery, 0) >= ${MasteryLevel.wellLearned.index})");
        break;
      case SelectionMode.bookmarked:
        w.add('q.id IN (SELECT question_id FROM bookmarks)');
        break;
      case SelectionMode.quickReview:
        w.add('COALESCE(p.attempt_count, 0) > 0');
        break;
    }
    if (c.difficulties.isNotEmpty) {
      w.add('q.difficulty IN (${c.difficulties.map((d) => d.index).join(',')})');
    }
    if (c.masteryLevels.isNotEmpty) {
      w.add('COALESCE(p.mastery, 0) IN (${c.masteryLevels.map((m) => m.index).join(',')})');
    }
    return (w.join(' AND '), args);
  }

  String _order(QuizConfig c, DateTime now, List<int>? adaptive) {
    final endToday = toMs(endOfDay(now));
    final parts = <String>[];
    if (adaptive != null && adaptive.isNotEmpty) {
      parts.add('CASE WHEN q.difficulty IN (${adaptive.join(',')}) THEN 0 ELSE 1 END');
    }
    switch (c.selection) {
      case SelectionMode.spaced:
        parts.add('p.due_at ASC');
        break;
      case SelectionMode.quickReview:
        parts.add('CASE WHEN p.due_at IS NOT NULL AND p.due_at <= $endToday THEN 0 ELSE 1 END');
        parts.add('(COALESCE(p.incorrect_count, 0) * 1.0 / (COALESCE(p.attempt_count, 0) + 1)) DESC');
        break;
      case SelectionMode.mistakes:
        parts.add('COALESCE(p.incorrect_count, 0) DESC');
        break;
      default:
        break;
    }
    if (c.shuffleQuestions) {
      parts.add('RANDOM()');
    } else {
      parts.add('b.sort_order, q.created_at, q.rowid');
    }
    return parts.join(', ');
  }

  Future<List<String>> _scopeBanks(QuizConfig c) async {
    if (c.fixedQuestionIds.isNotEmpty) return const [];
    return catalog.resolveBankIds(
      bankIds: c.bankIds,
      categoryIds: c.categoryIds,
      excludedCategoryIds: c.excludedCategoryIds,
    );
  }

  /// Recent accuracy (last 50 graded answers) within the selected banks.
  Future<double?> recentAccuracy(List<String> bankIds) async {
    final rows = await db.rawQuery('''
SELECT a.result FROM attempts a JOIN questions q ON q.id = a.question_id
WHERE a.result IN ('correct','incorrect') ${bankIds.isEmpty ? '' : 'AND q.bank_id IN ${sqlInList(bankIds)}'}
ORDER BY a.answered_at DESC LIMIT 50''');
    if (rows.length < 5) return null;
    final c = rows.where((r) => r['result'] == 'correct').length;
    return c / rows.length;
  }

  Future<SelectionPreview> preview(QuizConfig c, {DateTime? now}) async {
    final t = now ?? DateTime.now();
    final banks = await _scopeBanks(c);
    final (where, args) = _eligible(c, banks, t);
    final rows = await db.rawQuery(
        'SELECT q.bank_id, COUNT(*) AS n $_from WHERE $where GROUP BY q.bank_id', args);
    final avail = <String, int>{for (final b in banks) b: 0};
    for (final r in rows) {
      avail[r['bank_id'] as String] = intOf(r['n']);
    }
    final requested = c.fixedQuestionIds.isNotEmpty
        ? min(c.questionCount, c.fixedQuestionIds.length)
        : c.questionCount;
    final plan = c.manualCounts.isNotEmpty && c.fixedQuestionIds.isEmpty
        ? planManual(avail, c.manualCounts)
        : planAutomatic(avail, requested);
    List<int>? adaptive;
    if (c.adaptiveDifficulty && c.difficulties.isEmpty) {
      adaptive = adaptiveDifficultyTarget(await recentAccuracy(banks));
    }
    return SelectionPreview(
        bankIds: banks, availableByBank: avail, plan: plan, adaptiveTarget: adaptive);
  }

  /// Selects questions and creates a persistent session. Throws
  /// [InsufficientQuestionsException] when fewer questions are available than
  /// requested and [allowFewer] is false — questions are never duplicated.
  Future<QuizSession> create(QuizConfig c, {bool allowFewer = false, DateTime? now}) async {
    final t = now ?? DateTime.now();
    final pv = await preview(c, now: t);
    final plan = pv.plan;
    if (plan.planned == 0) {
      throw InsufficientQuestionsException(0, plan.requested);
    }
    if (plan.isShort && !allowFewer) {
      throw InsufficientQuestionsException(plan.planned, plan.requested);
    }
    final (where, args) = _eligible(c, pv.bankIds, t);
    final order = _order(c, t, pv.adaptiveTarget);

    final ids = <String>[];
    if (c.fixedQuestionIds.isNotEmpty) {
      final rows = await db.rawQuery('SELECT q.id $_from WHERE $where', args);
      final eligible = rows.map((r) => r['id'] as String).toSet();
      final ordered = c.fixedQuestionIds.where(eligible.contains).toList();
      if (c.shuffleQuestions) ordered.shuffle(_random);
      ids.addAll(ordered.take(plan.planned));
    } else {
      for (final e in plan.allocation.entries) {
        if (e.value <= 0) continue;
        final rows = await db.rawQuery(
            'SELECT q.id $_from WHERE $where AND q.bank_id = ? ORDER BY $order LIMIT ?',
            [...args, e.key, e.value]);
        ids.addAll(rows.map((r) => r['id'] as String));
      }
      final priorityOrder = c.selection == SelectionMode.spaced ||
          c.selection == SelectionMode.quickReview ||
          (pv.adaptiveTarget != null);
      if (c.shuffleQuestions && !priorityOrder) ids.shuffle(_random);
    }

    final qs = await questions.questionsByIds(ids);
    final session = {
      'id': newId(),
      'title': c.title,
      'config': c.encode(),
      'status': SessionStatus.active.key,
      'created_at': toMs(t),
      'current_index': 0,
      'elapsed_ms': 0,
      'total': qs.length,
      'correct': 0,
      'incorrect': 0,
      'unanswered': qs.length,
      'scope_label': c.title,
    };
    await db.transaction((txn) async {
      await txn.insert('sessions', session);
      for (var i = 0; i < qs.length; i++) {
        await txn.insert('session_questions', {
          'session_id': session['id'],
          'position': i,
          'question_id': qs[i].id,
          'option_order':
              jsonEncode(displayOrder(qs[i], shuffle: c.shuffleAnswers, random: _random)),
        });
      }
    });
    return (await this.session(session['id'] as String))!;
  }

  // ---------------- Reading ----------------

  Future<QuizSession?> session(String id) async {
    final rows = await db.query('sessions', where: 'id = ?', whereArgs: [id]);
    return rows.isEmpty ? null : QuizSession.fromRow(rows.first);
  }

  Future<List<SessionItem>> items(String sessionId) async {
    final rows = await db.query('session_questions',
        where: 'session_id = ?', whereArgs: [sessionId], orderBy: 'position');
    return rows.map(SessionItem.fromRow).toList();
  }

  Future<QuizSession?> latestActive() async {
    final rows = await db.query('sessions',
        where: 'status = ?',
        whereArgs: [SessionStatus.active.key],
        orderBy: 'created_at DESC',
        limit: 1);
    return rows.isEmpty ? null : QuizSession.fromRow(rows.first);
  }

  Future<List<QuizSession>> history({int limit = 50, int offset = 0, bool includeActive = false}) async {
    final rows = await db.query('sessions',
        where: includeActive ? null : 'status = ?',
        whereArgs: includeActive ? null : [SessionStatus.completed.key],
        orderBy: 'COALESCE(completed_at, created_at) DESC',
        limit: limit,
        offset: offset);
    return rows.map(QuizSession.fromRow).toList();
  }

  Future<int> completedCount() async {
    final r = await db.rawQuery(
        "SELECT COUNT(*) AS n FROM sessions WHERE status = 'completed'");
    return intOf(r.first['n']);
  }

  // ---------------- Writing ----------------

  /// Called when the question at [position] is displayed. The first display
  /// records the presentation (the question stops being "new").
  Future<void> markPresented(String sessionId, int position) async {
    await db.transaction((txn) async {
      final rows = await txn.query('session_questions',
          columns: ['question_id', 'presented_at'],
          where: 'session_id = ? AND position = ?',
          whereArgs: [sessionId, position]);
      if (rows.isEmpty || rows.first['presented_at'] != null) return;
      final now = DateTime.now();
      await txn.update('session_questions', {'presented_at': toMs(now)},
          where: 'session_id = ? AND position = ?', whereArgs: [sessionId, position]);
      await study.markPresented(rows.first['question_id'] as String,
          sessionId: sessionId, ex: txn, now: now);
    });
  }

  Future<void> saveCursor(String sessionId, int index, int elapsedMs) async {
    await db.update('sessions', {'current_index': index, 'elapsed_ms': elapsedMs},
        where: 'id = ?', whereArgs: [sessionId]);
  }

  /// Saves the learner's answer for one question. The result is computed and
  /// stored but not applied to the learning history yet ([finalizeItem] does
  /// that), so the answer survives an app restart. In end-of-quiz feedback mode
  /// the UI never displays this result before the quiz is submitted.
  Future<AttemptResult?> saveResponse({
    required String sessionId,
    required int position,
    required Question question,
    required QuestionResponse response,
    bool hintUsed = false,
    Confidence? confidence,
    int addDurationMs = 0,
  }) async {
    final outcome = grade(question, response);
    final AttemptResult? result = switch (outcome) {
      GradeOutcome.correct => AttemptResult.correct,
      GradeOutcome.incorrect => AttemptResult.incorrect,
      GradeOutcome.needsReview => AttemptResult.review,
      GradeOutcome.unanswered => null,
    };
    await db.rawUpdate('''
UPDATE session_questions SET response = ?, result = ?, hint_used = MAX(hint_used, ?),
  confidence = ?, answered_at = ?, duration_ms = duration_ms + ?
WHERE session_id = ? AND position = ? AND applied = 0''', [
      response.isEmpty ? null : response.encode(),
      result?.key,
      hintUsed ? 1 : 0,
      confidence?.index,
      result == null ? null : toMs(DateTime.now()),
      addDurationMs,
      sessionId,
      position,
    ]);
    return result;
  }

  Future<void> markHintUsed(String sessionId, int position) => db.rawUpdate(
      'UPDATE session_questions SET hint_used = 1 WHERE session_id = ? AND position = ?',
      [sessionId, position]);

  Future<void> setConfidence(String sessionId, int position, Confidence? c) => db.rawUpdate(
      'UPDATE session_questions SET confidence = ? WHERE session_id = ? AND position = ? AND applied = 0',
      [c?.index, sessionId, position]);

  /// Applies a saved answer to the learning history (attempt, schedule,
  /// mastery). Idempotent: an item is applied at most once.
  Future<AttemptOutcome?> finalizeItem(String sessionId, int position, Question q,
      {Confidence? confidence}) async {
    AttemptOutcome? out;
    await db.transaction((txn) async {
      out = await _finalize(txn, sessionId, position, q, confidence: confidence);
      await _recount(txn, sessionId);
    });
    return out;
  }

  Future<AttemptOutcome?> _finalize(Transaction txn, String sessionId, int position, Question q,
      {Confidence? confidence, bool skipIfUnanswered = false}) async {
    final rows = await txn.query('session_questions',
        where: 'session_id = ? AND position = ?', whereArgs: [sessionId, position]);
    if (rows.isEmpty) return null;
    final item = SessionItem.fromRow(rows.first);
    if (item.applied) return null;
    var result = item.result;
    if (result == null) {
      if (!skipIfUnanswered) return null;
      result = AttemptResult.skipped;
    }
    if (result == AttemptResult.review) return null; // waits for self-grading
    final s = await txn.query('sessions', columns: ['config'], where: 'id = ?', whereArgs: [sessionId]);
    final cfg = QuizConfig.decode(s.isEmpty ? null : s.first['config'] as String?);
    final conf = confidence ?? item.confidence;
    final outcome = await study.applyAttempt(
      ex: txn,
      question: q,
      result: result,
      response: item.response,
      hintUsed: item.hintUsed,
      confidence: conf,
      durationMs: item.durationMs,
      sessionId: sessionId,
      mode: '${cfg.selection.key}/${cfg.style.key}',
    );
    await txn.update(
      'session_questions',
      {
        'applied': 1,
        'result': result.key,
        'confidence': conf?.index,
        'mastery_after': outcome.masteryAfter.index,
        'answered_at': item.answeredAt == null ? toMs(DateTime.now()) : toMs(item.answeredAt!),
      },
      where: 'session_id = ? AND position = ?',
      whereArgs: [sessionId, position],
    );
    return outcome;
  }

  /// Flashcard review: the learner's own rating is the result, for any
  /// question type. "Didn't know" counts as forgotten; Hard/Medium/Easy as
  /// remembered with that confidence. Applied to the history immediately.
  Future<AttemptOutcome?> recordFlashcard(String sessionId, int position, Question q,
      {required Confidence rating, int durationMs = 0}) async {
    final remembered = rating != Confidence.didntKnow;
    await db.rawUpdate('''
UPDATE session_questions SET response = ?, result = ?, confidence = ?, answered_at = ?,
  duration_ms = duration_ms + ?
WHERE session_id = ? AND position = ? AND applied = 0''', [
      QuestionResponse(selfGrade: remembered).encode(),
      remembered ? AttemptResult.correct.key : AttemptResult.incorrect.key,
      rating.index,
      toMs(DateTime.now()),
      durationMs,
      sessionId,
      position,
    ]);
    return finalizeItem(sessionId, position, q, confidence: rating);
  }

  /// Manual review of a typed answer: the learner decides whether it was right.
  Future<AttemptOutcome?> resolveReview(
      String sessionId, int position, Question q, bool correct) async {
    AttemptOutcome? out;
    await db.transaction((txn) async {
      final rows = await txn.query('session_questions',
          where: 'session_id = ? AND position = ?', whereArgs: [sessionId, position]);
      if (rows.isEmpty) return;
      final item = SessionItem.fromRow(rows.first);
      if (item.applied) return;
      final resp = item.response.copyWith(selfGrade: correct);
      await txn.update(
        'session_questions',
        {
          'response': resp.encode(),
          'result': correct ? AttemptResult.correct.key : AttemptResult.incorrect.key,
        },
        where: 'session_id = ? AND position = ?',
        whereArgs: [sessionId, position],
      );
      final s = await txn.query('sessions', columns: ['status'], where: 'id = ?', whereArgs: [sessionId]);
      final completed = s.isNotEmpty && s.first['status'] == SessionStatus.completed.key;
      if (completed) {
        out = await _finalize(txn, sessionId, position, q);
      }
      await _recount(txn, sessionId);
    });
    return out;
  }

  /// Submits the quiz: unanswered questions are recorded as skipped and every
  /// saved answer is applied to the learning history.
  Future<QuizSession> complete(String sessionId, {int? elapsedMs}) async {
    final its = await items(sessionId);
    final qs = {for (final q in await questions.questionsByIds(its.map((i) => i.questionId).toList())) q.id: q};
    await db.transaction((txn) async {
      for (final it in its) {
        final q = qs[it.questionId];
        if (q == null) continue;
        await _finalize(txn, sessionId, it.position, q, skipIfUnanswered: true);
      }
      await txn.update(
        'sessions',
        {
          'status': SessionStatus.completed.key,
          'completed_at': toMs(DateTime.now()),
          if (elapsedMs != null) 'elapsed_ms': elapsedMs,
        },
        where: 'id = ?',
        whereArgs: [sessionId],
      );
      await _recount(txn, sessionId);
    });
    return (await session(sessionId))!;
  }

  Future<void> _recount(Transaction txn, String sessionId) async {
    final r = await txn.rawQuery('''
SELECT COUNT(*) AS total,
  SUM(CASE WHEN result = 'correct' THEN 1 ELSE 0 END) AS correct,
  SUM(CASE WHEN result = 'incorrect' THEN 1 ELSE 0 END) AS incorrect,
  SUM(CASE WHEN result IS NULL OR result IN ('skipped','review') THEN 1 ELSE 0 END) AS unanswered
FROM session_questions WHERE session_id = ?''', [sessionId]);
    final total = intOf(r.first['total']);
    final correct = intOf(r.first['correct']);
    await txn.update(
      'sessions',
      {
        'total': total,
        'correct': correct,
        'incorrect': intOf(r.first['incorrect']),
        'unanswered': intOf(r.first['unanswered']),
        'score': total == 0 ? 0.0 : correct * 100.0 / total,
      },
      where: 'id = ?',
      whereArgs: [sessionId],
    );
  }

  /// Abandons an unfinished quiz. Answers already applied stay in history;
  /// unapplied answers are discarded.
  Future<void> abandon(String sessionId) => db.update(
      'sessions', {'status': SessionStatus.abandoned.key},
      where: 'id = ?', whereArgs: [sessionId]);

  Future<void> deleteSession(String sessionId) =>
      db.delete('sessions', where: 'id = ?', whereArgs: [sessionId]);

  /// A new quiz with the same questions, as an explicit review (New Questions
  /// history is not affected — these questions were already presented).
  QuizConfig retakeConfig(QuizSession s, List<SessionItem> items, {bool mistakesOnly = false}) {
    final ids = items
        .where((i) => !mistakesOnly || i.result == AttemptResult.incorrect || i.result == AttemptResult.skipped)
        .map((i) => i.questionId)
        .toList();
    return s.config.copyWith(
      title: mistakesOnly ? '${s.title} — mistakes' : '${s.title} (retake)',
      selection: SelectionMode.review,
      fixedQuestionIds: ids,
      questionCount: ids.length,
      manualCounts: const {},
    );
  }
}
