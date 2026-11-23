import 'dart:math' as math;

import 'package:sqflite_common/sqlite_api.dart';

import '../core/dates.dart';
import '../core/ids.dart';
import '../core/models.dart';
import 'catalog_repository.dart';
import 'db.dart';

/// Activity of one local calendar day, aggregated from the attempt history.
class DayActivity {
  DayActivity({
    required this.day,
    this.answered = 0,
    this.correct = 0,
    this.incorrect = 0,
    this.skipped = 0,
    this.reviews = 0,
    this.studyMs = 0,
    this.masteredNew = 0,
  });
  final DateTime day;

  /// Graded answers (correct + incorrect).
  final int answered;
  final int correct;
  final int incorrect;
  final int skipped;

  /// Answers to questions that were due for spaced-repetition review.
  final int reviews;
  final int studyMs;

  /// Questions that reached "Mastered" on this day.
  final int masteredNew;

  double? get accuracy => answered == 0 ? null : correct / answered;
}

/// Home dashboard figures. Definitions:
/// * totalQuestions — non-archived questions in non-archived banks;
/// * uniqueAttempted — questions answered at least once;
/// * totalAttempts — every graded answer ever submitted;
/// * accuracy — correct ÷ (correct + incorrect) over all graded answers;
/// * dueToday — scheduled reviews due by the end of today (incl. overdue);
/// * streak — consecutive days with at least one graded answer, ending today
///   (or yesterday, if nothing has been studied yet today).
class DashboardStats {
  DashboardStats({
    required this.totalQuestions,
    required this.uniqueAttempted,
    required this.totalAttempts,
    required this.mastered,
    required this.needsReview,
    required this.dueToday,
    required this.overdue,
    required this.dueTomorrow,
    required this.dueThisWeek,
    required this.accuracy,
    required this.studyMs,
    required this.completedQuizzes,
    required this.currentStreak,
    required this.longestStreak,
    required this.today,
  });
  final int totalQuestions;
  final int uniqueAttempted;
  final int totalAttempts;
  final int mastered;
  final int needsReview;
  final int dueToday;
  final int overdue;
  final int dueTomorrow;
  final int dueThisWeek;
  final double? accuracy;
  final int studyMs;
  final int completedQuizzes;
  final int currentStreak;
  final int longestStreak;
  final DayActivity today;
}

class SubjectProgress {
  SubjectProgress(this.subject, this.total, this.mastered, this.attempted, this.answered);
  final Category subject;
  final int total;
  final int mastered;
  final int attempted;

  /// Graded answers given in this subject (all time).
  final int answered;

  /// Mastered ÷ total questions in the subject.
  double get masteredFraction => total == 0 ? 0 : mastered / total;
}

class WeakTopic {
  WeakTopic(this.bankId, this.bankName, this.correct, this.incorrect);
  final String bankId;
  final String bankName;
  final int correct;
  final int incorrect;
  double get accuracy => correct + incorrect == 0 ? 0 : correct / (correct + incorrect);
}

enum RecommendationAction { reviewDue, reviewOverdue, repeatedMistakes, practiceBanks, learnNew, quickQuiz }

class Recommendation {
  Recommendation(this.message, this.action, this.actionLabel, {this.bankIds = const [], this.priority = 0});
  final String message;
  final RecommendationAction action;
  final String actionLabel;
  final List<String> bankIds;
  final int priority;
}

enum GoalType {
  questions('questions', 'Answer questions', 'questions'),
  minutes('minutes', 'Study time', 'minutes'),
  reviews('reviews', 'Spaced repetition reviews', 'reviews'),
  mastered('mastered', 'Master new questions', 'questions mastered');

  const GoalType(this.key, this.label, this.unit);
  final String key;
  final String label;
  final String unit;

  static GoalType fromKey(String? k) =>
      values.firstWhere((g) => g.key == k, orElse: () => GoalType.questions);
}

class StudyGoal {
  StudyGoal({required this.id, required this.type, required this.target, this.categoryId, this.active = true});
  final String id;
  final GoalType type;
  final int target;
  final String? categoryId;
  final bool active;

