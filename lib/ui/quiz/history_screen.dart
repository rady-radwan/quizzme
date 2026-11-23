import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../app/services.dart';
import '../../core/dates.dart';
import '../../data/session_repository.dart';
import '../common/reloadable.dart';
import '../common/widgets.dart';
import 'results_screen.dart';

/// Every completed quiz; tap to reopen its full results.
class HistoryScreen extends StatelessWidget {
  const HistoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final fmt = DateFormat.yMMMd().add_Hm();
    return Scaffold(
      appBar: AppBar(title: const Text('Quiz history')),
      body: Reloadable<List<QuizSession>>(
        load: () => AppServices.I.sessions.history(limit: 500),
        builder: (context, list, _) {
          if (list.isEmpty) {
            return const EmptyState(
                icon: Icons.history, title: 'No completed quizzes yet', message: 'Finished quizzes appear here.');
          }
          return ListView.separated(
            padding: const EdgeInsets.all(12),
            itemCount: list.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, i) {
              final s = list[i];
              final c = s.config;
              return Card(
                child: ListTile(
                  leading: CircleAvatar(child: Text('${s.score?.round() ?? 0}')),
                  title: Text(s.title, maxLines: 2, overflow: TextOverflow.ellipsis),
                  subtitle: Text('${fmt.format(s.completedAt ?? s.createdAt)} · '
                      '${formatDuration(Duration(milliseconds: s.elapsedMs))}\n'
                      '${c.selection.label} · ${c.style.label} · ${s.correct}/${s.total} correct'
                      '${s.unanswered > 0 ? ' · ${s.unanswered} unanswered' : ''}'),
                  isThreeLine: true,
                  trailing: PopupMenuButton<String>(
                    onSelected: (v) async {
                      if (v != 'delete') return;
                      final ok = await confirm(context,
                          title: 'Remove from history?',
                          message: 'The quiz record is removed. Your answers stay in each question\'s '
                              'learning history and statistics.',
                          confirmLabel: 'Remove',
                          destructive: true);
                      if (!ok) return;
                      await AppServices.I.sessions.deleteSession(s.id);
                      AppServices.I.dataChanged();
                    },
                    itemBuilder: (_) => const [PopupMenuItem(value: 'delete', child: Text('Remove from history'))],
                  ),
                  onTap: () => Navigator.push(
                      context, MaterialPageRoute<void>(builder: (_) => ResultsScreen(sessionId: s.id))),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
