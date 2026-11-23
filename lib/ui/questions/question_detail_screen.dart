import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../app/services.dart';
import '../../app/theme.dart';
import '../../core/grading.dart';
import '../../core/models.dart';
import '../../core/shuffle.dart';
import '../banks/node_editor.dart';
import '../common/reloadable.dart';
import '../common/widgets.dart';
import '../quiz/question_media.dart';
import 'notes_section.dart';
import 'question_editor_screen.dart';

class _DetailData {
  _DetailData(this.q, this.p, this.bookmarked, this.attempts, this.bankName);
  final Question q;
  final QuestionProgress p;
  final bool bookmarked;
  final List<Map<String, Object?>> attempts;
  final String bankName;
}

/// Full view of one question: content, correct answer, mastery with its
/// explanation, attempt history, notes, and management actions.
class QuestionDetailScreen extends StatelessWidget {
  const QuestionDetailScreen({super.key, required this.questionId});
  final String questionId;

  Future<_DetailData?> _load() async {
    final svc = AppServices.I;
    final q = await svc.questions.question(questionId);
    if (q == null) return null;
    return _DetailData(
      q,
      await svc.study.progressOf(q.id),
      await svc.questions.isBookmarked(q.id),
      await svc.study.attemptsOf(q.id),
      (await svc.catalog.bank(q.bankId))?.name ?? '',
    );
  }

