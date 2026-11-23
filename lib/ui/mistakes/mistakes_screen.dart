import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../app/services.dart';
import '../../core/grading.dart';
import '../../core/models.dart';
import '../../data/study_repository.dart';
import '../common/reloadable.dart';
import '../common/widgets.dart';
import '../questions/notes_section.dart';
import '../questions/question_detail_screen.dart';
import '../quiz/quiz_launcher.dart';

class _MistakeView {
  _MistakeView(this.entry, this.question);
  final MistakeEntry entry;
  final Question question;
}

/// Every question answered incorrectly, with your answer, the correct answer
/// and the explanation. Marking a mistake as understood hides it here and
/// from mistake quizzes, but never deletes its history.
class MistakesScreen extends StatefulWidget {
  const MistakesScreen({super.key});

  @override
  State<MistakesScreen> createState() => _MistakesScreenState();
}

class _MistakesScreenState extends State<MistakesScreen> {
  String? _subjectId;
  bool _repeated = false;
  bool _bookmarked = false;
  bool _includeUnderstood = false;
  List<Category> _subjects = const [];

  @override
  void initState() {
    super.initState();
    AppServices.I.catalog.allCategories(includeArchived: false).then((c) {
      if (mounted) setState(() => _subjects = c.where((x) => x.isSubject).toList());
    });
  }

  Future<(List<_MistakeView>, List<String>?)> _load() async {
    final svc = AppServices.I;
    final banks = _subjectId == null ? null : await svc.catalog.bankIdsUnder(_subjectId!);
    final entries = await svc.study.mistakes(
      bankIds: banks,
      repeatedOnly: _repeated,
      bookmarkedOnly: _bookmarked,
      includeUnderstood: _includeUnderstood,
      limit: 300,
    );
    final qs = {
      for (final q in await svc.questions.questionsByIds(entries.map((e) => e.progress.questionId).toList())) q.id: q
    };
    return (
      [
        for (final e in entries)
          if (qs[e.progress.questionId] != null) _MistakeView(e, qs[e.progress.questionId]!)
      ],
      banks
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Mistakes Notebook')),
      body: Reloadable<(List<_MistakeView>, List<String>?)>(
        key: ValueKey('$_subjectId-$_repeated-$_bookmarked-$_includeUnderstood'),
        load: _load,
        builder: (context, data, reload) {
          final (list, _) = data;
          return ListView(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 32),
            children: [
              Readable(
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Wrap(spacing: 6, runSpacing: 6, children: [
                    if (_subjects.isNotEmpty)
                      DropdownButton<String?>(
                        value: _subjectId,
                        hint: const Text('All subjects'),
                        items: [
                          const DropdownMenuItem<String?>(value: null, child: Text('All subjects')),
                          for (final s in _subjects) DropdownMenuItem<String?>(value: s.id, child: Text(s.name)),
                        ],
                        onChanged: (v) => setState(() => _subjectId = v),
                      ),
                    FilterChip(
                        label: const Text('Repeated mistakes'),
                        selected: _repeated,
                        onSelected: (v) => setState(() => _repeated = v)),
                    FilterChip(
                        label: const Text('Bookmarked'),
                        selected: _bookmarked,
                        onSelected: (v) => setState(() => _bookmarked = v)),
                    FilterChip(
                        label: const Text('Show understood'),
                        selected: _includeUnderstood,
                        onSelected: (v) => setState(() => _includeUnderstood = v)),
                  ]),
                  const SizedBox(height: 8),
                  if (list.isEmpty)
                    const Padding(
                      padding: EdgeInsets.only(top: 40),
                      child: EmptyState(
                        icon: Icons.celebration_outlined,
                        title: 'No mistakes here',
                        message: 'Questions you answer incorrectly are collected here automatically.',
                      ),
                    )
                  else ...[
                    Row(children: [
                      Expanded(child: Text('${list.length} questions')),
                      FilledButton.icon(
                        onPressed: () => launchQuiz(
                          context,
                          defaultConfig(
                            title: 'Mistakes',
                            selection: SelectionMode.random,
                            fixedQuestionIds: list.map((m) => m.question.id).toList(),
                            count: list.length > 25 ? 25 : list.length,
                          ),
                        ),
                        icon: const Icon(Icons.play_arrow),
                        label: const Text('Quiz from mistakes'),
                      ),
                    ]),
                    const SizedBox(height: 8),
                    for (final m in list) _card(context, m),
                  ],
                ]),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _card(BuildContext context, _MistakeView m) {
    final svc = AppServices.I;
    final t = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final p = m.entry.progress;
    final q = m.question;
    final fmt = DateFormat.yMMMd();
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(
                child: InkWell(
                  onTap: () => Navigator.push(context,
                      MaterialPageRoute<void>(builder: (_) => QuestionDetailScreen(questionId: q.id))),
                  child: ContentText(q.text, style: t.titleSmall),
                ),
              ),
              IconButton(
                tooltip: m.entry.bookmarked ? 'Remove bookmark' : 'Bookmark',
                icon: Icon(m.entry.bookmarked ? Icons.bookmark : Icons.bookmark_border),
                onPressed: () async {
                  await svc.questions.toggleBookmark(q.id);
                  svc.dataChanged();
                },
              ),
            ]),
            const SizedBox(height: 6),
            Text('My answer', style: t.labelMedium?.copyWith(color: scheme.error)),
            ContentText(describeResponse(q, m.entry.lastWrongResponse)),
            const SizedBox(height: 6),
            Text('Correct answer', style: t.labelMedium),
            ContentText(q.correctAnswerText, style: const TextStyle(fontWeight: FontWeight.w600)),
            if ((q.explanation ?? '').isNotEmpty) ...[
              const SizedBox(height: 6),
              Text('Explanation', style: t.labelMedium),
              ContentText(q.explanation!),
            ],
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
              MasteryChip(p.mastery, dense: true),
              Text('Wrong ${p.incorrectCount}×', style: t.bodySmall),
              if (m.entry.lastWrongAt != null) Text('Last: ${fmt.format(m.entry.lastWrongAt!)}', style: t.bodySmall),
              if (p.understood) Text('Understood', style: t.bodySmall?.copyWith(fontStyle: FontStyle.italic)),
            ]),
            Row(children: [
              TextButton.icon(
                onPressed: () => showModalBottomSheet<void>(
                  context: context,
                  showDragHandle: true,
                  isScrollControlled: true,
                  builder: (_) => Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                    child: NotesSection(questionId: q.id),
                  ),
                ),
                icon: const Icon(Icons.sticky_note_2_outlined),
                label: const Text('Notes'),
              ),
              const Spacer(),
              TextButton.icon(
                onPressed: () async {
                  await svc.study.setUnderstood(q.id, !p.understood);
                  svc.dataChanged();
                  if (context.mounted && !p.understood) {
                    showMessage(context, 'Marked as understood. Its history is kept.');
                  }
                },
                icon: Icon(p.understood ? Icons.undo : Icons.task_alt),
                label: Text(p.understood ? 'Not understood' : 'Mark as understood'),
              ),
            ]),
          ]),
        ),
      ),
    );
  }
}
