import 'package:flutter/material.dart';

import '../../app/services.dart';
import '../../core/models.dart';
import '../../data/catalog_repository.dart';
import '../common/reloadable.dart';
import '../common/widgets.dart';
import '../import/import_screen.dart';
import '../questions/question_list_screen.dart';
import '../quiz/quiz_launcher.dart';
import '../quiz/quiz_setup_screen.dart';
import 'bank_screen.dart';
import 'category_screen.dart';
import 'node_editor.dart';

class BanksScreen extends StatefulWidget {
  const BanksScreen({super.key});

  @override
  State<BanksScreen> createState() => _BanksScreenState();
}

class _BanksScreenState extends State<BanksScreen> {
  bool _showArchived = false;
  final Set<String> _collapsed = {};

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Question banks'),
        actions: [
          IconButton(
            tooltip: 'Search all questions',
            icon: const Icon(Icons.search),
            onPressed: () => Navigator.push(context,
                MaterialPageRoute<void>(builder: (_) => const QuestionListScreen(title: 'All questions'))),
          ),
          PopupMenuButton<String>(
            onSelected: (v) {
              if (v == 'archived') setState(() => _showArchived = !_showArchived);
              if (v == 'import') {
                Navigator.push(context, MaterialPageRoute<void>(builder: (_) => const ImportScreen()));
              }
            },
            itemBuilder: (_) => [
              CheckedPopupMenuItem(value: 'archived', checked: _showArchived, child: const Text('Show archived')),
              const PopupMenuItem(value: 'import', child: Text('Import from Excel')),
            ],
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => CategoryActions.create(context),
        icon: const Icon(Icons.add),
        label: const Text('New subject'),
      ),
      body: Reloadable<List<CategoryNode>>(
        load: () => AppServices.I.catalog.tree(includeArchived: _showArchived),
        builder: (context, tree, reload) {
          if (tree.isEmpty) {
            return EmptyState(
              icon: Icons.library_books_outlined,
              title: 'No subjects yet',
              message: 'Create a subject such as "English" or "Engineering", then add topics and '
                  'question banks inside it.',
              actions: [
                FilledButton.icon(
                    onPressed: () => CategoryActions.create(context),
                    icon: const Icon(Icons.add),
                    label: const Text('New subject')),
              ],
            );
          }
          return ListView(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 96),
            children: [
              for (final n in tree)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Card(child: Column(children: _node(context, n, 0))),
                ),
            ],
          );
        },
      ),
    );
  }

  List<Widget> _node(BuildContext context, CategoryNode n, int depth) {
    final c = n.category;
    final open = !_collapsed.contains(c.id);
    final hasKids = n.children.isNotEmpty || n.banks.isNotEmpty;
    return [
      ListTile(
        contentPadding: EdgeInsetsDirectional.only(start: 12.0 + depth * 20, end: 4),
        leading: NodeAvatar(iconKey: c.iconKey, color: c.color, size: depth == 0 ? 40 : 34),
        title: Text(c.name,
            style: TextStyle(
                fontWeight: depth == 0 ? FontWeight.w700 : FontWeight.w600,
                decoration: c.archived ? TextDecoration.lineThrough : null)),
        subtitle: Text('${n.questionCount} questions'
            '${n.children.isNotEmpty ? ' · ${n.children.length} categories' : ''}'
            '${n.banks.isNotEmpty ? ' · ${n.banks.length} banks' : ''}'),
        onTap: () => Navigator.push(
            context, MaterialPageRoute<void>(builder: (_) => CategoryScreen(categoryId: c.id))),
        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
          if (hasKids)
            IconButton(
              tooltip: open ? 'Collapse' : 'Expand',
              icon: Icon(open ? Icons.expand_less : Icons.expand_more),
              onPressed: () => setState(() {
                if (open) {
                  _collapsed.add(c.id);
                } else {
                  _collapsed.remove(c.id);
                }
              }),
            ),
          _categoryMenu(context, c),
        ]),
      ),
      if (open) ...[
        for (final k in n.children) ..._node(context, k, depth + 1),
        for (final b in n.banks)
          ListTile(
            contentPadding: EdgeInsetsDirectional.only(start: 32.0 + depth * 20, end: 4),
            leading: NodeAvatar(iconKey: b.iconKey, color: b.color, fallback: Icons.quiz_outlined, size: 32),
            title: Text(b.name, style: TextStyle(decoration: b.archived ? TextDecoration.lineThrough : null)),
            subtitle: const Text('Question bank'),
            onTap: () =>
                Navigator.push(context, MaterialPageRoute<void>(builder: (_) => BankScreen(bankId: b.id))),
            trailing: IconButton(
              tooltip: 'Start a quiz from ${b.name}',
              icon: const Icon(Icons.play_circle_outline),
              onPressed: () => launchQuiz(context, defaultConfig(title: b.name, bankIds: [b.id])),
            ),
          ),
        if (!hasKids)
          Padding(
            padding: EdgeInsetsDirectional.only(start: 32.0 + depth * 20, bottom: 12, end: 12),
            child: Wrap(spacing: 8, children: [
              OutlinedButton.icon(
                onPressed: () => BankActions.create(context, c.id),
                icon: const Icon(Icons.add),
                label: const Text('Add bank'),
              ),
              TextButton.icon(
                onPressed: () => CategoryActions.create(context, parentId: c.id),
                icon: const Icon(Icons.create_new_folder_outlined),
                label: const Text('Add category'),
              ),
            ]),
          ),
      ],
    ];
  }

  Widget _categoryMenu(BuildContext context, Category c) {
    return PopupMenuButton<String>(
      tooltip: 'More',
      onSelected: (v) async {
        switch (v) {
          case 'quiz':
            await Navigator.push(context,
                MaterialPageRoute<void>(builder: (_) => QuizSetupScreen(initial: defaultConfig(title: c.name, categoryIds: [c.id]))));
            break;
          case 'bank':
            await BankActions.create(context, c.id);
            break;
          case 'sub':
            await CategoryActions.create(context, parentId: c.id);
            break;
          case 'edit':
            await CategoryActions.edit(context, c);
            break;
          case 'move':
            await CategoryActions.move(context, c);
            break;
          case 'archive':
            await CategoryActions.toggleArchive(context, c);
            break;
          case 'delete':
            await CategoryActions.delete(context, c);
            break;
        }
      },
      itemBuilder: (_) => [
        const PopupMenuItem(value: 'quiz', child: Text('Quiz this category…')),
        const PopupMenuItem(value: 'bank', child: Text('Add question bank')),
        const PopupMenuItem(value: 'sub', child: Text('Add sub-category')),
        const PopupMenuItem(value: 'edit', child: Text('Edit')),
        const PopupMenuItem(value: 'move', child: Text('Move')),
        PopupMenuItem(value: 'archive', child: Text(c.archived ? 'Restore from archive' : 'Archive')),
        const PopupMenuItem(value: 'delete', child: Text('Delete…')),
      ],
    );
  }
}