  factory StudyGoal.fromRow(Map<String, Object?> r) => StudyGoal(
        id: r['id'] as String,
        type: GoalType.fromKey(r['type'] as String?),
        target: intOf(r['target']),
        categoryId: r['category_id'] as String?,
        active: intOf(r['active']) == 1,
      );
}

class GoalProgress {
  GoalProgress(this.goal, this.categoryName, this.today, this.week, this.daysMetThisWeek,
      this.currentStreak, this.longestStreak);
  final StudyGoal goal;
  final String? categoryName;
  final int today;
  final int week;
  final int daysMetThisWeek;
  final int currentStreak;
  final int longestStreak;

  double get todayFraction => goal.target <= 0 ? 1 : math.min(1, today / goal.target);
  int get weekTarget => goal.target * 7;
  double get weekFraction => weekTarget <= 0 ? 1 : math.min(1, week / weekTarget);
  bool get metToday => today >= goal.target;

  String get title {
    final scope = categoryName == null ? '' : ' — $categoryName';
    return '${goal.type.label}: ${goal.target} ${goal.type.unit} a day$scope';
  }
}

class AchievementDef {
  const AchievementDef(this.id, this.title, this.description);
  final String id;
  final String title;
  final String description;
}

const List<AchievementDef> achievementDefs = [
  AchievementDef('first_steps', 'First Steps', 'Complete your first quiz.'),
  AchievementDef('getting_started', 'Getting Started', 'Answer 100 questions.'),
  AchievementDef('dedicated', 'Dedicated Learner', 'Answer 1,000 questions.'),
  AchievementDef('consistency', 'Consistency Champion', 'Maintain a seven-day study streak.'),
  AchievementDef('marathon', 'Marathon Learner', 'Maintain a thirty-day study streak.'),
  AchievementDef('knowledge_builder', 'Knowledge Builder', 'Master 100 questions.'),
  AchievementDef('perfect_score', 'Perfect Score', 'Complete a quiz of at least 5 questions with 100% accuracy.'),
  AchievementDef('revision_expert', 'Revision Expert', 'Complete 500 scheduled reviews.'),
];

class StatsRepository {
  StatsRepository(this.db, this.catalog);
  final Database db;
  final CatalogRepository catalog;

  // ---------------- Bank / category statistics ----------------

  Future<LearningStats> statsFor(List<String>? bankIds, {DateTime? now}) async {
    final t = now ?? DateTime.now();
    final scope = bankIds == null
        ? 'q.bank_id IN (SELECT id FROM banks WHERE archived = 0)'
        : 'q.bank_id IN ${sqlInList(bankIds)}';
    final r = await db.rawQuery('''
SELECT COUNT(*) AS total,
  SUM(CASE WHEN COALESCE(p.attempt_count, 0) = 0 THEN 1 ELSE 0 END) AS never,
  SUM(CASE WHEN p.attempt_count > 0 THEN 1 ELSE 0 END) AS attempted,
  SUM(CASE WHEN p.attempt_count > 0 AND p.mastery IN (1, 2) THEN 1 ELSE 0 END) AS needs,
  SUM(COALESCE(p.correct_count, 0)) AS correct,
  SUM(COALESCE(p.incorrect_count, 0)) AS incorrect,
  SUM(CASE WHEN p.due_at IS NOT NULL AND p.due_at <= ? THEN 1 ELSE 0 END) AS due,
  SUM(CASE WHEN p.due_at IS NOT NULL AND p.due_at < ? THEN 1 ELSE 0 END) AS overdue,
  SUM(CASE WHEN COALESCE(p.seen, 0) = 0 THEN 1 ELSE 0 END) AS unseen,
  SUM(CASE WHEN COALESCE(p.mastery, 0) = 0 THEN 1 ELSE 0 END) AS l0,
  SUM(CASE WHEN p.mastery = 1 THEN 1 ELSE 0 END) AS l1,
  SUM(CASE WHEN p.mastery = 2 THEN 1 ELSE 0 END) AS l2,
  SUM(CASE WHEN p.mastery = 3 THEN 1 ELSE 0 END) AS l3,
  SUM(CASE WHEN p.mastery = 4 THEN 1 ELSE 0 END) AS l4
FROM questions q LEFT JOIN progress p ON p.question_id = q.id
WHERE q.archived = 0 AND $scope''', [toMs(endOfDay(t)), toMs(startOfDay(t))]);
    final m = r.first;
    return LearningStats(
      total: intOf(m['total']),
      neverAttempted: intOf(m['never']),
      attempted: intOf(m['attempted']),
      mastered: intOf(m['l4']),
      needsReview: intOf(m['needs']),
      correct: intOf(m['correct']),
      incorrect: intOf(m['incorrect']),
      dueToday: intOf(m['due']),
      overdue: intOf(m['overdue']),
      unseen: intOf(m['unseen']),
      byLevel: {
        MasteryLevel.notLearned: intOf(m['l0']),
        MasteryLevel.learning: intOf(m['l1']),
        MasteryLevel.needsPractice: intOf(m['l2']),
        MasteryLevel.wellLearned: intOf(m['l3']),
        MasteryLevel.mastered: intOf(m['l4']),
      },
    );
  }

