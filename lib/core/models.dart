import 'dart:convert';

import 'dates.dart';

// ---------------------------------------------------------------------------
// Enumerations. Each has a stable string key that is stored in the database
// and in Excel files; never rename a key once released.
// ---------------------------------------------------------------------------

enum QuestionType {
  single('single', 'Multiple choice (one answer)'),
  multiple('multiple', 'Multiple choice (several answers)'),
  trueFalse('true_false', 'True or false'),
  fillBlank('fill_blank', 'Fill in the blank'),
  matching('matching', 'Matching'),
  shortAnswer('short_answer', 'Short written answer'),
  flashcard('flashcard', 'Flashcard');

  const QuestionType(this.key, this.label);
  final String key;
  final String label;

  bool get usesChoices =>
      this == single || this == multiple || this == trueFalse;
  bool get usesTypedAnswer => this == fillBlank || this == shortAnswer;

  static QuestionType fromKey(String? key) => QuestionType.values.firstWhere(
        (t) => t.key == key,
        orElse: () => QuestionType.single,
      );
}

enum Difficulty {
  easy('Easy'),
  medium('Medium'),
  hard('Hard'),
  expert('Expert');

  const Difficulty(this.label);
  final String label;

  static Difficulty fromIndex(int? i) =>
      (i != null && i >= 0 && i < values.length) ? values[i] : Difficulty.medium;

  /// Parses "Easy", "medium", "3", "Expert"... Returns null when unknown.
  static Difficulty? tryParse(String? s) {
    final v = (s ?? '').trim().toLowerCase();
    if (v.isEmpty) return null;
    for (final d in values) {
      if (d.label.toLowerCase() == v) return d;
    }
    final n = int.tryParse(v);
    if (n != null && n >= 1 && n <= 4) return values[n - 1];
    if (v == 'normal' || v == 'intermediate') return Difficulty.medium;
    if (v == 'beginner') return Difficulty.easy;
    if (v == 'advanced') return Difficulty.hard;
    return null;
  }
}

enum MasteryLevel {
  notLearned('Not Learned'),
  learning('Learning'),
  needsPractice('Needs Practice'),
  wellLearned('Well Learned'),
  mastered('Mastered');

  const MasteryLevel(this.label);
  final String label;

  static MasteryLevel fromIndex(int? i) =>
      (i != null && i >= 0 && i < values.length) ? values[i] : notLearned;
}

/// The self-rating offered after answering ("How well did you know it?").
enum Confidence {
  didntKnow("Didn't Know"),
  hard('Hard'),
  medium('Medium'),
  easy('Easy');

  const Confidence(this.label);
  final String label;

  static Confidence? fromIndex(int? i) =>
      (i != null && i >= 0 && i < values.length) ? values[i] : null;
}

enum AttemptResult {
  correct('correct'),
  incorrect('incorrect'),
  skipped('skipped'),

  /// A typed answer that did not match exactly and is waiting for the user's
  /// own judgement (manual review).
  review('review');

  const AttemptResult(this.key);
  final String key;

  static AttemptResult? fromKey(String? k) {
    for (final r in values) {
      if (r.key == k) return r;
    }
    return null;
  }
}

/// Which questions a quiz draws from.
enum SelectionMode {
  newQuestions('new', 'Learn New Questions', 'Only questions you have never seen'),
  review('review', 'Review Questions', 'Questions you have already attempted'),
  mistakes('mistakes', 'Mistakes Only', 'Questions you answered incorrectly'),
  spaced('spaced', 'Spaced Repetition', 'Questions scheduled for review today'),
  random('random', 'Random Quiz', 'Any questions from the selection'),
  mastery('mastery', 'Mastery Test', 'Questions you answered correctly before'),
  bookmarked('bookmarked', 'Bookmarked', 'Questions you bookmarked'),
  quickReview('quick', 'Quick Review', 'Due and most difficult questions first');

  const SelectionMode(this.key, this.label, this.description);
  final String key;
  final String label;
  final String description;

  static SelectionMode fromKey(String? k) =>
      values.firstWhere((m) => m.key == k, orElse: () => SelectionMode.random);
}

enum QuizStyle {
  practice('practice', 'Practice'),
  exam('exam', 'Exam'),
  flashcards('flashcards', 'Flashcards');

  const QuizStyle(this.key, this.label);
  final String key;
  final String label;

  static QuizStyle fromKey(String? k) =>
      values.firstWhere((m) => m.key == k, orElse: () => QuizStyle.practice);
}

