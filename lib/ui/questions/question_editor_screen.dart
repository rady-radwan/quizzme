import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../app/services.dart';
import '../../core/grading.dart';
import '../../core/ids.dart';
import '../../core/models.dart';
import '../../core/shuffle.dart';
import '../banks/node_editor.dart';
import '../common/file_io.dart';
import '../common/widgets.dart';

class _OptionRow {
  _OptionRow({String? id, String text = '', this.correct = false, String? match, String? explanation})
      : id = id ?? newId(),
        text = TextEditingController(text: text),
        match = TextEditingController(text: match ?? ''),
        explanation = TextEditingController(text: explanation ?? '');
  final String id;
  final TextEditingController text;
  final TextEditingController match;
  final TextEditingController explanation;
  bool correct;
  bool showExplanation = false;

  void dispose() {
    text.dispose();
    match.dispose();
    explanation.dispose();
  }
}

/// Create or edit any question type.
class QuestionEditorScreen extends StatefulWidget {
  const QuestionEditorScreen({super.key, required this.bankId, this.question});
  final String bankId;
  final Question? question;

  @override
  State<QuestionEditorScreen> createState() => _QuestionEditorScreenState();
}

class _QuestionEditorScreenState extends State<QuestionEditorScreen> {
  late QuestionType _type;
  late String _bankId;
  late Difficulty _difficulty;
  late bool _shuffle;
  late bool _caseSensitive;
  String? _image;
  String? _audio;
  final _text = TextEditingController();
  final _hint = TextEditingController();
  final _correctFb = TextEditingController();
  final _incorrectFb = TextEditingController();
  final _explanation = TextEditingController();
  final _tags = TextEditingController();
  final _source = TextEditingController();
  final _notes = TextEditingController();
  final _accepted = <TextEditingController>[];
  final _options = <_OptionRow>[];
  bool _saving = false;

  bool get _isEdit => widget.question != null;

  @override
  void initState() {
    super.initState();
    final q = widget.question;
    _bankId = q?.bankId ?? widget.bankId;
    _type = q?.type ?? QuestionType.single;
    _difficulty = q?.difficulty ?? Difficulty.medium;
    _shuffle = q?.shuffleOptions ?? true;
    _caseSensitive = q?.caseSensitive ?? false;
    _image = q?.imagePath;
    _audio = q?.audioPath;
    _text.text = q?.text ?? '';
    _hint.text = q?.hint ?? '';
    _correctFb.text = q?.correctFeedback ?? '';
    _incorrectFb.text = q?.incorrectFeedback ?? '';
    _explanation.text = q?.explanation ?? '';
    _tags.text = q?.tags.join(', ') ?? '';
    _source.text = q?.source ?? '';
    _notes.text = q?.studyNotes ?? '';
    if (q != null) {
      for (final o in q.options) {
        _options.add(_OptionRow(
            id: o.id, text: o.text, correct: o.isCorrect, match: o.matchText, explanation: o.explanation)
          ..showExplanation = (o.explanation ?? '').isNotEmpty);
      }
      for (final a in q.acceptedAnswers) {
        _accepted.add(TextEditingController(text: a));
      }
    }
    _ensureShape();
  }

  @override
  void dispose() {
    for (final c in [_text, _hint, _correctFb, _incorrectFb, _explanation, _tags, _source, _notes, ..._accepted]) {
      c.dispose();
    }
    for (final o in _options) {
      o.dispose();
    }
    super.dispose();
  }

  /// Makes sure the option/answer lists suit the current type.
  void _ensureShape() {
    switch (_type) {
      case QuestionType.trueFalse:
        if (_options.length != 2) {
          final wasTrue = _options.isNotEmpty && _options.first.correct;
          for (final o in _options) {
            o.dispose();
          }
          _options
            ..clear()
            ..add(_OptionRow(text: 'True', correct: wasTrue))
            ..add(_OptionRow(text: 'False', correct: !wasTrue));
        }
        break;
      case QuestionType.single:
      case QuestionType.multiple:
      case QuestionType.matching:
        while (_options.length < (_type == QuestionType.matching ? 3 : 4)) {
          _options.add(_OptionRow(correct: _type == QuestionType.matching));
        }
        if (_type == QuestionType.matching) {
          for (final o in _options) {
            o.correct = true;
          }
        }
        break;
      case QuestionType.fillBlank:
      case QuestionType.shortAnswer:
      case QuestionType.flashcard:
        if (_accepted.isEmpty) _accepted.add(TextEditingController());
        break;
    }
  }

