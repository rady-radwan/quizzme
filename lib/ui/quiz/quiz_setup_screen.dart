import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/services.dart';
import '../../core/models.dart';
import '../../data/catalog_repository.dart';
import '../../data/session_repository.dart';
import '../common/widgets.dart';
import 'history_screen.dart';
import 'quiz_launcher.dart';

/// Custom quiz generator. Simple by default; everything else lives under
/// "Advanced settings".
class QuizSetupScreen extends StatefulWidget {
  const QuizSetupScreen({super.key, this.initial, this.embedded = false});
  final QuizConfig? initial;
  final bool embedded;

  @override
  State<QuizSetupScreen> createState() => _QuizSetupScreenState();
}

class _QuizSetupScreenState extends State<QuizSetupScreen> {
  late QuizConfig _c;
  List<CategoryNode> _tree = const [];
  Map<String, QuestionBank> _banks = const {};
  Map<String, Category> _cats = const {};
  SelectionPreview? _preview;
  Timer? _debounce;
  bool _manual = false;
  bool _starting = false;
  final _customCount = TextEditingController();
  static const _counts = [5, 10, 25, 50, 100];

  @override
  void initState() {
    super.initState();
    _c = widget.initial ?? defaultConfig(title: 'Quiz');
    _manual = _c.manualCounts.isNotEmpty;
    if (!_counts.contains(_c.questionCount)) _customCount.text = '${_c.questionCount}';
    AppServices.I.dataVersion.addListener(_loadTree);
    _loadTree();
  }

  @override
  void dispose() {
    AppServices.I.dataVersion.removeListener(_loadTree);
    _debounce?.cancel();
    _customCount.dispose();
    super.dispose();
  }

  Future<void> _loadTree() async {
    final svc = AppServices.I;
    final tree = await svc.catalog.tree();
    final banks = {for (final b in await svc.catalog.allBanks()) b.id: b};
    final cats = {for (final c in await svc.catalog.allCategories()) c.id: c};
    if (!mounted) return;
    setState(() {
      _tree = tree;
      _banks = banks;
      _cats = cats;
    });
    _refreshPreview();
  }

  /// With nothing selected, a quiz draws from every subject.
  QuizConfig get _effective {
    if (_c.fixedQuestionIds.isNotEmpty || _c.bankIds.isNotEmpty || _c.categoryIds.isNotEmpty) return _c;
    return _c.copyWith(categoryIds: _tree.map((n) => n.category.id).toList());
  }

  void _set(QuizConfig c) {
    setState(() => _c = c);
    _refreshPreview();
  }

