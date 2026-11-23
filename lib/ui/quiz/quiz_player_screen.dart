import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/services.dart';
import '../../app/theme.dart';
import '../../core/grading.dart';
import '../../core/models.dart';
import '../../data/session_repository.dart';
import '../common/desktop.dart';
import '../common/widgets.dart';
import '../questions/notes_section.dart';
import 'answer_widgets.dart';
import 'question_media.dart';
import 'results_screen.dart';

/// Distraction-free quiz screen. Every answer is saved immediately, so the
/// quiz can be resumed after the app is closed. In end-of-quiz feedback mode
/// correctness is never shown (nor restored) before the quiz is submitted.
class QuizPlayerScreen extends StatefulWidget {
  const QuizPlayerScreen({super.key, required this.sessionId});
  final String sessionId;

  @override
  State<QuizPlayerScreen> createState() => _QuizPlayerScreenState();
}

class _QuizPlayerScreenState extends State<QuizPlayerScreen> with WidgetsBindingObserver {
  final _svc = AppServices.I;
  QuizSession? _session;
  List<SessionItem> _items = [];
  Map<String, Question> _questions = {};
  Map<String, String> _paths = {};
  final Map<int, QuestionResponse> _responses = {};
  final Map<int, AttemptResult> _results = {};
  final Map<int, Confidence?> _confidence = {};
  final Set<int> _hintShown = {};
  final Set<int> _presented = {};
  final Set<int> _applied = {};
  Timer? _pendingSave;
  Future<void> Function()? _pendingAction;
  final Set<String> _bookmarks = {};
  final Map<int, int> _durations = {};
  final _textCtrl = TextEditingController();
  int _index = 0;
  int _elapsedBase = 0;
  final Stopwatch _watch = Stopwatch();
  DateTime _questionShownAt = DateTime.now();
  Timer? _ticker;
  Timer? _autosave;
  bool _busy = false;
  bool _finishing = false;
  String? _error;