  Question _build() {
    final keepOptions = _type.usesChoices || _type == QuestionType.matching;
    final opts = <AnswerOption>[];
    if (keepOptions) {
      var pos = 0;
      for (final o in _options) {
        if (o.text.text.trim().isEmpty) continue;
        opts.add(AnswerOption(
          id: o.id,
          position: pos++,
          text: o.text.text.trim(),
          isCorrect: _type == QuestionType.matching ? true : o.correct,
          matchText: _type == QuestionType.matching ? o.match.text.trim() : null,
          explanation: o.explanation.text.trim().isEmpty ? null : o.explanation.text.trim(),
        ));
      }
    }
    String? opt(TextEditingController c) => c.text.trim().isEmpty ? null : c.text.trim();
    final base = widget.question;
    final accepted = _type.usesTypedAnswer || _type == QuestionType.flashcard
        ? _accepted.map((c) => c.text.trim()).where((t) => t.isNotEmpty).toList()
        : <String>[];
    final q = Question(
      id: base?.id ?? newId(),
      bankId: _bankId,
      type: _type,
      text: _text.text.trim(),
      options: opts,
      externalId: base?.externalId,
      hint: opt(_hint),
      explanation: opt(_explanation),
      correctFeedback: opt(_correctFb),
      incorrectFeedback: opt(_incorrectFb),
      difficulty: _difficulty,
      tags: splitTagInput(_tags.text),
      shuffleOptions: _shuffle,
      caseSensitive: _caseSensitive,
      acceptedAnswers: accepted,
      source: opt(_source),
      studyNotes: opt(_notes),
      imagePath: _image,
      audioPath: _audio,
      importId: base?.importId,
      contentVersion: base?.contentVersion ?? 1,
      archived: base?.archived ?? false,
      createdAt: base?.createdAt,
    );
    return q;
  }

  String? _validate(Question q) {
    if (q.text.isEmpty) return 'Please enter the question text.';
    switch (q.type) {
      case QuestionType.single:
      case QuestionType.multiple:
        if (q.options.length < 2) return 'Add at least two answer options.';
        final n = q.options.where((o) => o.isCorrect).length;
        if (n == 0) return 'Mark the correct answer.';
        if (q.type == QuestionType.single && n > 1) {
          return 'Only one answer can be correct. Choose "Multiple choice (several answers)" for more.';
        }
        break;
      case QuestionType.trueFalse:
        if (q.options.where((o) => o.isCorrect).length != 1) return 'Choose whether the statement is true or false.';
        break;
      case QuestionType.matching:
        if (q.options.length < 2) return 'Add at least two pairs.';
        if (q.options.any((o) => (o.matchText ?? '').isEmpty)) return 'Every item needs a match.';
        break;
      case QuestionType.fillBlank:
      case QuestionType.shortAnswer:
      case QuestionType.flashcard:
        if (q.acceptedAnswers.isEmpty) {
          return q.type == QuestionType.flashcard ? 'Enter the answer for the back of the card.' : 'Enter at least one accepted answer.';
        }
        break;
    }
    return null;
  }

  String _answerKey(Question q) {
    final c = q.options.where((o) => o.isCorrect).map((o) => normalizeAnswer('${o.text}=${o.matchText ?? ''}')).toList()
      ..sort();
    final a = q.acceptedAnswers.map(normalizeAnswer).toList()..sort();
    return '${q.type.key}|${c.join('|')}|${a.join('|')}';
  }

