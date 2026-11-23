import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../app/services.dart';
import '../../data/stats_repository.dart';
import '../banks/node_editor.dart';
import '../common/reloadable.dart';
import '../common/widgets.dart';

class _GoalsData {
  _GoalsData(this.goals, this.unlocked);
  final List<GoalProgress> goals;
  final Map<String, DateTime> unlocked;
}

/// Daily study goals with today/week progress and streaks, plus achievements.
class GoalsTab extends StatelessWidget {
  const GoalsTab({super.key});

  Future<_GoalsData> _load() async {
    final s = AppServices.I.stats;
    return _GoalsData(await s.goalProgress(), await s.unlockedAchievements());
  }

  @override
  Widget build(BuildContext context) {
    final gamification = AppServices.I.settings.value.gamification;
    return Reloadable<_GoalsData>(
      load: _load,
      builder: (context, d, _) => ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          Readable(
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              SectionHeader('Daily goals',
                  padding: const EdgeInsets.fromLTRB(4, 4, 4, 8),
                  action: TextButton.icon(
                    onPressed: () => _addGoal(context),
                    icon: const Icon(Icons.add),
                    label: const Text('Add goal'),
                  )),
              if (d.goals.isEmpty)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      const Text('Set a small daily goal, such as answering 25 questions or studying English '
                          'for 20 minutes. The Home screen also uses your daily question goal from Settings.'),
                      const SizedBox(height: 12),
                      FilledButton(onPressed: () => _addGoal(context), child: const Text('Create a goal')),
                    ]),
                  ),
                ),
              for (final g in d.goals) _goalCard(context, g),
              if (gamification) ...[
                const SectionHeader('Achievements'),
                Card(
                  child: Column(children: [
                    for (final a in achievementDefs)
                      ListTile(
                        leading: Icon(
                          d.unlocked.containsKey(a.id) ? Icons.emoji_events : Icons.emoji_events_outlined,
                          color: d.unlocked.containsKey(a.id) ? Colors.amber.shade700 : Theme.of(context).disabledColor,
                        ),
                        title: Text(a.title),
                        subtitle: Text(d.unlocked.containsKey(a.id)
                            ? '${a.description} · ${DateFormat.yMMMd().format(d.unlocked[a.id]!)}'
                            : a.description),
                      ),
                  ]),
                ),
              ],
            ]),
          ),
        ],
      ),
    );
  }

  Widget _goalCard(BuildContext context, GoalProgress g) {
    final t = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              Expanded(child: Text(g.title, style: t.titleSmall)),
              PopupMenuButton<String>(
                onSelected: (v) async {
                  final svc = AppServices.I;
                  if (v == 'edit') {
                    final s = await promptText(context, title: 'Daily target', initial: '${g.goal.target}');
                    final n = int.tryParse(s ?? '');
                    if (n != null && n > 0) await svc.stats.updateGoalTarget(g.goal.id, n);
                  } else if (v == 'delete') {
                    await svc.stats.deleteGoal(g.goal.id);
                  }
                  svc.dataChanged();
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'edit', child: Text('Change target')),
                  PopupMenuItem(value: 'delete', child: Text('Delete goal')),
                ],
              ),
            ]),
            const SizedBox(height: 8),
            LabeledProgress(
              label: "Today's progress",
              value: g.todayFraction,
              trailing: '${g.today} / ${g.goal.target} (${(g.todayFraction * 100).round()}%)',
            ),
            const SizedBox(height: 10),
            LabeledProgress(
              label: 'This week (${g.daysMetThisWeek} days met)',
              value: g.weekFraction,
              trailing: '${g.week} / ${g.weekTarget}',
            ),
            const SizedBox(height: 8),
            Text('Current streak: ${g.currentStreak} days · Longest: ${g.longestStreak} days', style: t.bodySmall),
          ]),
        ),
      ),
    );
  }

  static Future<void> _addGoal(BuildContext context) async {
    var type = GoalType.questions;
    final target = TextEditingController(text: '25');
    String? categoryId;
    String? categoryName;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, setState) => AlertDialog(
          title: const Text('New daily goal'),
          content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            DropdownButtonFormField<GoalType>(
              initialValue: type,
              decoration: const InputDecoration(labelText: 'Goal'),
              items: [for (final g in GoalType.values) DropdownMenuItem(value: g, child: Text(g.label))],
              onChanged: (v) => setState(() {
                type = v ?? type;
                target.text = switch (type) {
                  GoalType.questions => '25',
                  GoalType.minutes => '20',
                  GoalType.reviews => '15',
                  GoalType.mastered => '10',
                };
              }),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: target,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(labelText: 'Per day (${type.unit})'),
            ),
            if (type != GoalType.mastered) ...[
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: () async {
                  final id = await pickCategory(c, title: 'Limit to a subject or category', allowRoot: true);
                  if (id == null) return;
                  final cat = id.isEmpty ? null : await AppServices.I.catalog.category(id);
                  setState(() {
                    categoryId = cat?.id;
                    categoryName = cat?.name;
                  });
                },
                icon: const Icon(Icons.filter_alt_outlined),
                label: Text(categoryName == null ? 'All subjects' : 'Only: $categoryName'),
              ),
            ],
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Add')),
          ],
        ),
      ),
    );
    final n = int.tryParse(target.text.trim());
    target.dispose();
    if (ok != true || n == null || n <= 0) return;
    await AppServices.I.stats.addGoal(type, n, categoryId: type == GoalType.mastered ? null : categoryId);
    AppServices.I.dataChanged();
  }
}
