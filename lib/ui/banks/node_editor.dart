import 'package:flutter/material.dart';

import '../../app/services.dart';
import '../../app/theme.dart';
import '../../core/models.dart';
import '../../data/catalog_repository.dart';
import '../common/widgets.dart';

class NodeEditResult {
  NodeEditResult(this.name, this.description, this.iconKey, this.color);
  final String name;
  final String? description;
  final String? iconKey;
  final int? color;
}

/// Dialog to create or edit a subject, category or bank.
Future<NodeEditResult?> showNodeEditor(
  BuildContext context, {
  required String title,
  String? name,
  String? description,
  String? iconKey,
  int? color,
}) {
  return showDialog<NodeEditResult>(
    context: context,
    builder: (c) => _NodeEditorDialog(
        title: title, name: name, description: description, iconKey: iconKey, color: color),
  );
}

class _NodeEditorDialog extends StatefulWidget {
  const _NodeEditorDialog({required this.title, this.name, this.description, this.iconKey, this.color});
  final String title;
  final String? name;
  final String? description;
  final String? iconKey;
  final int? color;

  @override
  State<_NodeEditorDialog> createState() => _NodeEditorDialogState();
}

class _NodeEditorDialogState extends State<_NodeEditorDialog> {
  late final TextEditingController _name = TextEditingController(text: widget.name);
  late final TextEditingController _desc = TextEditingController(text: widget.description);
  late String? _icon = widget.iconKey;
  late int? _color = widget.color;

  @override
  void dispose() {
    _name.dispose();
    _desc.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AlertDialog(
      title: Text(widget.title),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _name,
              autofocus: widget.name == null,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(labelText: 'Name'),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _desc,
              maxLines: 3,
              minLines: 1,
              decoration: const InputDecoration(labelText: 'Description (optional)'),
            ),
            const SizedBox(height: 16),
            const Text('Icon'),
            const SizedBox(height: 8),
            Wrap(spacing: 6, runSpacing: 6, children: [
              for (final e in appIcons.entries)
                Semantics(
                  label: 'Icon ${e.key}',
                  selected: _icon == e.key,
                  button: true,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(10),
                    onTap: () => setState(() => _icon = e.key),
                    child: Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                            color: _icon == e.key ? scheme.primary : scheme.outlineVariant,
                            width: _icon == e.key ? 2 : 1),
                      ),
                      child: Icon(e.value, size: 22),
                    ),
                  ),
                ),
            ]),
            const SizedBox(height: 16),
            const Text('Color'),
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final c in accentChoices)
                Semantics(
                  label: 'Color',
                  selected: _color == c,
                  button: true,
                  child: InkWell(
                    customBorder: const CircleBorder(),
                    onTap: () => setState(() => _color = c),
                    child: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: Color(c),
                        shape: BoxShape.circle,
                        border: Border.all(color: _color == c ? scheme.onSurface : Colors.transparent, width: 3),
                      ),
                    ),
                  ),
                ),
            ]),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          onPressed: _name.text.trim().isEmpty
              ? null
              : () => Navigator.pop(
                  context,
                  NodeEditResult(_name.text.trim(), _desc.text.trim().isEmpty ? null : _desc.text.trim(),
                      _icon, _color)),
          child: const Text('Save'),
        ),
      ],
    );
  }
}

/// Picks a question bank from the whole tree. Returns the bank id.
Future<String?> pickBank(BuildContext context, {String title = 'Choose a question bank', String? excludeBankId}) async {
  final tree = await AppServices.I.catalog.tree();
  if (!context.mounted) return null;
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (c) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.7,
      builder: (c, scroll) => ListView(
        controller: scroll,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text(title, style: Theme.of(c).textTheme.titleMedium),
          ),
          if (tree.isEmpty)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Text('No question banks yet. Create a subject and a bank in the Banks tab first.'),
            ),
          for (final n in tree) ..._bankTiles(c, n, 0, excludeBankId),
        ],
      ),
    ),
  );
}

List<Widget> _bankTiles(BuildContext c, CategoryNode n, int depth, String? exclude) => [
      Padding(
        padding: EdgeInsetsDirectional.only(start: 16.0 + depth * 16, top: 8, bottom: 2),
        child: Text(n.category.name, style: const TextStyle(fontWeight: FontWeight.w700)),
      ),
      for (final b in n.banks)
        if (b.id != exclude)
          ListTile(
            contentPadding: EdgeInsetsDirectional.only(start: 24.0 + depth * 16, end: 16),
            leading: NodeAvatar(iconKey: b.iconKey, color: b.color, fallback: Icons.quiz_outlined, size: 32),
            title: Text(b.name),
            onTap: () => Navigator.pop(c, b.id),
          ),
      for (final k in n.children) ..._bankTiles(c, k, depth + 1, exclude),
    ];

