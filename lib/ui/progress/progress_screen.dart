import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../app/services.dart';
import '../../app/theme.dart';
import '../../core/dates.dart';
import '../../core/models.dart';
import '../../data/stats_repository.dart';
import '../common/charts.dart';
import '../common/reloadable.dart';
import '../common/widgets.dart';
import '../quiz/history_screen.dart';
import '../quiz/quiz_launcher.dart';
import 'goals_screen.dart';

class ProgressScreen extends StatelessWidget {
  const ProgressScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 4,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Progress'),
          actions: [
            IconButton(
              tooltip: 'Quiz history',
              icon: const Icon(Icons.history),
              onPressed: () =>
                  Navigator.push(context, MaterialPageRoute<void>(builder: (_) => const HistoryScreen())),
            ),
          ],
          bottom: const TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: [
              Tab(text: 'Overview'),
              Tab(text: 'Activity'),
              Tab(text: 'Topics'),
              Tab(text: 'Goals'),
            ],
          ),
        ),
        body: const TabBarView(children: [_Overview(), _Activity(), _Topics(), GoalsTab()]),
      ),
    );
  }
}

// ---------------------------------------------------------------------------

class _OverviewData {
  _OverviewData(this.dash, this.stats, this.upcoming, this.heat);
  final DashboardStats dash;
  final LearningStats stats;
  final List<int> upcoming;
  final Map<String, int> heat;
}

class _Overview extends StatelessWidget {
  const _Overview();

  Future<_OverviewData> _load() async {
    final s = AppServices.I.stats;
    final now = DateTime.now();
    final days = await s.dailyActivity(addDays(now, -7 * 26), now);
    return _OverviewData(
      await s.dashboard(),
      await s.statsFor(null),
      await s.upcomingReviews(days: 14),
      {for (final d in days) dayKey(d.day): d.answered},
    );
  }

  @override
  Widget build(BuildContext context) {
    return Reloadable<_OverviewData>(
      load: _load,
      builder: (context, d, reload) {
        final s = d.dash;
        final scheme = Theme.of(context).colorScheme;
        final fmt = DateFormat.E();
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
          children: [
            Readable(
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                StatGrid(children: [
                  StatTile(label: 'Total questions', value: '${s.totalQuestions}', icon: Icons.quiz_outlined),
                  StatTile(label: 'Unique questions attempted', value: '${s.uniqueAttempted}', icon: Icons.done),
                  StatTile(label: 'Total answers', value: '${s.totalAttempts}', icon: Icons.done_all),
                  StatTile(
                      label: 'Mastered',
                      value: '${s.mastered}',
                      icon: Icons.workspace_premium,
                      color: masteryColor(MasteryLevel.mastered, scheme)),
                  StatTile(label: 'Needing review', value: '${s.needsReview}', icon: Icons.replay),
                  StatTile(label: 'Average accuracy', value: percent(s.accuracy), icon: Icons.track_changes),
                  StatTile(
                      label: 'Total study time',
                      value: formatDuration(Duration(milliseconds: s.studyMs)),
                      icon: Icons.timer_outlined),
                  StatTile(label: 'Completed quizzes', value: '${s.completedQuizzes}', icon: Icons.flag_outlined),
                  StatTile(
                      label: 'Current streak (longest ${s.longestStreak})',
                      value: '${s.currentStreak} days',
                      icon: Icons.local_fire_department_outlined),
                ]),
                const SectionHeader('Revision'),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      Row(children: [
                        Expanded(child: _big(context, 'Due today', s.dueToday)),
                        Expanded(child: _big(context, 'Overdue', s.overdue)),
                        Expanded(child: _big(context, 'Tomorrow', s.dueTomorrow)),
                        Expanded(child: _big(context, 'Next 7 days', s.dueThisWeek)),
                      ]),
                      const SizedBox(height: 16),
                      Text('Upcoming reviews', style: Theme.of(context).textTheme.labelLarge),
                      const SizedBox(height: 8),
                      BarChart(
                        height: 120,
                        labelEvery: 2,
                        data: [
                          for (var i = 0; i < d.upcoming.length; i++)
                            BarDatum(fmt.format(addDays(DateTime.now(), i + 1)).substring(0, 2),
                                d.upcoming[i].toDouble())
                        ],
                      ),
                      const SizedBox(height: 12),
                      FilledButton.icon(
                        onPressed: s.dueToday == 0
                            ? null
                            : () => launchQuiz(
                                context,
                                defaultConfig(
                                    title: 'Due reviews',
                                    selection: SelectionMode.spaced,
                                    count: math.min(100, s.dueToday))),
                        icon: const Icon(Icons.event_repeat),
                        label: const Text('Review due questions'),
                      ),
                    ]),
                  ),
                ),
                const SectionHeader('Mastery'),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      MasteryBar(byLevel: d.stats.byLevel, height: 16),
                      const SizedBox(height: 10),
                      MasteryLegend(byLevel: d.stats.byLevel),
                      const SizedBox(height: 10),
                      Text(
                        'Mastered = recalled correctly at least 4 times in a row with a review interval of '
                        '3+ weeks and 80%+ accuracy. Levels drop when reviews become overdue.',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ]),
                  ),
                ),
                const SectionHeader('Study calendar'),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: ActivityHeatmap(
                      counts: d.heat,
                      end: DateTime.now(),
                      weeks: 26,
                      onTapDay: (day, n) =>
                          showMessage(context, '${DateFormat.yMMMEd().format(day)}: $n questions'),
                    ),
                  ),
                ),
              ]),
            ),
          ],
        );
      },
    );
  }

  static Widget _big(BuildContext context, String label, int v) => Column(children: [
        Text('$v', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
        Text(label, textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodySmall),
      ]);
}