enum FeedbackTiming {
  immediate('immediate', 'After each question'),
  endOfQuiz('end', 'At the end of the quiz');

  const FeedbackTiming(this.key, this.label);
  final String key;
  final String label;

  static FeedbackTiming fromKey(String? k) => values
      .firstWhere((m) => m.key == k, orElse: () => FeedbackTiming.immediate);
}

enum SessionStatus {
  active('active'),
  completed('completed'),
  abandoned('abandoned');

  const SessionStatus(this.key);
  final String key;

  static SessionStatus fromKey(String? k) =>
      values.firstWhere((m) => m.key == k, orElse: () => SessionStatus.active);
}

// ---------------------------------------------------------------------------
// Row helpers
// ---------------------------------------------------------------------------

bool _b(Object? v) => v == 1 || v == true || v == '1';
int _i(Object? v, [int d = 0]) =>
    v is int ? v : (v is num ? v.toInt() : int.tryParse('${v ?? ''}') ?? d);
double _d(Object? v, [double d = 0]) =>
    v is num ? v.toDouble() : double.tryParse('${v ?? ''}') ?? d;
String? _s(Object? v) => v?.toString();

List<String> decodeStringList(Object? v) {
  if (v == null) return const [];
  final s = v.toString();
  if (s.isEmpty) return const [];
  try {
    final d = jsonDecode(s);
    if (d is List) return d.map((e) => e.toString()).toList();
  } catch (_) {}
  return const [];
}

String encodeStringList(List<String> v) => jsonEncode(v);

/// Tags are stored as ",tag one,tag two," so that `LIKE '%,tag,%'` matches a
/// whole tag. Tags are trimmed and lower-cased for matching, display keeps it.
String encodeTags(List<String> tags) {
  final clean = tags.map((t) => t.trim()).where((t) => t.isNotEmpty).toList();
  if (clean.isEmpty) return '';
  return ',${clean.join(',')},';
}

List<String> decodeTags(Object? v) => (v?.toString() ?? '')
    .split(',')
    .map((t) => t.trim())
    .where((t) => t.isNotEmpty)
    .toList();

List<String> splitTagInput(String input) => input
    .split(RegExp(r'[,;#]'))
    .map((t) => t.trim())
    .where((t) => t.isNotEmpty)
    .toSet()
    .toList();

// ---------------------------------------------------------------------------
// Entities
// ---------------------------------------------------------------------------

/// A node in the subject tree. A category whose [parentId] is null is a
/// top-level Subject; any category can hold sub-categories and banks, so the
/// hierarchy can be as deep as needed.
class Category {
  Category({
    required this.id,
    required this.name,
    this.parentId,
    this.description,
    this.iconKey,
    this.color,
    this.sortOrder = 0,
    this.archived = false,
    DateTime? createdAt,
    DateTime? updatedAt,
  })  : createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  final String id;
  final String? parentId;
  final String name;
  final String? description;
  final String? iconKey;
  final int? color;
  final int sortOrder;
  final bool archived;
  final DateTime createdAt;
  final DateTime updatedAt;

  bool get isSubject => parentId == null;

  factory Category.fromRow(Map<String, Object?> r) => Category(
        id: r['id'] as String,
        parentId: _s(r['parent_id']),
        name: r['name'] as String,
        description: _s(r['description']),
        iconKey: _s(r['icon']),
        color: r['color'] == null ? null : _i(r['color']),
        sortOrder: _i(r['sort_order']),
        archived: _b(r['archived']),
        createdAt: fromMs(r['created_at']),
        updatedAt: fromMs(r['updated_at']),
      );

  Map<String, Object?> toRow() => {
        'id': id,
        'parent_id': parentId,
        'name': name,
        'description': description,
        'icon': iconKey,
        'color': color,
        'sort_order': sortOrder,
        'archived': archived ? 1 : 0,
        'created_at': toMs(createdAt),
        'updated_at': toMs(updatedAt),
      };

  Category copyWith({
    String? name,
    String? description,
    String? iconKey,
    int? color,
    bool? archived,
    String? parentId,
    bool clearParent = false,
  }) =>
      Category(
        id: id,
        parentId: clearParent ? null : (parentId ?? this.parentId),
        name: name ?? this.name,
        description: description ?? this.description,
        iconKey: iconKey ?? this.iconKey,
        color: color ?? this.color,
        sortOrder: sortOrder,
        archived: archived ?? this.archived,
        createdAt: createdAt,
        updatedAt: DateTime.now(),
      );
}