/// Picks a category (or "top level" when [allowRoot]). Returns '' for root.
Future<String?> pickCategory(BuildContext context,
    {String title = 'Choose a location', bool allowRoot = true, String? excludeSubtreeOf}) async {
  final svc = AppServices.I;
  final tree = await svc.catalog.tree();
  final excluded = excludeSubtreeOf == null
      ? <String>{}
      : (await svc.catalog.descendantCategoryIds(excludeSubtreeOf)).toSet();
  if (!context.mounted) return null;
  List<Widget> tiles(BuildContext c, CategoryNode n, int depth) => [
        if (!excluded.contains(n.category.id))
          ListTile(
            contentPadding: EdgeInsetsDirectional.only(start: 16.0 + depth * 18, end: 16),
            leading: NodeAvatar(iconKey: n.category.iconKey, color: n.category.color, size: 32),
            title: Text(n.category.name),
            onTap: () => Navigator.pop(c, n.category.id),
          ),
        if (!excluded.contains(n.category.id))
          for (final k in n.children) ...tiles(c, k, depth + 1),
      ];
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (c) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.7,
      builder: (c, scroll) => ListView(controller: scroll, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Text(title, style: Theme.of(c).textTheme.titleMedium),
        ),
        if (allowRoot)
          ListTile(
            leading: const Icon(Icons.vertical_align_top),
            title: const Text('Top level (make it a subject)'),
            onTap: () => Navigator.pop(c, ''),
          ),
        for (final n in tree) ...tiles(c, n, 0),
      ]),
    ),
  );
}

/// Shared actions for categories.
class CategoryActions {
  static Future<Category?> create(BuildContext context, {String? parentId}) async {
    final r = await showNodeEditor(context, title: parentId == null ? 'New subject' : 'New category');
    if (r == null) return null;
    final c = await AppServices.I.catalog.createCategory(
        name: r.name, parentId: parentId, description: r.description, iconKey: r.iconKey, color: r.color);
    AppServices.I.dataChanged();
    return c;
  }

  static Future<void> edit(BuildContext context, Category c) async {
    final r = await showNodeEditor(context,
        title: 'Edit ${c.isSubject ? 'subject' : 'category'}',
        name: c.name,
        description: c.description,
        iconKey: c.iconKey,
        color: c.color);
    if (r == null) return;
    await AppServices.I.catalog
        .updateCategory(c.copyWith(name: r.name, description: r.description ?? '', iconKey: r.iconKey, color: r.color));
    AppServices.I.dataChanged();
  }

  static Future<void> move(BuildContext context, Category c) async {
    final target = await pickCategory(context, title: 'Move "${c.name}" to…', excludeSubtreeOf: c.id);
    if (target == null) return;
    try {
      await AppServices.I.catalog.moveCategory(c.id, target.isEmpty ? null : target);
      AppServices.I.dataChanged();
    } catch (e) {
      if (context.mounted) showMessage(context, '$e');
    }
  }

  static Future<void> toggleArchive(BuildContext context, Category c) async {
    await AppServices.I.catalog.updateCategory(c.copyWith(archived: !c.archived));
    AppServices.I.dataChanged();
    if (context.mounted) {
      showMessage(context, c.archived ? '"${c.name}" restored' : '"${c.name}" archived (hidden from quizzes)');
    }
  }

  /// Returns true when deleted.
  static Future<bool> delete(BuildContext context, Category c) async {
    final svc = AppServices.I;
    final stats = await svc.stats.statsForCategory(c.id);
    if (!context.mounted) return false;
    final ok = await confirmTyped(context,
        title: 'Delete "${c.name}"?',
        message: 'This permanently deletes the ${c.isSubject ? 'subject' : 'category'}, everything inside it '
            'and ${stats.total} questions with their learning history. Consider making a backup first.');
    if (!ok) return false;
    await svc.catalog.deleteCategory(c.id);
    svc.dataChanged();
    return true;
  }
}

class BankActions {
  static Future<QuestionBank?> create(BuildContext context, String categoryId) async {
    final r = await showNodeEditor(context, title: 'New question bank');
    if (r == null) return null;
    final b = await AppServices.I.catalog.createBank(
        categoryId: categoryId, name: r.name, description: r.description, iconKey: r.iconKey, color: r.color);
    AppServices.I.dataChanged();
    return b;
  }

  static Future<void> edit(BuildContext context, QuestionBank b) async {
    final r = await showNodeEditor(context,
        title: 'Edit question bank', name: b.name, description: b.description, iconKey: b.iconKey, color: b.color);
    if (r == null) return;
    await AppServices.I.catalog
        .updateBank(b.copyWith(name: r.name, description: r.description ?? '', iconKey: r.iconKey, color: r.color));
    AppServices.I.dataChanged();
  }

  static Future<void> move(BuildContext context, QuestionBank b) async {
    final target = await pickCategory(context, title: 'Move "${b.name}" to…', allowRoot: false);
    if (target == null || target.isEmpty) return;
    await AppServices.I.catalog.updateBank(b.copyWith(categoryId: target));
    AppServices.I.dataChanged();
  }

  static Future<void> toggleArchive(BuildContext context, QuestionBank b) async {
    await AppServices.I.catalog.updateBank(b.copyWith(archived: !b.archived));
    AppServices.I.dataChanged();
    if (context.mounted) {
      showMessage(context, b.archived ? '"${b.name}" restored' : '"${b.name}" archived (hidden from quizzes)');
    }
  }

  static Future<bool> delete(BuildContext context, QuestionBank b) async {
    final svc = AppServices.I;
    final stats = await svc.stats.statsFor([b.id]);
    if (!context.mounted) return false;
    final ok = await confirmTyped(context,
        title: 'Delete "${b.name}"?',
        message: 'This permanently deletes the bank and its ${stats.total} questions with their learning '
            'history. Consider exporting or backing up first.');
    if (!ok) return false;
    await svc.catalog.deleteBank(b.id);
    svc.dataChanged();
    return true;
  }
}
