import 'package:flutter/material.dart';

import '../../app/services.dart';
import '../../core/models.dart';
import '../../data/question_repository.dart';
import '../common/file_io.dart';
import '../common/reloadable.dart';
import '../common/stats_panel.dart';
import '../common/widgets.dart';
import '../import/import_screen.dart';
import '../questions/question_editor_screen.dart';
import '../questions/question_list_screen.dart';
import '../quiz/quiz_launcher.dart';
import '../quiz/quiz_setup_screen.dart';
import 'bank_tools.dart';
import 'node_editor.dart';

class _BankData {
  _BankData(this.bank, this.path, this.stats);
  final QuestionBank bank;
  final List<Category> path;
  final LearningStats stats;
}

class BankScreen extends StatelessWidget {
  const BankScreen({super.key, required this.bankId});
  final String bankId;

  Future<_BankData?> _load() async {
    final svc = AppServices.I;
    final b = await svc.catalog.bank(bankId);
    if (b == null) return null;
    return _BankData(b, await svc.catalog.categoryPath(b.categoryId), await svc.stats.statsFor([b.id]));
  }

  @override
  Widget build(BuildContext context) {
    return Reloadable<_BankData?>(
      load: _load,
      loading: const Scaffold(body: Center(child: CircularProgressIndicator())),
      builder: (context, d, reload) {
        if (d == null) {
          return Scaffold(appBar: AppBar(), body: const Center(child: Text('This bank no longer exists.')));
        }
        final b = d.bank;
        final s = d.stats;
        QuizConfig cfg(SelectionMode m, {QuizStyle style = QuizStyle.practice}) =>
            defaultConfig(title: b.name, bankIds: [b.id], selection: m, style: style);
        void openList(String title, QuestionFilter f) => Navigator.push(context,
            MaterialPageRoute<void>(builder: (_) => QuestionListScreen(title: title, filter: f)));
        return Scaffold(
          appBar: AppBar(
            title: Text(b.name),
            actions: [
              PopupMenuButton<String>(
                onSelected: (v) => _menu(context, v, d),
                itemBuilder: (_) => [
                  const PopupMenuItem(value: 'edit', child: Text('Edit bank')),
                  const PopupMenuItem(value: 'move', child: Text('Move to another category')),
                  PopupMenuItem(value: 'archive', child: Text(b.archived ? 'Restore from archive' : 'Archive')),
                  const PopupMenuItem(value: 'delete', child: Text('Delete bank…')),
                ],
              ),
            ],
          ),
          floatingActionButton: FloatingActionButton(
            tooltip: 'Add question',
            onPressed: () => Navigator.push(context,
                MaterialPageRoute<void>(builder: (_) => QuestionEditorScreen(bankId: b.id))),
            child: const Icon(Icons.add),
          ),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
            children: [
              Readable(
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Text([...d.path.map((p) => p.name), b.name].join(' → '),
                      style: Theme.of(context).textTheme.bodySmall),
                  if (b.description != null && b.description!.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(b.description!),
                  ],
                  if (b.archived) ...[
                    const SizedBox(height: 8),
                    const Card(
                        child: ListTile(
                            leading: Icon(Icons.archive_outlined),
                            title: Text('This bank is archived and hidden from quizzes.'))),
                  ],
                  const SizedBox(height: 12),
                  StudyButtons(
                    newCount: s.unseen,
                    dueCount: s.dueToday,
                    onQuiz: () => Navigator.push(context,
                        MaterialPageRoute<void>(builder: (_) => QuizSetupScreen(initial: cfg(SelectionMode.random)))),
                    onNew: () => launchQuiz(context, cfg(SelectionMode.newQuestions)),
                    onDue: () => launchQuiz(context, cfg(SelectionMode.spaced).copyWith(questionCount: s.dueToday)),
                    onFlashcards: () => launchQuiz(context, cfg(SelectionMode.random, style: QuizStyle.flashcards)),
                  ),
                  const SizedBox(height: 16),
                  StatsPanel(
                    stats: s,
                    onTapDue: () => openList('Due today', QuestionFilter(bankIds: [b.id], dueForRevision: true)),
                    onTapNeverAttempted: () =>
                        openList('Never attempted', QuestionFilter(bankIds: [b.id], neverAttempted: true)),
                    onTapNeedsReview: () => openList('Needs review',
                        QuestionFilter(bankIds: [b.id], masteryLevels: {MasteryLevel.learning, MasteryLevel.needsPractice})),
                  ),
                  const SectionHeader('Questions'),
                  Card(
                    child: Column(children: [
                      ListTile(
                        leading: const Icon(Icons.list_alt),
                        title: const Text('Browse, search and filter'),
                        subtitle: Text('${s.total} questions'),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => openList(b.name, QuestionFilter(bankIds: [b.id])),
                      ),
                      ListTile(
                        leading: const Icon(Icons.add_circle_outline),
                        title: const Text('Add a question'),
                        onTap: () => Navigator.push(context,
                            MaterialPageRoute<void>(builder: (_) => QuestionEditorScreen(bankId: b.id))),
                      ),
                      ListTile(
                        leading: const Icon(Icons.upload_file),
                        title: const Text('Import from Excel'),
                        subtitle: const Text('Add more questions from an .xlsx file'),
                        onTap: () => Navigator.push(
                            context, MaterialPageRoute<void>(builder: (_) => ImportScreen(bankId: b.id))),
                      ),
                      ListTile(
                        leading: const Icon(Icons.history),
                        title: const Text('Import history'),
                        onTap: () => Navigator.push(
                            context, MaterialPageRoute<void>(builder: (_) => ImportHistoryScreen(bankId: b.id))),
                      ),
                      ListTile(
                        leading: const Icon(Icons.download_outlined),
                        title: const Text('Export to Excel'),
                        onTap: () => _export(context, b),
                      ),
                      ListTile(
                        leading: const Icon(Icons.content_copy_outlined),
                        title: const Text('Find duplicate questions'),
                        onTap: () => Navigator.push(
                            context, MaterialPageRoute<void>(builder: (_) => DuplicatesScreen(bankIds: [b.id]))),
                      ),
                    ]),
                  ),
                  const SectionHeader('Progress'),
                  Card(
                    child: Column(children: [
                      ListTile(
                        leading: const Icon(Icons.restart_alt),
                        title: const Text('Reset new-question progress'),
                        subtitle: const Text('Make all questions "new" again; history is kept'),
                        onTap: () async {
                          final ok = await confirm(context,
                              title: 'Reset new-question progress?',
                              message: 'All ${s.total} questions will count as new again in Learn New Questions '
                                  'mode. Your statistics, history and review schedule are kept.',
                              confirmLabel: 'Reset');
                          if (!ok) return;
                          await AppServices.I.study.resetNewProgress([b.id]);
                          AppServices.I.dataChanged();
                        },
                      ),
                      ListTile(
                        leading: const Icon(Icons.delete_sweep_outlined),
                        title: const Text('Clear learning progress'),
                        subtitle: const Text('Erase history, schedules and mastery for this bank'),
                        onTap: () async {
                          final ok = await confirmTyped(context,
                              title: 'Clear learning progress?',
                              message: 'This erases every answer, review schedule and mastery level for the '
                                  'questions in "${b.name}". The questions themselves are kept.',
                              word: 'CLEAR');
                          if (!ok) return;
                          await AppServices.I.study.clearLearningProgress([b.id]);
                          AppServices.I.dataChanged();
                        },
                      ),
                    ]),
                  ),
                ]),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _menu(BuildContext context, String v, _BankData d) async {
    switch (v) {
      case 'edit':
        await BankActions.edit(context, d.bank);
        break;
      case 'move':
        await BankActions.move(context, d.bank);
        break;
      case 'archive':
        await BankActions.toggleArchive(context, d.bank);
        break;
      case 'delete':
        final deleted = await BankActions.delete(context, d.bank);
        if (deleted && context.mounted) Navigator.pop(context);
        break;
    }
  }

  static Future<void> _export(BuildContext context, QuestionBank b) async {
    try {
      final f = await AppServices.I.exports.exportBank(b.id);
      final ok = await saveBytes(f.fileName, f.bytes, title: 'Export question bank');
      if (ok && context.mounted) showMessage(context, 'Exported ${f.fileName}');
    } catch (e) {
      if (context.mounted) showErrorDialog(context, 'Export failed', '$e');
    }
  }
}
