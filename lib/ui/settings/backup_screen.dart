import 'dart:io';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../app/services.dart';
import '../../data/backup_service.dart';
import '../../data/db.dart';
import '../common/file_io.dart';
import '../common/reloadable.dart';
import '../common/widgets.dart';

class BackupScreen extends StatefulWidget {
  const BackupScreen({super.key});

  @override
  State<BackupScreen> createState() => _BackupScreenState();
}

class _BackupScreenState extends State<BackupScreen> {
  bool _busy = false;
  String _status = '';

  Future<void> _backup() async {
    setState(() {
      _busy = true;
      _status = 'Creating backup…';
    });
    try {
      final bytes = await AppServices.I.backups.create();
      final name = BackupService.suggestedFileName(DateTime.now());
      final ok = await saveBytes(name, bytes, title: 'Save backup');
      if (mounted) showMessage(context, ok ? 'Backup saved: $name' : 'Backup cancelled');
    } catch (e) {
      if (mounted) showErrorDialog(context, 'Backup failed', '$e');
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _status = '';
        });
      }
    }
  }

  Future<void> _restore() async {
    final svc = AppServices.I;
    final f = await pickFile(extensions: ['zip']);
    if (f == null || !mounted) return;
    BackupInfo info;
    try {
      info = svc.backups.inspect(f.bytes);
    } on BackupException catch (e) {
      showErrorDialog(context, 'Backup error', e.message);
      return;
    } catch (_) {
      showErrorDialog(context, 'Backup error', 'The selected backup could not be validated.');
      return;
    }
    final fmt = DateFormat.yMMMd().add_Hm();
    final c = info.counts;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Restore this backup?'),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Created: ${info.createdAt == null ? 'unknown' : fmt.format(info.createdAt!)}'),
            Text('App version: ${info.appVersion}'),
            const SizedBox(height: 8),
            Text('${c['categories'] ?? 0} subjects & categories'),
            Text('${c['banks'] ?? 0} question banks'),
            Text('${c['questions'] ?? 0} questions'),
            Text('${c['attempts'] ?? 0} answers in history'),
            Text('${c['sessions'] ?? 0} quizzes'),
            Text('${c['notes'] ?? 0} notes · ${c['bookmarks'] ?? 0} bookmarks'),
            Text('${info.mediaFiles} images and audio files'),
            const SizedBox(height: 12),
            const Text(
              'Restoring REPLACES all current data in Quiz me. A safety copy of your current data is saved '
              'automatically first.',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Continue')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final sure = await confirmTyped(context,
        title: 'Replace all data?',
        message: 'Your current questions and history will be replaced by the backup.',
        word: 'RESTORE');
    if (!sure) return;
    setState(() {
      _busy = true;
      _status = 'Saving a safety copy…';
    });
    try {
      final safety = await svc.backups.create();
      final dir = Directory(p.join((await getApplicationSupportDirectory()).path, 'safety-backups'));
      await dir.create(recursive: true);
      await File(p.join(dir.path, BackupService.suggestedFileName(DateTime.now()))).writeAsBytes(safety, flush: true);
      // Keep only the 3 most recent safety copies.
      final files = dir.listSync().whereType<File>().toList()
        ..sort((a, b) => b.statSync().modified.compareTo(a.statSync().modified));
      for (final old in files.skip(3)) {
        await old.delete();
      }
      setState(() => _status = 'Restoring…');
      await svc.backups.restore(f.bytes);
      await svc.settings.update(await svc.settingsRepo.load());
      svc.dataChanged();
      await svc.refreshReminders();
      if (mounted) showMessage(context, 'Backup restored');
    } on BackupException catch (e) {
      if (mounted) showErrorDialog(context, 'Restore failed', '${e.message}\nYour existing data was not changed.');
    } catch (e) {
      if (mounted) showErrorDialog(context, 'Restore failed', 'Your existing data was not changed.\n$e');
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _status = '';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_busy,
      child: Scaffold(
        appBar: AppBar(title: const Text('Backup & restore')),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Readable(
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                const Text('A backup is a single .zip file containing everything: subjects, banks, questions, '
                    'answers, explanations, images, audio, quiz history, statistics, mastery levels, review '
                    'schedules, bookmarks, notes, goals and settings. Keep it somewhere safe, such as cloud '
                    'storage or your computer.'),
                const SizedBox(height: 20),
                if (_busy) ...[
                  const LinearProgressIndicator(),
                  const SizedBox(height: 8),
                  Text(_status),
                  const SizedBox(height: 20),
                ],
                FilledButton.icon(
                  onPressed: _busy ? null : _backup,
                  icon: const Icon(Icons.backup_outlined),
                  label: const Text('Create backup'),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: _busy ? null : _restore,
                  icon: const Icon(Icons.settings_backup_restore),
                  label: const Text('Restore from backup'),
                ),
                const SizedBox(height: 20),
                Text('Backups use a versioned format, so they can be restored by future versions of the app.',
                    style: Theme.of(context).textTheme.bodySmall),
              ]),
            ),
          ],
        ),
      ),
    );
  }
}

/// Row counts of every table and the database file size.
class DatabaseInfoScreen extends StatelessWidget {
  const DatabaseInfoScreen({super.key});

  Future<(Map<String, int>, int, int)> _load() async {
    final db = AppServices.I.db;
    final counts = <String, int>{};
    for (final t in AppDatabase.tables) {
      final r = await db.rawQuery('SELECT COUNT(*) AS n FROM $t');
      counts[t] = intOf(r.first['n']);
    }
    var size = 0;
    try {
      size = await File(db.path).length();
    } catch (_) {}
    var media = 0;
    try {
      for (final f in (await AppServices.I.media.all()).values) {
        media += await f.length();
      }
    } catch (_) {}
    return (counts, size, media);
  }

  static String _mb(int bytes) => '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Database information')),
      body: Reloadable<(Map<String, int>, int, int)>(
        load: _load,
        builder: (context, d, _) {
          final (counts, size, media) = d;
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Card(
                child: Column(children: [
                  ListTile(title: const Text('Database size'), trailing: Text(_mb(size))),
                  ListTile(title: const Text('Media size'), trailing: Text(_mb(media))),
                  ListTile(title: const Text('Schema version'), trailing: Text('${AppDatabase.schemaVersion}')),
                ]),
              ),
              const SizedBox(height: 12),
              Card(
                child: Column(children: [
                  for (final e in counts.entries)
                    ListTile(dense: true, title: Text(e.key), trailing: Text('${e.value}')),
                ]),
              ),
            ],
          );
        },
      ),
    );
  }
}
