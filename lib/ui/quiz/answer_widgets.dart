import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../core/grading.dart';
import '../../core/models.dart';
import '../../core/shuffle.dart';
import '../common/widgets.dart';

/// Renders the answer area for any question type.
///
/// [order] is the stored display order of option ids for this presentation;
/// [revealed] shows correctness (only ever true when feedback is allowed).
class AnswerArea extends StatelessWidget {
  const AnswerArea({
    super.key,
    required this.question,
    required this.order,
    required this.response,
    required this.onChanged,
    required this.revealed,
    required this.locked,
    this.textController,
  });

  final Question question;
  final List<String> order;
  final QuestionResponse response;
  final ValueChanged<QuestionResponse> onChanged;
  final bool revealed;
  final bool locked;
  final TextEditingController? textController;

  List<AnswerOption> get _ordered {
    final byId = {for (final o in question.options) o.id: o};
    final list = [for (final id in order) if (byId[id] != null) byId[id]!];
    // Options added after the quiz started still appear, at the end.
    for (final o in question.options) {
      if (!order.contains(o.id)) list.add(o);
    }
    return list;
  }

  @override
  Widget build(BuildContext context) {
    switch (question.type) {
      case QuestionType.single:
      case QuestionType.trueFalse:
      case QuestionType.multiple:
        return _choices(context);
      case QuestionType.fillBlank:
      case QuestionType.shortAnswer:
        return _typed(context);
      case QuestionType.matching:
        return _matching(context);
      case QuestionType.flashcard:
        return _flashcard(context);
    }
  }

