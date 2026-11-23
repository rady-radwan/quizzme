import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../app/services.dart';
import '../../app/theme.dart';
import '../../core/dates.dart';
import '../../core/grading.dart';
import '../../core/models.dart';
import '../../data/session_repository.dart';
import '../common/reloadable.dart';
import '../common/widgets.dart';
import 'quiz_launcher.dart';

class _ResultData {
  _ResultData(this.session, this.items, this.questions, this.progress);
  final QuizSession session;
  final List<SessionItem> items;
  final Map<String, Question> questions;
  final Map<String, QuestionProgress> progress;
}

class ResultsScreen extends StatefulWidget {
  const ResultsScreen({super.key, required this.sessionId});
  final String sessionId;

  @override
  State<ResultsScreen> createState() => _ResultsScreenState();
}

class _ResultsScreenState extends State<ResultsScreen> {
  bool _mistakesOnly = false;

  Future<_ResultData?> _load() async {
    final svc = AppServices.I;
    final s = await svc.sessions.session(widget.sessionId);
    if (s == null) return null;
    final items = await svc.sessions.items(s.id);
    final ids = items.map((i) => i.questionId).toList();
    final qs = {for (final q in await svc.questions.questionsByIds(ids)) q.id: q};
    return _ResultData(s, items, qs, await svc.study.progressFor(ids));
  }