  Future<LearningStats> statsForCategory(String categoryId) async =>
      statsFor(await catalog.bankIdsUnder(categoryId));

  // ---------------- Activity ----------------

  Future<List<DayActivity>> dailyActivity(DateTime from, DateTime to, {List<String>? bankIds}) async {
    final scope = bankIds == null
        ? ''
        : 'AND question_id IN (SELECT id FROM questions WHERE bank_id IN ${sqlInList(bankIds)})';
    final rows = await db.rawQuery('''
SELECT date(answered_at / 1000, 'unixepoch', 'localtime') AS d,
  SUM(CASE WHEN result IN ('correct','incorrect') THEN 1 ELSE 0 END) AS n,
  SUM(CASE WHEN result = 'correct' THEN 1 ELSE 0 END) AS c,
  SUM(CASE WHEN result = 'incorrect' THEN 1 ELSE 0 END) AS i,
  SUM(CASE WHEN result = 'skipped' THEN 1 ELSE 0 END) AS s,
  SUM(CASE WHEN was_due = 1 AND result IN ('correct','incorrect') THEN 1 ELSE 0 END) AS r,
  SUM(duration_ms) AS ms,
  SUM(CASE WHEN mastery_after = 4 AND mastery_before < 4 THEN 1 ELSE 0 END) AS m
FROM attempts
WHERE answered_at >= ? AND answered_at <= ? $scope
GROUP BY d ORDER BY d''', [toMs(startOfDay(from)), toMs(endOfDay(to))]);
    final byDay = <String, DayActivity>{};
    for (final r in rows) {
      final key = r['d'] as String?;
      if (key == null) continue;
      byDay[key] = DayActivity(
        day: parseDayKey(key),
        answered: intOf(r['n']),
        correct: intOf(r['c']),
        incorrect: intOf(r['i']),
        skipped: intOf(r['s']),
        reviews: intOf(r['r']),
        studyMs: intOf(r['ms']),
        masteredNew: intOf(r['m']),
      );
    }
    // Fill missing days with zeros so charts have a continuous axis.
    final out = <DayActivity>[];
    final days = calendarDaysBetween(from, to);
    for (var i = 0; i <= days; i++) {
      final d = addDays(startOfDay(from), i);
      out.add(byDay[dayKey(d)] ?? DayActivity(day: d));
    }
    return out;
  }

  /// All local days that have at least one graded answer, ascending.
  Future<List<DateTime>> activeDays() async {
    final rows = await db.rawQuery('''
SELECT DISTINCT date(answered_at / 1000, 'unixepoch', 'localtime') AS d FROM attempts
WHERE result IN ('correct','incorrect') ORDER BY d''');
    return rows.map((r) => r['d'] as String?).whereType<String>().map(parseDayKey).toList();
  }

  /// (current, longest) streak from ascending active days.
  static (int, int) streaks(List<DateTime> days, DateTime now) {
    if (days.isEmpty) return (0, 0);
    final keys = days.map(dayKey).toSet();
    var longest = 0;
    var run = 0;
    DateTime? prev;
    for (final d in days) {
      if (prev != null && calendarDaysBetween(prev, d) == 1) {
        run++;
      } else {
        run = 1;
      }
      longest = math.max(longest, run);
      prev = d;
    }
    var cursor = startOfDay(now);
    if (!keys.contains(dayKey(cursor))) cursor = addDays(cursor, -1);
    var current = 0;
    while (keys.contains(dayKey(cursor))) {
      current++;
      cursor = addDays(cursor, -1);
    }
    return (current, longest);
  }