class QuestionBank {
  QuestionBank({
    required this.id,
    required this.categoryId,
    required this.name,
    this.description,
    this.iconKey,
    this.color,
    this.sortOrder = 0,
    this.archived = false,
    DateTime? createdAt,
    DateTime? updatedAt,
  })  : createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  final String id;
  final String categoryId;
  final String name;
  final String? description;
  final String? iconKey;
  final int? color;
  final int sortOrder;
  final bool archived;
  final DateTime createdAt;
  final DateTime updatedAt;

  factory QuestionBank.fromRow(Map<String, Object?> r) => QuestionBank(
        id: r['id'] as String,
        categoryId: r['category_id'] as String,
        name: r['name'] as String,
        description: _s(r['description']),
        iconKey: _s(r['icon']),
        color: r['color'] == null ? null : _i(r['color']),
        sortOrder: _i(r['sort_order']),
        archived: _b(r['archived']),
        createdAt: fromMs(r['created_at']),
        updatedAt: fromMs(r['updated_at']),
      );

  Map<String, Object?> toRow() => {
        'id': id,
        'category_id': categoryId,
        'name': name,
        'description': description,
        'icon': iconKey,
        'color': color,
        'sort_order': sortOrder,
        'archived': archived ? 1 : 0,
        'created_at': toMs(createdAt),
        'updated_at': toMs(updatedAt),
      };

  QuestionBank copyWith({
    String? name,
    String? description,
    String? iconKey,
    int? color,
    bool? archived,
    String? categoryId,
  }) =>
      QuestionBank(
        id: id,
        categoryId: categoryId ?? this.categoryId,
        name: name ?? this.name,
        description: description ?? this.description,
        iconKey: iconKey ?? this.iconKey,
        color: color ?? this.color,
        sortOrder: sortOrder,
        archived: archived ?? this.archived,
        createdAt: createdAt,
        updatedAt: DateTime.now(),
      );
}

/// One answer option. [id] is a stable identifier that never changes when the
/// options are shuffled for display — correctness is always checked by id,
/// never by the letter shown on screen.
class AnswerOption {
  AnswerOption({
    required this.id,
    required this.text,
    this.position = 0,
    this.isCorrect = false,
    this.matchText,
    this.explanation,
  });

  final String id;
  final int position;
  final String text;
  final bool isCorrect;

  /// For matching questions: the item on the right that pairs with [text].
  final String? matchText;

  /// Optional "why this option is wrong/right" explanation.
  final String? explanation;

  factory AnswerOption.fromRow(Map<String, Object?> r) => AnswerOption(
        id: r['id'] as String,
        position: _i(r['position']),
        text: (r['text'] ?? '') as String,
        isCorrect: _b(r['is_correct']),
        matchText: _s(r['match_text']),
        explanation: _s(r['explanation']),
      );

  Map<String, Object?> toRow(String questionId) => {
        'id': id,
        'question_id': questionId,
        'position': position,
        'text': text,
        'is_correct': isCorrect ? 1 : 0,
        'match_text': matchText,
        'explanation': explanation,
      };

  AnswerOption copyWith({
    String? text,
    int? position,
    bool? isCorrect,
    String? matchText,
    String? explanation,
  }) =>
      AnswerOption(
        id: id,
        text: text ?? this.text,
        position: position ?? this.position,
        isCorrect: isCorrect ?? this.isCorrect,
        matchText: matchText ?? this.matchText,
        explanation: explanation ?? this.explanation,
      );
}

class Question {
  Question({
    required this.id,
    required this.bankId,
    required this.type,
    required this.text,
    this.options = const [],
    this.externalId,
    this.hint,
    this.explanation,
    this.correctFeedback,
    this.incorrectFeedback,
    this.difficulty = Difficulty.medium,
    this.tags = const [],
    this.shuffleOptions = true,
    this.caseSensitive = false,
    this.acceptedAnswers = const [],
    this.source,
    this.studyNotes,
    this.imagePath,
    this.audioPath,
    this.importId,
    this.fingerprint = '',
    this.contentVersion = 1,
    this.archived = false,
    DateTime? createdAt,
    DateTime? updatedAt,
  })  : createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  final String id;
  final String bankId;
  final QuestionType type;
  final String text;
  final List<AnswerOption> options;
  final String? externalId;
  final String? hint;
  final String? explanation;
  final String? correctFeedback;
  final String? incorrectFeedback;
  final Difficulty difficulty;
  final List<String> tags;
  final bool shuffleOptions;
  final bool caseSensitive;

