import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../app/services.dart';
import '../../data/question_repository.dart';
import '../common/reloadable.dart';
import '../common/widgets.dart';
import '../questions/question_detail_screen.dart';
import '../questions/question_list_screen.dart';

/// Every import into a bank, with counts and the log of messages.
class ImportHistoryScreen extends StatelessWidget {
  const ImportHistoryScreen({super.key, this.bankId});
  final String? bankId;

  @override
  Widget build(BuildContext context) {
    final svc = AppServices.I;
    return Scaffold(
      appBar: AppBar(title: const Text('Import history')),
      body: Reloadable<List<ImportRecord>>(
        load: () => bankId == null ? svc.questions.allImports() : svc.questions.importsForBank(bankId!),
        builder: (context, list, _) {
          if (list.isEmpty) {
            return const EmptyState(icon: Icons.history, title: 'No imports yet');
          }
          final fmt = DateFormat.yMMMd().add_Hm();
          return ListView.separated(
            padding: const EdgeInsets.all(12),
            itemCount: list.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, i) {
              final r = list[i];
              final failed = r.status != 'completed';
              return Card(
                child: ExpansionTile(
                  leading: Icon(failed ? Icons.error_outline : Icons.check_circle_outline,
                      color: failed ? Theme.of(context).colorScheme.error : null),
                  title: Text(r.fileName),
                  subtitle: Text('${fmt.format(r.importedAt)} · ${r.status}\n'
                      '${r.imported} imported · ${r.updated} updated · ${r.skipped} skipped · ${r.errors} errors'),
                  isThreeLine: true,
                  childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                  children: [
                    if (!failed)
                      Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: TextButton.icon(
                          icon: const Icon(Icons.filter_list),
                          label: const Text('Show questions from this import'),
                          onPressed: () => Navigator.push(
                              context,
                              MaterialPageRoute<void>(
                                  builder: (_) => QuestionListScreen(
                                      title: r.fileName,
                                      filter: QuestionFilter(importId: r.id, includeArchived: true)))),
                        ),
                      ),
                    if (r.log.isNotEmpty)
                      SelectableText(r.log, style: Theme.of(context).textTheme.bodySmall)
                    else
                      const Text('No warnings.'),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}

/// Groups of questions with identical content, so extras can be removed.
class DuplicatesScreen extends StatelessWidget {
  const DuplicatesScreen({super.key, required this.bankIds});
  final List<String> bankIds;

  @override
  Widget build(BuildContext context) {
    final svc = AppServices.I;
    return Scaffold(
      appBar: AppBar(title: const Text('Duplicate questions')),
      body: Reloadable<List<List<QuestionListItem>>>(
        load: () => svc.questions.duplicateGroups(bankIds),
        builder: (context, groups, _) {
          if (groups.isEmpty) {
            return const EmptyState(
                icon: Icons.verified_outlined,
                title: 'No duplicates found',
                message: 'Every question in this bank has unique content.');
          }
          return ListView(
            padding: const EdgeInsets.all(12),
            children: [
              Text('${groups.length} groups of identical questions. The oldest copy usually has the most '
                  'history; archive or delete the others.'),
              const SizedBox(height: 8),
              for (final g in groups)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Card(
                    child: Column(children: [
                      for (var i = 0; i < g.length; i++)
                        ListTile(
                          title: ContentText(g[i].text, maxLines: 2),
                          subtitle: Text('${i == 0 ? 'Oldest · ' : ''}${g[i].attempts} attempts · ${g[i].bankName}'),
                          onTap: () => Navigator.push(context,
                              MaterialPageRoute<void>(builder: (_) => QuestionDetailScreen(questionId: g[i].id))),
                          trailing: i == 0
                              ? null
                              : PopupMenuButton<String>(
                                  onSelected: (v) async {
                                    if (v == 'archive') {
                                      await svc.questions.setArchived([g[i].id], true);
                                    } else if (v == 'delete') {
                                      final ok = await confirm(context,
                                          title: 'Delete this copy?',
                                          message: 'The copy and its history will be permanently deleted.',
                                          confirmLabel: 'Delete',
                                          destructive: true);
                                      if (!ok) return;
                                      await svc.questions.delete([g[i].id]);
                                    }
                                    svc.dataChanged();
                                  },
                                  itemBuilder: (_) => const [
                                    PopupMenuItem(value: 'archive', child: Text('Archive this copy')),
                                    PopupMenuItem(value: 'delete', child: Text('Delete this copy')),
                                  ],
                                ),
                        ),
                    ]),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}