  void _refreshPreview() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), () async {
      try {
        final p = await AppServices.I.sessions.preview(_effective);
        if (mounted) setState(() => _preview = p);
      } catch (_) {}
    });
  }

  String get _scopeLabel {
    if (_c.fixedQuestionIds.isNotEmpty) return '${_c.fixedQuestionIds.length} selected questions';
    final parts = [
      ..._c.categoryIds.map((id) => _cats[id]?.name).whereType<String>(),
      ..._c.bankIds.map((id) => _banks[id]?.name).whereType<String>(),
    ];
    if (parts.isEmpty) return 'All subjects';
    var s = parts.join(', ');
    if (_c.excludedCategoryIds.isNotEmpty) {
      s += ' (excluding ${_c.excludedCategoryIds.map((id) => _cats[id]?.name ?? '').join(', ')})';
    }
    return s;
  }

  String _autoTitle() {
    if (_c.fixedQuestionIds.isNotEmpty) return _c.title;
    final label = _scopeLabel;
    return label.length > 60 ? '${label.substring(0, 57)}…' : label;
  }

  Future<void> _start() async {
    setState(() => _starting = true);
    final cfg = _effective.copyWith(
      title: _c.title == 'Quiz' || widget.initial == null ? _autoTitle() : _c.title,
      manualCounts: _manual ? _c.manualCounts : const {},
      questionCount: _manual ? _c.manualCounts.values.fold<int>(0, (a, b) => a + b) : _c.questionCount,
    );
    await launchQuiz(context, cfg, allowEdit: false);
    if (mounted) setState(() => _starting = false);
    _refreshPreview();
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final p = _preview;
    final requested = _manual ? _c.manualCounts.values.fold<int>(0, (a, b) => a + b) : _c.questionCount;
    final available = p?.available;
    final planned = p?.plan.planned;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.embedded ? 'New quiz' : 'Quiz settings'),
        automaticallyImplyLeading: !widget.embedded,
        actions: [
          IconButton(
            tooltip: 'Quiz history',
            icon: const Icon(Icons.history),
            onPressed: () =>
                Navigator.push(context, MaterialPageRoute<void>(builder: (_) => const HistoryScreen())),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
        children: [
          Readable(
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              if (widget.embedded)
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.play_circle_outline),
                    title: const Text('Continue last quiz'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => continueLastQuiz(context),
                  ),
                ),
              Text('What to study', style: t.labelLarge),
              const SizedBox(height: 6),
              Card(
                child: ListTile(
                  leading: const Icon(Icons.folder_open_outlined),
                  title: Text(_scopeLabel, maxLines: 3, overflow: TextOverflow.ellipsis),
                  subtitle: const Text('Tap to choose subjects, categories or banks'),
                  trailing: const Icon(Icons.edit_outlined),
                  onTap: _c.fixedQuestionIds.isNotEmpty ? null : _chooseScope,
                ),
              ),
              const SizedBox(height: 16),
              Text('Mode', style: t.labelLarge),
              const SizedBox(height: 6),
              Wrap(spacing: 6, runSpacing: 6, children: [
                for (final m in SelectionMode.values)
                  ChoiceChip(
                    label: Text(m.label),
                    tooltip: m.description,
                    selected: _c.selection == m,
                    onSelected: (_) => _set(_c.copyWith(selection: m)),
                  ),
              ]),
              const SizedBox(height: 4),
              Text(_c.selection.description, style: t.bodySmall),
              const SizedBox(height: 16),
              Text('Style', style: t.labelLarge),
              const SizedBox(height: 6),
              SegmentedButton<QuizStyle>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(value: QuizStyle.practice, label: Text('Practice'), icon: Icon(Icons.school_outlined)),
                  ButtonSegment(value: QuizStyle.exam, label: Text('Exam'), icon: Icon(Icons.timer_outlined)),
                  ButtonSegment(value: QuizStyle.flashcards, label: Text('Cards'), icon: Icon(Icons.style_outlined)),
                ],
                selected: {_c.style},
                onSelectionChanged: (s) {
                  final style = s.first;
                  _set(_c.copyWith(
                    style: style,
                    feedback: style == QuizStyle.exam ? FeedbackTiming.endOfQuiz : _c.feedback,
                    hintsEnabled: style == QuizStyle.exam ? false : _c.hintsEnabled,
                  ));
                },
              ),
              const SizedBox(height: 4),
              Text(
                switch (_c.style) {
                  QuizStyle.practice => 'Relaxed: optional hints, explanations, no time pressure.',
                  QuizStyle.exam => 'No hints, answers revealed after you submit, optional countdown.',
                  QuizStyle.flashcards => 'Tap to reveal, then rate how well you remembered.',
                },
                style: t.bodySmall,
              ),
              const SizedBox(height: 16),
              if (!_manual) ...[
                Text('Number of questions', style: t.labelLarge),
                const SizedBox(height: 6),
                Wrap(spacing: 6, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
                  for (final n in _counts)
                    ChoiceChip(
                      label: Text('$n'),
                      selected: _c.questionCount == n && _customCount.text.isEmpty,
                      onSelected: (_) {
                        _customCount.clear();
                        _set(_c.copyWith(questionCount: n));
                      },
                    ),
                  SizedBox(
                    width: 110,
                    child: TextField(
                      controller: _customCount,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'Custom', isDense: true),
                      onChanged: (v) {
                        final n = int.tryParse(v.trim());
                        if (n != null && n > 0 && n <= 10000) _set(_c.copyWith(questionCount: n));
                      },
                    ),
                  ),
                ]),
                const SizedBox(height: 16),
              ],
              if (_c.style != QuizStyle.flashcards) ...[
                Text('Show answers', style: t.labelLarge),
                const SizedBox(height: 6),
                SegmentedButton<FeedbackTiming>(
                  showSelectedIcon: false,
                  segments: [
                    for (final f in FeedbackTiming.values) ButtonSegment(value: f, label: Text(f.label)),
                  ],
                  selected: {_c.feedback},
                  onSelectionChanged: _c.style == QuizStyle.exam ? null : (s) => _set(_c.copyWith(feedback: s.first)),
                ),
                const SizedBox(height: 8),
              ],
              _advanced(context),
            ]),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: Row(children: [
            Expanded(
              child: Text(
                available == null
                    ? 'Counting questions…'
                    : available == 0
                        ? 'No questions match these settings'
                        : planned! < requested
                            ? 'Only $available available'
                            : '$available available',
                style: t.bodyMedium,
              ),
            ),
            FilledButton.icon(
              onPressed: _starting || available == 0 ? null : _start,
              icon: const Icon(Icons.play_arrow),
              label: Text('Start (${planned == null ? requested : (planned < requested ? planned : requested)})'),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _advanced(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final banks = _preview?.availableByBank ?? const <String, int>{};
    return Card(
      child: ExpansionTile(
        title: const Text('Advanced settings'),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Hints'),
            subtitle: Text(_c.style == QuizStyle.exam ? 'Not available in exam mode' : 'Allow asking for a hint'),
            value: _c.hintsAllowed,
            onChanged: _c.style == QuizStyle.exam ? null : (v) => _set(_c.copyWith(hintsEnabled: v)),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Shuffle questions'),
            value: _c.shuffleQuestions,
            onChanged: (v) => _set(_c.copyWith(shuffleQuestions: v)),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Shuffle answers'),
            subtitle: const Text('The correct answer always stays correct'),
            value: _c.shuffleAnswers,
            onChanged: (v) => _set(_c.copyWith(shuffleAnswers: v)),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Timer'),
            subtitle: Text(_c.timerEnabled ? '${_c.timeLimitMinutes} minute countdown' : 'No time limit'),
            value: _c.timerEnabled,
            onChanged: (v) => _set(_c.copyWith(timerEnabled: v, timeLimitMinutes: _c.timeLimitMinutes <= 0 ? 15 : null)),
          ),
          if (_c.timerEnabled)
            Slider(
              value: _c.timeLimitMinutes.clamp(1, 180).toDouble(),
              min: 1,
              max: 180,
              divisions: 179,
              label: '${_c.timeLimitMinutes} min',
              onChanged: (v) => _set(_c.copyWith(timeLimitMinutes: v.round())),
            ),
          if (_c.selection == SelectionMode.random)
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Include previously attempted questions'),
              value: _c.includeAttempted,
              onChanged: (v) => _set(_c.copyWith(includeAttempted: v)),
            ),
          if (_c.selection == SelectionMode.mistakes)
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Only if my most recent answer was wrong'),
              subtitle: const Text('Off: every question I have ever answered wrongly'),
              value: _c.mistakesLastOnly,
              onChanged: (v) => _set(_c.copyWith(mistakesLastOnly: v)),
            ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Rate my confidence after each answer'),
            subtitle: const Text('Easy / Medium / Hard / Didn\'t know — improves review scheduling'),
            value: _c.confidenceRatings,
            onChanged: (v) => _set(_c.copyWith(confidenceRatings: v)),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Adaptive difficulty'),
            subtitle: Text(_c.difficulties.isNotEmpty
                ? 'Off while a difficulty filter is selected'
                : _preview?.adaptiveTarget == null
                    ? 'Prefers harder questions as you improve'
                    : 'Currently preferring: ${_preview!.adaptiveTarget!.map((i) => Difficulty.values[i].label).join(' & ')}'),
            value: _c.adaptiveDifficulty,
            onChanged: (v) => _set(_c.copyWith(adaptiveDifficulty: v)),
          ),
          const SizedBox(height: 8),
          Text('Difficulty', style: t.labelLarge),
          const SizedBox(height: 6),
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final d in Difficulty.values)
              FilterChip(
                label: Text(d.label),
                selected: _c.difficulties.contains(d),
                onSelected: (v) {
                  final s = [..._c.difficulties];
                  v ? s.add(d) : s.remove(d);
                  _set(_c.copyWith(difficulties: s));
                },
              ),
          ]),
          const SizedBox(height: 12),
          Text('Only these mastery levels', style: t.labelLarge),
          const SizedBox(height: 6),
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final m in MasteryLevel.values)
              FilterChip(
                label: Text(m.label),
                selected: _c.masteryLevels.contains(m),
                onSelected: (v) {
                  final s = [..._c.masteryLevels];
                  v ? s.add(m) : s.remove(m);
                  _set(_c.copyWith(masteryLevels: s));
                },
              ),
          ]),
          if (banks.length > 1 && _c.fixedQuestionIds.isEmpty) ...[
            const SizedBox(height: 12),
            Text('Question distribution', style: t.labelLarge),
            const SizedBox(height: 6),
            SegmentedButton<bool>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(value: false, label: Text('Automatic')),
                ButtonSegment(value: true, label: Text('Manual')),
              ],
              selected: {_manual},
              onSelectionChanged: (s) => setState(() {
                _manual = s.first;
                if (_manual && _c.manualCounts.isEmpty) {
                  final per = (_c.questionCount / banks.length).ceil();
                  _c = _c.copyWith(manualCounts: {
                    for (final e in banks.entries) e.key: per > e.value ? e.value : per,
                  });
                }
                _refreshPreview();
              }),
            ),
            if (_manual)
              for (final e in banks.entries)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Row(children: [
                    Expanded(child: Text('${_banks[e.key]?.name ?? 'Bank'} (${e.value} available)')),
                    IconButton(
                      tooltip: 'Fewer',
                      icon: const Icon(Icons.remove),
                      onPressed: () => _bump(e.key, -1),
                    ),
                    SizedBox(width: 36, child: Text('${_c.manualCounts[e.key] ?? 0}', textAlign: TextAlign.center)),
                    IconButton(
                      tooltip: 'More',
                      icon: const Icon(Icons.add),
                      onPressed: () => _bump(e.key, 1),
                    ),
                  ]),
                ),
            if (_manual && (_preview?.plan.shortages.isNotEmpty ?? false))
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'Not enough questions in: ${_preview!.plan.shortages.keys.map((k) => _banks[k]?.name ?? '').join(', ')}',
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
          ],
        ],
      ),
    );
  }

  void _bump(String bankId, int delta) {
    final m = {..._c.manualCounts};
    final v = (m[bankId] ?? 0) + delta;
    m[bankId] = v < 0 ? 0 : v;
    _set(_c.copyWith(manualCounts: m));
  }

  Future<void> _chooseScope() async {
    final result = await showModalBottomSheet<(List<String>, List<String>, List<String>)>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _ScopeSheet(
        tree: _tree,
        categoryIds: _c.categoryIds.toSet(),
        bankIds: _c.bankIds.toSet(),
        excluded: _c.excludedCategoryIds.toSet(),
      ),
    );
    if (result == null) return;
    _set(_c.copyWith(
      categoryIds: result.$1,
      bankIds: result.$2,
      excludedCategoryIds: result.$3,
      manualCounts: const {},
    ));
    setState(() => _manual = false);
  }
}