  /// For fill-in-the-blank / short answers: every accepted answer.
  final List<String> acceptedAnswers;
  final String? source;
  final String? studyNotes;

  /// Paths are relative to the app's media folder (see MediaStore).
  final String? imagePath;
  final String? audioPath;
  final String? importId;
  final String fingerprint;

  /// Bumped when the user resets a question after a major content change.
  final int contentVersion;
  final bool archived;
  final DateTime createdAt;
  final DateTime updatedAt;

  List<AnswerOption> get correctOptions =>
      options.where((o) => o.isCorrect).toList();

  /// Human-readable correct answer, used in feedback and the mistakes notebook.
  String get correctAnswerText {
    switch (type) {
      case QuestionType.single:
      case QuestionType.multiple:
      case QuestionType.trueFalse:
        return correctOptions.map((o) => o.text).join('; ');
      case QuestionType.fillBlank:
      case QuestionType.shortAnswer:
      case QuestionType.flashcard:
        return acceptedAnswers.isNotEmpty ? acceptedAnswers.first : '';
      case QuestionType.matching:
        return options.map((o) => '${o.text} → ${o.matchText ?? ''}').join('; ');
    }
  }

  factory Question.fromRow(Map<String, Object?> r,
          [List<AnswerOption> options = const []]) =>
      Question(
        id: r['id'] as String,
        bankId: r['bank_id'] as String,
        type: QuestionType.fromKey(r['type'] as String?),
        text: (r['text'] ?? '') as String,
        options: options,
        externalId: _s(r['external_id']),
        hint: _s(r['hint']),
        explanation: _s(r['explanation']),
        correctFeedback: _s(r['correct_feedback']),
        incorrectFeedback: _s(r['incorrect_feedback']),
        difficulty: Difficulty.fromIndex(_i(r['difficulty'], 1)),
        tags: decodeTags(r['tags']),
        shuffleOptions: r['shuffle_options'] == null ? true : _b(r['shuffle_options']),
        caseSensitive: _b(r['case_sensitive']),
        acceptedAnswers: decodeStringList(r['accepted_answers']),
        source: _s(r['source']),
        studyNotes: _s(r['study_notes']),
        imagePath: _s(r['image_path']),
        audioPath: _s(r['audio_path']),
        importId: _s(r['import_id']),
        fingerprint: (r['fingerprint'] ?? '') as String,
        contentVersion: _i(r['content_version'], 1),
        archived: _b(r['archived']),
        createdAt: fromMs(r['created_at']),
        updatedAt: fromMs(r['updated_at']),
      );

  Map<String, Object?> toRow() => {
        'id': id,
        'bank_id': bankId,
        'external_id': externalId,
        'type': type.key,
        'text': text,
        'hint': hint,
        'explanation': explanation,
        'correct_feedback': correctFeedback,
        'incorrect_feedback': incorrectFeedback,
        'difficulty': difficulty.index,
        'tags': encodeTags(tags),
        'shuffle_options': shuffleOptions ? 1 : 0,
        'case_sensitive': caseSensitive ? 1 : 0,
        'accepted_answers': encodeStringList(acceptedAnswers),
        'source': source,
        'study_notes': studyNotes,
        'image_path': imagePath,
        'audio_path': audioPath,
        'import_id': importId,
        'fingerprint': fingerprint,
        'content_version': contentVersion,
        'archived': archived ? 1 : 0,
        'created_at': toMs(createdAt),
        'updated_at': toMs(updatedAt),
      };

  Question copyWith({
    String? id,
    String? bankId,
    QuestionType? type,
    String? text,
    List<AnswerOption>? options,
    String? externalId,
    String? hint,
    String? explanation,
    String? correctFeedback,
    String? incorrectFeedback,
    Difficulty? difficulty,
    List<String>? tags,
    bool? shuffleOptions,
    bool? caseSensitive,
    List<String>? acceptedAnswers,
    String? source,
    String? studyNotes,
    String? imagePath,
    String? audioPath,
    bool clearImage = false,
    bool clearAudio = false,
    String? importId,
    String? fingerprint,
    int? contentVersion,
    bool? archived,
  }) =>
      Question(
        id: id ?? this.id,
        bankId: bankId ?? this.bankId,
        type: type ?? this.type,
        text: text ?? this.text,
        options: options ?? this.options,
        externalId: externalId ?? this.externalId,
        hint: hint ?? this.hint,
        explanation: explanation ?? this.explanation,
        correctFeedback: correctFeedback ?? this.correctFeedback,
        incorrectFeedback: incorrectFeedback ?? this.incorrectFeedback,
        difficulty: difficulty ?? this.difficulty,
        tags: tags ?? this.tags,
        shuffleOptions: shuffleOptions ?? this.shuffleOptions,
        caseSensitive: caseSensitive ?? this.caseSensitive,
        acceptedAnswers: acceptedAnswers ?? this.acceptedAnswers,
        source: source ?? this.source,
        studyNotes: studyNotes ?? this.studyNotes,
        imagePath: clearImage ? null : (imagePath ?? this.imagePath),
        audioPath: clearAudio ? null : (audioPath ?? this.audioPath),
        importId: importId ?? this.importId,
        fingerprint: fingerprint ?? this.fingerprint,
        contentVersion: contentVersion ?? this.contentVersion,
        archived: archived ?? this.archived,
        createdAt: createdAt,
        updatedAt: DateTime.now(),
      );
}