  @override
  Widget build(BuildContext context) {
    return Reloadable<_ResultData?>(
      load: _load,
      loading: const Scaffold(body: Center(child: CircularProgressIndicator())),
      builder: (context, d, reload) {
        if (d == null) {
          return Scaffold(appBar: AppBar(), body: const Center(child: Text('This quiz was deleted.')));
        }
        final s = d.session;
        final scheme = Theme.of(context).colorScheme;
        final t = Theme.of(context).textTheme;
        final pending = d.items.where((i) => i.result == AttemptResult.review).toList();
        final skipped = d.items.where((i) => i.result == null || i.result == AttemptResult.skipped).length;
        final shown = d.items
            .where((i) => !_mistakesOnly || i.result != AttemptResult.correct)
            .toList();
        final fmt = DateFormat.yMMMd().add_Hm();
        return Scaffold(
          appBar: AppBar(title: const Text('Results')),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            children: [
              Readable(
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  _scoreCard(context, s),
                  const SizedBox(height: 12),
                  StatGrid(minTileWidth: 110, children: [
                    StatTile(
                        label: 'Correct', value: '${s.correct}', icon: Icons.check_circle, color: correctColor(scheme)),
                    StatTile(
                        label: 'Incorrect', value: '${s.incorrect}', icon: Icons.cancel, color: incorrectColor(scheme)),
                    StatTile(label: 'Unanswered', value: '$skipped', icon: Icons.remove_circle_outline),
                    StatTile(label: 'Accuracy', value: percent(s.accuracy), icon: Icons.track_changes),
                    StatTile(
                        label: 'Time',
                        value: formatDuration(Duration(milliseconds: s.elapsedMs)),
                        icon: Icons.timer_outlined),
                    StatTile(label: 'Questions', value: '${s.total}', icon: Icons.quiz_outlined),
                  ]),
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(fmt.format(s.completedAt ?? s.createdAt), style: t.bodySmall),
                  ),
                  if (pending.isNotEmpty) ...[
                    const SectionHeader('Check your written answers'),
                    for (final it in pending)
                      if (d.questions[it.questionId] != null)
                        _pendingCard(context, it, d.questions[it.questionId]!),
                  ],
                  const SizedBox(height: 12),
                  Wrap(spacing: 8, runSpacing: 8, children: [
                    if (s.incorrect + skipped > 0)
                      FilledButton.icon(
                        onPressed: () => launchQuiz(
                            context, AppServices.I.sessions.retakeConfig(s, d.items, mistakesOnly: true)),
                        icon: const Icon(Icons.error_outline),
                        label: const Text('Review mistakes'),
                      ),
                    OutlinedButton.icon(
                      onPressed: () => launchQuiz(context, AppServices.I.sessions.retakeConfig(s, d.items)),
                      icon: const Icon(Icons.replay),
                      label: const Text('Retake quiz'),
                    ),
                    OutlinedButton.icon(
                      onPressed: () => _practiceSimilar(context, d),
                      icon: const Icon(Icons.auto_awesome_motion_outlined),
                      label: const Text('Practice similar'),
                    ),
                    TextButton.icon(
                      onPressed: () => Navigator.of(context).popUntil((r) => r.isFirst),
                      icon: const Icon(Icons.home_outlined),
                      label: const Text('Return home'),
                    ),
                  ]),
                  SectionHeader('Question review',
                      action: FilterChip(
                        label: const Text('Mistakes only'),
                        selected: _mistakesOnly,
                        onSelected: (v) => setState(() => _mistakesOnly = v),
                      )),
                  for (final it in shown)
                    if (d.questions[it.questionId] != null)
                      _reviewTile(context, it, d.questions[it.questionId]!, d.progress[it.questionId]),
                ]),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _scoreCard(BuildContext context, QuizSession s) {
    final scheme = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    final score = s.score?.round() ?? 0;
    final message = score >= 90
        ? 'Outstanding! 🎉'
        : score >= 75
            ? 'Great work!'
            : score >= 50
                ? 'Good effort — review your mistakes.'
                : 'Keep practising — you\'ll get there.';
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 22),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [scheme.primary, Color.lerp(scheme.primary, scheme.tertiary, 0.8)!],
        ),
        borderRadius: BorderRadius.circular(26),
      ),
      child: Column(children: [
        Text(s.status == SessionStatus.completed ? 'Quiz completed!' : 'Quiz not finished',
            style: t.headlineSmall?.copyWith(color: Colors.white, fontWeight: FontWeight.w800)),
        const SizedBox(height: 4),
        Text(s.title,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: t.bodyMedium?.copyWith(color: Colors.white.withValues(alpha: 0.85))),
        const SizedBox(height: 18),
        Text('Your final score is', style: t.titleMedium?.copyWith(color: Colors.white)),
        const SizedBox(height: 12),
        Semantics(
          label: 'Score $score percent',
          child: Container(
            width: 150,
            height: 150,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: const LinearGradient(
                  begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [brandGold, brandOrange]),
              border: Border.all(color: Colors.white.withValues(alpha: 0.85), width: 5),
              boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.25), blurRadius: 18, offset: const Offset(0, 8))],
            ),
            alignment: Alignment.center,
            child: ExcludeSemantics(
              child: Text('$score%',
                  style: const TextStyle(fontSize: 44, fontWeight: FontWeight.w900, color: Colors.white)),
            ),
          ),
        ),
        const SizedBox(height: 14),
        Text('${s.correct} of ${s.total} correct · $message',
            textAlign: TextAlign.center, style: t.bodyLarge?.copyWith(color: Colors.white)),
      ]),
    );
  }

  Widget _pendingCard(BuildContext context, SessionItem it, Question q) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            ContentText(q.text, style: const TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Text('Your answer: ${it.response.text ?? ''}'),
            Text('Expected: ${acceptedAnswersOf(q).join(' / ')}'),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => _resolve(it, q, false),
                  child: const Text('I was wrong'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton(
                  onPressed: () => _resolve(it, q, true),
                  child: const Text('I was right'),
                ),
              ),
            ]),
          ]),
        ),
      ),
    );
  }

  Future<void> _resolve(SessionItem it, Question q, bool correct) async {
    await AppServices.I.sessions.resolveReview(it.sessionId, it.position, q, correct);
    AppServices.I.dataChanged();
  }

  Widget _reviewTile(BuildContext context, SessionItem it, Question q, QuestionProgress? p) {
    final scheme = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    final r = it.result;
    final (icon, color, label) = switch (r) {
      AttemptResult.correct => (Icons.check_circle, correctColor(scheme), 'Correct'),
      AttemptResult.incorrect => (Icons.cancel, incorrectColor(scheme), 'Incorrect'),
      AttemptResult.review => (Icons.rate_review_outlined, scheme.tertiary, 'Needs your review'),
      _ => (Icons.remove_circle_outline, scheme.outline, 'Not answered'),
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Card(
        child: ExpansionTile(
          leading: Icon(icon, color: color, semanticLabel: label),
          title: ContentText(q.text, maxLines: 2),
          subtitle: Text('Question ${it.position + 1} · $label'),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Your answer', style: t.labelLarge),
            ContentText(describeResponse(q, it.response)),
            const SizedBox(height: 8),
            Text('Correct answer', style: t.labelLarge),
            ContentText(q.correctAnswerText),
            for (final w in wrongChoiceExplanations(q, it.response)) ...[
              const SizedBox(height: 8),
              Text('Why your choice is wrong', style: t.labelLarge),
              ContentText(w),
            ],
            if ((q.explanation ?? '').isNotEmpty) ...[
              const SizedBox(height: 8),
              Text('Explanation', style: t.labelLarge),
              ContentText(q.explanation!),
            ],
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
              if (p != null) MasteryChip(p.mastery, dense: true),
              Text(it.hintUsed ? 'Hint used' : 'No hint', style: t.bodySmall),
              if (it.confidence != null) Text('Confidence: ${it.confidence!.label}', style: t.bodySmall),
            ]),
          ],
        ),
      ),
    );
  }

  Future<void> _practiceSimilar(BuildContext context, _ResultData d) async {
    final bankIds = d.questions.values.map((q) => q.bankId).toSet().toList();
    await launchQuiz(
      context,
      defaultConfig(
        title: 'Practice: ${d.session.title}',
        selection: SelectionMode.quickReview,
        bankIds: bankIds,
        count: d.session.total,
      ),
    );
  }
}