// ---------------------------------------------------------------------------

enum _Range { daily, weekly, monthly }

class _Activity extends StatefulWidget {
  const _Activity();
  @override
  State<_Activity> createState() => _ActivityState();
}

class _ActivityState extends State<_Activity> {
  _Range _range = _Range.daily;

  Future<List<DayActivity>> _load() {
    final now = DateTime.now();
    final from = switch (_range) {
      _Range.daily => addDays(now, -29),
      _Range.weekly => addDays(startOfWeek(now), -7 * 11),
      _Range.monthly => DateTime(now.year, now.month - 11, 1),
    };
    return AppServices.I.stats.dailyActivity(from, now);
  }

  /// Buckets days into the selected range.
  List<(String, List<DayActivity>)> _buckets(List<DayActivity> days) {
    final out = <(String, List<DayActivity>)>[];
    switch (_range) {
      case _Range.daily:
        for (final d in days) {
          out.add((DateFormat.d().format(d.day), [d]));
        }
        break;
      case _Range.weekly:
        final map = <String, List<DayActivity>>{};
        for (final d in days) {
          map.putIfAbsent(dayKey(startOfWeek(d.day)), () => []).add(d);
        }
        for (final e in map.entries) {
          out.add((DateFormat.Md().format(parseDayKey(e.key)), e.value));
        }
        break;
      case _Range.monthly:
        final map = <String, List<DayActivity>>{};
        for (final d in days) {
          map.putIfAbsent('${d.day.year}-${d.day.month}', () => []).add(d);
        }
        for (final e in map.entries) {
          out.add((DateFormat.MMM().format(e.value.first.day), e.value));
        }
        break;
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    return Reloadable<List<DayActivity>>(
      key: ValueKey(_range),
      load: _load,
      builder: (context, days, _) {
        final scheme = Theme.of(context).colorScheme;
        final b = _buckets(days);
        int sum(List<DayActivity> l, int Function(DayActivity) f) => l.fold(0, (a, x) => a + f(x));
        final labelEvery = _range == _Range.daily ? 5 : 2;
        final totalAnswered = sum(days, (d) => d.answered);
        final activeDays = days.where((d) => d.answered > 0).length;
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
          children: [
            Readable(
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                SegmentedButton<_Range>(
                  showSelectedIcon: false,
                  segments: const [
                    ButtonSegment(value: _Range.daily, label: Text('30 days')),
                    ButtonSegment(value: _Range.weekly, label: Text('12 weeks')),
                    ButtonSegment(value: _Range.monthly, label: Text('12 months')),
                  ],
                  selected: {_range},
                  onSelectionChanged: (s) => setState(() => _range = s.first),
                ),
                const SizedBox(height: 12),
                Text('$totalAnswered questions answered · studied on $activeDays of ${days.length} days',
                    style: Theme.of(context).textTheme.bodySmall),
                _chartCard(
                  context,
                  'Correct vs incorrect answers',
                  BarChart(
                    labelEvery: labelEvery,
                    color: correctColor(scheme),
                    secondaryColor: incorrectColor(scheme),
                    data: [
                      for (final x in b)
                        BarDatum(x.$1, sum(x.$2, (d) => d.correct).toDouble(),
                            secondary: sum(x.$2, (d) => d.incorrect).toDouble())
                    ],
                  ),
                  legend: 'Green = correct, red = incorrect',
                ),
                _chartCard(
                  context,
                  'Accuracy over time',
                  LineChart(
                    labels: [for (final x in b) x.$1],
                    values: [
                      for (final x in b)
                        sum(x.$2, (d) => d.answered) == 0
                            ? null
                            : sum(x.$2, (d) => d.correct) / sum(x.$2, (d) => d.answered)
                    ],
                  ),
                ),
                _chartCard(
                  context,
                  'Study time (minutes)',
                  BarChart(
                    labelEvery: labelEvery,
                    color: scheme.tertiary,
                    data: [
                      for (final x in b) BarDatum(x.$1, (sum(x.$2, (d) => d.studyMs) / 60000).roundToDouble())
                    ],
                  ),
                ),
                _chartCard(
                  context,
                  'Spaced repetition reviews',
                  BarChart(
                    labelEvery: labelEvery,
                    color: scheme.secondary,
                    data: [for (final x in b) BarDatum(x.$1, sum(x.$2, (d) => d.reviews).toDouble())],
                  ),
                ),
                _chartCard(
                  context,
                  'Questions mastered',
                  BarChart(
                    labelEvery: labelEvery,
                    color: masteryColor(MasteryLevel.mastered, scheme),
                    data: [for (final x in b) BarDatum(x.$1, sum(x.$2, (d) => d.masteredNew).toDouble())],
                  ),
                ),
              ]),
            ),
          ],
        );
      },
    );
  }

  static Widget _chartCard(BuildContext context, String title, Widget chart, {String? legend}) => Padding(
        padding: const EdgeInsets.only(top: 12),
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: Theme.of(context).textTheme.labelLarge),
              const SizedBox(height: 12),
              chart,
              if (legend != null) ...[
                const SizedBox(height: 6),
                Text(legend, style: Theme.of(context).textTheme.bodySmall),
              ],
            ]),
          ),
        ),
      );
}