/// Per-question learning state (one row per question that has ever been seen).
class QuestionProgress {
  QuestionProgress({
    required this.questionId,
    this.seen = false,
    this.presentedCount = 0,
    this.attemptCount = 0,
    this.correctCount = 0,
    this.incorrectCount = 0,
    this.skippedCount = 0,
    this.hintCount = 0,
    this.consecutiveCorrect = 0,
    this.lastResult,
    this.firstPresentedAt,
    this.lastPresentedAt,
    this.lastAttemptAt,
    this.ease = 2.5,
    this.intervalDays = 0,
    this.repetitions = 0,
    this.lapses = 0,
    this.dueAt,
    this.lastReviewAt,
    this.mastery = MasteryLevel.notLearned,
    this.masteryReason = '',
    this.understood = false,
  });

  final String questionId;

  /// True once the question has been shown in any session. New Questions mode
  /// only picks questions where this is false. Resetting new-question progress
  /// sets it back to false without touching any of the history below.
  final bool seen;
  final int presentedCount;
  final int attemptCount;
  final int correctCount;
  final int incorrectCount;
  final int skippedCount;
  final int hintCount;
  final int consecutiveCorrect;
  final AttemptResult? lastResult;
  final DateTime? firstPresentedAt;
  final DateTime? lastPresentedAt;
  final DateTime? lastAttemptAt;

  // Spaced repetition state.
  final double ease;
  final int intervalDays;
  final int repetitions;
  final int lapses;

  /// Null means "not yet scheduled" — which is different from "never studied".
  final DateTime? dueAt;
  final DateTime? lastReviewAt;

  final MasteryLevel mastery;
  final String masteryReason;

  /// Mistakes notebook: the user marked this mistake as understood.
  final bool understood;

  double? get accuracy {
    final graded = correctCount + incorrectCount;
    return graded == 0 ? null : correctCount / graded;
  }

  factory QuestionProgress.fromRow(Map<String, Object?> r) => QuestionProgress(
        questionId: r['question_id'] as String,
        seen: _b(r['seen']),
        presentedCount: _i(r['presented_count']),
        attemptCount: _i(r['attempt_count']),
        correctCount: _i(r['correct_count']),
        incorrectCount: _i(r['incorrect_count']),
        skippedCount: _i(r['skipped_count']),
        hintCount: _i(r['hint_count']),
        consecutiveCorrect: _i(r['consecutive_correct']),
        lastResult: AttemptResult.fromKey(r['last_result'] as String?),
        firstPresentedAt: fromMs(r['first_presented_at']),
        lastPresentedAt: fromMs(r['last_presented_at']),
        lastAttemptAt: fromMs(r['last_attempt_at']),
        ease: _d(r['ease'], 2.5),
        intervalDays: _i(r['interval_days']),
        repetitions: _i(r['repetitions']),
        lapses: _i(r['lapses']),
        dueAt: fromMs(r['due_at']),
        lastReviewAt: fromMs(r['last_review_at']),
        mastery: MasteryLevel.fromIndex(_i(r['mastery'])),
        masteryReason: (r['mastery_reason'] ?? '') as String,
        understood: _b(r['understood']),
      );

