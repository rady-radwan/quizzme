import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/services.dart';
import '../../core/models.dart';
import '../../data/question_repository.dart';
import '../banks/node_editor.dart';
import '../common/widgets.dart';
import '../quiz/quiz_launcher.dart';
import 'question_detail_screen.dart';

/// Paginated, searchable, filterable question list with bulk actions.
class QuestionListScreen extends StatefulWidget {
  const QuestionListScreen({super.key, required this.title, this.filter = const QuestionFilter()});
  final String title;
  final QuestionFilter filter;

  @override
  State<QuestionListScreen> createState() => _QuestionListScreenState();
}

class _QuestionListScreenState extends State<QuestionListScreen> {
  static const _page = 50;
  late QuestionFilter _filter = widget.filter;
  final _items = <QuestionListItem>[];
  final _selected = <String>{};
  final _scroll = ScrollController();
  final _search = TextEditingController();
  Timer? _debounce;
  bool _loading = false;
  bool _done = false;
  int _total = 0;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    _search.text = widget.filter.text;
    _scroll.addListener(() {
      if (_scroll.position.pixels > _scroll.position.maxScrollExtent - 600) _more();
    });
    AppServices.I.dataVersion.addListener(_refresh);
    _refresh();
  }

  @override
  void dispose() {
    AppServices.I.dataVersion.removeListener(_refresh);
    _debounce?.cancel();
    _scroll.dispose();
    _search.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    final gen = ++_generation;
    final repo = AppServices.I.questions;
    final total = await repo.count(_filter);
    final first = await repo.search(_filter, limit: _page);
    if (!mounted || gen != _generation) return;
    setState(() {
      _total = total;
      _items
        ..clear()
        ..addAll(first);
      _done = first.length < _page;
      _selected.retainWhere((id) => _items.any((i) => i.id == id));
    });
  }

  Future<void> _more() async {
    if (_loading || _done) return;
    _loading = true;
    final gen = _generation;
    final next = await AppServices.I.questions.search(_filter, limit: _page, offset: _items.length);
    _loading = false;
    if (!mounted || gen != _generation) return;
    setState(() {
      _items.addAll(next);
      _done = next.length < _page;
    });
  }

  void _setFilter(QuestionFilter f) {
    _filter = f;
    _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final selecting = _selected.isNotEmpty;
    return Scaffold(
      appBar: AppBar(
        title: Text(selecting ? '${_selected.length} selected' : widget.title),
        leading: selecting
            ? IconButton(
                tooltip: 'Clear selection',
                icon: const Icon(Icons.close),
                onPressed: () => setState(_selected.clear))
            : null,
        actions: selecting ? _bulkActions(context) : [
          IconButton(
            tooltip: 'Quiz these questions',
            icon: const Icon(Icons.play_circle_outline),
            onPressed: _total == 0 ? null : () => _quizFromFilter(context),
          ),
        ],
      ),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
          child: Row(children: [
            Expanded(
              child: TextField(
                controller: _search,
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search),
                  hintText: 'Search questions, answers, tags, notes',
                  isDense: true,
                ),
                onChanged: (v) {
                  _debounce?.cancel();
                  _debounce = Timer(const Duration(milliseconds: 300), () => _setFilter(_filter.copyWith(text: v)));
                },
              ),
            ),
            const SizedBox(width: 8),
            Badge(
              isLabelVisible: _filter.activeCount - (_filter.text.isEmpty ? 0 : 1) > 0,
              label: Text('${_filter.activeCount - (_filter.text.isEmpty ? 0 : 1)}'),
              child: IconButton.filledTonal(
                tooltip: 'Filters',
                icon: const Icon(Icons.tune),
                onPressed: () async {
                  final f = await showModalBottomSheet<QuestionFilter>(
                    context: context,
                    isScrollControlled: true,
                    showDragHandle: true,
                    builder: (_) => FilterSheet(initial: _filter),
                  );
                  if (f != null) _setFilter(f.copyWith(text: _search.text));
                },
              ),
            ),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: Align(
            alignment: AlignmentDirectional.centerStart,
            child: Text('$_total questions', style: Theme.of(context).textTheme.bodySmall),
          ),
        ),
        Expanded(
          child: _items.isEmpty
              ? EmptyState(
                  icon: Icons.search_off,
                  title: _total == 0 && _filter.activeCount == 0 ? 'No questions yet' : 'No matching questions',
                  message: _filter.activeCount > 0 ? 'Try removing some filters.' : null,
                )
              : ListView.builder(
                  controller: _scroll,
                  padding: const EdgeInsets.fromLTRB(12, 4, 12, 32),
                  itemCount: _items.length + (_done ? 0 : 1),
                  itemBuilder: (context, i) {
                    if (i >= _items.length) {
                      return const Padding(
                          padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator()));
                    }
                    return _tile(context, _items[i]);
                  },
                ),
        ),
      ]),
    );
  }

  Widget _tile(BuildContext context, QuestionListItem q) {
    final sel = _selected.contains(q.id);
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Card(
        color: sel ? scheme.secondaryContainer : null,
        child: ListTile(
          onTap: () {
            if (_selected.isNotEmpty) {
              setState(() => sel ? _selected.remove(q.id) : _selected.add(q.id));
            } else {
              Navigator.push(context,
                  MaterialPageRoute<void>(builder: (_) => QuestionDetailScreen(questionId: q.id)));
            }
          },
          onLongPress: () => setState(() => sel ? _selected.remove(q.id) : _selected.add(q.id)),
          title: ContentText(q.text, maxLines: 3),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Wrap(spacing: 6, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
              MasteryChip(q.mastery, dense: true),
              Text('${q.type.label} · ${q.difficulty.label}', style: Theme.of(context).textTheme.bodySmall),
              if (q.attempts > 0)
                Text('${percent(q.accuracy)} of ${q.attempts}', style: Theme.of(context).textTheme.bodySmall),
              if (q.archived) const Text('Archived', style: TextStyle(fontStyle: FontStyle.italic)),
              if (widget.filter.bankIds == null || widget.filter.bankIds!.length > 1)
                Text(q.bankName, style: Theme.of(context).textTheme.bodySmall),
            ]),
          ),
          trailing: sel
              ? const Icon(Icons.check_circle)
              : (q.bookmarked ? const Icon(Icons.bookmark, size: 20) : null),
        ),
      ),
    );
  }

  List<Widget> _bulkActions(BuildContext context) {
    final svc = AppServices.I;
    final ids = _selected.toList();
    return [
      IconButton(
        tooltip: 'Select all loaded',
        icon: const Icon(Icons.select_all),
        onPressed: () => setState(() => _selected.addAll(_items.map((e) => e.id))),
      ),
      IconButton(
        tooltip: 'Quiz selected',
        icon: const Icon(Icons.play_circle_outline),
        onPressed: () => launchQuiz(context,
            defaultConfig(title: 'Selected questions', selection: SelectionMode.random, fixedQuestionIds: ids)),
      ),
      PopupMenuButton<String>(
        onSelected: (v) async {
          switch (v) {
            case 'move':
              final bank = await pickBank(context, title: 'Move ${ids.length} questions to…');
              if (bank == null) return;
              await svc.questions.move(ids, bank);
              break;
            case 'bookmark':
              for (final id in ids) {
                if (!await svc.questions.isBookmarked(id)) await svc.questions.toggleBookmark(id);
              }
              break;
            case 'archive':
              await svc.questions.setArchived(ids, true);
              break;
            case 'unarchive':
              await svc.questions.setArchived(ids, false);
              break;
            case 'delete':
              if (!context.mounted) return;
              final ok = await confirm(context,
                  title: 'Delete ${ids.length} questions?',
                  message: 'They will be permanently deleted together with their learning history.',
                  confirmLabel: 'Delete',
                  destructive: true);
              if (!ok) return;
              await svc.questions.delete(ids);
              break;
          }
          _selected.clear();
          svc.dataChanged();
        },
        itemBuilder: (_) => const [
          PopupMenuItem(value: 'move', child: Text('Move to another bank')),
          PopupMenuItem(value: 'bookmark', child: Text('Bookmark')),
          PopupMenuItem(value: 'archive', child: Text('Archive')),
          PopupMenuItem(value: 'unarchive', child: Text('Restore from archive')),
          PopupMenuItem(value: 'delete', child: Text('Delete…')),
        ],
      ),
    ];
  }

  Future<void> _quizFromFilter(BuildContext context) async {
    final ids = await AppServices.I.questions.searchIds(_filter, limit: 1000);
    if (!context.mounted) return;
    await launchQuiz(
        context,
        defaultConfig(title: widget.title, selection: SelectionMode.random, fixedQuestionIds: ids)
            .copyWith(questionCount: ids.length > 50 ? 50 : ids.length));
  }
}