// ---------------------------------------------------------------------------

class _TopicsData {
  _TopicsData(this.weak, this.subjects, this.answered30);
  final List<WeakTopic> weak;
  final List<SubjectProgress> subjects;
  final Map<String, int> answered30;
}

class _Topics extends StatelessWidget {
  const _Topics();

  Future<_TopicsData> _load() async {
    final s = AppServices.I.stats;
    final now = DateTime.now();
    return _TopicsData(await s.weakTopics(limit: 8), await s.subjectProgress(),
        await s.answeredBySubject(addDays(now, -29), now));
  }

  @override
  Widget build(BuildContext context) {
    return Reloadable<_TopicsData>(
      load: _load,
      builder: (context, d, _) {
        final scheme = Theme.of(context).colorScheme;
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
          children: [
            Readable(
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                const SectionHeader('Weakest topics', padding: EdgeInsets.fromLTRB(4, 4, 4, 8)),
                if (d.weak.isEmpty)
                  const Card(
                    child: Padding(
                      padding: EdgeInsets.all(16),
                      child: Text('No weak topics yet. Topics appear here once you have answered at least '
                          '5 questions in a bank with less than 85% accuracy.'),
                    ),
                  )
                else ...[
                  Card(
                    child: Column(children: [
                      for (final w in d.weak)
                        ListTile(
                          title: Text(w.bankName),
                          subtitle: Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: LabeledProgress(
                              label: '${w.correct + w.incorrect} answers',
                              value: w.accuracy,
                              trailing: '${(w.accuracy * 100).round()}% accuracy',
                              color: w.accuracy < 0.6 ? incorrectColor(scheme) : null,
                            ),
                          ),
                        ),
                    ]),
                  ),
                  const SizedBox(height: 10),
                  FilledButton.icon(
                    onPressed: () => launchQuiz(
                      context,
                      defaultConfig(
                        title: 'Weak topics',
                        selection: SelectionMode.quickReview,
                        bankIds: d.weak.take(3).map((w) => w.bankId).toList(),
                        count: 20,
                      ),
                    ),
                    icon: const Icon(Icons.fitness_center),
                    label: const Text('Practice my weak topics'),
                  ),
                ],
                const SectionHeader('Subjects'),
                if (d.subjects.isEmpty)
                  const Card(child: Padding(padding: EdgeInsets.all(16), child: Text('No subjects yet.')))
                else
                  Card(
                    child: Column(children: [
                      for (final s in d.subjects)
                        ListTile(
                          leading: NodeAvatar(iconKey: s.subject.iconKey, color: s.subject.color, size: 36),
                          title: Text(s.subject.name),
                          subtitle: Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: LabeledProgress(
                              label: '${s.mastered} of ${s.total} mastered · ${s.attempted} attempted',
                              value: s.masteredFraction,
                            ),
                          ),
                        ),
                    ]),
                  ),
                if (d.answered30.isNotEmpty) ...[
                  const SectionHeader('Questions answered per subject (30 days)'),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: BarChart(
                        data: [
                          for (final e in d.answered30.entries)
                            BarDatum(e.key.length > 8 ? '${e.key.substring(0, 7)}…' : e.key, e.value.toDouble())
                        ],
                      ),
                    ),
                  ),
                ],
              ]),
            ),
          ],
        );
      },
    );
  }
}