  Map<String, Object?> toRow() => {
        'question_id': questionId,
        'seen': seen ? 1 : 0,
        'presented_count': presentedCount,
        'attempt_count': attemptCount,
        'correct_count': correctCount,
        'incorrect_count': incorrectCount,
        'skipped_count': skippedCount,
        'hint_count': hintCount,
        'consecutive_correct': consecutiveCorrect,
        'last_result': lastResult?.key,
        'first_presented_at': firstPresentedAt == null ? null : toMs(firstPresentedAt!),
        'last_presented_at': lastPresentedAt == null ? null : toMs(lastPresentedAt!),
        'last_attempt_at': lastAttemptAt == null ? null : toMs(lastAttemptAt!),
        'ease': ease,
        'interval_days': intervalDays,
        'repetitions': repetitions,
        'lapses': lapses,
        'due_at': dueAt == null ? null : toMs(dueAt!),
        'last_review_at': lastReviewAt == null ? null : toMs(lastReviewAt!),
        'mastery': mastery.index,
        'mastery_reason': masteryReason,
        'understood': understood ? 1 : 0,
        'updated_at': toMs(DateTime.now()),
      };

  QuestionProgress copyWith({
    bool? seen,
    int? presentedCount,
    int? attemptCount,
    int? correctCount,
    int? incorrectCount,
    int? skippedCount,
    int? hintCount,
    int? consecutiveCorrect,
    AttemptResult? lastResult,
    DateTime? firstPresentedAt,
    DateTime? lastPresentedAt,
    DateTime? lastAttemptAt,
    double? ease,
    int? intervalDays,
    int? repetitions,
    int? lapses,
    DateTime? dueAt,
    bool clearDue = false,
    DateTime? lastReviewAt,
    MasteryLevel? mastery,
    String? masteryReason,
    bool? understood,
  }) =>
      QuestionProgress(
        questionId: questionId,
        seen: seen ?? this.seen,
        presentedCount: presentedCount ?? this.presentedCount,
        attemptCount: attemptCount ?? this.attemptCount,
        correctCount: correctCount ?? this.correctCount,
        incorrectCount: incorrectCount ?? this.incorrectCount,
        skippedCount: skippedCount ?? this.skippedCount,
        hintCount: hintCount ?? this.hintCount,
        consecutiveCorrect: consecutiveCorrect ?? this.consecutiveCorrect,
        lastResult: lastResult ?? this.lastResult,
        firstPresentedAt: firstPresentedAt ?? this.firstPresentedAt,
        lastPresentedAt: lastPresentedAt ?? this.lastPresentedAt,
        lastAttemptAt: lastAttemptAt ?? this.lastAttemptAt,
        ease: ease ?? this.ease,
        intervalDays: intervalDays ?? this.intervalDays,
        repetitions: repetitions ?? this.repetitions,
        lapses: lapses ?? this.lapses,
        dueAt: clearDue ? null : (dueAt ?? this.dueAt),
        lastReviewAt: lastReviewAt ?? this.lastReviewAt,
        mastery: mastery ?? this.mastery,
        masteryReason: masteryReason ?? this.masteryReason,
        understood: understood ?? this.understood,
      );
}

/// What the learner entered for one question. Serialised to JSON in the
/// database so that interrupted quizzes resume exactly where they stopped.
class QuestionResponse {
  QuestionResponse({
    Set<String>? selected,
    this.text,
    Map<String, String>? matches,
    this.selfGrade,
  })  : selected = selected ?? <String>{},
        matches = matches ?? <String, String>{};

  /// Selected option ids (single, multiple, true/false).
  final Set<String> selected;

  /// Typed answer (fill in the blank, short answer).
  final String? text;

  /// Matching: left option id -> option id whose matchText was chosen.
  final Map<String, String> matches;

  /// Learner's own judgement: flashcards ("remembered") and manual review of
  /// typed answers. Null when not given.
  final bool? selfGrade;

  bool get isEmpty =>
      selected.isEmpty &&
      (text == null || text!.trim().isEmpty) &&
      matches.isEmpty &&
      selfGrade == null;

  Map<String, Object?> toJson() => {
        if (selected.isNotEmpty) 'selected': selected.toList(),
        if (text != null) 'text': text,
        if (matches.isNotEmpty) 'matches': matches,
        if (selfGrade != null) 'selfGrade': selfGrade,
      };

  String encode() => jsonEncode(toJson());

  static QuestionResponse decode(String? s) {
    if (s == null || s.isEmpty) return QuestionResponse();
    try {
      final m = jsonDecode(s) as Map<String, dynamic>;
      return QuestionResponse(
        selected: ((m['selected'] as List?) ?? const [])
            .map((e) => e.toString())
            .toSet(),
        text: m['text'] as String?,
        matches: ((m['matches'] as Map?) ?? const {})
            .map((k, v) => MapEntry(k.toString(), v.toString())),
        selfGrade: m['selfGrade'] as bool?,
      );
    } catch (_) {
      return QuestionResponse();
    }
  }