/// Bottom sheet with every combinable filter.
class FilterSheet extends StatefulWidget {
  const FilterSheet({super.key, required this.initial});
  final QuestionFilter initial;

  @override
  State<FilterSheet> createState() => _FilterSheetState();
}

class _FilterSheetState extends State<FilterSheet> {
  late QuestionFilter f = widget.initial;
  List<String> _tags = const [];

  @override
  void initState() {
    super.initState();
    AppServices.I.questions.tagsIn(widget.initial.bankIds).then((t) {
      if (mounted) setState(() => _tags = t);
    });
  }

  Widget _flag(String label, bool value, QuestionFilter Function(bool) apply) => FilterChip(
        label: Text(label),
        selected: value,
        onSelected: (v) => setState(() => f = apply(v)),
      );

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.8,
      builder: (context, scroll) => ListView(
        controller: scroll,
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        children: [
          Row(children: [
            Expanded(child: Text('Filters', style: t.titleLarge)),
            TextButton(
                onPressed: () => setState(() => f = QuestionFilter(bankIds: widget.initial.bankIds)),
                child: const Text('Clear')),
          ]),
          const SizedBox(height: 8),
          Text('History', style: t.labelLarge),
          const SizedBox(height: 6),
          Wrap(spacing: 6, runSpacing: 6, children: [
            _flag('Never attempted', f.neverAttempted, (v) => f.copyWith(neverAttempted: v)),
            _flag('Previously incorrect', f.previouslyIncorrect, (v) => f.copyWith(previouslyIncorrect: v)),
            _flag('Correct on last attempt', f.correctOnLast, (v) => f.copyWith(correctOnLast: v)),
            _flag('Incorrect multiple times', f.incorrectMultiple, (v) => f.copyWith(incorrectMultiple: v)),
            _flag('Due for revision', f.dueForRevision, (v) => f.copyWith(dueForRevision: v)),
            _flag('Overdue', f.overdue, (v) => f.copyWith(overdue: v)),
            _flag('Mastered', f.mastered, (v) => f.copyWith(mastered: v)),
            _flag('Not studied in 30 days', f.notStudied30Days, (v) => f.copyWith(notStudied30Days: v)),
            _flag('Bookmarked', f.bookmarkedOnly, (v) => f.copyWith(bookmarkedOnly: v)),
            _flag('Archived only', f.archivedOnly, (v) => f.copyWith(archivedOnly: v)),
          ]),
          const SizedBox(height: 16),
          Text('Mastery status', style: t.labelLarge),
          const SizedBox(height: 6),
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final m in MasteryLevel.values)
              FilterChip(
                label: Text(m.label),
                selected: f.masteryLevels.contains(m),
                onSelected: (v) => setState(() {
                  final s = {...f.masteryLevels};
                  v ? s.add(m) : s.remove(m);
                  f = f.copyWith(masteryLevels: s);
                }),
              ),
          ]),
          const SizedBox(height: 16),
          Text('Difficulty', style: t.labelLarge),
          const SizedBox(height: 6),
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final d in Difficulty.values)
              FilterChip(
                label: Text(d.label),
                selected: f.difficulties.contains(d),
                onSelected: (v) => setState(() {
                  final s = {...f.difficulties};
                  v ? s.add(d) : s.remove(d);
                  f = f.copyWith(difficulties: s);
                }),
              ),
          ]),
          const SizedBox(height: 16),
          Text('Question type', style: t.labelLarge),
          const SizedBox(height: 6),
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final q in QuestionType.values)
              FilterChip(
                label: Text(q.label),
                selected: f.types.contains(q),
                onSelected: (v) => setState(() {
                  final s = {...f.types};
                  v ? s.add(q) : s.remove(q);
                  f = f.copyWith(types: s);
                }),
              ),
          ]),
          if (_tags.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text('Tag', style: t.labelLarge),
            const SizedBox(height: 6),
            Wrap(spacing: 6, runSpacing: 6, children: [
              for (final tag in _tags.take(60))
                ChoiceChip(
                  label: Text(tag),
                  selected: f.tag == tag,
                  onSelected: (v) => setState(() => f = v ? f.copyWith(tag: tag) : f.copyWith(clearTag: true)),
                ),
            ]),
          ],
          if (f.importId != null) ...[
            const SizedBox(height: 16),
            InputChip(
              label: const Text('From one import'),
              onDeleted: () => setState(() => f = f.copyWith(clearImport: true)),
            ),
          ],
          const SizedBox(height: 24),
          FilledButton(onPressed: () => Navigator.pop(context, f), child: const Text('Apply filters')),
        ],
      ),
    );
  }
}
