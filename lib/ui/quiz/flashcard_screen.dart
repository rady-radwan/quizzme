import 'package:flutter/material.dart';

import '../../app/services.dart';
import '../../core/grading.dart';
import '../../core/models.dart';
import '../../data/session_repository.dart';
import '../common/widgets.dart';
import 'question_media.dart';
import 'results_screen.dart';

/// Flashcard mode: front = question, tap to reveal the back (answer and
/// explanation), then rate how well you remembered it. Ratings feed the
/// spaced-repetition schedule. Swipe left for the next card, right to go back.
class FlashcardScreen extends StatefulWidget {
  const FlashcardScreen({super.key, required this.sessionId});
  final String sessionId;

  @override
  State<FlashcardScreen> createState() => _FlashcardScreenState();
}

class _FlashcardScreenState extends State<FlashcardScreen> {
  final _svc = AppServices.I;
  QuizSession? _session;
  List<SessionItem> _items = [];
  Map<String, Question> _questions = {};
  final Map<int, Confidence> _rated = {};
  final Set<int> _presented = {};
  int _index = 0;
  bool _revealed = false;
  bool _finishing = false;
  DateTime _shownAt = DateTime.now();
  final Stopwatch _watch = Stopwatch();
  int _elapsedBase = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    final s = _session;
    if (s != null && !_finishing) {
      _svc.sessions.saveCursor(s.id, _index, _elapsedBase + _watch.elapsedMilliseconds);
    }
    _svc.speech.stopSpeaking();
    super.dispose();
  }

  Future<void> _load() async {
    final s = await _svc.sessions.session(widget.sessionId);
    if (s == null) return;
    final items = await _svc.sessions.items(s.id);
    final qs = {for (final q in await _svc.questions.questionsByIds(items.map((i) => i.questionId).toList())) q.id: q};
    for (final it in items) {
      if (it.applied && it.confidence != null) _rated[it.position] = it.confidence!;
      if (it.presentedAt != null) _presented.add(it.position);
    }
    if (!mounted) return;
    setState(() {
      _session = s;
      _items = items.where((i) => qs.containsKey(i.questionId)).toList();
      _questions = qs;
      _elapsedBase = s.elapsedMs;
      _index = s.currentIndex.clamp(0, _items.isEmpty ? 0 : _items.length - 1);
    });
    _watch.start();
    if (_items.isNotEmpty) _go(_index);
  }

  void _go(int i) {
    setState(() {
      _index = i;
      _revealed = _rated.containsKey(_items[i].position);
    });
    _shownAt = DateTime.now();
    if (_presented.add(_items[i].position)) {
      _svc.sessions.markPresented(_session!.id, _items[i].position);
    }
    _svc.sessions.saveCursor(_session!.id, i, _elapsedBase + _watch.elapsedMilliseconds);
  }

  Future<void> _rate(Confidence c) async {
    final it = _items[_index];
    final q = _questions[it.questionId];
    if (q == null || _rated.containsKey(it.position)) return;
    final ms = DateTime.now().difference(_shownAt).inMilliseconds;
    await _svc.sessions.recordFlashcard(_session!.id, it.position, q, rating: c, durationMs: ms);
    setState(() => _rated[it.position] = c);
    final next = _nextUnrated();
    if (next == null) {
      await _finish();
    } else {
      _go(next);
    }
  }

  int? _nextUnrated() {
    for (var k = 1; k <= _items.length; k++) {
      final i = (_index + k) % _items.length;
      if (!_rated.containsKey(_items[i].position)) return i;
    }
    return null;
  }

  Future<void> _finish() async {
    setState(() => _finishing = true);
    _watch.stop();
    await _svc.sessions.complete(_session!.id, elapsedMs: _elapsedBase + _watch.elapsedMilliseconds);
    _svc.dataChanged();
    if (_svc.settings.value.gamification) await _svc.stats.checkAchievements();
    _svc.refreshReminders();
    if (!mounted) return;
    Navigator.pushReplacement(
        context, MaterialPageRoute<void>(builder: (_) => ResultsScreen(sessionId: _session!.id)));
  }

  String _backText(Question q) {
    switch (q.type) {
      case QuestionType.fillBlank:
      case QuestionType.shortAnswer:
        return acceptedAnswersOf(q).join('\n');
      case QuestionType.flashcard:
        return q.acceptedAnswers.isEmpty ? '' : q.acceptedAnswers.first;
      case QuestionType.matching:
        return q.options.map((o) => '${o.text} → ${o.matchText ?? ''}').join('\n');
      default:
        return q.correctAnswerText;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_session == null) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    if (_items.isEmpty) {
      return Scaffold(appBar: AppBar(), body: const EmptyState(icon: Icons.style_outlined, title: 'No cards'));
    }
    final it = _items[_index];
    final q = _questions[it.questionId]!;
    final theme = Theme.of(context);
    final rated = _rated[it.position];
    final reduce = MediaQuery.of(context).disableAnimations;

    final front = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        Text('Question', style: theme.textTheme.labelLarge),
        const Spacer(),
        SpeakButton(text: q.text),
      ]),
      const SizedBox(height: 8),
      ContentText(q.text, style: theme.textTheme.headlineSmall),
      QuestionMedia(question: q),
      if (q.type.usesChoices) ...[
        const SizedBox(height: 12),
        for (final o in q.options)
          Padding(padding: const EdgeInsets.only(bottom: 4), child: ContentText('• ${o.text}')),
      ],
      const SizedBox(height: 24),
      Center(child: Text('Tap to reveal the answer', style: theme.textTheme.bodySmall)),
    ]);

    final back = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        Text('Answer', style: theme.textTheme.labelLarge),
        const Spacer(),
        SpeakButton(text: _backText(q)),
      ]),
      const SizedBox(height: 8),
      ContentText(_backText(q), style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
      if ((q.explanation ?? '').isNotEmpty) ...[
        const SizedBox(height: 16),
        Text('Explanation', style: theme.textTheme.labelLarge),
        ContentText(q.explanation!),
      ],
      const SizedBox(height: 12),
      Text(q.text, style: theme.textTheme.bodySmall, maxLines: 3, overflow: TextOverflow.ellipsis),
    ]);

    return Scaffold(
      appBar: AppBar(
        title: Text('Card ${_index + 1} of ${_items.length}'),
        actions: [
          TextButton(onPressed: _finishing ? null : _finish, child: const Text('Finish')),
        ],
      ),
      body: _finishing
          ? const Center(child: CircularProgressIndicator())
          : SafeArea(
              child: Column(children: [
                LinearProgressIndicator(value: _rated.length / _items.length, semanticsLabel: 'Cards rated'),
                Expanded(
                  child: GestureDetector(
                    onHorizontalDragEnd: (d) {
                      final v = d.primaryVelocity ?? 0;
                      final rtl = Directionality.of(context) == TextDirection.rtl;
                      final forward = rtl ? v > 300 : v < -300;
                      final backward = rtl ? v < -300 : v > 300;
                      if (forward && _index < _items.length - 1) _go(_index + 1);
                      if (backward && _index > 0) _go(_index - 1);
                    },
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(16),
                      child: Readable(
                        child: Semantics(
                          button: !_revealed,
                          label: _revealed ? null : 'Card. Double tap to reveal the answer.',
                          child: GestureDetector(
                            onTap: () => setState(() => _revealed = !_revealed),
                            child: AnimatedSwitcher(
                              duration: reduce ? Duration.zero : const Duration(milliseconds: 220),
                              child: Card(
                                key: ValueKey('${it.position}-$_revealed'),
                                color: _revealed ? theme.colorScheme.secondaryContainer : null,
                                child: ConstrainedBox(
                                  constraints: const BoxConstraints(minHeight: 280),
                                  child: Padding(padding: const EdgeInsets.all(20), child: _revealed ? back : front),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                  child: !_revealed
                      ? Row(children: [
                          IconButton(
                            tooltip: 'Previous card',
                            onPressed: _index == 0 ? null : () => _go(_index - 1),
                            icon: const Icon(Icons.chevron_left),
                          ),
                          Expanded(
                            child: FilledButton(
                              onPressed: () => setState(() => _revealed = true),
                              child: const Text('Show answer'),
                            ),
                          ),
                          IconButton(
                            tooltip: 'Next card',
                            onPressed: _index >= _items.length - 1 ? null : () => _go(_index + 1),
                            icon: const Icon(Icons.chevron_right),
                          ),
                        ])
                      : rated != null
                          ? Row(children: [
                              Expanded(child: Text('Rated: ${rated.label}', textAlign: TextAlign.center)),
                              FilledButton(
                                onPressed: () {
                                  final n = _nextUnrated();
                                  if (n == null) {
                                    _finish();
                                  } else {
                                    _go(n);
                                  }
                                },
                                child: const Text('Next card'),
                              ),
                            ])
                          : Column(mainAxisSize: MainAxisSize.min, children: [
                              Text('How well did you remember?', style: theme.textTheme.labelLarge),
                              const SizedBox(height: 8),
                              Row(children: [
                                for (final c in Confidence.values)
                                  Expanded(
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(horizontal: 3),
                                      child: c == Confidence.didntKnow
                                          ? OutlinedButton(
                                              onPressed: () => _rate(c),
                                              style: OutlinedButton.styleFrom(
                                                  padding: const EdgeInsets.symmetric(horizontal: 4)),
                                              child: const Text('Forgot', textAlign: TextAlign.center),
                                            )
                                          : FilledButton.tonal(
                                              onPressed: () => _rate(c),
                                              style: FilledButton.styleFrom(
                                                  padding: const EdgeInsets.symmetric(horizontal: 4)),
                                              child: Text(c.label, textAlign: TextAlign.center),
                                            ),
                                    ),
                                  ),
                              ]),
                            ]),
                ),
              ]),
            ),
    );
  }
}
