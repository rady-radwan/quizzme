import 'package:flutter/material.dart';

import '../../app/services.dart';
import '../../core/models.dart';
import '../../data/question_repository.dart';
import '../common/reloadable.dart';
import '../common/stats_panel.dart';
import '../common/widgets.dart';
import '../questions/question_list_screen.dart';
import '../quiz/quiz_launcher.dart';
import '../quiz/quiz_setup_screen.dart';
import 'bank_screen.dart';
import 'node_editor.dart';

class _CategoryData {
  _CategoryData(this.category, this.path, this.children, this.banks, this.stats, this.bankIds, this.counts);
  final Category category;
  final List<Category> path;
  final List<Category> children;
  final List<QuestionBank> banks;
  final LearningStats stats;
  final List<String> bankIds;
  final Map<String, int> counts;
}

class CategoryScreen extends StatelessWidget {
  const CategoryScreen({super.key, required this.categoryId});
  final String categoryId;

  Future<_CategoryData?> _load() async {
    final svc = AppServices.I;
    final c = await svc.catalog.category(categoryId);
    if (c == null) return null;
    final all = await svc.catalog.allCategories();
    final children = all.where((x) => x.parentId == c.id).toList();
    final banks = await svc.catalog.banksIn(c.id);
    final bankIds = await svc.catalog.bankIdsUnder(c.id);
    return _CategoryData(c, await svc.catalog.categoryPath(c.id), children, banks,
        await svc.stats.statsFor(bankIds), bankIds, await svc.catalog.questionCountsByBank());
  }

  @override
  Widget build(BuildContext context) {
    return Reloadable<_CategoryData?>(
      load: _load,
      loading: const Scaffold(body: Center(child: CircularProgressIndicator())),
      builder: (context, d, reload) {
        if (d == null) {
          return Scaffold(appBar: AppBar(), body: const Center(child: Text('This category no longer exists.')));
        }
        final c = d.category;
        QuizConfig cfg(SelectionMode m, {QuizStyle style = QuizStyle.practice}) =>
            defaultConfig(title: c.name, categoryIds: [c.id], selection: m, style: style);
        return Scaffold(
          appBar: AppBar(
            title: Text(c.name),
            actions: [
              IconButton(
                tooltip: 'Browse questions',
                icon: const Icon(Icons.list_alt),
                onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute<void>(
                        builder: (_) => QuestionListScreen(
                            title: c.name, filter: QuestionFilter(bankIds: d.bankIds)))),
              ),
              PopupMenuButton<String>(
                onSelected: (v) async {
                  if (v == 'edit') await CategoryActions.edit(context, c);
                  if (v == 'move' && context.mounted) await CategoryActions.move(context, c);
                  if (v == 'archive' && context.mounted) await CategoryActions.toggleArchive(context, c);
                  if (v == 'reset' && context.mounted) {
                    final ok = await confirm(context,
                        title: 'Reset new-question progress?',
                        message: 'Every question in "${c.name}" will count as new again. History is kept.',
                        confirmLabel: 'Reset');
                    if (ok) {
                      await AppServices.I.study.resetNewProgress(d.bankIds);
                      AppServices.I.dataChanged();
                    }
                  }
                  if (v == 'delete' && context.mounted) {
                    final deleted = await CategoryActions.delete(context, c);
                    if (deleted && context.mounted) Navigator.pop(context);
                  }
                },
                itemBuilder: (_) => [
                  const PopupMenuItem(value: 'edit', child: Text('Edit')),
                  const PopupMenuItem(value: 'move', child: Text('Move')),
                  PopupMenuItem(value: 'archive', child: Text(c.archived ? 'Restore from archive' : 'Archive')),
                  const PopupMenuItem(value: 'reset', child: Text('Reset new-question progress')),
                  const PopupMenuItem(value: 'delete', child: Text('Delete…')),
                ],
              ),
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            children: [
              Readable(
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  if (d.path.length > 1)
                    Text(d.path.map((p) => p.name).join(' → '),
                        style: Theme.of(context).textTheme.bodySmall),
                  if (c.description != null && c.description!.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(c.description!),
                  ],
                  const SizedBox(height: 12),
                  StudyButtons(
                    newCount: d.stats.unseen,
                    dueCount: d.stats.dueToday,
                    onQuiz: () => Navigator.push(context,
                        MaterialPageRoute<void>(builder: (_) => QuizSetupScreen(initial: cfg(SelectionMode.random)))),
                    onNew: () => launchQuiz(context, cfg(SelectionMode.newQuestions)),
                    onDue: () => launchQuiz(context, cfg(SelectionMode.spaced).copyWith(questionCount: d.stats.dueToday)),
                    onFlashcards: () => launchQuiz(context, cfg(SelectionMode.random, style: QuizStyle.flashcards)),
                  ),
                  const SizedBox(height: 16),
                  StatsPanel(stats: d.stats),
                  SectionHeader('Contents', action: PopupMenuButton<String>(
                    icon: const Icon(Icons.add),
                    tooltip: 'Add',
                    onSelected: (v) {
                      if (v == 'bank') BankActions.create(context, c.id);
                      if (v == 'sub') CategoryActions.create(context, parentId: c.id);
                    },
                    itemBuilder: (_) => const [
                      PopupMenuItem(value: 'bank', child: Text('New question bank')),
                      PopupMenuItem(value: 'sub', child: Text('New sub-category')),
                    ],
                  )),
                  if (d.children.isEmpty && d.banks.isEmpty)
                    const Card(
                      child: Padding(
                        padding: EdgeInsets.all(16),
                        child: Text('Empty. Use + to add a question bank or a sub-category.'),
                      ),
                    ),
                  for (final k in d.children)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Card(
                        child: ListTile(
                          leading: NodeAvatar(iconKey: k.iconKey, color: k.color),
                          title: Text(k.name),
                          subtitle: Text(k.archived ? 'Category · archived' : 'Category'),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => Navigator.push(context,
                              MaterialPageRoute<void>(builder: (_) => CategoryScreen(categoryId: k.id))),
                        ),
                      ),
                    ),
                  for (final b in d.banks)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Card(
                        child: ListTile(
                          leading: NodeAvatar(iconKey: b.iconKey, color: b.color, fallback: Icons.quiz_outlined),
                          title: Text(b.name),
                          subtitle: Text('${d.counts[b.id] ?? 0} questions${b.archived ? ' · archived' : ''}'),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => Navigator.push(
                              context, MaterialPageRoute<void>(builder: (_) => BankScreen(bankId: b.id))),
                        ),
                      ),
                    ),
                ]),
              ),
            ],
          ),
        );
      },
    );
  }
}
