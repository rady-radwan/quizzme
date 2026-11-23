import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../app/services.dart';
import '../../data/question_repository.dart';
import '../common/widgets.dart';

/// Personal notes for one question: add, edit, delete.
class NotesSection extends StatefulWidget {
  const NotesSection({super.key, required this.questionId, this.compact = false});
  final String questionId;
  final bool compact;

  @override
  State<NotesSection> createState() => _NotesSectionState();
}

class _NotesSectionState extends State<NotesSection> {
  List<Note> _notes = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant NotesSection old) {
    super.didUpdateWidget(old);
    if (old.questionId != widget.questionId) _load();
  }

  Future<void> _load() async {
    final n = await AppServices.I.questions.notesFor(widget.questionId);
    if (mounted) setState(() => _notes = n);
  }

  Future<void> _add() async {
    final t = await promptText(context, title: 'Add note', hint: 'Write a note for this question', maxLines: 5);
    if (t == null || t.isEmpty) return;
    await AppServices.I.questions.addNote(widget.questionId, t);
    await _load();
  }

  Future<void> _edit(Note n) async {
    final t = await promptText(context, title: 'Edit note', initial: n.text, maxLines: 5);
    if (t == null || t.isEmpty) return;
    await AppServices.I.questions.updateNote(n.id, t);
    await _load();
  }

  Future<void> _delete(Note n) async {
    final ok = await confirm(context,
        title: 'Delete note?', message: 'This note will be deleted.', confirmLabel: 'Delete', destructive: true);
    if (!ok) return;
    await AppServices.I.questions.deleteNote(n.id);
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final fmt = DateFormat.yMMMd();
    return Card(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        for (final n in _notes)
          ListTile(
            title: ContentText(n.text),
            subtitle: Text(fmt.format(n.updatedAt)),
            trailing: PopupMenuButton<String>(
              onSelected: (v) => v == 'edit' ? _edit(n) : _delete(n),
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'edit', child: Text('Edit')),
                PopupMenuItem(value: 'delete', child: Text('Delete')),
              ],
            ),
          ),
        if (_notes.isEmpty && !widget.compact)
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: Text('No notes yet.'),
          ),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: TextButton.icon(onPressed: _add, icon: const Icon(Icons.note_add_outlined), label: const Text('Add note')),
          ),
        ),
      ]),
    );
  }
}
