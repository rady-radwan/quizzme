import 'models.dart';

enum GradeOutcome { correct, incorrect, needsReview, unanswered }

/// Normalises a typed answer for comparison: trims, collapses whitespace,
/// strips surrounding quotes and trailing punctuation, and lower-cases unless
/// the question is case sensitive.
String normalizeAnswer(String s, {bool caseSensitive = false}) {
  var v = s.trim().replaceAll(RegExp(r'\s+'), ' ');
  v = v.replaceAll(RegExp('^["\'“”‘’]+|["\'“”‘’]+\$'), '');
  v = v.replaceAll(RegExp(r'[.!?,;:]+$'), '').trim();
  return caseSensitive ? v : v.toLowerCase();
}

/// All typed answers accepted for a fill-in-the-blank / short answer question:
/// the explicit accepted-answers list plus any options marked correct.
List<String> acceptedAnswersOf(Question q) {
  final out = <String>[...q.acceptedAnswers];
  for (final o in q.options) {
    if (o.isCorrect && o.text.trim().isNotEmpty) out.add(o.text);
  }
  return out.where((a) => a.trim().isNotEmpty).toSet().toList();
}

bool isAnswered(Question q, QuestionResponse r) {
  switch (q.type) {
    case QuestionType.single:
    case QuestionType.multiple:
    case QuestionType.trueFalse:
      return r.selected.isNotEmpty;
    case QuestionType.fillBlank:
    case QuestionType.shortAnswer:
      return (r.text ?? '').trim().isNotEmpty;
    case QuestionType.matching:
      return r.matches.length >= q.options.length && q.options.isNotEmpty;
    case QuestionType.flashcard:
      return r.selfGrade != null;
  }
}

/// Grades a response. Options are compared by their stable ids, so the order
/// in which they were displayed never matters.
///
/// Short written answers that do not match any accepted answer return
/// [GradeOutcome.needsReview] (the learner decides), because simple text
/// matching cannot judge meaning. Fill-in-the-blank answers are strict.
/// Once the learner has given a self-grade, it is used.
GradeOutcome grade(Question q, QuestionResponse r) {
  if (!isAnswered(q, r)) return GradeOutcome.unanswered;
  switch (q.type) {
    case QuestionType.single:
    case QuestionType.trueFalse:
    case QuestionType.multiple:
      final correct = q.options.where((o) => o.isCorrect).map((o) => o.id).toSet();
      if (correct.isEmpty) return GradeOutcome.incorrect;
      final ok = r.selected.length == correct.length &&
          r.selected.every(correct.contains);
      return ok ? GradeOutcome.correct : GradeOutcome.incorrect;
    case QuestionType.fillBlank:
    case QuestionType.shortAnswer:
      if (r.selfGrade != null) {
        return r.selfGrade! ? GradeOutcome.correct : GradeOutcome.incorrect;
      }
      final given = normalizeAnswer(r.text ?? '', caseSensitive: q.caseSensitive);
      final match = acceptedAnswersOf(q).any(
          (a) => normalizeAnswer(a, caseSensitive: q.caseSensitive) == given);
      if (match) return GradeOutcome.correct;
      return q.type == QuestionType.shortAnswer
          ? GradeOutcome.needsReview
          : GradeOutcome.incorrect;
    case QuestionType.matching:
      // Each left item must be paired with the option whose matchText belongs
      // to it. Two options may share identical right-hand text; compare text.
      for (final o in q.options) {
        final chosenId = r.matches[o.id];
        if (chosenId == null) return GradeOutcome.incorrect;
        final chosen = q.options.where((x) => x.id == chosenId);
        if (chosen.isEmpty) return GradeOutcome.incorrect;
        final a = normalizeAnswer(chosen.first.matchText ?? '');
        final b = normalizeAnswer(o.matchText ?? '');
        if (a != b) return GradeOutcome.incorrect;
      }
      return GradeOutcome.correct;
    case QuestionType.flashcard:
      return r.selfGrade == true ? GradeOutcome.correct : GradeOutcome.incorrect;
  }
}

/// Human-readable description of what the learner answered.
String describeResponse(Question q, QuestionResponse r) {
  if (r.isEmpty) return 'No answer';
  switch (q.type) {
    case QuestionType.single:
    case QuestionType.multiple:
    case QuestionType.trueFalse:
      final texts = q.options
          .where((o) => r.selected.contains(o.id))
          .map((o) => o.text)
          .toList();
      return texts.isEmpty ? 'No answer' : texts.join('; ');
    case QuestionType.fillBlank:
    case QuestionType.shortAnswer:
      return (r.text ?? '').trim().isEmpty ? 'No answer' : r.text!.trim();
    case QuestionType.matching:
      final parts = <String>[];
      for (final o in q.options) {
        final id = r.matches[o.id];
        final m = q.options.where((x) => x.id == id);
        parts.add('${o.text} → ${m.isEmpty ? '?' : (m.first.matchText ?? '')}');
      }
      return parts.join('; ');
    case QuestionType.flashcard:
      return r.selfGrade == true ? 'Remembered' : 'Forgotten';
  }
}

/// The explanation for the specific wrong option(s) the learner picked.
List<String> wrongChoiceExplanations(Question q, QuestionResponse r) {
  return q.options
      .where((o) => r.selected.contains(o.id) && !o.isCorrect)
      .map((o) => o.explanation ?? '')
      .where((e) => e.trim().isNotEmpty)
      .toList();
}