  Future<DashboardStats> dashboard({DateTime? now}) async {
    final t = now ?? DateTime.now();
    final s = await statsFor(null, now: t);
    final endTomorrow = toMs(endOfDay(addDays(t, 1)));
    final endWeek = toMs(endOfDay(addDays(t, 7)));
    final due = await db.rawQuery('''
SELECT
  SUM(CASE WHEN p.due_at > ? AND p.due_at <= ? THEN 1 ELSE 0 END) AS tomorrow,
  SUM(CASE WHEN p.due_at > ? AND p.due_at <= ? THEN 1 ELSE 0 END) AS week
FROM progress p JOIN questions q ON q.id = p.question_id
JOIN banks b ON b.id = q.bank_id
WHERE q.archived = 0 AND b.archived = 0''', [toMs(endOfDay(t)), endTomorrow, toMs(endOfDay(t)), endWeek]);
    final totals = await db.rawQuery('''
SELECT SUM(CASE WHEN result IN ('correct','incorrect') THEN 1 ELSE 0 END) AS n,
  SUM(duration_ms) AS ms FROM attempts''');
    final quizzes = await db.rawQuery("SELECT COUNT(*) AS n FROM sessions WHERE status = 'completed'");
    final (current, longest) = streaks(await activeDays(), t);
    final today = (await dailyActivity(t, t)).first;
    return DashboardStats(
      totalQuestions: s.total,
      uniqueAttempted: s.attempted,
      totalAttempts: intOf(totals.first['n']),
      mastered: s.mastered,
      needsReview: s.needsReview,
      dueToday: s.dueToday,
      overdue: s.overdue,
      dueTomorrow: intOf(due.first['tomorrow']),
      dueThisWeek: intOf(due.first['week']),
      accuracy: s.accuracy,
      studyMs: intOf(totals.first['ms']),
      completedQuizzes: intOf(quizzes.first['n']),
      currentStreak: current,
      longestStreak: longest,
      today: today,
    );
  }

  /// Reviews scheduled for each of the next [days] days (index 0 = tomorrow).
  Future<List<int>> upcomingReviews({int days = 14, DateTime? now}) async {
    final t = now ?? DateTime.now();
    final rows = await db.rawQuery('''
SELECT date(p.due_at / 1000, 'unixepoch', 'localtime') AS d, COUNT(*) AS n
FROM progress p JOIN questions q ON q.id = p.question_id
WHERE q.archived = 0 AND p.due_at > ? AND p.due_at <= ?
GROUP BY d''', [toMs(endOfDay(t)), toMs(endOfDay(addDays(t, days)))]);
    final by = {for (final r in rows) r['d'] as String: intOf(r['n'])};
    return [for (var i = 1; i <= days; i++) by[dayKey(addDays(t, i))] ?? 0];
  }

  // ---------------- Subjects & topics ----------------

  Future<List<SubjectProgress>> subjectProgress() async {
    final subjectOf = await catalog.subjectOfBanks();
    final rows = await db.rawQuery('''
SELECT q.bank_id, COUNT(*) AS total,
  SUM(CASE WHEN p.mastery = 4 THEN 1 ELSE 0 END) AS mastered,
  SUM(CASE WHEN p.attempt_count > 0 THEN 1 ELSE 0 END) AS attempted,
  SUM(COALESCE(p.correct_count, 0) + COALESCE(p.incorrect_count, 0)) AS answered
FROM questions q JOIN banks b ON b.id = q.bank_id LEFT JOIN progress p ON p.question_id = q.id
WHERE q.archived = 0 AND b.archived = 0 GROUP BY q.bank_id''');
    final agg = <String, List<int>>{};
    final subjects = <String, Category>{};
    for (final r in rows) {
      final s = subjectOf[r['bank_id']];
      if (s == null || s.archived) continue;
      subjects[s.id] = s;
      final a = agg.putIfAbsent(s.id, () => [0, 0, 0, 0]);
      a[0] += intOf(r['total']);
      a[1] += intOf(r['mastered']);
      a[2] += intOf(r['attempted']);
      a[3] += intOf(r['answered']);
    }
    final out = [
      for (final e in agg.entries)
        SubjectProgress(subjects[e.key]!, e.value[0], e.value[1], e.value[2], e.value[3])
    ];
    out.sort((a, b) => a.subject.sortOrder.compareTo(b.subject.sortOrder));
    return out;
  }

