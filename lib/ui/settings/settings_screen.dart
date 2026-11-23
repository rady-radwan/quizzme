import 'package:flutter/material.dart';

import '../../app/services.dart';
import '../../app/theme.dart';
import '../../core/models.dart';
import '../../data/settings_repository.dart';
import '../../services/notification_service.dart';
import '../banks/bank_tools.dart';
import '../banks/node_editor.dart';
import '../common/file_io.dart';
import '../common/widgets.dart';
import '../import/import_screen.dart';
import 'backup_screen.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final ctrl = AppServices.I.settings;
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListenableBuilder(
        listenable: ctrl,
        builder: (context, _) {
          final s = ctrl.value;
          void set(AppSettings n) => ctrl.update(n);
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 48),
            children: [
              Readable(
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  ..._appearance(context, s, set),
                  ..._quiz(context, s, set),
                  ..._learning(context, s, set),
                  ..._notifications(context, s, set),
                  ..._data(context),
                  ..._app(context, s, set),
                ]),
              ),
            ],
          );
        },
      ),
    );
  }

  // ---------------- Appearance ----------------

  List<Widget> _appearance(BuildContext context, AppSettings s, void Function(AppSettings) set) {
    final t = Theme.of(context).textTheme;
    return [
      const SectionHeader('Appearance'),
      Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text('Theme', style: t.labelLarge),
            const SizedBox(height: 8),
            Wrap(spacing: 6, runSpacing: 6, children: [
              for (final th in AppTheme.values)
                ChoiceChip(label: Text(th.label), selected: s.theme == th, onSelected: (_) => set(s.copyWith(theme: th))),
            ]),
            const SizedBox(height: 12),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Custom accent colour'),
              value: s.useCustomAccent,
              onChanged: (v) => set(s.copyWith(useCustomAccent: v)),
            ),
            if (s.useCustomAccent)
              Wrap(spacing: 8, runSpacing: 8, children: [
                for (final c in accentChoices)
                  Semantics(
                    button: true,
                    selected: s.accentColor == c,
                    label: 'Accent colour',
                    child: InkWell(
                      customBorder: const CircleBorder(),
                      onTap: () => set(s.copyWith(accentColor: c)),
                      child: Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: Color(c),
                          shape: BoxShape.circle,
                          border: Border.all(
                              color: s.accentColor == c ? Theme.of(context).colorScheme.onSurface : Colors.transparent,
                              width: 3),
                        ),
                      ),
                    ),
                  ),
              ]),
            const Divider(height: 28),
            Text('Font', style: t.labelLarge),
            const SizedBox(height: 6),
            SegmentedButton<AppFont>(
              showSelectedIcon: false,
              segments: [for (final f in AppFont.values) ButtonSegment(value: f, label: Text(f.label.split(' ').first))],
              selected: {s.font},
              onSelectionChanged: (v) => set(s.copyWith(font: v.first)),
            ),
            const SizedBox(height: 12),
            Text('Text size: ${(s.textScale * 100).round()}%', style: t.labelLarge),
            Slider(
              value: s.textScale,
              min: 0.8,
              max: 1.8,
              divisions: 10,
              label: '${(s.textScale * 100).round()}%',
              onChanged: (v) => set(s.copyWith(textScale: double.parse(v.toStringAsFixed(2)))),
            ),
            Text('Line spacing: ${s.lineHeight.toStringAsFixed(1)}', style: t.labelLarge),
            Slider(
              value: s.lineHeight,
              min: 1.2,
              max: 2.0,
              divisions: 8,
              label: s.lineHeight.toStringAsFixed(1),
              onChanged: (v) => set(s.copyWith(lineHeight: double.parse(v.toStringAsFixed(1)))),
            ),
            Card(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              child: const Padding(
                padding: EdgeInsets.all(12),
                child: Text('Preview: Which sentence is grammatically correct? He goes to work every day.\n'
                    'أي جملة صحيحة نحوياً؟ هو يذهب إلى العمل كل يوم.'),
              ),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('High contrast'),
              subtitle: const Text('Stronger colours and outlines'),
              value: s.highContrast,
              onChanged: (v) => set(s.copyWith(highContrast: v)),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Reduce motion'),
              subtitle: const Text('Turn off page and card animations'),
              value: s.reduceMotion,
              onChanged: (v) => set(s.copyWith(reduceMotion: v)),
            ),
            const SizedBox(height: 4),
            DropdownButtonFormField<LayoutDirectionPref>(
              initialValue: s.layoutDirection,
              decoration: const InputDecoration(labelText: 'Layout direction'),
              items: [
                for (final d in LayoutDirectionPref.values)
                  DropdownMenuItem(
                      value: d,
                      child: Text(d == LayoutDirectionPref.auto ? 'Automatic (follow device language)' : d.label)),
              ],
              onChanged: (v) => set(s.copyWith(layoutDirection: v)),
            ),
            const SizedBox(height: 4),
            Text('Arabic and other right-to-left questions are always displayed right-to-left.',
                style: t.bodySmall),
          ]),
        ),
      ),
    ];
  }

  // ---------------- Quiz ----------------

  List<Widget> _quiz(BuildContext context, AppSettings s, void Function(AppSettings) set) {
    final t = Theme.of(context).textTheme;
    return [
      const SectionHeader('Quiz preferences'),
      Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text('Default number of questions', style: t.labelLarge),
            const SizedBox(height: 6),
            Wrap(spacing: 6, children: [
              for (final n in const [5, 10, 25, 50, 100])
                ChoiceChip(
                    label: Text('$n'),
                    selected: s.defaultQuestionCount == n,
                    onSelected: (_) => set(s.copyWith(defaultQuestionCount: n))),
            ]),
            const SizedBox(height: 12),
            DropdownButtonFormField<SelectionMode>(
              initialValue: s.defaultSelection,
              decoration: const InputDecoration(labelText: 'Default quiz mode'),
              items: [for (final m in SelectionMode.values) DropdownMenuItem(value: m, child: Text(m.label))],
              onChanged: (v) => set(s.copyWith(defaultSelection: v)),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<FeedbackTiming>(
              initialValue: s.defaultFeedback,
              decoration: const InputDecoration(labelText: 'Show answers'),
              items: [for (final f in FeedbackTiming.values) DropdownMenuItem(value: f, child: Text(f.label))],
              onChanged: (v) => set(s.copyWith(defaultFeedback: v)),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Shuffle questions'),
              value: s.shuffleQuestions,
              onChanged: (v) => set(s.copyWith(shuffleQuestions: v)),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Shuffle answers'),
              value: s.shuffleAnswers,
              onChanged: (v) => set(s.copyWith(shuffleAnswers: v)),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Hints in practice mode'),
              value: s.hintsEnabled,
              onChanged: (v) => set(s.copyWith(hintsEnabled: v)),
            ),
            Text(s.timerMinutes == 0 ? 'Exam timer: off' : 'Exam timer: ${s.timerMinutes} minutes',
                style: t.labelLarge),
            Slider(
              value: s.timerMinutes.toDouble(),
              min: 0,
              max: 180,
              divisions: 36,
              label: s.timerMinutes == 0 ? 'Off' : '${s.timerMinutes} min',
              onChanged: (v) => set(s.copyWith(timerMinutes: v.round())),
            ),
          ]),
        ),
      ),
    ];
  }

  // ---------------- Learning ----------------

  List<Widget> _learning(BuildContext context, AppSettings s, void Function(AppSettings) set) {
    final t = Theme.of(context).textTheme;
    return [
      const SectionHeader('Learning preferences'),
      Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text('Daily question goal: ${s.dailyQuestionGoal == 0 ? 'off' : s.dailyQuestionGoal}', style: t.labelLarge),
            Slider(
              value: s.dailyQuestionGoal.clamp(0, 200).toDouble(),
              min: 0,
              max: 200,
              divisions: 40,
              label: '${s.dailyQuestionGoal}',
              onChanged: (v) => set(s.copyWith(dailyQuestionGoal: v.round())),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Confidence ratings'),
              subtitle: const Text('Rate Easy / Medium / Hard / Didn\'t know after answering'),
              value: s.confidenceRatings,
              onChanged: (v) => set(s.copyWith(confidenceRatings: v)),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Adaptive difficulty by default'),
              subtitle: const Text('Harder questions when you do well, easier ones when you struggle'),
              value: s.adaptiveDifficulty,
              onChanged: (v) => set(s.copyWith(adaptiveDifficulty: v)),
            ),
            const Divider(height: 28),
            Text('Spaced repetition', style: t.titleSmall),
            const SizedBox(height: 4),
            Text(
              'Quiz me uses an SM-2 based schedule. A wrong answer brings a question back tomorrow; each '
              'successful review multiplies the interval by the question\'s ease (about 2.5×), so reviews '
              'spread out to weeks, months and years. "Easy" grows faster, "Hard" slower.',
              style: t.bodySmall,
            ),
            const SizedBox(height: 8),
            _stepper(context, 'First review after', s.srsFirstInterval, 1, 7, 'day',
                (v) => set(s.copyWith(srsFirstInterval: v))),
            _stepper(context, 'Second review after', s.srsSecondInterval, 1, 14, 'day',
                (v) => set(s.copyWith(srsSecondInterval: v))),
            _stepper(context, 'Longest interval', s.srsMaxInterval ~/ 30, 1, 120, 'month',
                (v) => set(s.copyWith(srsMaxInterval: v * 30))),
            Text('"Easy" bonus: ×${s.srsEasyBonus.toStringAsFixed(2)}', style: t.bodyMedium),
            Slider(
              value: s.srsEasyBonus,
              min: 1.0,
              max: 2.0,
              divisions: 10,
              onChanged: (v) => set(s.copyWith(srsEasyBonus: double.parse(v.toStringAsFixed(2)))),
            ),
          ]),
        ),
      ),
    ];
  }

  static Widget _stepper(BuildContext context, String label, int value, int min, int max, String unit,
      void Function(int) onChanged) {
    return Row(children: [
      Expanded(child: Text('$label: $value $unit${value == 1 ? '' : 's'}')),
      IconButton(
          tooltip: 'Decrease',
          onPressed: value <= min ? null : () => onChanged(value - 1),
          icon: const Icon(Icons.remove)),
      IconButton(
          tooltip: 'Increase',
          onPressed: value >= max ? null : () => onChanged(value + 1),
          icon: const Icon(Icons.add)),
    ]);
  }

  // ---------------- Notifications ----------------

  List<Widget> _notifications(BuildContext context, AppSettings s, void Function(AppSettings) set) {
    final svc = AppServices.I;
    const dayNames = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    Future<void> apply(AppSettings n) async {
      set(n);
      await svc.refreshReminders();
    }

    return [
      const SectionHeader('Reminders'),
      Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            if (!NotificationService.supported)
              const Text('Reminders are available on Android and iOS.')
            else ...[
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Study reminders'),
                subtitle: const Text('At most one gentle reminder per day'),
                value: s.notificationsEnabled,
                onChanged: (v) async {
                  if (v) {
                    final granted = await svc.notifications.requestPermission();
                    if (!granted && context.mounted) {
                      showMessage(context, 'Notifications are not allowed for Quiz me in system settings.');
                    }
                  }
                  await apply(s.copyWith(notificationsEnabled: v));
                },
              ),
              if (s.notificationsEnabled) ...[
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.schedule),
                  title: const Text('Reminder time'),
                  trailing: Text(TimeOfDay(hour: s.reminderHour, minute: s.reminderMinute).format(context)),
                  onTap: () async {
                    final tod = await showTimePicker(
                        context: context, initialTime: TimeOfDay(hour: s.reminderHour, minute: s.reminderMinute));
                    if (tod != null) await apply(s.copyWith(reminderHour: tod.hour, reminderMinute: tod.minute));
                  },
                ),
                const Text('Days'),
                const SizedBox(height: 6),
                Wrap(spacing: 6, runSpacing: 6, children: [
                  for (var d = 1; d <= 7; d++)
                    FilterChip(
                      label: Text(dayNames[d - 1]),
                      selected: s.reminderDays.contains(d),
                      onSelected: (v) {
                        final days = [...s.reminderDays];
                        v ? days.add(d) : days.remove(d);
                        days.sort();
                        apply(s.copyWith(reminderDays: days));
                      },
                    ),
                ]),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Remind me about due reviews'),
                  value: s.dueReminders,
                  onChanged: (v) => apply(s.copyWith(dueReminders: v)),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Remind me about my daily goal'),
                  value: s.goalReminders,
                  onChanged: (v) => apply(s.copyWith(goalReminders: v)),
                ),
              ],
            ],
          ]),
        ),
      ),
    ];
  }

  // ---------------- Data ----------------

  List<Widget> _data(BuildContext context) {
    final svc = AppServices.I;
    return [
      const SectionHeader('Data management'),
      Card(
        child: Column(children: [
          ListTile(
            leading: const Icon(Icons.upload_file),
            title: const Text('Import questions'),
            onTap: () => Navigator.push(context, MaterialPageRoute<void>(builder: (_) => const ImportScreen())),
          ),
          ListTile(
            leading: const Icon(Icons.download_outlined),
            title: const Text('Export a question bank to Excel'),
            onTap: () async {
              final id = await pickBank(context, title: 'Export which bank?');
              if (id == null) return;
              try {
                final f = await svc.exports.exportBank(id);
                final ok = await saveBytes(f.fileName, f.bytes, title: 'Export question bank');
                if (ok && context.mounted) showMessage(context, 'Exported ${f.fileName}');
              } catch (e) {
                if (context.mounted) showErrorDialog(context, 'Export failed', '$e');
              }
            },
          ),
          ListTile(
            leading: const Icon(Icons.backup_outlined),
            title: const Text('Backup & restore'),
            subtitle: const Text('Everything: questions, media, history, schedules, notes, settings'),
            onTap: () => Navigator.push(context, MaterialPageRoute<void>(builder: (_) => const BackupScreen())),
          ),
          ListTile(
            leading: const Icon(Icons.history),
            title: const Text('Import history'),
            onTap: () =>
                Navigator.push(context, MaterialPageRoute<void>(builder: (_) => const ImportHistoryScreen())),
          ),
          ListTile(
            leading: const Icon(Icons.storage_outlined),
            title: const Text('Database information'),
            onTap: () => Navigator.push(context, MaterialPageRoute<void>(builder: (_) => const DatabaseInfoScreen())),
          ),
          ListTile(
            leading: const Icon(Icons.restart_alt),
            title: const Text('Reset new-question history'),
            subtitle: const Text('All questions count as new again; statistics are kept'),
            onTap: () async {
              final ok = await confirm(context,
                  title: 'Reset new-question history?',
                  message: 'Every question will be eligible for Learn New Questions mode again. Your answer '
                      'history, statistics and review schedules are kept.',
                  confirmLabel: 'Reset');
              if (!ok) return;
              final banks = (await svc.catalog.allBanks()).map((b) => b.id).toList();
              await svc.study.resetNewProgress(banks);
              svc.dataChanged();
              if (context.mounted) showMessage(context, 'New-question history reset');
            },
          ),
          ListTile(
            leading: Icon(Icons.delete_sweep_outlined, color: Theme.of(context).colorScheme.error),
            title: const Text('Clear all learning progress'),
            subtitle: const Text('Erase answers, schedules and mastery; keep questions'),
            onTap: () async {
              final ok = await confirmTyped(context,
                  title: 'Clear all learning progress?',
                  message: 'This permanently erases your answer history, review schedules, mastery levels and '
                      'statistics for every question. Questions, notes and bookmarks are kept. Make a backup first '
                      'if you might want them back.',
                  word: 'CLEAR');
              if (!ok) return;
              await svc.study.clearLearningProgress(null);
              svc.dataChanged();
              if (context.mounted) showMessage(context, 'Learning progress cleared');
            },
          ),
        ]),
      ),
    ];
  }

  // ---------------- App ----------------

  List<Widget> _app(BuildContext context, AppSettings s, void Function(AppSettings) set) {
    final svc = AppServices.I;
    return [
      const SectionHeader('Application'),
      Card(
        child: Column(children: [
          SwitchListTile(
            title: const Text('Achievements'),
            subtitle: const Text('Subtle badges for milestones'),
            value: s.gamification,
            onChanged: (v) => set(s.copyWith(gamification: v)),
          ),
          ListTile(
            leading: const Icon(Icons.record_voice_over_outlined),
            title: const Text('Read-aloud speed'),
            subtitle: Slider(
              value: s.ttsRate,
              min: 0.2,
              max: 1.0,
              divisions: 8,
              onChanged: (v) => set(s.copyWith(ttsRate: double.parse(v.toStringAsFixed(1)))),
            ),
            trailing: IconButton(
              tooltip: 'Test',
              icon: const Icon(Icons.play_arrow),
              onPressed: () => svc.speech.speak('He goes to work every day.'),
            ),
          ),
          const ListTile(leading: Icon(Icons.info_outline), title: Text('Version'), trailing: Text(appVersion)),
          ListTile(
            leading: const Icon(Icons.article_outlined),
            title: const Text('About Quiz me'),
            onTap: () => showAboutDialog(
              context: context,
              applicationName: 'Quiz me',
              applicationVersion: appVersion,
              applicationLegalese: 'Personal learning, quiz and knowledge-retention app.',
              children: const [
                SizedBox(height: 12),
                Text('Learn with quizzes and flashcards, review efficiently with spaced repetition, '
                    'and remember what you learn for years.'),
              ],
            ),
          ),
          ListTile(
            leading: const Icon(Icons.privacy_tip_outlined),
            title: const Text('Privacy'),
            onTap: () => showErrorDialog(
              context,
              'Privacy',
              'Quiz me stores all of your questions, answers, notes and statistics only on this device. '
                  'It has no account, no analytics, no advertising and does not send your data anywhere. '
                  'Files leave the device only when you export or back up and choose where to save them. '
                  'Text-to-speech uses your device\'s own speech engine.',
            ),
          ),
        ]),
      ),
    ];
  }
}