  QuestionResponse copyWith({
    Set<String>? selected,
    String? text,
    Map<String, String>? matches,
    bool? selfGrade,
    bool clearSelfGrade = false,
  }) =>
      QuestionResponse(
        selected: selected ?? Set<String>.of(this.selected),
        text: text ?? this.text,
        matches: matches ?? Map<String, String>.of(this.matches),
        selfGrade: clearSelfGrade ? null : (selfGrade ?? this.selfGrade),
      );
}

/// The configuration a quiz was created with (stored as JSON on the session).
class QuizConfig {
  QuizConfig({
    this.title = 'Quiz',
    this.bankIds = const [],
    this.categoryIds = const [],
    this.excludedCategoryIds = const [],
    this.questionCount = 10,
    this.selection = SelectionMode.random,
    this.style = QuizStyle.practice,
    this.feedback = FeedbackTiming.immediate,
    this.hintsEnabled = true,
    this.shuffleQuestions = true,
    this.shuffleAnswers = true,
    this.timerEnabled = false,
    this.timeLimitMinutes = 0,
    this.difficulties = const [],
    this.masteryLevels = const [],
    this.includeAttempted = true,
    this.mistakesLastOnly = true,
    this.adaptiveDifficulty = false,
    this.confidenceRatings = true,
    this.manualCounts = const {},
    this.fixedQuestionIds = const [],
  });

  final String title;
  final List<String> bankIds;
  final List<String> categoryIds;
  final List<String> excludedCategoryIds;
  final int questionCount;
  final SelectionMode selection;
  final QuizStyle style;
  final FeedbackTiming feedback;
  final bool hintsEnabled;
  final bool shuffleQuestions;
  final bool shuffleAnswers;
  final bool timerEnabled;
  final int timeLimitMinutes;
  final List<Difficulty> difficulties;
  final List<MasteryLevel> masteryLevels;

  /// Random mode only: whether previously attempted questions may appear.
  final bool includeAttempted;

  /// Mistakes mode: only questions whose most recent answer was wrong (true)
  /// or every question that was ever answered wrong (false).
  final bool mistakesLastOnly;
  final bool adaptiveDifficulty;
  final bool confidenceRatings;

  /// Manual distribution: bank id -> number of questions.
  final Map<String, int> manualCounts;

  /// When non-empty the quiz uses exactly these questions (retake, mistakes
  /// list, bookmarks list, weak topics...).
  final List<String> fixedQuestionIds;

  bool get isExam => style == QuizStyle.exam;
  bool get hintsAllowed => hintsEnabled && style != QuizStyle.exam;

  Map<String, Object?> toJson() => {
        'title': title,
        'bankIds': bankIds,
        'categoryIds': categoryIds,
        'excludedCategoryIds': excludedCategoryIds,
        'questionCount': questionCount,
        'selection': selection.key,
        'style': style.key,
        'feedback': feedback.key,
        'hintsEnabled': hintsEnabled,
        'shuffleQuestions': shuffleQuestions,
        'shuffleAnswers': shuffleAnswers,
        'timerEnabled': timerEnabled,
        'timeLimitMinutes': timeLimitMinutes,
        'difficulties': difficulties.map((d) => d.index).toList(),
        'masteryLevels': masteryLevels.map((d) => d.index).toList(),
        'includeAttempted': includeAttempted,
        'mistakesLastOnly': mistakesLastOnly,
        'adaptiveDifficulty': adaptiveDifficulty,
        'confidenceRatings': confidenceRatings,
        'manualCounts': manualCounts,
        'fixedQuestionIds': fixedQuestionIds,
      };

  String encode() => jsonEncode(toJson());