  Future<void> _save() async {
    final q = _build();
    final err = _validate(q);
    if (err != null) {
      showMessage(context, err);
      return;
    }
    final svc = AppServices.I;
    var reset = false;
    final old = widget.question;
    if (old != null && _answerKey(old) != _answerKey(q)) {
      final p = await svc.study.progressOf(old.id);
      if (!mounted) return;
      if (p.attemptCount > 0) {
        final choice = await showDialog<String>(
          context: context,
          builder: (c) => AlertDialog(
            title: const Text('The correct answer changed'),
            content: Text('This question has been answered ${p.attemptCount} times. Earlier answers may no '
                'longer be valid. Reset its mastery and review schedule? The answer history is kept either way.'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(c), child: const Text('Cancel')),
              TextButton(onPressed: () => Navigator.pop(c, 'keep'), child: const Text('Keep progress')),
              FilledButton(onPressed: () => Navigator.pop(c, 'reset'), child: const Text('Reset progress')),
            ],
          ),
        );
        if (choice == null) return;
        reset = choice == 'reset';
      }
    }
    setState(() => _saving = true);
    try {
      await svc.questions.saveQuestion(q, resetLearning: reset);
      svc.dataChanged();
      if (!mounted) return;
      showMessage(context, _isEdit ? 'Question saved' : 'Question added');
      Navigator.pop(context, true);
    } catch (e) {
      if (mounted) showErrorDialog(context, 'Could not save', '$e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _pickMedia(bool image) async {
    final f = await pickFile(
        extensions: image ? null : ['mp3', 'm4a', 'aac', 'wav', 'ogg', 'flac'],
        type: image ? FileType.image : FileType.custom);
    if (f == null) return;
    try {
      final rel = await AppServices.I.media.save(f.bytes, f.name);
      setState(() {
        if (image) {
          _image = rel;
        } else {
          _audio = rel;
        }
      });
    } catch (e) {
      if (mounted) showMessage(context, '$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(
        title: Text(_isEdit ? 'Edit question' : 'New question'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FilledButton(onPressed: _saving ? null : _save, child: const Text('Save')),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 48),
        children: [
          Readable(
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              if (!_isEdit)
                FutureBuilder<String>(
                  future: AppServices.I.catalog.bank(_bankId).then((b) => b?.name ?? ''),
                  builder: (context, s) => ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.folder_outlined),
                    title: Text('Bank: ${s.data ?? ''}'),
                    trailing: TextButton(
                      onPressed: () async {
                        final b = await pickBank(context);
                        if (b != null) setState(() => _bankId = b);
                      },
                      child: const Text('Change'),
                    ),
                  ),
                ),
              DropdownButtonFormField<QuestionType>(
                initialValue: _type,
                decoration: const InputDecoration(labelText: 'Question type'),
                items: [
                  for (final q in QuestionType.values) DropdownMenuItem(value: q, child: Text(q.label)),
                ],
                onChanged: (v) {
                  if (v == null) return;
                  setState(() {
                    _type = v;
                    _ensureShape();
                  });
                },
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _text,
                maxLines: 6,
                minLines: 2,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(
                  labelText: _type == QuestionType.flashcard ? 'Front of the card' : 'Question',
                  helperText: _type == QuestionType.fillBlank ? 'Use ___ to show where the blank is.' : null,
                ),
              ),
              const SizedBox(height: 16),
              ..._answerEditor(context),
              const SizedBox(height: 16),
              Text('Difficulty', style: t.labelLarge),
              const SizedBox(height: 6),
              SegmentedButton<Difficulty>(
                segments: [for (final d in Difficulty.values) ButtonSegment(value: d, label: Text(d.label))],
                selected: {_difficulty},
                onSelectionChanged: (s) => setState(() => _difficulty = s.first),
                showSelectedIcon: false,
              ),
              const SizedBox(height: 16),
              TextField(controller: _hint, decoration: const InputDecoration(labelText: 'Hint (optional)')),
              const SizedBox(height: 12),
              TextField(
                  controller: _explanation,
                  maxLines: 5,
                  minLines: 1,
                  decoration: const InputDecoration(labelText: 'Explanation (optional)')),
              const SizedBox(height: 12),
              TextField(
                  controller: _correctFb,
                  decoration: const InputDecoration(labelText: 'Message after a correct answer (optional)')),
              const SizedBox(height: 12),
              TextField(
                  controller: _incorrectFb,
                  decoration: const InputDecoration(labelText: 'Message after an incorrect answer (optional)')),
              const SizedBox(height: 12),
              TextField(
                  controller: _tags,
                  decoration: const InputDecoration(labelText: 'Tags (comma separated)')),
              const SizedBox(height: 16),
              Text('Media', style: t.labelLarge),
              const SizedBox(height: 6),
              Wrap(spacing: 8, runSpacing: 8, children: [
                if (_image == null)
                  OutlinedButton.icon(
                      onPressed: () => _pickMedia(true), icon: const Icon(Icons.image_outlined), label: const Text('Add image'))
                else
                  InputChip(
                      avatar: const Icon(Icons.image),
                      label: const Text('Image attached'),
                      onDeleted: () => setState(() => _image = null)),
                if (_audio == null)
                  OutlinedButton.icon(
                      onPressed: () => _pickMedia(false), icon: const Icon(Icons.audiotrack), label: const Text('Add audio'))
                else
                  InputChip(
                      avatar: const Icon(Icons.audiotrack),
                      label: const Text('Audio attached'),
                      onDeleted: () => setState(() => _audio = null)),
              ]),
              if (_image != null) ...[
                const SizedBox(height: 8),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 180),
                  child: Builder(builder: (context) {
                    final f = AppServices.I.media.resolve(_image);
                    return f == null ? const SizedBox.shrink() : Image.file(f, fit: BoxFit.contain);
                  }),
                ),
              ],
              ExpansionTile(
                tilePadding: EdgeInsets.zero,
                title: const Text('More options'),
                children: [
                  if (_type.usesChoices || _type == QuestionType.matching)
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Shuffle answers'),
                      subtitle: const Text('Turn off when the order matters (e.g. "All of the above")'),
                      value: _shuffle,
                      onChanged: (v) => setState(() => _shuffle = v),
                    ),
                  if (_type.usesTypedAnswer)
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Case sensitive'),
                      value: _caseSensitive,
                      onChanged: (v) => setState(() => _caseSensitive = v),
                    ),
                  TextField(controller: _source, decoration: const InputDecoration(labelText: 'Source or reference')),
                  const SizedBox(height: 12),
                  TextField(
                      controller: _notes,
                      maxLines: 4,
                      minLines: 1,
                      decoration: const InputDecoration(labelText: 'Study notes')),
                  const SizedBox(height: 12),
                ],
              ),
            ]),
          ),
        ],
      ),
    );
  }

  List<Widget> _answerEditor(BuildContext context) {
    final t = Theme.of(context).textTheme;
    switch (_type) {
      case QuestionType.single:
      case QuestionType.multiple:
        return [
          Text(_type == QuestionType.single ? 'Answers — tap the circle to mark the correct one' : 'Answers — tick every correct one',
              style: t.labelLarge),
          const SizedBox(height: 8),
          for (var i = 0; i < _options.length; i++) _optionTile(i),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton.icon(
              onPressed: _options.length >= 10 ? null : () => setState(() => _options.add(_OptionRow())),
              icon: const Icon(Icons.add),
              label: const Text('Add option'),
            ),
          ),
        ];
      case QuestionType.trueFalse:
        return [
          Text('The statement is…', style: t.labelLarge),
          const SizedBox(height: 8),
          SegmentedButton<int>(
            segments: const [
              ButtonSegment(value: 0, label: Text('True')),
              ButtonSegment(value: 1, label: Text('False')),
            ],
            selected: {_options.first.correct ? 0 : 1},
            onSelectionChanged: (s) => setState(() {
              _options[0].correct = s.first == 0;
              _options[1].correct = s.first == 1;
            }),
          ),
        ];
      case QuestionType.matching:
        return [
          Text('Pairs (left item → its match)', style: t.labelLarge),
          const SizedBox(height: 8),
          for (var i = 0; i < _options.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(children: [
                Expanded(child: TextField(controller: _options[i].text, decoration: InputDecoration(labelText: 'Item ${i + 1}'))),
                const Padding(padding: EdgeInsets.symmetric(horizontal: 6), child: Icon(Icons.arrow_forward)),
                Expanded(child: TextField(controller: _options[i].match, decoration: const InputDecoration(labelText: 'Match'))),
                IconButton(
                  tooltip: 'Remove pair',
                  icon: const Icon(Icons.remove_circle_outline),
                  onPressed: _options.length <= 2
                      ? null
                      : () => setState(() => _options.removeAt(i).dispose()),
                ),
              ]),
            ),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton.icon(
              onPressed: _options.length >= 10 ? null : () => setState(() => _options.add(_OptionRow(correct: true))),
              icon: const Icon(Icons.add),
              label: const Text('Add pair'),
            ),
          ),
        ];
      case QuestionType.fillBlank:
      case QuestionType.shortAnswer:
      case QuestionType.flashcard:
        return [
          Text(
              _type == QuestionType.flashcard
                  ? 'Back of the card'
                  : 'Accepted answers (any of these counts as correct)',
              style: t.labelLarge),
          const SizedBox(height: 8),
          for (var i = 0; i < _accepted.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(children: [
                Expanded(
                  child: TextField(
                    controller: _accepted[i],
                    maxLines: _type == QuestionType.flashcard ? 4 : 1,
                    minLines: 1,
                    decoration: InputDecoration(labelText: i == 0 ? 'Answer' : 'Alternative ${i + 1}'),
                  ),
                ),
                if (_accepted.length > 1)
                  IconButton(
                    tooltip: 'Remove',
                    icon: const Icon(Icons.remove_circle_outline),
                    onPressed: () => setState(() => _accepted.removeAt(i).dispose()),
                  ),
              ]),
            ),
          if (_type != QuestionType.flashcard)
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton.icon(
                onPressed: () => setState(() => _accepted.add(TextEditingController())),
                icon: const Icon(Icons.add),
                label: const Text('Add alternative answer'),
              ),
            ),
          if (_type == QuestionType.shortAnswer)
            Text('If an answer does not match exactly, you will be asked to judge it yourself.',
                style: t.bodySmall),
        ];
    }
  }

  Widget _optionTile(int i) {
    final o = _options[i];
    final single = _type == QuestionType.single;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(children: [
        Row(children: [
          IconButton(
            tooltip: o.correct ? 'Correct answer' : 'Mark as correct',
            icon: Icon(single
                ? (o.correct ? Icons.radio_button_checked : Icons.radio_button_unchecked)
                : (o.correct ? Icons.check_box : Icons.check_box_outline_blank)),
            color: o.correct ? Theme.of(context).colorScheme.primary : null,
            onPressed: () => setState(() {
              if (single) {
                for (final x in _options) {
                  x.correct = false;
                }
                o.correct = true;
              } else {
                o.correct = !o.correct;
              }
            }),
          ),
          Expanded(
            child: TextField(
              controller: o.text,
              decoration: InputDecoration(labelText: 'Option ${optionLetter(i)}'),
            ),
          ),
          PopupMenuButton<String>(
            onSelected: (v) => setState(() {
              if (v == 'explain') o.showExplanation = !o.showExplanation;
              if (v == 'up' && i > 0) _options.insert(i - 1, _options.removeAt(i));
              if (v == 'down' && i < _options.length - 1) _options.insert(i + 1, _options.removeAt(i));
              if (v == 'remove' && _options.length > 2) _options.removeAt(i).dispose();
            }),
            itemBuilder: (_) => [
              PopupMenuItem(value: 'explain', child: Text(o.showExplanation ? 'Hide explanation' : 'Explain this option')),
              const PopupMenuItem(value: 'up', child: Text('Move up')),
              const PopupMenuItem(value: 'down', child: Text('Move down')),
              const PopupMenuItem(value: 'remove', child: Text('Remove')),
            ],
          ),
        ]),
        if (o.showExplanation)
          Padding(
            padding: const EdgeInsetsDirectional.only(start: 48, top: 6),
            child: TextField(
              controller: o.explanation,
              decoration: const InputDecoration(labelText: 'Why this option is right/wrong', isDense: true),
            ),
          ),
      ]),
    );
  }
}