/// Tree with checkboxes. Selecting a category includes everything inside;
/// sub-categories of a selected category can then be excluded.
class _ScopeSheet extends StatefulWidget {
  const _ScopeSheet({required this.tree, required this.categoryIds, required this.bankIds, required this.excluded});
  final List<CategoryNode> tree;
  final Set<String> categoryIds;
  final Set<String> bankIds;
  final Set<String> excluded;

  @override
  State<_ScopeSheet> createState() => _ScopeSheetState();
}

class _ScopeSheetState extends State<_ScopeSheet> {
  late final Set<String> _cats = {...widget.categoryIds};
  late final Set<String> _banks = {...widget.bankIds};
  late final Set<String> _excluded = {...widget.excluded};

  List<Widget> _rows(CategoryNode n, int depth, bool parentIncluded, bool parentExcluded) {
    final id = n.category.id;
    final included = _cats.contains(id);
    final excluded = _excluded.contains(id) || parentExcluded;
    final covered = (parentIncluded || included) && !excluded;
    return [
      ListTile(
        dense: true,
        contentPadding: EdgeInsetsDirectional.only(start: 8.0 + depth * 18, end: 8),
        leading: parentIncluded
            ? IconButton(
                tooltip: excluded ? 'Include again' : 'Exclude',
                icon: Icon(excluded ? Icons.remove_circle : Icons.check_circle_outline,
                    color: excluded ? Theme.of(context).colorScheme.error : null),
                onPressed: parentExcluded
                    ? null
                    : () => setState(() => excluded ? _excluded.remove(id) : _excluded.add(id)),
              )
            : Checkbox(
                value: included,
                onChanged: (v) => setState(() {
                  if (v == true) {
                    _cats.add(id);
                  } else {
                    _cats.remove(id);
                  }
                }),
              ),
        title: Text(n.category.name,
            style: TextStyle(
                fontWeight: depth == 0 ? FontWeight.w700 : FontWeight.w500,
                decoration: excluded ? TextDecoration.lineThrough : null)),
        subtitle: Text('${n.questionCount} questions'),
      ),
      for (final k in n.children) ..._rows(k, depth + 1, covered || parentIncluded, excluded),
      for (final b in n.banks)
        ListTile(
          dense: true,
          contentPadding: EdgeInsetsDirectional.only(start: 26.0 + depth * 18, end: 8),
          leading: Checkbox(
            value: covered || _banks.contains(b.id),
            onChanged: covered
                ? null
                : (v) => setState(() {
                      if (v == true) {
                        _banks.add(b.id);
                      } else {
                        _banks.remove(b.id);
                      }
                    }),
          ),
          title: Text(b.name),
        ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.85,
      builder: (context, scroll) => Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 8, 8),
          child: Row(children: [
            Expanded(child: Text('Choose what to study', style: Theme.of(context).textTheme.titleMedium)),
            TextButton(
              onPressed: () => setState(() {
                _cats.clear();
                _banks.clear();
                _excluded.clear();
              }),
              child: const Text('All subjects'),
            ),
          ]),
        ),
        Expanded(
          child: widget.tree.isEmpty
              ? const EmptyState(icon: Icons.library_books_outlined, title: 'No subjects yet')
              : ListView(
                  controller: scroll,
                  children: [for (final n in widget.tree) ..._rows(n, 0, false, false)],
                ),
        ),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () {
                  // Keep exclusions only under selected categories.
                  Navigator.pop(context, (_cats.toList(), _banks.toList(), _excluded.toList()));
                },
                child: const Text('Done'),
              ),
            ),
          ),
        ),
      ]),
    );
  }
}