  static QuizConfig decode(String? s) {
    if (s == null || s.isEmpty) return QuizConfig();
    final m = jsonDecode(s) as Map<String, dynamic>;
    List<String> sl(Object? v) =>
        ((v as List?) ?? const []).map((e) => e.toString()).toList();
    return QuizConfig(
      title: (m['title'] ?? 'Quiz') as String,
      bankIds: sl(m['bankIds']),
      categoryIds: sl(m['categoryIds']),
      excludedCategoryIds: sl(m['excludedCategoryIds']),
      questionCount: _i(m['questionCount'], 10),
      selection: SelectionMode.fromKey(m['selection'] as String?),
      style: QuizStyle.fromKey(m['style'] as String?),
      feedback: FeedbackTiming.fromKey(m['feedback'] as String?),
      hintsEnabled: m['hintsEnabled'] != false,
      shuffleQuestions: m['shuffleQuestions'] != false,
      shuffleAnswers: m['shuffleAnswers'] != false,
      timerEnabled: m['timerEnabled'] == true,
      timeLimitMinutes: _i(m['timeLimitMinutes']),
      difficulties: ((m['difficulties'] as List?) ?? const [])
          .map((e) => Difficulty.fromIndex(_i(e)))
          .toList(),
      masteryLevels: ((m['masteryLevels'] as List?) ?? const [])
          .map((e) => MasteryLevel.fromIndex(_i(e)))
          .toList(),
      includeAttempted: m['includeAttempted'] != false,
      mistakesLastOnly: m['mistakesLastOnly'] != false,
      adaptiveDifficulty: m['adaptiveDifficulty'] == true,
      confidenceRatings: m['confidenceRatings'] != false,
      manualCounts: ((m['manualCounts'] as Map?) ?? const {})
          .map((k, v) => MapEntry(k.toString(), _i(v))),
      fixedQuestionIds: sl(m['fixedQuestionIds']),
    );
  }

  QuizConfig copyWith({
    String? title,
    List<String>? bankIds,
    List<String>? categoryIds,
    List<String>? excludedCategoryIds,
    int? questionCount,
    SelectionMode? selection,
    QuizStyle? style,
    FeedbackTiming? feedback,
    bool? hintsEnabled,
    bool? shuffleQuestions,
    bool? shuffleAnswers,
    bool? timerEnabled,
    int? timeLimitMinutes,
    List<Difficulty>? difficulties,
    List<MasteryLevel>? masteryLevels,
    bool? includeAttempted,
    bool? mistakesLastOnly,
    bool? adaptiveDifficulty,
    bool? confidenceRatings,
    Map<String, int>? manualCounts,
    List<String>? fixedQuestionIds,
  }) =>
      QuizConfig(
        title: title ?? this.title,
        bankIds: bankIds ?? this.bankIds,
        categoryIds: categoryIds ?? this.categoryIds,
        excludedCategoryIds: excludedCategoryIds ?? this.excludedCategoryIds,
        questionCount: questionCount ?? this.questionCount,
        selection: selection ?? this.selection,
        style: style ?? this.style,
        feedback: feedback ?? this.feedback,
        hintsEnabled: hintsEnabled ?? this.hintsEnabled,
        shuffleQuestions: shuffleQuestions ?? this.shuffleQuestions,
        shuffleAnswers: shuffleAnswers ?? this.shuffleAnswers,
        timerEnabled: timerEnabled ?? this.timerEnabled,
        timeLimitMinutes: timeLimitMinutes ?? this.timeLimitMinutes,
        difficulties: difficulties ?? this.difficulties,
        masteryLevels: masteryLevels ?? this.masteryLevels,
        includeAttempted: includeAttempted ?? this.includeAttempted,
        mistakesLastOnly: mistakesLastOnly ?? this.mistakesLastOnly,
        adaptiveDifficulty: adaptiveDifficulty ?? this.adaptiveDifficulty,
        confidenceRatings: confidenceRatings ?? this.confidenceRatings,
        manualCounts: manualCounts ?? this.manualCounts,
        fixedQuestionIds: fixedQuestionIds ?? this.fixedQuestionIds,
      );
}

/// Statistics for a bank or a category subtree, computed from the database.
class LearningStats {
  const LearningStats({
    this.total = 0,
    this.neverAttempted = 0,
    this.attempted = 0,
    this.mastered = 0,
    this.needsReview = 0,
    this.correct = 0,
    this.incorrect = 0,
    this.dueToday = 0,
    this.overdue = 0,
    this.unseen = 0,
    this.byLevel = const {},
  });

  final int total;
  final int neverAttempted;
  final int attempted;
  final int mastered;

  /// Attempted questions currently "Learning" or "Needs Practice".
  final int needsReview;
  final int correct;
  final int incorrect;

  /// Scheduled for review on or before the end of today (includes overdue).
  final int dueToday;

  /// Scheduled before the start of today.
  final int overdue;

  /// Never presented in any session (eligible for New Questions mode).
  final int unseen;
  final Map<MasteryLevel, int> byLevel;

  double? get accuracy {
    final g = correct + incorrect;
    return g == 0 ? null : correct / g;
  }

  double get masteredFraction => total == 0 ? 0 : mastered / total;
}
