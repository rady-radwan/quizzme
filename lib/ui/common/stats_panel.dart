import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../core/models.dart';
import 'widgets.dart';

/// The statistics block shown at the top of every bank and category.
class StatsPanel extends StatelessWidget {
  const StatsPanel({super.key, required this.stats, this.onTapDue, this.onTapNeverAttempted, this.onTapNeedsReview});
  final LearningStats stats;
  final VoidCallback? onTapDue;
  final VoidCallback? onTapNeverAttempted;
  final VoidCallback? onTapNeedsReview;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        StatGrid(children: [
          StatTile(label: 'Total questions', value: '${stats.total}', icon: Icons.quiz_outlined),
          StatTile(
              label: 'Never attempted',
              value: '${stats.neverAttempted}',
              icon: Icons.fiber_new_outlined,
              onTap: onTapNeverAttempted),
          StatTile(label: 'Attempted', value: '${stats.attempted}', icon: Icons.done_all),
          StatTile(
              label: 'Mastered',
              value: '${stats.mastered}',
              icon: Icons.workspace_premium,
              color: masteryColor(MasteryLevel.mastered, scheme)),
          StatTile(
              label: 'Needs review',
              value: '${stats.needsReview}',
              icon: Icons.replay,
              color: masteryColor(MasteryLevel.learning, scheme),
              onTap: onTapNeedsReview),
          StatTile(label: 'Overall accuracy', value: percent(stats.accuracy), icon: Icons.track_changes),
          StatTile(
              label: stats.overdue > 0 ? 'Due today (${stats.overdue} overdue)' : 'Due today',
              value: '${stats.dueToday}',
              icon: Icons.event_available,
              onTap: onTapDue),
        ]),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Mastery', style: Theme.of(context).textTheme.labelLarge),
              const SizedBox(height: 8),
              MasteryBar(byLevel: stats.byLevel),
              const SizedBox(height: 8),
              MasteryLegend(byLevel: stats.byLevel),
            ]),
          ),
        ),
      ],
    );
  }
}

/// A row of primary study buttons for a bank or category.
class StudyButtons extends StatelessWidget {
  const StudyButtons({super.key, required this.onQuiz, required this.onNew, required this.onDue, required this.onFlashcards, this.dueCount = 0, this.newCount = 0});
  final VoidCallback onQuiz;
  final VoidCallback onNew;
  final VoidCallback onDue;
  final VoidCallback onFlashcards;
  final int dueCount;
  final int newCount;

  @override
  Widget build(BuildContext context) {
    return Wrap(spacing: 8, runSpacing: 8, children: [
      FilledButton.icon(onPressed: onQuiz, icon: const Icon(Icons.play_arrow), label: const Text('Start quiz')),
      OutlinedButton.icon(
          onPressed: onNew, icon: const Icon(Icons.fiber_new_outlined), label: Text('New ($newCount)')),
      OutlinedButton.icon(
          onPressed: dueCount == 0 ? null : onDue,
          icon: const Icon(Icons.event_repeat),
          label: Text('Review due ($dueCount)')),
      OutlinedButton.icon(onPressed: onFlashcards, icon: const Icon(Icons.style_outlined), label: const Text('Flashcards')),
    ]);
  }
}