  /// Banks with the lowest accuracy (at least [minAnswers] graded answers and
  /// below [maxAccuracy]).
  Future<List<WeakTopic>> weakTopics({int limit = 5, int minAnswers = 5, double maxAccuracy = 0.85}) async {
    final rows = await db.rawQuery('''
SELECT q.bank_id, b.name AS bank_name, SUM(p.correct_count) AS c, SUM(p.incorrect_count) AS i
FROM progress p JOIN questions q ON q.id = p.question_id JOIN banks b ON b.id = q.bank_id
WHERE q.archived = 0 AND b.archived = 0
GROUP BY q.bank_id
HAVING (SUM(p.correct_count) + SUM(p.incorrect_count)) >= ?
ORDER BY (SUM(p.correct_count) * 1.0 / (SUM(p.correct_count) + SUM(p.incorrect_count))) ASC
LIMIT ?''', [minAnswers, limit * 2]);
    return rows
        .map((r) => WeakTopic(r['bank_id'] as String, (r['bank_name'] ?? '') as String,
            intOf(r['c']), intOf(r['i'])))
        .where((w) => w.accuracy < maxAccuracy)
        .take(limit)
        .toList();
  }

  /// Graded answers per bank in [from]..[to]: bank id -> (correct, incorrect).
  Future<Map<String, (int, int)>> bankAccuracyBetween(DateTime from, DateTime to) async {
    final rows = await db.rawQuery('''
SELECT q.bank_id,
  SUM(CASE WHEN a.result = 'correct' THEN 1 ELSE 0 END) AS c,
  SUM(CASE WHEN a.result = 'incorrect' THEN 1 ELSE 0 END) AS i
FROM attempts a JOIN questions q ON q.id = a.question_id
WHERE a.answered_at >= ? AND a.answered_at <= ? GROUP BY q.bank_id''', [toMs(from), toMs(to)]);
    return {for (final r in rows) r['bank_id'] as String: (intOf(r['c']), intOf(r['i']))};
  }

  /// Answers per subject between two dates (for the per-subject chart).
  Future<Map<String, int>> answeredBySubject(DateTime from, DateTime to) async {
    final subjectOf = await catalog.subjectOfBanks();
    final rows = await db.rawQuery('''
SELECT q.bank_id, COUNT(*) AS n FROM attempts a JOIN questions q ON q.id = a.question_id
WHERE a.result IN ('correct','incorrect') AND a.answered_at >= ? AND a.answered_at <= ?
GROUP BY q.bank_id''', [toMs(startOfDay(from)), toMs(endOfDay(to))]);
    final out = <String, int>{};
    for (final r in rows) {
      final s = subjectOf[r['bank_id']];
      if (s == null) continue;
      out[s.name] = (out[s.name] ?? 0) + intOf(r['n']);
    }
    return out;
  }

  // ---------------- Recommendations ----------------

