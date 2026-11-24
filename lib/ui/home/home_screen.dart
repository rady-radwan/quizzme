import 'package:flutter/material.dart';

import '../../app/services.dart';
import '../../app/theme.dart';
import '../../core/dates.dart';
import '../../core/models.dart';
import '../../data/sample_data.dart';
import '../../data/session_repository.dart';
import '../../data/stats_repository.dart';
import '../banks/category_screen.dart';
import '../common/desktop.dart';
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
    final width = MediaQuery.sizeOf(context).width;
    final wide = width >= 840 || (isDesktop && width >= 600);
    return Scaffold(
      // On wide screens the side menu already shows the logo.
      // Wide screens: the side menu shows the logo, the top bar greets.
      appBar: wide
          ? AppBar(
              toolbarHeight: 84,
              titleSpacing: 28,
              title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(_greeting(), style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800)),
                const SizedBox(height: 2),
                Opacity(
                  opacity: 0.75,
                  child: Text(_messages[DateTime.now().difference(DateTime(2024)).inDays % _messages.length],
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w400)),
                ),
              ]),
            )
          : AppBar(
              centerTitle: true,
              toolbarHeight: 60,
              title: const AppLogo(size: 36, useAmbientColor: true),
            ),
      body: SafeArea(
        top: false,
        child: Reloadable<_HomeData>(
          load: _load,
          builder: (context, d, reload) => RefreshIndicator(
            onRefresh: reload,
            child: ListView(
              padding: EdgeInsets.fromLTRB(wide ? 28 : 16, wide ? 16 : 12, wide ? 28 : 16, 32),
              children: [
                Readable(maxWidth: 1240, child: _content(context, d, wide)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static String _greeting() {
    final h = DateTime.now().hour;
    if (h < 5) return 'Good evening';
    if (h < 12) return 'Good morning';
    if (h < 17) return 'Good afternoon';
    return 'Good evening';
  }

  Widget _header(BuildContext context, _HomeData d, String msg) {
    final t = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    return Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(_greeting(), style: t.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 2),
          Text(msg, style: t.bodyMedium?.copyWith(color: scheme.onSurfaceVariant)),
        ]),
      ),
      if (d.dash.currentStreak > 0) _StreakBadge(days: d.dash.currentStreak),
    ]);
  }

  Widget _content(BuildContext context, _HomeData d, bool wide) {
    final svc = AppServices.I;
    final goal = svc.settings.value.dailyQuestionGoal;
    final today = d.dash.today.answered;
    final msg = _messages[DateTime.now().difference(DateTime(2024)).inDays % _messages.length];

    if (d.dash.totalQuestions == 0) {
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (!wide) ...[_header(context, d, msg), const SizedBox(height: 18)],
        _welcome(context),
      ]);
    }

    final main = <Widget>[
      _heroCard(context, today, goal, wide ? d.dash.currentStreak : 0),
      const SizedBox(height: 14),
      _statsRow(context, d.dash),
      if (d.active != null) ...[
        const SizedBox(height: 14),
        _continueCard(context, d.active!, d.activeAnswered),
      ],
      const SectionHeader('Quick actions'),
      _quickActions(context),
    ];
    final side = <Widget>[
      if (d.recs.isNotEmpty) ...[
        const SectionHeader('Suggestions'),
        for (final r in d.recs) _recTile(context, r),
      ],
      if (d.subjects.isNotEmpty) ...[
        SectionHeader('My subjects',
            action: TextButton(onPressed: () => HomeShell.of(context)?.select(2), child: const Text('All banks'))),
        for (final s in d.subjects) _subjectCard(context, s),
      ],
      if (d.last != null) ...[
        const SectionHeader('Recent activity'),
        _recentCard(context, d.last!),
      ],
    ];

    return LayoutBuilder(builder: (context, c) {
      if (c.maxWidth < 1000) {
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (!wide) ...[_header(context, d, msg), const SizedBox(height: 18)],
          ...main,
          ...side,
        ]);
      }
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(flex: 7, child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: main)),
          const SizedBox(width: 24),
          Expanded(
            flex: 5,
            child: Transform.translate(
              // Align the first section title with the top of the hero card.
              offset: const Offset(0, -24),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: side),
            ),
          ),
        ]),
      ]);
    });
  }
  Widget _welcome(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Center(
            child: Image.asset('assets/branding/logo.png', height: 150),
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

  /// Gradient hero: today's progress towards the daily goal.
  Widget _heroCard(BuildContext context, int today, int goal, int streak) {
    final scheme = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    final frac = goal <= 0 ? 1.0 : (today / goal).clamp(0.0, 1.0);
    final dark = scheme.brightness == Brightness.dark;
    final c1 = dark ? const Color(0xFF2F5BEA) : brandBlue;
    final c2 = dark ? const Color(0xFF6A3FD8) : const Color(0xFF5B3FD6);
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(26),
        gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [c1, c2]),
        boxShadow: [BoxShadow(color: c1.withValues(alpha: 0.35), blurRadius: 24, offset: const Offset(0, 10))],
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(children: [
        Positioned(right: -40, top: -50, child: _bubble(170, 0.10)),
        Positioned(right: 90, bottom: -70, child: _bubble(140, 0.08)),
        Positioned(left: -30, bottom: -40, child: _bubble(100, 0.06)),
        Padding(
          padding: const EdgeInsets.all(22),
          child: Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  const Icon(Icons.auto_graph_rounded, color: Colors.white70, size: 20),
                  const SizedBox(width: 6),
                  Text("Today's learning", style: t.labelLarge?.copyWith(color: Colors.white70)),
                  if (streak > 0) ...[
                    const SizedBox(width: 10),
                    _StreakBadge(days: streak, compact: true),
                  ],
                ]),
                const SizedBox(height: 10),
                Text.rich(
                  TextSpan(children: [
                    TextSpan(text: '$today', style: const TextStyle(fontSize: 40, fontWeight: FontWeight.w800)),
                    if (goal > 0)
                      TextSpan(
                          text: ' / $goal',
                          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w600, color: Colors.white70)),
                  ]),
                  style: const TextStyle(color: Colors.white, height: 1.1),
                ),
                Text(goal > 0 ? 'questions completed' : 'questions answered today',
                    style: t.bodyMedium?.copyWith(color: Colors.white70)),
                const SizedBox(height: 14),
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: LinearProgressIndicator(
                    value: frac,
                    minHeight: 10,
                    color: brandGold,
                    backgroundColor: Colors.white.withValues(alpha: 0.22),
                    semanticsLabel: 'Daily goal progress',
                    semanticsValue: '${(frac * 100).round()}',
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  goal <= 0
                      ? 'Keep going!'
                      : today >= goal
                          ? 'Daily goal reached — well done!'
                          : '${goal - today} more to reach your daily goal',
                  style: t.bodySmall?.copyWith(color: Colors.white.withValues(alpha: 0.9)),
                ),
              ]),
            ),
            const SizedBox(width: 18),
            _HeroRing(value: frac, label: '${(frac * 100).round()}%'),
          ]),
        ),
      ]),
    );
  }

  static Widget _bubble(double size, double alpha) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.white.withValues(alpha: alpha)),
      );

  /// Four colourful numbers; "Due today" carries the main call to action.
  Widget _statsRow(BuildContext context, DashboardStats s) {
    final dark = Theme.of(context).colorScheme.brightness == Brightness.dark;
    final blue = dark ? const Color(0xFF7FB0FF) : const Color(0xFF1E63E9);
    final orange = dark ? const Color(0xFFFFB067) : const Color(0xFFE8710A);
    final green = dark ? const Color(0xFF7BD88F) : const Color(0xFF1E9E4A);
    final purple = dark ? const Color(0xFFC4A7FF) : const Color(0xFF7048E8);
    void review() => launchQuiz(
        context,
        defaultConfig(
            title: 'Due reviews', selection: SelectionMode.spaced, count: s.dueToday > 100 ? 100 : s.dueToday));
    final tiles = [
      _MiniStat(
        icon: Icons.event_available_rounded,
        color: blue,
        value: '${s.dueToday}',
        label: 'Due today',
        action: s.dueToday == 0 ? null : 'Review now',
        onTap: s.dueToday == 0 ? null : review,
      ),
      _MiniStat(
        icon: Icons.warning_amber_rounded,
        color: orange,
        value: '${s.overdue}',
        label: 'Overdue',
        onTap: s.overdue == 0 ? null : review,
      ),
      _MiniStat(icon: Icons.workspace_premium_rounded, color: green, value: '${s.mastered}', label: 'Mastered'),
      _MiniStat(
        icon: Icons.track_changes_rounded,
        color: purple,
        value: s.accuracy == null ? '—' : '${(s.accuracy! * 100).round()}%',
        label: 'Accuracy',
      ),
    ];
    return LayoutBuilder(builder: (context, c) {
      final cols = c.maxWidth >= 560 ? 4 : 2;
      final w = (c.maxWidth - (cols - 1) * 12) / cols;
      return Wrap(spacing: 12, runSpacing: 12, children: [for (final t in tiles) SizedBox(width: w, child: t)]);
    });
  }
  Widget _continueCard(BuildContext context, QuizSession s, int answered) {
    final scheme = Theme.of(context).colorScheme;
    final frac = s.total == 0 ? 0.0 : answered / s.total;
    return Card(
      child: InkWell(
        onTap: () => openSession(context, s),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(children: [
            IconBadge(icon: Icons.play_arrow_rounded, color: scheme.primary, size: 48, filled: true),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Continue where you left off',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                Text('${s.title} · $answered of ${s.total} answered · started ${_ago(s.createdAt)}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
                const SizedBox(height: 8),
                GradientProgressBar(value: frac, height: 6),
              ]),
            ),
            const SizedBox(width: 8),
            Icon(Icons.chevron_right_rounded, color: scheme.onSurfaceVariant),
          ]),
        ),
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
    final dark = Theme.of(context).colorScheme.brightness == Brightness.dark;
    Color c(int light, int darkC) => Color(dark ? darkC : light);
    final actions = <(IconData, String, String, Color, VoidCallback)>[
      (
        Icons.play_arrow_rounded,
        'Start Quiz',
        'Build a custom quiz',
        c(0xFF1E63E9, 0xFF6EA2FF),
        () => HomeShell.of(context)?.select(1)
      ),
      (
        Icons.fiber_new_rounded,
        'New Questions',
        'Learn something new',
        c(0xFF0E9F6E, 0xFF5FD6A5),
        () => launchQuiz(context, defaultConfig(title: 'New questions', selection: SelectionMode.newQuestions))
      ),
      (
        Icons.error_outline_rounded,
        'Review Mistakes',
        'Fix what you missed',
        c(0xFFE03131, 0xFFFF8787),
        () => Navigator.push(context, MaterialPageRoute<void>(builder: (_) => const MistakesScreen()))
      ),
      (
        Icons.style_rounded,
        'Flashcards',
        'Flip and remember',
        c(0xFF7048E8, 0xFFB197FC),
        () => launchQuiz(context,
            defaultConfig(title: 'Flashcards', selection: SelectionMode.random, style: QuizStyle.flashcards, count: 20))
      ),
      (
        Icons.bolt_rounded,
        'Quick Review',
        '10 questions, fast',
        c(0xFFE8710A, 0xFFFFB067),
        () => launchQuiz(context, defaultConfig(title: 'Quick review', selection: SelectionMode.quickReview, count: 10))
      ),
      (
        Icons.library_books_rounded,
        'Question Banks',
        'Browse your library',
        c(0xFF0B8F9B, 0xFF66D9E8),
        () => HomeShell.of(context)?.select(2)
      ),
    ];
    return LayoutBuilder(builder: (context, cons) {
      final cols = cons.maxWidth > 520 ? 3 : 2;
      final w = (cons.maxWidth - (cols - 1) * 12) / cols;
      return Wrap(spacing: 12, runSpacing: 12, children: [
        for (final a in actions)
          SizedBox(
            width: w,
            child: _ActionTile(icon: a.$1, title: a.$2, subtitle: a.$3, color: a.$4, onTap: a.$5),
          ),
      ]);
    });
  }

  Widget _recTile(BuildContext context, Recommendation r) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Card(
        child: InkWell(
          onTap: () => _runRecommendation(context, r),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 10, 14),
            child: Row(children: [
              const IconBadge(icon: Icons.lightbulb_rounded, color: brandGold, size: 40),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(r.message),
                  const SizedBox(height: 4),
                  Text(r.actionLabel,
                      style: TextStyle(color: scheme.primary, fontWeight: FontWeight.w700, fontSize: 13)),
                ]),
              ),
              Icon(Icons.chevron_right_rounded, color: scheme.onSurfaceVariant),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _subjectCard(BuildContext context, SubjectProgress s) {
    final scheme = Theme.of(context).colorScheme;
    final pct = (s.masteredFraction * 100).round();
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Card(
        child: InkWell(
          onTap: () => Navigator.push(
              context, MaterialPageRoute<void>(builder: (_) => CategoryScreen(categoryId: s.subject.id))),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(children: [
              NodeAvatar(iconKey: s.subject.iconKey, color: s.subject.color, size: 44),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Expanded(
                      child: Text(s.subject.name,
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                    ),
                    Text('$pct%',
                        style: TextStyle(fontWeight: FontWeight.w800, color: progressColor(context, s.masteredFraction))),
                  ]),
                  const SizedBox(height: 2),
                  Text('${s.total} questions · $pct% mastered',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
                  const SizedBox(height: 8),
                  GradientProgressBar(value: s.masteredFraction, height: 6),
                ]),
              ),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _recentCard(BuildContext context, QuizSession last) {
    final scheme = Theme.of(context).colorScheme;
    final score = last.score?.round() ?? 0;
    final color = score >= 80 ? correctColor(scheme) : (score >= 50 ? brandGold : incorrectColor(scheme));
    return Card(
      child: InkWell(
        onTap: () =>
            Navigator.push(context, MaterialPageRoute<void>(builder: (_) => ResultsScreen(sessionId: last.id))),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(children: [
            ProgressRing(value: score / 100, label: '$score%', size: 48, color: color),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(last.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                Text('Last quiz · ${last.correct}/${last.total} correct',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
              ]),
            ),
            Icon(Icons.chevron_right_rounded, color: scheme.onSurfaceVariant),
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

class _StreakBadge extends StatelessWidget {
  const _StreakBadge({required this.days, this.compact = false});
  final int days;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Study streak',
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: compact ? 10 : 14, vertical: compact ? 4 : 8),
        decoration: BoxDecoration(
          gradient: const LinearGradient(colors: [Color(0xFFFF9A3C), Color(0xFFFF5F6D)]),
          borderRadius: BorderRadius.circular(30),
          boxShadow: [
            BoxShadow(color: const Color(0xFFFF7A00).withValues(alpha: 0.3), blurRadius: 12, offset: const Offset(0, 4))
          ],
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.local_fire_department_rounded, color: Colors.white, size: 20),
          const SizedBox(width: 6),
          Text('$days day${days == 1 ? '' : 's'}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
        ]),
      ),
    );
  }
}

/// White ring on the hero card.
class _HeroRing extends StatelessWidget {
  const _HeroRing({required this.value, required this.label});
  final double value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Daily goal $label',
      child: ExcludeSemantics(
        child: SizedBox(
          width: 108,
          height: 108,
          child: Stack(alignment: Alignment.center, children: [
            SizedBox(
              width: 108,
              height: 108,
              child: CircularProgressIndicator(
                value: value.clamp(0.0, 1.0),
                strokeWidth: 10,
                strokeCap: StrokeCap.round,
                color: Colors.white,
                backgroundColor: Colors.white.withValues(alpha: 0.2),
              ),
            ),
            Column(mainAxisSize: MainAxisSize.min, children: [
              Text(label, style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w800)),
              const Text('of goal', style: TextStyle(color: Colors.white70, fontSize: 12)),
            ]),
          ]),
        ),
      ),
    );
  }
}