  Widget _choices(BuildContext context) {
    final multi = question.type == QuestionType.multiple;
    final scheme = Theme.of(context).colorScheme;
    final reduce = MediaQuery.of(context).disableAnimations;
    final glass = Theme.of(context).extension<GlassTheme>() != null;
    final opts = _ordered;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (multi)
        Padding(
          padding: const EdgeInsets.only(bottom: 8, left: 4),
          child: Text('Select all that apply', style: Theme.of(context).textTheme.bodySmall),
        ),
      for (var i = 0; i < opts.length; i++)
        Builder(builder: (context) {
          final o = opts[i];
          final selected = response.selected.contains(o.id);
          var accent = scheme.primary;
          var active = selected;
          IconData? mark = selected ? Icons.check_circle : null;
          var dim = false;
          if (revealed) {
            if (o.isCorrect) {
              accent = correctColor(scheme);
              active = true;
              mark = Icons.check_circle;
            } else if (selected) {
              accent = incorrectColor(scheme);
              active = true;
              mark = Icons.cancel;
            } else {
              dim = true;
              mark = null;
            }
          }
          final isTf = question.type == QuestionType.trueFalse;
          final letter = optionLetter(i);
          // Glass themes fill the active option with solid colour.
          final solid = glass && active;
          final onAccent = accent == scheme.primary ? scheme.onPrimary : Colors.white;
          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Semantics(
              button: true,
              selected: selected,
              label: '${isTf ? '' : 'Option $letter: '}${o.text}'
                  '${revealed && o.isCorrect ? ', correct answer' : ''}'
                  '${revealed && selected && !o.isCorrect ? ', your answer, incorrect' : ''}',
              excludeSemantics: true,
              child: AnimatedOpacity(
                duration: reduce ? Duration.zero : const Duration(milliseconds: 200),
                opacity: dim ? 0.55 : 1,
                child: AnimatedContainer(
                  duration: reduce ? Duration.zero : const Duration(milliseconds: 180),
                  decoration: BoxDecoration(
                    color: solid ? accent : (active ? accent.withValues(alpha: 0.10) : scheme.surfaceContainerLow),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                        color: active ? accent : scheme.outlineVariant, width: active ? 2 : 1),
                    boxShadow: active && !reduce
                        ? [BoxShadow(color: accent.withValues(alpha: 0.22), blurRadius: 12, offset: const Offset(0, 3))]
                        : null,
                  ),
                  child: Material(
                    type: MaterialType.transparency,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(16),
                      onTap: locked
                          ? null
                          : () {
                              final s = {...response.selected};
                              if (multi) {
                                selected ? s.remove(o.id) : s.add(o.id);
                              } else {
                                s
                                  ..clear()
                                  ..add(o.id);
                              }
                              onChanged(response.copyWith(selected: s));
                            },
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(minHeight: 60),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          child: Row(children: [
                            AnimatedContainer(
                              duration: reduce ? Duration.zero : const Duration(milliseconds: 180),
                              width: 38,
                              height: 38,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: solid
                                    ? onAccent.withValues(alpha: 0.22)
                                    : (active ? accent : scheme.surfaceContainerHighest),
                                borderRadius: BorderRadius.circular(multi ? 8 : 11),
                              ),
                              child: isTf
                                  ? Icon(o.isCorrect && revealed ? Icons.check : (selected ? Icons.check : Icons.circle_outlined),
                                      size: 18, color: solid ? onAccent : (active ? Colors.white : scheme.onSurfaceVariant))
                                  : Text(letter,
                                      style: TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w800,
                                          color: solid ? onAccent : (active ? Colors.white : scheme.onSurface))),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: ContentText(o.text,
                                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                                      fontWeight: active ? FontWeight.w600 : FontWeight.w500,
                                      color: solid ? onAccent : (active ? accent : null))),
                            ),
                            if (mark != null) ...[
                              const SizedBox(width: 8),
                              Icon(mark, color: solid ? onAccent : accent, size: 26),
                            ],
                          ]),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
        }),
    ]);
  }

  Widget _typed(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final outcome = revealed ? grade(question, response) : null;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      TextField(
        controller: textController,
        enabled: !locked,
        minLines: question.type == QuestionType.shortAnswer ? 2 : 1,
        maxLines: question.type == QuestionType.shortAnswer ? 5 : 1,
        textCapitalization: TextCapitalization.none,
        autocorrect: false,
        style: Theme.of(context).textTheme.bodyLarge,
        decoration: InputDecoration(
          labelText: question.type == QuestionType.fillBlank ? 'Your answer' : 'Type your answer',
          suffixIcon: outcome == GradeOutcome.correct
              ? Icon(Icons.check_circle, color: correctColor(scheme))
              : outcome == GradeOutcome.incorrect
                  ? Icon(Icons.cancel, color: incorrectColor(scheme))
                  : null,
        ),
        onChanged: (v) => onChanged(response.copyWith(text: v)),
      ),
      if (revealed) ...[
        const SizedBox(height: 10),
        Text('Accepted answers:', style: Theme.of(context).textTheme.labelLarge),
        for (final a in acceptedAnswersOf(question)) ContentText('• $a'),
      ],
    ]);
  }

  Widget _matching(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final left = [...question.options]..sort((a, b) => a.position.compareTo(b.position));
    final right = _ordered; // shuffled right-hand column
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text('Match each item', style: Theme.of(context).textTheme.bodySmall),
      const SizedBox(height: 8),
      for (final l in left)
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Builder(builder: (context) {
            final chosenId = response.matches[l.id];
            final chosen = question.options.where((x) => x.id == chosenId);
            final ok = chosen.isNotEmpty &&
                normalizeAnswer(chosen.first.matchText ?? '') == normalizeAnswer(l.matchText ?? '');
            return Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  ContentText(l.text, style: const TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 6),
                  DropdownButton<String>(
                    isExpanded: true,
                    value: chosenId,
                    hint: const Text('Choose a match'),
                    items: [
                      for (final r in right)
                        DropdownMenuItem(value: r.id, child: ContentText(r.matchText ?? '', maxLines: 2)),
                    ],
                    onChanged: locked
                        ? null
                        : (v) {
                            if (v == null) return;
                            final m = {...response.matches, l.id: v};
                            onChanged(response.copyWith(matches: m));
                          },
                  ),
                  if (revealed)
                    Row(children: [
                      Icon(ok ? Icons.check_circle : Icons.cancel,
                          size: 18, color: ok ? correctColor(scheme) : incorrectColor(scheme)),
                      const SizedBox(width: 6),
                      Expanded(child: Text(ok ? 'Correct' : 'Correct match: ${l.matchText ?? ''}')),
                    ]),
                ]),
              ),
            );
          }),
        ),
    ]);
  }

  Widget _flashcard(BuildContext context) {
    final back = question.acceptedAnswers.isEmpty ? '' : question.acceptedAnswers.first;
    final shown = response.text == 'revealed' || response.selfGrade != null || revealed;
    if (!shown) {
      return OutlinedButton.icon(
        onPressed: locked ? null : () => onChanged(response.copyWith(text: 'revealed')),
        icon: const Icon(Icons.visibility_outlined),
        label: const Text('Show answer'),
      );
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Card(
        color: Theme.of(context).colorScheme.secondaryContainer,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: ContentText(back, style: Theme.of(context).textTheme.titleMedium),
        ),
      ),
      const SizedBox(height: 12),
      Text('Did you remember it?', style: Theme.of(context).textTheme.labelLarge),
      const SizedBox(height: 6),
      Row(children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: locked ? null : () => onChanged(response.copyWith(selfGrade: false)),
            icon: Icon(response.selfGrade == false ? Icons.radio_button_checked : Icons.close),
            label: const Text('Forgot'),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: OutlinedButton.icon(
            onPressed: locked ? null : () => onChanged(response.copyWith(selfGrade: true)),
            icon: Icon(response.selfGrade == true ? Icons.radio_button_checked : Icons.check),
            label: const Text('Remembered'),
          ),
        ),
      ]),
    ]);
  }
}