  @override
  Widget build(BuildContext context) {
    return Reloadable<_DetailData?>(
      load: _load,
      loading: const Scaffold(body: Center(child: CircularProgressIndicator())),
      builder: (context, d, reload) {
        if (d == null) {
          return Scaffold(appBar: AppBar(), body: const Center(child: Text('This question was deleted.')));
        }
        final q = d.q;
        final p = d.p;
        final theme = Theme.of(context);
        final scheme = theme.colorScheme;
        final svc = AppServices.I;
        final fmt = DateFormat.yMMMd().add_Hm();
        return Scaffold(
          appBar: AppBar(
            title: Text(d.bankName),
            actions: [
              IconButton(
                tooltip: d.bookmarked ? 'Remove bookmark' : 'Bookmark',
                icon: Icon(d.bookmarked ? Icons.bookmark : Icons.bookmark_border),
                onPressed: () async {
                  await svc.questions.toggleBookmark(q.id);
                  svc.dataChanged();
                },
              ),
              IconButton(
                tooltip: 'Edit',
                icon: const Icon(Icons.edit_outlined),
                onPressed: () => Navigator.push(context,
                    MaterialPageRoute<void>(builder: (_) => QuestionEditorScreen(bankId: q.bankId, question: q))),
              ),
              PopupMenuButton<String>(
                onSelected: (v) => _action(context, v, q),
                itemBuilder: (_) => [
                  const PopupMenuItem(value: 'duplicate', child: Text('Duplicate')),
                  const PopupMenuItem(value: 'move', child: Text('Move to another bank')),
                  const PopupMenuItem(value: 'reset', child: Text('Reset review schedule')),
                  PopupMenuItem(value: 'archive', child: Text(q.archived ? 'Restore from archive' : 'Archive')),
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
                  Wrap(spacing: 8, runSpacing: 6, children: [
                    MasteryChip(p.mastery),
                    Chip(label: Text(q.type.label), visualDensity: VisualDensity.compact),
                    Chip(label: Text(q.difficulty.label), visualDensity: VisualDensity.compact),
                    for (final t in q.tags) Chip(label: Text('#$t'), visualDensity: VisualDensity.compact),
                  ]),
                  const SizedBox(height: 12),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                        ContentText(q.text, style: theme.textTheme.titleMedium),
                        QuestionMedia(question: q),
                        const SizedBox(height: 12),
                        ..._answer(context, q),
                      ]),
                    ),
                  ),
                  if ((q.explanation ?? '').isNotEmpty || (q.hint ?? '').isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          if ((q.hint ?? '').isNotEmpty) ...[
                            Text('Hint', style: theme.textTheme.labelLarge),
                            ContentText(q.hint!),
                            const SizedBox(height: 10),
                          ],
                          if ((q.explanation ?? '').isNotEmpty) ...[
                            Text('Explanation', style: theme.textTheme.labelLarge),
                            ContentText(q.explanation!),
                          ],
                          if ((q.source ?? '').isNotEmpty) ...[
                            const SizedBox(height: 10),
                            Text('Source', style: theme.textTheme.labelLarge),
                            ContentText(q.source!),
                          ],
                          if ((q.studyNotes ?? '').isNotEmpty) ...[
                            const SizedBox(height: 10),
                            Text('Study notes', style: theme.textTheme.labelLarge),
                            ContentText(q.studyNotes!),
                          ],
                        ]),
                      ),
                    ),
                  ],
                  const SectionHeader('Learning status'),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Row(children: [
                          Icon(masteryIcon(p.mastery), color: masteryColor(p.mastery, scheme)),
                          const SizedBox(width: 8),
                          Text(p.mastery.label, style: theme.textTheme.titleMedium),
                        ]),
                        const SizedBox(height: 6),
                        Text('Why: ${p.masteryReason.isEmpty ? 'Not answered yet.' : p.masteryReason}'),
                        const Divider(height: 24),
                        _kv('Answered', '${p.attemptCount} times (${p.correctCount} correct, ${p.incorrectCount} wrong)'),
                        _kv('Accuracy', percent(p.accuracy)),
                        _kv('Skipped', '${p.skippedCount}'),
                        _kv('Hints used', '${p.hintCount}'),
                        _kv('Next review',
                            p.dueAt == null ? 'Not scheduled yet' : DateFormat.yMMMEd().format(p.dueAt!)),
                        _kv('Review interval', p.intervalDays == 0 ? '—' : '${p.intervalDays} days'),
                        _kv('Successful reviews in a row', '${p.repetitions}'),
                        _kv('Times forgotten', '${p.lapses}'),
                        _kv('Last answered', p.lastAttemptAt == null ? 'Never' : fmt.format(p.lastAttemptAt!)),
                        _kv('New-question status', p.seen ? 'Already presented' : 'New (never presented)'),
                      ]),
                    ),
                  ),
                  const SectionHeader('My notes'),
                  NotesSection(questionId: q.id),
                  if (d.attempts.isNotEmpty) ...[
                    const SectionHeader('Answer history'),
                    Card(
                      child: Column(children: [
                        for (final a in d.attempts)
                          ListTile(
                            dense: true,
                            leading: Icon(
                              a['result'] == 'correct'
                                  ? Icons.check_circle
                                  : a['result'] == 'incorrect'
                                      ? Icons.cancel
                                      : Icons.remove_circle_outline,
                              color: a['result'] == 'correct'
                                  ? correctColor(scheme)
                                  : a['result'] == 'incorrect'
                                      ? incorrectColor(scheme)
                                      : null,
                            ),
                            title: Text(describeResponse(q, QuestionResponse.decode(a['response'] as String?))),
                            subtitle: Text([
                              fmt.format(DateTime.fromMillisecondsSinceEpoch(a['answered_at'] as int)),
                              if (a['hint_used'] == 1) 'hint used',
                              if (a['confidence'] != null)
                                Confidence.fromIndex(a['confidence'] as int)?.label ?? '',
                              if ((a['content_version'] as int? ?? 1) != q.contentVersion) 'earlier version',
                            ].join(' · ')),
                          ),
                      ]),
                    ),
                  ],
                ]),
              ),
            ],
          ),
        );
      },
    );
  }

  static Widget _kv(String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(flex: 5, child: Text(k)),
          Expanded(flex: 6, child: Text(v, style: const TextStyle(fontWeight: FontWeight.w600))),
        ]),
      );

  static List<Widget> _answer(BuildContext context, Question q) {
    final scheme = Theme.of(context).colorScheme;
    switch (q.type) {
      case QuestionType.single:
      case QuestionType.multiple:
      case QuestionType.trueFalse:
        return [
          for (var i = 0; i < q.options.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Icon(q.options[i].isCorrect ? Icons.check_circle : Icons.circle_outlined,
                    size: 20, color: q.options[i].isCorrect ? correctColor(scheme) : scheme.outline),
                const SizedBox(width: 8),
                Text('${optionLetter(i)}. '),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    ContentText(q.options[i].text),
                    if ((q.options[i].explanation ?? '').isNotEmpty)
                      ContentText(q.options[i].explanation!,
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(fontStyle: FontStyle.italic)),
                  ]),
                ),
              ]),
            ),
        ];
      case QuestionType.matching:
        return [
          for (final o in q.options)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(children: [
                Expanded(child: ContentText(o.text)),
                const Icon(Icons.arrow_forward, size: 16),
                const SizedBox(width: 6),
                Expanded(child: ContentText(o.matchText ?? '')),
              ]),
            ),
        ];
      case QuestionType.fillBlank:
      case QuestionType.shortAnswer:
      case QuestionType.flashcard:
        final acc = acceptedAnswersOf(q);
        return [
          Text(q.type == QuestionType.flashcard ? 'Back of the card' : 'Accepted answers',
              style: Theme.of(context).textTheme.labelLarge),
          for (final a in acc) ContentText('• $a'),
          if (q.caseSensitive) const Text('Case sensitive', style: TextStyle(fontStyle: FontStyle.italic)),
        ];
    }
  }

  static Future<void> _action(BuildContext context, String v, Question q) async {
    final svc = AppServices.I;
    switch (v) {
      case 'duplicate':
        final copy = await svc.questions.duplicate(q.id);
        svc.dataChanged();
        if (context.mounted) {
          Navigator.pushReplacement(
              context, MaterialPageRoute<void>(builder: (_) => QuestionDetailScreen(questionId: copy.id)));
        }
        break;
      case 'move':
        final bank = await pickBank(context, title: 'Move question to…', excludeBankId: q.bankId);
        if (bank == null) return;
        await svc.questions.move([q.id], bank);
        svc.dataChanged();
        break;
      case 'reset':
        final ok = await confirm(context,
            title: 'Reset review schedule?',
            message: 'The question starts again as if never reviewed. Its answer history is kept.',
            confirmLabel: 'Reset');
        if (!ok) return;
        await svc.study.resetQuestionSchedule(q.id);
        svc.dataChanged();
        break;
      case 'archive':
        await svc.questions.setArchived([q.id], !q.archived);
        svc.dataChanged();
        break;
      case 'delete':
        final ok = await confirm(context,
            title: 'Delete this question?',
            message: 'The question, its notes and its learning history will be permanently deleted.',
            confirmLabel: 'Delete',
            destructive: true);
        if (!ok) return;
        await svc.questions.delete([q.id]);
        svc.dataChanged();
        if (context.mounted) Navigator.pop(context);
        break;
    }
  }
}