  QuizConfig get _cfg => _session!.config;
  bool get _immediate => _cfg.feedback == FeedbackTiming.immediate && !_cfg.isExam;
  SessionItem get _item => _items[_index];
  Question? get _q => _questions[_item.questionId];
  int get _elapsedMs => _elapsedBase + _watch.elapsedMilliseconds;
  int? get _remainingMs =>
      _cfg.timerEnabled && _cfg.timeLimitMinutes > 0 ? _cfg.timeLimitMinutes * 60000 - _elapsedMs : null;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _ticker?.cancel();
    _autosave?.cancel();
    _flushPending();
    _persistCursor();
    _svc.speech.stopSpeaking();
    _textCtrl.dispose();
    _keys.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive) {
      _watch.stop();
      _persistCursor();
    } else if (state == AppLifecycleState.resumed && _session != null && !_finishing) {
      _watch.start();
      _questionShownAt = DateTime.now();
    }
  }

  Future<void> _load() async {
    try {
      final s = await _svc.sessions.session(widget.sessionId);
      if (s == null) throw StateError('This quiz no longer exists.');
      if (s.status == SessionStatus.completed) {
        if (!mounted) return;
        Navigator.pushReplacement(
            context, MaterialPageRoute<void>(builder: (_) => ResultsScreen(sessionId: s.id)));
        return;
      }
      final items = await _svc.sessions.items(s.id);
      final qs = await _svc.questions.questionsByIds(items.map((i) => i.questionId).toList());
      final byId = {for (final q in qs) q.id: q};
      final paths = <String, String>{};
      for (final b in qs.map((q) => q.bankId).toSet()) {
        final bank = await _svc.catalog.bank(b);
        if (bank == null) continue;
        final path = await _svc.catalog.categoryPath(bank.categoryId);
        paths[b] = [...path.map((c) => c.name), bank.name].join(' → ');
      }
      for (final q in qs) {
        if (await _svc.questions.isBookmarked(q.id)) _bookmarks.add(q.id);
      }
      for (final it in items) {
        _responses[it.position] = it.response;
        if (it.result != null) _results[it.position] = it.result!;
        _confidence[it.position] = it.confidence;
        if (it.hintUsed) _hintShown.add(it.position);
        if (it.presentedAt != null) _presented.add(it.position);
        if (it.applied) _applied.add(it.position);
        _durations[it.position] = 0;
      }
      if (!mounted) return;
      setState(() {
        _session = s;
        _items = items.where((i) => byId.containsKey(i.questionId)).toList();
        _questions = byId;
        _paths = paths;
        _elapsedBase = s.elapsedMs;
        _index = s.currentIndex.clamp(0, _items.isEmpty ? 0 : _items.length - 1);
      });
      if (_items.isEmpty) {
        setState(() => _error = 'The questions of this quiz were deleted.');
        return;
      }
      _watch.start();
      _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
      _autosave = Timer.periodic(const Duration(seconds: 15), (_) => _persistCursor());
      _show(_index);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  void _tick() {
    if (!mounted || _session == null) return;
    final r = _remainingMs;
    if (r != null && r <= 0 && !_finishing) {
      _finish(timeUp: true);
      return;
    }
    if (_cfg.timerEnabled) setState(() {});
  }

  Future<void> _persistCursor() async {
    if (_session == null) return;
    try {
      await _svc.sessions.saveCursor(_session!.id, _index, _elapsedMs);
    } catch (_) {}
  }

  void _show(int i) {
    _flushPending();
    _recordDuration();
    setState(() => _index = i);
    // Keep keyboard shortcuts working after a text field of the previous
    // question is removed from the tree.
    _keys.requestFocus();
    _questionShownAt = DateTime.now();
    final r = _responses[i];
    _textCtrl.text = (r?.text == 'revealed' ? '' : r?.text) ?? '';
    if (_presented.add(i)) {
      _svc.sessions.markPresented(_session!.id, _items[i].position);
    }
    _persistCursor();
  }

  void _recordDuration() {
    if (_items.isEmpty) return;
    final key = _items[_index].position;
    final ms = DateTime.now().difference(_questionShownAt).inMilliseconds;
    _durations[key] = (_durations[key] ?? 0) + ms;
    _questionShownAt = DateTime.now();
  }

  int _takeDuration(int position) {
    _recordDuration();
    final d = _durations[position] ?? 0;
    _durations[position] = 0;
    return d;
  }

  bool get _locked => _immediate && _results.containsKey(_item.position);

  // ---------------- Answering ----------------

  void _onChanged(QuestionResponse r) {
    setState(() => _responses[_item.position] = r);
    if (!_immediate) {
      // End-of-quiz mode: save silently (debounced); nothing is revealed.
      final pos = _item.position;
      _pendingSave?.cancel();
      _pendingAction = () => _saveHidden(pos, r);
      _pendingSave = Timer(const Duration(milliseconds: 350), _flushPending);
    } else if (_q?.type == QuestionType.flashcard && r.selfGrade != null) {
      _submit();
    }
  }

  /// Runs a debounced save now. Awaited before submitting the quiz so the
  /// last answer can never be lost.
  Future<void> _flushPending() async {
    _pendingSave?.cancel();
    _pendingSave = null;
    final a = _pendingAction;
    _pendingAction = null;
    if (a != null) await a();
  }

  Future<void> _saveHidden(int position, QuestionResponse r) async {
    final q = _questions[_items.firstWhere((i) => i.position == position).questionId];
    if (q == null) return;
    final res = await _svc.sessions.saveResponse(
      sessionId: _session!.id,
      position: position,
      question: q,
      response: r,
      hintUsed: _hintShown.contains(position),
      confidence: _confidence[position],
      addDurationMs: _takeDuration(position),
    );
    if (res == null) {
      _results.remove(position);
    } else {
      _results[position] = res;
    }
  }

  Future<void> _submit() async {
    final q = _q;
    if (q == null || _busy) return;
    final pos = _item.position;
    var r = _responses[pos] ?? QuestionResponse();
    if (!isAnswered(q, r)) return;
    setState(() => _busy = true);
    try {
      var res = await _svc.sessions.saveResponse(
        sessionId: _session!.id,
        position: pos,
        question: q,
        response: r,
        hintUsed: _hintShown.contains(pos),
        confidence: _confidence[pos],
        addDurationMs: _takeDuration(pos),
      );
      if (res == AttemptResult.review && mounted) {
        final ok = await _selfGrade(q, r);
        if (ok == null) {
          setState(() => _busy = false);
          return;
        }
        r = r.copyWith(selfGrade: ok);
        _responses[pos] = r;
        res = await _svc.sessions.saveResponse(
            sessionId: _session!.id, position: pos, question: q, response: r, hintUsed: _hintShown.contains(pos));
      }
      if (res != null) _results[pos] = res;
      if (!_cfg.confidenceRatings) {
        await _svc.sessions.finalizeItem(_session!.id, pos, q);
        _applied.add(pos);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<bool?> _selfGrade(Question q, QuestionResponse r) => showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('Check your answer'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Your answer did not match exactly. Compare it with the expected answer:'),
              const SizedBox(height: 12),
              Text('Your answer', style: Theme.of(c).textTheme.labelLarge),
              ContentText(r.text ?? ''),
              const SizedBox(height: 8),
              Text('Expected', style: Theme.of(c).textTheme.labelLarge),
              for (final a in acceptedAnswersOf(q)) ContentText('• $a'),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('I was wrong')),
            FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('I was right')),
          ],
        ),
      );

  Future<void> _next() async {
    final pos = _item.position;
    final q = _q;
    if (_immediate && _results.containsKey(pos) && q != null && !_applied.contains(pos)) {
      await _svc.sessions.finalizeItem(_session!.id, pos, q, confidence: _confidence[pos]);
      _applied.add(pos);
    }
    if (_index < _items.length - 1) {
      _show(_index + 1);
    } else {
      await _finish();
    }
  }

  Future<void> _finish({bool timeUp = false}) async {
    if (_finishing) return;
    await _flushPending();
    final unanswered = _items.where((i) => !_results.containsKey(i.position)).length;
    if (!timeUp) {
      final ok = await confirm(context,
          title: 'Submit quiz?',
          message: unanswered == 0
              ? 'You have answered every question.'
              : '$unanswered ${unanswered == 1 ? 'question is' : 'questions are'} unanswered and will be marked as skipped.',
          confirmLabel: 'Submit');
      if (!ok) return;
    }
    setState(() => _finishing = true);
    _watch.stop();
    _ticker?.cancel();
    try {
      await _svc.sessions.complete(_session!.id, elapsedMs: _elapsedMs);
      _svc.dataChanged();
      final fresh = _svc.settings.value.gamification ? await _svc.stats.checkAchievements() : const [];
      _svc.refreshReminders();
      if (!mounted) return;
      if (timeUp) showMessage(context, "Time's up — your quiz was submitted.");
      for (final a in fresh) {
        showMessage(context, 'Achievement unlocked: ${a.title}');
      }
      Navigator.pushReplacement(
          context, MaterialPageRoute<void>(builder: (_) => ResultsScreen(sessionId: _session!.id)));
    } catch (e) {
      if (mounted) {
        setState(() => _finishing = false);
        showErrorDialog(context, 'Could not submit', '$e');
      }
    }
  }

  Future<void> _toggleBookmark() async {
    final q = _q;
    if (q == null) return;
    final on = await _svc.questions.toggleBookmark(q.id);
    setState(() => on ? _bookmarks.add(q.id) : _bookmarks.remove(q.id));
  }

  void _showHint() {
    final pos = _item.position;
    setState(() => _hintShown.add(pos));
    _svc.sessions.markHintUsed(_session!.id, pos);
  }

  Future<bool> _confirmLeave() async {
    final r = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Leave the quiz?'),
        content: const Text('Your answers are saved. You can continue this quiz later from the Home screen.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, 'abandon'), child: const Text('Discard quiz')),
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('Stay')),
          FilledButton(onPressed: () => Navigator.pop(c, 'later'), child: const Text('Continue later')),
        ],
      ),
    );
    if (r == 'abandon' && mounted) {
      final ok = await confirm(context,
          title: 'Discard this quiz?',
          message: 'Answers you already confirmed stay in your history; the rest of this quiz is closed.',
          confirmLabel: 'Discard',
          destructive: true);
      if (!ok) return false;
      await _svc.sessions.abandon(_session!.id);
      _svc.dataChanged();
      return true;
    }
    if (r == 'later') {
      await _persistCursor();
      return true;
    }
    return false;
  }

  // ---------------- Keyboard (Windows / hardware keyboards) ----------------

  final FocusNode _keys = FocusNode(debugLabel: 'quiz-keys');

  /// Action of the big bottom button for the current question, or null.
  VoidCallback? _primaryAction(Question q, QuestionResponse response, AttemptResult? result) {
    final last = _index == _items.length - 1;
    if (_immediate) {
      final awaitingSubmit = result == null || result == AttemptResult.review;
      if (awaitingSubmit) return isAnswered(q, response) && !_busy ? _submit : null;
      return _busy ? null : _next;
    }
    return last ? () => _finish() : () => _show(_index + 1);
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent e) {
    if (e is! KeyDownEvent && e is! KeyRepeatEvent) return KeyEventResult.ignored;
    if (_session == null || _finishing || _items.isEmpty) return KeyEventResult.ignored;
    final route = ModalRoute.of(context);
    if (route != null && !route.isCurrent) return KeyEventResult.ignored;
    final q = _q;
    if (q == null) return KeyEventResult.ignored;
    final k = e.logicalKey;
    final ctrl = HardwareKeyboard.instance.isControlPressed;
    final pos = _item.position;
    final response = _responses[pos] ?? QuestionResponse();

    if (k == LogicalKeyboardKey.f1) {
      showShortcutsDialog(context, 'Quiz shortcuts', quizShortcuts);
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.escape) {
      if (isEditingText) {
        _keys.requestFocus();
      } else {
        Navigator.of(context).maybePop();
      }
      return KeyEventResult.handled;
    }
    if (ctrl) {
      if (k == LogicalKeyboardKey.keyB) {
        _toggleBookmark();
        return KeyEventResult.handled;
      }
      if (k == LogicalKeyboardKey.keyG) {
        _showGrid();
        return KeyEventResult.handled;
      }
      if (k == LogicalKeyboardKey.keyR) {
        _svc.speech.speak(_speechText(q));
        return KeyEventResult.handled;
      }
      if (isEnterKey(k)) {
        _finish();
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }
    if (!noCommandModifier) return KeyEventResult.ignored;
    final typing = isEditingText;

    if (isEnterKey(k)) {
      if (e is KeyRepeatEvent) return KeyEventResult.handled;
      final action = _primaryAction(q, response, _results[pos]);
      if (action == null) return typing ? KeyEventResult.ignored : KeyEventResult.handled;
      action();
      return KeyEventResult.handled;
    }
    // Everything below is a single printable key: leave it to the text field.
    if (typing) return KeyEventResult.ignored;

    if (k == LogicalKeyboardKey.arrowRight || k == LogicalKeyboardKey.arrowLeft) {
      final rtl = Directionality.of(context) == TextDirection.rtl;
      final forward = (k == LogicalKeyboardKey.arrowRight) != rtl;
      if (forward) {
        final revealedNow = _immediate && _results.containsKey(pos) && _results[pos] != AttemptResult.review;
        if (revealedNow) {
          _next();
        } else if (_index < _items.length - 1) {
          _show(_index + 1);
        }
      } else if (_index > 0) {
        _show(_index - 1);
      }
      return KeyEventResult.handled;
    }
    if (q.type.usesChoices && !_locked && !_busy) {
      final count = _item.optionOrder.length > q.options.length ? _item.optionOrder.length : q.options.length;
      final hintKey = k == LogicalKeyboardKey.keyH && count < 8;
      final i = hintKey ? null : optionIndexForKey(k);
      if (i != null) {
        final byId = {for (final o in q.options) o.id: o};
        final ordered = [
          for (final id in _item.optionOrder)
            if (byId.containsKey(id)) id,
          for (final o in q.options)
            if (!_item.optionOrder.contains(o.id)) o.id,
        ];
        if (i >= ordered.length) return KeyEventResult.handled;
        final id = ordered[i];
        final sel = {...response.selected};
        if (q.type == QuestionType.multiple) {
          sel.contains(id) ? sel.remove(id) : sel.add(id);
        } else {
          sel
            ..clear()
            ..add(id);
        }
        _onChanged(response.copyWith(selected: sel));
        return KeyEventResult.handled;
      }
    }
    if (k == LogicalKeyboardKey.keyH) {
      final canHint = _cfg.hintsAllowed && (q.hint ?? '').isNotEmpty && !_hintShown.contains(pos) && !_locked;
      if (canHint) _showHint();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  // ---------------- UI ----------------

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return Scaffold(appBar: AppBar(), body: EmptyState(icon: Icons.error_outline, title: _error!));
    }
    if (_session == null) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    final q = _q;
    final pos = _item.position;
    final result = _results[pos];
    final revealed = _immediate && result != null && result != AttemptResult.review;
    final response = _responses[pos] ?? QuestionResponse();
    final theme = Theme.of(context);
    final bookmarked = q != null && _bookmarks.contains(q.id);

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final leave = await _confirmLeave();
        if (leave && context.mounted) Navigator.of(context).pop();
      },
      child: Focus(
        focusNode: _keys,
        autofocus: true,
        onKeyEvent: _onKey,
        child: Scaffold(
        appBar: AppBar(
          centerTitle: true,
          leading: IconButton(
            tooltip: 'Leave quiz',
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.of(context).maybePop(),
          ),
          title: const AppLogo(size: 30, useAmbientColor: true),
          actions: [
            if (isDesktop)
              IconButton(
                tooltip: 'Keyboard shortcuts (F1)',
                icon: const Icon(Icons.keyboard_outlined),
                onPressed: () => showShortcutsDialog(context, 'Quiz shortcuts', quizShortcuts),
              ),
            if (q != null)
              IconButton(
                tooltip: bookmarked ? 'Remove bookmark' : 'Bookmark',
                icon: Icon(bookmarked ? Icons.bookmark : Icons.bookmark_border),
                onPressed: _toggleBookmark,
              ),
            PopupMenuButton<String>(
              tooltip: 'More',
              onSelected: (v) {
                if (v == 'grid') _showGrid();
                if (v == 'submit') _finish();
                if (v == 'speak' && q != null) _svc.speech.speak(_speechText(q));
              },
              itemBuilder: (_) => const [
                PopupMenuItem(
                    value: 'grid', child: ListTile(leading: Icon(Icons.grid_view), title: Text('All questions'))),
                PopupMenuItem(
                    value: 'speak', child: ListTile(leading: Icon(Icons.volume_up_outlined), title: Text('Read aloud'))),
                PopupMenuItem(
                    value: 'submit', child: ListTile(leading: Icon(Icons.flag_outlined), title: Text('Submit quiz'))),
              ],
            ),
          ],
        ),
        body: _finishing
            ? const Center(child: CircularProgressIndicator())
            : q == null
                ? const Center(child: Text('Question unavailable'))
                : SafeArea(
                    child: Column(children: [
                      Expanded(
                        child: ListView(
                          padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                          children: [
                            Readable(
                              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                                _headerCard(context, q),
                                const SizedBox(height: 14),
                                _questionCard(context, q),
                                const SizedBox(height: 16),
                                AnswerArea(
                                  key: ValueKey('answer-$pos'),
                                  question: q,
                                  order: _item.optionOrder,
                                  response: response,
                                  onChanged: _onChanged,
                                  revealed: revealed,
                                  locked: _locked || _busy,
                                  textController: _textCtrl,
                                ),
                                const SizedBox(height: 6),
                                _helperRow(context, q, bookmarked),
                                if (_hintShown.contains(pos) && (q.hint ?? '').isNotEmpty) ...[
                                  const SizedBox(height: 10),
                                  Container(
                                    padding: const EdgeInsets.all(14),
                                    decoration: BoxDecoration(
                                      color: brandGold.withValues(alpha: 0.14),
                                      borderRadius: BorderRadius.circular(16),
                                      border: Border.all(color: brandGold.withValues(alpha: 0.6)),
                                    ),
                                    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                      const Icon(Icons.lightbulb, color: brandGold),
                                      const SizedBox(width: 10),
                                      Expanded(child: ContentText(q.hint!)),
                                    ]),
                                  ),
                                ],
                                if (revealed) ...[
                                  const SizedBox(height: 12),
                                  FeedbackPanel(question: q, response: response, result: result),
                                ],
                                if ((revealed && _cfg.confidenceRatings && !_applied.contains(pos)) ||
                                    (!_immediate && _cfg.confidenceRatings && !_cfg.isExam && isAnswered(q, response))) ...[
                                  const SizedBox(height: 12),
                                  ConfidencePicker(
                                    label: revealed ? 'How well did you know it?' : 'How sure are you?',
                                    value: _confidence[pos],
                                    onChanged: (c) {
                                      setState(() => _confidence[pos] = c);
                                      _svc.sessions.setConfidence(_session!.id, pos, c);
                                    },
                                  ),
                                ],
                                if (!_cfg.isExam && revealed) ...[
                                  const SizedBox(height: 12),
                                  ExpansionTile(
                                    tilePadding: EdgeInsets.zero,
                                    leading: const Icon(Icons.sticky_note_2_outlined),
                                    title: const Text('My notes'),
                                    children: [NotesSection(questionId: q.id, compact: true)],
                                  ),
                                ],
                              ]),
                            ),
                          ],
                        ),
                      ),
                      _bottomBar(context, q, response, result, theme),
                    ]),
                  ),
        ),
      ),
    );
  }

  /// "English / Grammar · Question 12 of 25" with a progress (or countdown) ring.
  Widget _headerCard(BuildContext context, Question q) {
    final t = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final path = (_paths[q.bankId] ?? '').split(' → ').where((p) => p.isNotEmpty).toList();
    final shortPath = path.length > 2 ? path.sublist(path.length - 2) : path;
    final progress = (_index + 1) / _items.length;
    final rem = _remainingMs;
    Widget ring;
    if (rem != null) {
      final d = Duration(milliseconds: rem < 0 ? 0 : rem);
      final total = _cfg.timeLimitMinutes * 60000;
      final text = d.inMinutes >= 1
          ? '${d.inMinutes}:${(d.inSeconds % 60).toString().padLeft(2, '0')}'
          : '${d.inSeconds}s';
      ring = ProgressRing(
        value: total == 0 ? 0 : rem / total,
        label: text,
        color: rem < 60000 ? incorrectColor(scheme) : null,
        semanticLabel: 'Time left $text',
      );
    } else {
      ring = ProgressRing(
        value: progress,
        label: '${(progress * 100).round()}%',
        semanticLabel: 'Quiz progress ${(progress * 100).round()} percent',
      );
    }
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
      decoration: BoxDecoration(
        color: scheme.surfaceContainer,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.6)),
      ),
      child: Column(children: [
        Row(children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: [scheme.primary, Color.lerp(scheme.primary, scheme.tertiary, 0.75)!]),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(Icons.menu_book_rounded, color: Colors.white),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(shortPath.isEmpty ? _session!.title : shortPath.join(' / '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: t.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 2),
              Text('Question ${_index + 1} of ${_items.length}',
                  style: t.bodyMedium?.copyWith(color: scheme.primary, fontWeight: FontWeight.w600)),
            ]),
          ),
          const SizedBox(width: 8),
          ring,
        ]),
        const SizedBox(height: 12),
        GradientProgressBar(value: progress),
      ]),
    );
  }

  Widget _questionCard(BuildContext context, Question q) {
    final t = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 14, 8, 18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [scheme.primary.withValues(alpha: 0.10), scheme.tertiary.withValues(alpha: 0.06)],
        ),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: scheme.primary.withValues(alpha: 0.45), width: 1.5),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          CircleAvatar(
            radius: 13,
            backgroundColor: scheme.primary,
            child: Text('?', style: TextStyle(color: scheme.onPrimary, fontWeight: FontWeight.w800)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text('QUESTION ${_index + 1}',
                style: t.labelLarge?.copyWith(
                    color: scheme.primary, fontWeight: FontWeight.w800, letterSpacing: 1.1)),
          ),
          SpeakButton(text: _speechText(q)),
        ]),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.only(right: 10),
          child: ContentText(q.text,
              style: t.headlineSmall?.copyWith(fontWeight: FontWeight.w700, height: 1.3)),
        ),
        Padding(padding: const EdgeInsets.only(right: 10), child: QuestionMedia(question: q)),
      ]),
    );
  }

  /// Hint and Bookmark as two pill buttons side by side.
  Widget _helperRow(BuildContext context, Question q, bool bookmarked) {
    final scheme = Theme.of(context).colorScheme;
    final pos = _item.position;
    final hintAvailable = _cfg.hintsAllowed && (q.hint ?? '').isNotEmpty;
    final canHint = hintAvailable && !_hintShown.contains(pos) && !_locked;
    ButtonStyle pill() => OutlinedButton.styleFrom(
          minimumSize: const Size(0, 50),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          side: BorderSide(color: scheme.outlineVariant),
          backgroundColor: scheme.surfaceContainerLow,
        );
    return Row(children: [
      if (hintAvailable) ...[
        Expanded(
          child: OutlinedButton.icon(
            style: pill(),
            onPressed: canHint ? _showHint : null,
            icon: const Icon(Icons.lightbulb_outline, color: brandGold),
            label: Text(_hintShown.contains(pos) ? 'Hint shown' : 'Hint'),
          ),
        ),
        const SizedBox(width: 10),
      ],
      Expanded(
        child: OutlinedButton.icon(
          style: pill(),
          onPressed: _toggleBookmark,
          icon: Icon(bookmarked ? Icons.bookmark : Icons.bookmark_border, color: const Color(0xFFE0457B)),
          label: Text(bookmarked ? 'Bookmarked' : 'Bookmark'),
        ),
      ),
    ]);
  }

  String _speechText(Question q) {
    final b = StringBuffer(q.text);
    if (q.type.usesChoices) {
      final byId = {for (final o in q.options) o.id: o};
      var i = 0;
      for (final id in _item.optionOrder) {
        final o = byId[id];
        if (o == null) continue;
        b.write('. Option ${String.fromCharCode(65 + i++)}: ${o.text}');
      }
    }
    return b.toString();
  }

  Widget _bottomBar(BuildContext context, Question q, QuestionResponse response, AttemptResult? result, ThemeData theme) {
    final answered = isAnswered(q, response);
    final last = _index == _items.length - 1;
    final scheme = theme.colorScheme;
    final awaitingSubmit = _immediate && (result == null || result == AttemptResult.review);

    String label;
    IconData icon;
    final action = _primaryAction(q, response, result);
    if (_immediate) {
      if (awaitingSubmit) {
        label = 'Check Answer';
        icon = Icons.check_circle_outline;
      } else {
        label = last ? 'Finish Quiz' : 'Next Question';
        icon = last ? Icons.flag_outlined : Icons.arrow_forward_rounded;
      }
    } else {
      label = last ? 'Submit Quiz' : 'Next';
      icon = last ? Icons.flag_outlined : Icons.arrow_forward_rounded;
    }

    final showSkip = !last && (awaitingSubmit || (!_immediate && !answered));
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
      decoration: BoxDecoration(
        // Glass themes have a transparent scaffold: use a frosted panel instead.
        color: theme.scaffoldBackgroundColor.a < 1 ? scheme.surfaceContainerHigh : theme.scaffoldBackgroundColor,
        borderRadius: theme.scaffoldBackgroundColor.a < 1 ? const BorderRadius.vertical(top: Radius.circular(24)) : null,
        boxShadow: theme.scaffoldBackgroundColor.a < 1
            ? null
            : [BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 10, offset: const Offset(0, -2))],
      ),
      child: Readable(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          GradientButton(label: label, icon: icon, onPressed: action),
          const SizedBox(height: 4),
          Row(children: [
            TextButton.icon(
              onPressed: _index == 0 ? null : () => _show(_index - 1),
              icon: const Icon(Icons.chevron_left),
              label: const Text('Previous'),
            ),
            const Spacer(),
            Text('${_results.length}/${_items.length} answered',
                style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
            const Spacer(),
            if (showSkip)
              TextButton(
                onPressed: () => _show(_index + 1),
                child: const Row(mainAxisSize: MainAxisSize.min, children: [
                  Text('Skip'),
                  SizedBox(width: 4),
                  Icon(Icons.chevron_right, size: 20),
                ]),
              )
            else
              const SizedBox(width: 88),
          ]),
        ]),
      ),
    );
  }

  void _showGrid() {
    final scheme = Theme.of(context).colorScheme;
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (c) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text('Questions', style: Theme.of(c).textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(_immediate ? 'Green = correct, red = incorrect, outlined = not answered'
                : 'Filled = answered, outlined = not answered yet',
                style: Theme.of(c).textTheme.bodySmall),
            const SizedBox(height: 12),
            Flexible(
              child: SingleChildScrollView(
                child: Wrap(spacing: 8, runSpacing: 8, children: [
                  for (var i = 0; i < _items.length; i++)
                    Builder(builder: (_) {
                      final res = _results[_items[i].position];
                      Color? bg;
                      if (res != null) {
                        if (_immediate && res == AttemptResult.correct) {
                          bg = correctColor(scheme);
                        } else if (_immediate && res == AttemptResult.incorrect) {
                          bg = incorrectColor(scheme);
                        } else {
                          bg = scheme.primary;
                        }
                      }
                      return SizedBox(
                        width: 48,
                        height: 48,
                        child: OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            padding: EdgeInsets.zero,
                            backgroundColor: bg,
                            foregroundColor: bg == null ? null : scheme.onPrimary,
                            side: BorderSide(color: i == _index ? scheme.onSurface : scheme.outline, width: i == _index ? 2 : 1),
                            minimumSize: const Size(48, 48),
                          ),
                          onPressed: () {
                            Navigator.pop(c);
                            _show(i);
                          },
                          child: Text('${i + 1}'),
                        ),
                      );
                    }),
                ]),
              ),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () {
                Navigator.pop(c);
                final next = List.generate(_items.length, (k) => (k + _index + 1) % _items.length)
                    .firstWhere((k) => !_results.containsKey(_items[k].position), orElse: () => -1);
                if (next >= 0) {
                  _show(next);
                } else {
                  showMessage(context, 'Every question has been answered.');
                }
              },
              icon: const Icon(Icons.skip_next),
              label: const Text('Go to next unanswered'),
            ),
            const SizedBox(height: 8),
            FilledButton.icon(
              onPressed: () {
                Navigator.pop(c);
                _finish();
              },
              icon: const Icon(Icons.flag),
              label: const Text('Submit quiz'),
            ),
          ]),
        ),
      ),
    );
  }
}