  /// Offline study suggestions computed from the stored history.
  Future<List<Recommendation>> recommendations({DateTime? now}) async {
    final t = now ?? DateTime.now();
    final out = <Recommendation>[];
    final s = await statsFor(null, now: t);
    if (s.total == 0) return out;
    if (s.overdue > 0) {
      out.add(Recommendation(
          '${s.overdue} ${_q(s.overdue)} ${s.overdue == 1 ? 'is' : 'are'} overdue for review.',
          RecommendationAction.reviewOverdue, 'Review Overdue Questions', priority: 100));
    } else if (s.dueToday > 0) {
      out.add(Recommendation('You have ${s.dueToday} ${_q(s.dueToday)} due for review.',
          RecommendationAction.reviewDue, 'Review Now', priority: 90));
    }
    final rep = await db.rawQuery('''
SELECT COUNT(*) AS n FROM progress p JOIN questions q ON q.id = p.question_id
WHERE q.archived = 0 AND p.incorrect_count >= 2 AND p.last_result = 'incorrect' AND p.understood = 0''');
    final repeated = intOf(rep.first['n']);
    if (repeated > 0) {
      out.add(Recommendation(
          'You have $repeated ${_q(repeated)} that you repeatedly answered incorrectly.',
          RecommendationAction.repeatedMistakes, 'Practice Mistakes', priority: 80));
    }

    // Declining accuracy: last 7 days vs the 30 days before.
    final banks = {for (final b in await catalog.allBanks()) b.id: b};
    final recent = await bankAccuracyBetween(t.subtract(const Duration(days: 7)), t);
    final before = await bankAccuracyBetween(
        t.subtract(const Duration(days: 37)), t.subtract(const Duration(days: 7)));
    for (final e in recent.entries) {
      final b = before[e.key];
      final (rc, ri) = e.value;
      if (b == null || rc + ri < 5) continue;
      final (bc, bi) = b;
      if (bc + bi < 5) continue;
      final ra = rc / (rc + ri);
      final ba = bc / (bc + bi);
      if (ba - ra >= 0.10 && banks[e.key] != null) {
        out.add(Recommendation(
            'Your accuracy in ${banks[e.key]!.name} has decreased '
            '(${(ba * 100).round()}% → ${(ra * 100).round()}%).',
            RecommendationAction.practiceBanks, 'Practice Weak Topics',
            bankIds: [e.key], priority: 70));
      }
    }

    // Subjects not studied recently.
    final subjectOf = await catalog.subjectOfBanks();
    final last = await db.rawQuery('''
SELECT q.bank_id, MAX(a.answered_at) AS last FROM attempts a JOIN questions q ON q.id = a.question_id
GROUP BY q.bank_id''');
    final lastBySubject = <String, int>{};
    final banksBySubject = <String, List<String>>{};
    for (final r in last) {
      final sub = subjectOf[r['bank_id']];
      if (sub == null || sub.archived) continue;
      final v = intOf(r['last']);
      lastBySubject[sub.id] = math.max(lastBySubject[sub.id] ?? 0, v);
    }
    for (final e in subjectOf.entries) {
      banksBySubject.putIfAbsent(e.value.id, () => []).add(e.key);
    }
    for (final e in lastBySubject.entries) {
      final days = calendarDaysBetween(DateTime.fromMillisecondsSinceEpoch(e.value), t);
      if (days >= 7) {
        final name = subjectOf.values.firstWhere((c) => c.id == e.key).name;
        out.add(Recommendation("You haven't studied $name in $days days.",
            RecommendationAction.practiceBanks, 'Complete a Quick Quiz',
            bankIds: banksBySubject[e.key] ?? [], priority: 50 + math.min(days, 30)));
      }
    }

    if (s.unseen > 0 && out.length < 4) {
      out.add(Recommendation('${s.unseen} ${_q(s.unseen)} ${s.unseen == 1 ? 'is' : 'are'} waiting to be learned.',
          RecommendationAction.learnNew, 'Learn New Questions', priority: 30));
    }
    final weak = await weakTopics(limit: 3);
    if (weak.isNotEmpty && !out.any((r) => r.action == RecommendationAction.practiceBanks)) {
      out.add(Recommendation(
          'Weakest topic: ${weak.first.bankName} (${(weak.first.accuracy * 100).round()}% accuracy).',
          RecommendationAction.practiceBanks, 'Practice Weak Topics',
          bankIds: weak.map((w) => w.bankId).toList(), priority: 40));
    }
    out.sort((a, b) => b.priority.compareTo(a.priority));
    return out.take(5).toList();
  }

  static String _q(int n) => n == 1 ? 'question' : 'questions';

  // ---------------- Goals ----------------

  Future<List<StudyGoal>> goals({bool activeOnly = true}) async {
    final rows = await db.query('goals',
        where: activeOnly ? 'active = 1' : null, orderBy: 'created_at');
    return rows.map(StudyGoal.fromRow).toList();
  }

  Future<StudyGoal> addGoal(GoalType type, int target, {String? categoryId}) async {
    final g = StudyGoal(id: newId(), type: type, target: target, categoryId: categoryId);
    await db.insert('goals', {
      'id': g.id,
      'type': type.key,
      'target': target,
      'category_id': categoryId,
      'active': 1,
      'created_at': toMs(DateTime.now()),
    });
    return g;
  }

