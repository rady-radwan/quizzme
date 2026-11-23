import 'package:flutter/material.dart';

import '../../app/services.dart';
import '../../app/theme.dart';
import '../../core/dates.dart';
import '../../core/models.dart';
import '../../data/sample_data.dart';
import '../../data/session_repository.dart';
import '../../data/stats_repository.dart';
import '../banks/category_screen.dart';
import '../common/reloadable.dart';
import '../common/widgets.dart';
import '../import/import_screen.dart';
import '../mistakes/mistakes_screen.dart';
import '../quiz/quiz_launcher.dart';
import '../quiz/results_screen.dart';
import '../shell.dart';

class _HomeData {
  _HomeData(this.dash, this.subjects, this.recs, this.active, this.last, this.activeAnswered);
  final DashboardStats dash;
  final List<SubjectProgress> subjects;
  final List<Recommendation> recs;
  final QuizSession? active;
  final QuizSession? last;
  final int activeAnswered;
}

const _messages = [
  'Small steps every day build knowledge that lasts.',
  'Review today what you might forget tomorrow.',
  'Consistency beats intensity.',
  'Every question answered is a memory strengthened.',
  'Learning is a habit — keep your streak alive.',
  'Mistakes are where the learning happens.',
  'Your future self will thank you for today\'s review.',
];

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  Future<_HomeData> _load() async {
    final svc = AppServices.I;
    final dash = await svc.stats.dashboard();
    final subjects = await svc.stats.subjectProgress();
    final recs = await svc.stats.recommendations();
    final active = await svc.sessions.latestActive();
    var answered = 0;
    if (active != null) {
      answered = (await svc.sessions.items(active.id)).where((i) => i.result != null).length;
    }
    final hist = await svc.sessions.history(limit: 1);
    return _HomeData(dash, subjects, recs, active, hist.isEmpty ? null : hist.first, answered);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Reloadable<_HomeData>(
          load: _load,
          builder: (context, d, reload) => RefreshIndicator(
            onRefresh: reload,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
              children: [
                Readable(child: _content(context, d)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _content(BuildContext context, _HomeData d) {
    final theme = Theme.of(context);
    final svc = AppServices.I;
    final goal = svc.settings.value.dailyQuestionGoal;
    final today = d.dash.today.answered;
    final msg = _messages[DateTime.now().difference(DateTime(2024)).inDays % _messages.length];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const AppLogo(size: 44),
              const SizedBox(height: 6),
              Text(msg, style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            ]),
          ),
          if (d.dash.currentStreak > 0)
            Tooltip(
              message: 'Study streak',
              child: Chip(
                avatar: const Icon(Icons.local_fire_department, size: 18),
                label: Text('${d.dash.currentStreak} day${d.dash.currentStreak == 1 ? '' : 's'}'),
              ),
            ),
        ]),
        const SizedBox(height: 16),
        if (d.dash.totalQuestions == 0) _welcome(context) else ...[
          _todayCard(context, today, goal),
          const SizedBox(height: 12),
          _reviewCard(context, d.dash),
          if (d.active != null) ...[
            const SizedBox(height: 12),
            _continueCard(context, d.active!, d.activeAnswered),
          ],
          const SectionHeader('Quick actions'),
          _quickActions(context),
          if (d.recs.isNotEmpty) ...[
            const SectionHeader('Suggestions'),
            for (final r in d.recs) _recTile(context, r),
          ],
          if (d.subjects.isNotEmpty) ...[
            SectionHeader('My subjects',
                action: TextButton(
                    onPressed: () => HomeShell.of(context)?.select(2), child: const Text('All banks'))),
            Card(
              child: Column(children: [
                for (final s in d.subjects)
                  ListTile(
                    leading: NodeAvatar(iconKey: s.subject.iconKey, color: s.subject.color, size: 36),
                    title: Text(s.subject.name),
                    subtitle: Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: LabeledProgress(
                        label: '${s.total} questions',
                        value: s.masteredFraction,
                        trailing: '${(s.masteredFraction * 100).round()}% mastered',
                      ),
                    ),
                    onTap: () => Navigator.push(context,
                        MaterialPageRoute<void>(builder: (_) => CategoryScreen(categoryId: s.subject.id))),
                  ),
              ]),
            ),
          ],
          if (d.last != null) ...[
            const SectionHeader('Recent activity'),
            Card(
              child: ListTile(
                leading: const Icon(Icons.history),
                title: Text('Last quiz: ${d.last!.title}'),
                subtitle: Text('Score: ${d.last!.score?.round() ?? 0}% · '
                    '${d.last!.correct}/${d.last!.total} correct'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.push(context,
                    MaterialPageRoute<void>(builder: (_) => ResultsScreen(sessionId: d.last!.id))),
              ),
            ),
          ],
        ],
      ],
    );
  }

  Widget _welcome(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Center(
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
              child: Image.asset('assets/branding/logo.png', height: 150),
            ),
          ),
          const SizedBox(height: 16),
          Text('Welcome to Quiz me', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          const Text('Organise what you learn into subjects and question banks, import your '
              'questions from Excel, and let spaced repetition remind you before you forget.'),
          const SizedBox(height: 16),
          Wrap(spacing: 8, runSpacing: 8, children: [
            FilledButton.icon(
              onPressed: () => HomeShell.of(context)?.select(2),
              icon: const Icon(Icons.create_new_folder_outlined),
              label: const Text('Create a subject'),
            ),
            OutlinedButton.icon(
              onPressed: () => Navigator.push(
                  context, MaterialPageRoute<void>(builder: (_) => const ImportScreen())),
              icon: const Icon(Icons.upload_file),
              label: const Text('Import from Excel'),
            ),
            OutlinedButton.icon(
              onPressed: () async {
                await SampleData.create(AppServices.I.catalog, AppServices.I.questions);
                AppServices.I.dataChanged();
              },
              icon: const Icon(Icons.auto_awesome_outlined),
              label: const Text('Try sample questions'),
            ),
          ]),
        ]),
      ),
    );
  }

  Widget _todayCard(BuildContext context, int today, int goal) {
    final frac = goal <= 0 ? 1.0 : (today / goal).clamp(0.0, 1.0);
    final theme = Theme.of(context);
    return Card(
      color: theme.colorScheme.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text("Today's learning",
              style: theme.textTheme.labelLarge?.copyWith(color: theme.colorScheme.onPrimaryContainer)),
          const SizedBox(height: 6),
          Text(goal > 0 ? '$today / $goal questions completed' : '$today questions answered today',
              style: theme.textTheme.titleLarge?.copyWith(
                  color: theme.colorScheme.onPrimaryContainer, fontWeight: FontWeight.w700)),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: frac,
              minHeight: 10,
              semanticsLabel: 'Daily goal progress',
              semanticsValue: '${(frac * 100).round()} percent',
            ),
          ),
          const SizedBox(height: 6),
          if (goal > 0)
            Text(today >= goal ? 'Daily goal reached — well done!' : '${(frac * 100).round()}% of daily goal',
                style: TextStyle(color: theme.colorScheme.onPrimaryContainer)),
        ]),
      ),
    );
  }

  Widget _reviewCard(BuildContext context, DashboardStats s) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Questions due today', style: theme.textTheme.labelLarge),
              const SizedBox(height: 4),
              Text('${s.dueToday}', style: theme.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w800)),
              Text(
                s.overdue > 0
                    ? '${s.overdue} overdue · ${s.dueTomorrow} due tomorrow'
                    : '${s.dueTomorrow} due tomorrow · ${s.mastered} mastered',
                style: theme.textTheme.bodySmall,
              ),
            ]),
          ),
          FilledButton(
            onPressed: s.dueToday == 0
                ? null
                : () => launchQuiz(
                    context,
                    defaultConfig(
                        title: 'Due reviews',
                        selection: SelectionMode.spaced,
                        count: s.dueToday > 100 ? 100 : s.dueToday)),
            child: const Text('Review now'),
          ),
        ]),
      ),
    );
  }

  Widget _continueCard(BuildContext context, QuizSession s, int answered) {
    return Card(
      child: ListTile(
        leading: const Icon(Icons.play_circle_outline, size: 32),
        title: const Text('Continue last quiz'),
        subtitle: Text('${s.title} · $answered of ${s.total} answered · started ${_ago(s.createdAt)}'),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => openSession(context, s),
      ),
    );
  }

  static String _ago(DateTime t) {
    final days = calendarDaysBetween(t, DateTime.now());
    if (days == 0) return 'today';
    if (days == 1) return 'yesterday';
    return '$days days ago';
  }

  Widget _quickActions(BuildContext context) {
    final actions = <(IconData, String, VoidCallback)>[
      (Icons.play_arrow_rounded, 'Start Quiz', () => HomeShell.of(context)?.select(1)),
      (
        Icons.fiber_new_outlined,
        'New Questions',
        () => launchQuiz(context, defaultConfig(title: 'New questions', selection: SelectionMode.newQuestions))
      ),
      (
        Icons.error_outline,
        'Review Mistakes',
        () => Navigator.push(context, MaterialPageRoute<void>(builder: (_) => const MistakesScreen()))
      ),
      (
        Icons.style_outlined,
        'Flashcards',
        () => launchQuiz(context,
            defaultConfig(title: 'Flashcards', selection: SelectionMode.random, style: QuizStyle.flashcards, count: 20))
      ),
      (
        Icons.bolt_outlined,
        'Quick Review',
        () => launchQuiz(context, defaultConfig(title: 'Quick review', selection: SelectionMode.quickReview, count: 10))
      ),
      (Icons.library_books_outlined, 'Question Banks', () => HomeShell.of(context)?.select(2)),
    ];
    return LayoutBuilder(builder: (context, c) {
      final cols = c.maxWidth > 560 ? 3 : 2;
      final w = (c.maxWidth - (cols - 1) * 8) / cols;
      return Wrap(spacing: 8, runSpacing: 8, children: [
        for (final a in actions)
          SizedBox(
            width: w,
            child: Card(
              child: InkWell(
                onTap: a.$3,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                  child: Row(children: [
                    Icon(a.$1, color: Theme.of(context).colorScheme.primary),
                    const SizedBox(width: 10),
                    Expanded(child: Text(a.$2, style: const TextStyle(fontWeight: FontWeight.w600))),
                  ]),
                ),
              ),
            ),
          ),
      ]);
    });
  }

  Widget _recTile(BuildContext context, Recommendation r) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Icon(Icons.lightbulb_outline, size: 20, color: Theme.of(context).colorScheme.tertiary),
              const SizedBox(width: 8),
              Expanded(child: Text(r.message)),
            ]),
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: TextButton(onPressed: () => _runRecommendation(context, r), child: Text(r.actionLabel)),
            ),
          ]),
        ),
      ),
    );
  }

  static void _runRecommendation(BuildContext context, Recommendation r) {
    switch (r.action) {
      case RecommendationAction.reviewDue:
      case RecommendationAction.reviewOverdue:
        launchQuiz(context, defaultConfig(title: 'Due reviews', selection: SelectionMode.spaced, count: 50));
        break;
      case RecommendationAction.repeatedMistakes:
        launchQuiz(
            context,
            defaultConfig(title: 'Repeated mistakes', selection: SelectionMode.mistakes, count: 20)
                .copyWith(mistakesLastOnly: true));
        break;
      case RecommendationAction.practiceBanks:
        launchQuiz(context,
            defaultConfig(title: 'Focused practice', selection: SelectionMode.quickReview, bankIds: r.bankIds, count: 15));
        break;
      case RecommendationAction.learnNew:
        launchQuiz(context, defaultConfig(title: 'New questions', selection: SelectionMode.newQuestions));
        break;
      case RecommendationAction.quickQuiz:
        launchQuiz(context, defaultConfig(title: 'Quick quiz', selection: SelectionMode.random, count: 10));
        break;
    }
  }
}

/// Used by other screens to colour a mastery percentage.
Color progressColor(BuildContext context, double f) =>
    masteryColor(f >= 0.8 ? MasteryLevel.mastered : f >= 0.5 ? MasteryLevel.wellLearned : MasteryLevel.learning,
        Theme.of(context).colorScheme);
