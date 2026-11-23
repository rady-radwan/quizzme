import 'package:flutter/material.dart';

import '../../app/services.dart';
import '../../core/models.dart';
import '../../data/session_repository.dart';
import '../common/widgets.dart';
import 'flashcard_screen.dart';
import 'quiz_player_screen.dart';
import 'quiz_setup_screen.dart';

/// Builds a quiz configuration from the user's default preferences.
QuizConfig defaultConfig({
  String title = 'Quiz',
  SelectionMode? selection,
  QuizStyle style = QuizStyle.practice,
  List<String> bankIds = const [],
  List<String> categoryIds = const [],
  List<String> fixedQuestionIds = const [],
  int? count,
}) {
  final s = AppServices.I.settings.value;
  return QuizConfig(
    title: title,
    bankIds: bankIds,
    categoryIds: categoryIds,
    fixedQuestionIds: fixedQuestionIds,
    questionCount: count ?? (fixedQuestionIds.isNotEmpty ? fixedQuestionIds.length : s.defaultQuestionCount),
    selection: selection ?? s.defaultSelection,
    style: style,
    feedback: style == QuizStyle.exam ? FeedbackTiming.endOfQuiz : s.defaultFeedback,
    hintsEnabled: s.hintsEnabled,
    shuffleQuestions: s.shuffleQuestions,
    shuffleAnswers: s.shuffleAnswers,
    timerEnabled: style == QuizStyle.exam && s.timerMinutes > 0,
    timeLimitMinutes: s.timerMinutes,
    adaptiveDifficulty: s.adaptiveDifficulty,
    confidenceRatings: s.confidenceRatings,
  );
}

Future<void> openSession(BuildContext context, QuizSession s) async {
  final route = MaterialPageRoute<void>(
    builder: (_) => s.config.style == QuizStyle.flashcards
        ? FlashcardScreen(sessionId: s.id)
        : QuizPlayerScreen(sessionId: s.id),
  );
  await Navigator.of(context).push(route);
  AppServices.I.dataChanged();
}

/// Creates the session and opens it, handling "not enough questions".
/// Returns true when a quiz was started.
Future<bool> launchQuiz(BuildContext context, QuizConfig config, {bool allowEdit = true}) async {
  final svc = AppServices.I;
  try {
    final s = await svc.sessions.create(config);
    if (!context.mounted) return false;
    await openSession(context, s);
    return true;
  } on InsufficientQuestionsException catch (e) {
    if (!context.mounted) return false;
    if (e.available == 0) {
      return _noQuestions(context, config, allowEdit: allowEdit);
    }
    final choice = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Not enough questions'),
        content: Text('Only ${e.available} questions match your selected criteria '
            '(you asked for ${e.requested}). Questions are never repeated to fill a quiz.'),
        actions: [
          if (allowEdit) TextButton(onPressed: () => Navigator.pop(c, 'edit'), child: const Text('Change filters')),
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(c, 'fewer'), child: Text('Start with ${e.available}')),
        ],
      ),
    );
    if (!context.mounted) return false;
    if (choice == 'fewer') {
      final s = await svc.sessions.create(config, allowFewer: true);
      if (!context.mounted) return false;
      await openSession(context, s);
      return true;
    }
    if (choice == 'edit') {
      await Navigator.of(context).push(MaterialPageRoute<void>(
          builder: (_) => QuizSetupScreen(initial: config)));
    }
    return false;
  } catch (e) {
    if (context.mounted) await showErrorDialog(context, 'Could not start the quiz', '$e');
    return false;
  }
}

Future<bool> _noQuestions(BuildContext context, QuizConfig config, {required bool allowEdit}) async {
  final svc = AppServices.I;
  if (config.selection != SelectionMode.newQuestions) {
    final msg = switch (config.selection) {
      SelectionMode.spaced => 'No questions are due for review today. Great work!',
      SelectionMode.mistakes => 'There are no mistakes to practise in this selection.',
      SelectionMode.bookmarked => 'You have not bookmarked any questions in this selection yet.',
      SelectionMode.review || SelectionMode.quickReview || SelectionMode.mastery =>
        'You have not answered any matching questions yet. Try Learn New Questions first.',
      _ => 'No questions match your selected criteria.',
    };
    final edit = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Nothing to study here'),
        content: Text(msg),
        actions: [
          if (allowEdit) TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('Change filters')),
          FilledButton(onPressed: () => Navigator.pop(c, false), child: const Text('OK')),
        ],
      ),
    );
    if (edit == true && context.mounted) {
      await Navigator.of(context)
          .push(MaterialPageRoute<void>(builder: (_) => QuizSetupScreen(initial: config)));
    }
    return false;
  }

  // New Questions mode with nothing left.
  final banks = await svc.catalog.resolveBankIds(
      bankIds: config.bankIds, categoryIds: config.categoryIds, excludedCategoryIds: config.excludedCategoryIds);
  final stats = await svc.stats.statsFor(banks);
  if (!context.mounted) return false;
  if (stats.total == 0) {
    await showErrorDialog(context, 'No questions yet',
        'This selection has no questions. Import an Excel file or add questions first.');
    return false;
  }
  final choice = await showDialog<SelectionMode?>(
    context: context,
    builder: (c) => AlertDialog(
      icon: const Icon(Icons.emoji_events_outlined),
      title: const Text('You have completed all new questions in this bank!'),
      content: const Text('Keep the knowledge fresh with one of these:'),
      actions: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          alignment: WrapAlignment.end,
          children: [
            OutlinedButton(onPressed: () => Navigator.pop(c, SelectionMode.review), child: const Text('Review Questions')),
            OutlinedButton(onPressed: () => Navigator.pop(c, SelectionMode.mistakes), child: const Text('Practice Mistakes')),
            OutlinedButton(onPressed: () => Navigator.pop(c, SelectionMode.spaced), child: const Text('Start Spaced Repetition')),
            TextButton(onPressed: () => Navigator.pop(c, SelectionMode.newQuestions), child: const Text('Reset New Question Progress')),
          ],
        ),
      ],
    ),
  );
  if (choice == null || !context.mounted) return false;
  if (choice == SelectionMode.newQuestions) {
    final ok = await confirm(context,
        title: 'Reset new-question progress?',
        message: 'All ${stats.total} questions in this selection will count as new again. '
            'Your answer history, statistics and review schedule are kept.',
        confirmLabel: 'Reset');
    if (!ok) return false;
    await svc.study.resetNewProgress(banks);
    svc.dataChanged();
    if (!context.mounted) return false;
    return launchQuiz(context, config, allowEdit: allowEdit);
  }
  return launchQuiz(context, config.copyWith(selection: choice, mistakesLastOnly: false), allowEdit: allowEdit);
}

/// Opens an unfinished quiz if there is one.
Future<void> continueLastQuiz(BuildContext context) async {
  final s = await AppServices.I.sessions.latestActive();
  if (!context.mounted) return;
  if (s == null) {
    showMessage(context, 'There is no unfinished quiz.');
    return;
  }
  await openSession(context, s);
}