  Future<void> updateGoalTarget(String id, int target) =>
      db.update('goals', {'target': target}, where: 'id = ?', whereArgs: [id]);

  Future<void> deleteGoal(String id) => db.delete('goals', where: 'id = ?', whereArgs: [id]);

  static int goalValue(GoalType type, DayActivity d) {
    switch (type) {
      case GoalType.questions:
        return d.answered;
      case GoalType.minutes:
        return d.studyMs ~/ 60000;
      case GoalType.reviews:
        return d.reviews;
      case GoalType.mastered:
        return d.masteredNew;
    }
  }

  Future<List<GoalProgress>> goalProgress({DateTime? now}) async {
    final t = now ?? DateTime.now();
    final out = <GoalProgress>[];
    final from = addDays(t, -365);
    final weekStart = startOfWeek(t);
    for (final g in await goals()) {
      List<String>? banks;
      String? catName;
      if (g.categoryId != null) {
        banks = await catalog.bankIdsUnder(g.categoryId!);
        catName = (await catalog.category(g.categoryId!))?.name;
      }
      final days = await dailyActivity(from, t, bankIds: banks);
      final values = days.map((d) => goalValue(g.type, d)).toList();
      final today = values.last;
      var week = 0;
      var metWeek = 0;
      for (var i = 0; i < days.length; i++) {
        if (!days[i].day.isBefore(weekStart)) {
          week += values[i];
          if (values[i] >= g.target) metWeek++;
        }
      }
      var longest = 0;
      var run = 0;
      for (final v in values) {
        run = v >= g.target ? run + 1 : 0;
        longest = math.max(longest, run);
      }
      var current = 0;
      var i = values.length - 1;
      if (i >= 0 && values[i] < g.target) i--; // today not finished yet
      while (i >= 0 && values[i] >= g.target) {
        current++;
        i--;
      }
      out.add(GoalProgress(g, catName, today, week, metWeek, current, longest));
    }
    return out;
  }

  // ---------------- Achievements ----------------

  Future<Map<String, DateTime>> unlockedAchievements() async {
    final rows = await db.query('achievements');
    return {for (final r in rows) r['id'] as String: fromMs(r['unlocked_at'])!};
  }

  /// Unlocks any newly earned achievements and returns them.
  Future<List<AchievementDef>> checkAchievements({DateTime? now}) async {
    final t = now ?? DateTime.now();
    final unlocked = await unlockedAchievements();
    final r = await db.rawQuery('''
SELECT
  (SELECT COUNT(*) FROM sessions WHERE status = 'completed') AS quizzes,
  (SELECT COUNT(*) FROM attempts WHERE result IN ('correct','incorrect')) AS answers,
  (SELECT COUNT(*) FROM progress WHERE mastery = 4) AS mastered,
  (SELECT COUNT(*) FROM attempts WHERE was_due = 1 AND result IN ('correct','incorrect')) AS reviews,
  (SELECT COUNT(*) FROM sessions WHERE status = 'completed' AND total >= 5 AND correct = total) AS perfect''');
    final m = r.first;
    final (_, longest) = streaks(await activeDays(), t);
    final earned = <String>{
      if (intOf(m['quizzes']) >= 1) 'first_steps',
      if (intOf(m['answers']) >= 100) 'getting_started',
      if (intOf(m['answers']) >= 1000) 'dedicated',
      if (longest >= 7) 'consistency',
      if (longest >= 30) 'marathon',
      if (intOf(m['mastered']) >= 100) 'knowledge_builder',
      if (intOf(m['perfect']) >= 1) 'perfect_score',
      if (intOf(m['reviews']) >= 500) 'revision_expert',
    };
    final fresh = <AchievementDef>[];
    for (final def in achievementDefs) {
      if (earned.contains(def.id) && !unlocked.containsKey(def.id)) {
        await db.insert('achievements', {'id': def.id, 'unlocked_at': toMs(t)},
            conflictAlgorithm: ConflictAlgorithm.ignore);
        fresh.add(def);
      }
    }
    return fresh;
  }
}