class _MiniStat extends StatelessWidget {
  const _MiniStat({
    required this.icon,
    required this.color,
    required this.value,
    required this.label,
    this.action,
    this.onTap,
  });
  final IconData icon;
  final Color color;
  final String value;
  final String label;
  final String? action;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              IconBadge(icon: icon, color: color, size: 36),
              const Spacer(),
              if (action != null)
                Flexible(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration:
                        BoxDecoration(color: color.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(20)),
                    child: Text(action!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w700)),
                  ),
                ),
            ]),
            const SizedBox(height: 10),
            Text(value,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800, color: color)),
            Text(label, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
          ]),
        ),
      ),
    );
  }
}

class _ActionTile extends StatefulWidget {
  const _ActionTile(
      {required this.icon, required this.title, required this.subtitle, required this.color, required this.onTap});
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;

  @override
  State<_ActionTile> createState() => _ActionTileState();
}

class _ActionTileState extends State<_ActionTile> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: AnimatedScale(
        scale: _hover ? 1.02 : 1,
        duration: const Duration(milliseconds: 140),
        child: Card(
          child: InkWell(
            onTap: widget.onTap,
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                IconBadge(icon: widget.icon, color: widget.color, size: 44, filled: true),
                const SizedBox(height: 12),
                Text(widget.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                const SizedBox(height: 2),
                Text(widget.subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}