/// Correct / incorrect panel with feedback messages and explanations.
class FeedbackPanel extends StatelessWidget {
  const FeedbackPanel({super.key, required this.question, required this.response, required this.result});
  final Question question;
  final QuestionResponse response;
  final AttemptResult result;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    final correct = result == AttemptResult.correct;
    final color = correct ? correctColor(scheme) : incorrectColor(scheme);
    final message = correct ? question.correctFeedback : question.incorrectFeedback;
    final whyWrong = correct ? const <String>[] : wrongChoiceExplanations(question, response);
    return Semantics(
      liveRegion: true,
      child: Card(
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16), side: BorderSide(color: color, width: 2)),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              Icon(correct ? Icons.check_circle : Icons.cancel, color: color, size: 28),
              const SizedBox(width: 10),
              Text(correct ? 'Correct!' : 'Incorrect',
                  style: t.titleLarge?.copyWith(color: color, fontWeight: FontWeight.w700)),
            ]),
            if (!correct && question.type != QuestionType.matching) ...[
              const SizedBox(height: 10),
              Text('Correct answer', style: t.labelLarge),
              ContentText(question.correctAnswerText, style: t.bodyLarge?.copyWith(fontWeight: FontWeight.w600)),
            ],
            if ((message ?? '').isNotEmpty) ...[
              const SizedBox(height: 10),
              ContentText(message!),
            ],
            for (final w in whyWrong) ...[
              const SizedBox(height: 10),
              Text('Why your choice is wrong', style: t.labelLarge),
              ContentText(w),
            ],
            if ((question.explanation ?? '').isNotEmpty) ...[
              const SizedBox(height: 10),
              Text('Explanation', style: t.labelLarge),
              ContentText(question.explanation!),
            ],
          ]),
        ),
      ),
    );
  }
}

/// Easy / Medium / Hard / Didn't know selector.
class ConfidencePicker extends StatelessWidget {
  const ConfidencePicker({super.key, required this.value, required this.onChanged, this.label = 'How well did you know it?'});
  final Confidence? value;
  final ValueChanged<Confidence?> onChanged;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: Theme.of(context).textTheme.labelLarge),
      const SizedBox(height: 6),
      Wrap(spacing: 6, runSpacing: 6, children: [
        for (final c in Confidence.values.reversed)
          ChoiceChip(
            label: Text(c.label),
            selected: value == c,
            onSelected: (s) => onChanged(s ? c : null),
          ),
      ]),
    ]);
  }
}
