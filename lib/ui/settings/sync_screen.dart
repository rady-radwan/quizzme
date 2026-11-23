import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../app/services.dart';
import '../../sync/sync_service.dart';
import '../common/widgets.dart';

/// Settings → Sync between devices (Google Drive).
class SyncScreen extends StatefulWidget {
  const SyncScreen({super.key});

  @override
  State<SyncScreen> createState() => _SyncScreenState();
}

class _SyncScreenState extends State<SyncScreen> {
  SyncService? get _sync => AppServices.I.sync;
  bool _working = false;

  Future<void> _connect() async {
    final sync = _sync!;
    setState(() => _working = true);
    try {
      final state = await sync.connect();
      if (!mounted) return;
      FirstSyncChoice? choice;
      switch (state) {
        case ConnectState.cloudEmpty:
          choice = FirstSyncChoice.useDevice;
        case ConnectState.deviceEmpty:
          choice = FirstSyncChoice.useCloud;
        case ConnectState.bothHaveData:
          choice = await _askFirstSync();
      }
      if (choice == null) {
        await sync.disconnect();
        return;
      }
      await sync.finishConnect(choice);
      if (mounted) showMessage(context, 'Sync is on. Your devices now share the same progress.');
    } catch (e) {
      if (mounted) showErrorDialog(context, 'Could not turn on sync', '$e');
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<FirstSyncChoice?> _askFirstSync() => showDialog<FirstSyncChoice>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('Your Google Drive already has Quiz me data'),
          content: const SingleChildScrollView(
            child: Text('This device also has data. What should happen?\n\n'
                '• Combine: keep everything from both. If you imported the same Excel file on both devices, '
                'its questions will appear twice.\n\n'
                '• Use Google Drive data: this device switches to the data from your other device. '
                'Data that exists only on this device is removed.\n\n'
                '• Use this device\'s data: your other devices switch to this device\'s data on their next sync.'),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c), child: const Text('Cancel')),
            TextButton(
                onPressed: () => Navigator.pop(c, FirstSyncChoice.useDevice),
                child: const Text("Use this device's data")),
            TextButton(
                onPressed: () => Navigator.pop(c, FirstSyncChoice.useCloud), child: const Text('Use Google Drive data')),
            FilledButton(onPressed: () => Navigator.pop(c, FirstSyncChoice.merge), child: const Text('Combine')),
          ],
        ),
      );

  Future<void> _disconnect() async {
    final sync = _sync!;
    final r = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Turn off sync on this device?'),
        content: const Text('Your data stays on this device. You can also delete the copy kept in Google Drive '
            '(your other devices keep their own data).'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(c, 'delete'), child: const Text('Turn off and delete Drive copy')),
          FilledButton(onPressed: () => Navigator.pop(c, 'off'), child: const Text('Turn off')),
        ],
      ),
    );
    if (r == null) return;
    setState(() => _working = true);
    try {
      await sync.disconnect(deleteCloudData: r == 'delete');
    } catch (e) {
      if (mounted) showErrorDialog(context, 'Could not turn off sync', '$e');
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _syncNow() async {
    try {
      await _sync!.syncNow(rethrowErrors: true);
      if (mounted) showMessage(context, 'Up to date');
    } catch (_) {
      // Shown on the screen.
    }
  }

  Future<void> _reauth() async {
    try {
      await _sync!.reauthenticate();
    } catch (e) {
      if (mounted) showErrorDialog(context, 'Sign-in failed', '$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final sync = _sync;
    return Scaffold(
      appBar: AppBar(title: const Text('Sync between devices')),
      body: sync == null
          ? const EmptyState(icon: Icons.cloud_off_outlined, title: 'Sync is not available')
          : ListenableBuilder(
              listenable: sync,
              builder: (context, _) => ListView(
                padding: const EdgeInsets.all(16),
                children: [Readable(child: _content(context, sync))],
              ),
            ),
    );
  }

  Widget _content(BuildContext context, SyncService sync) {
    final t = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final last = sync.lastSync;
    final lastText = last == null ? 'Not synced yet' : 'Last synced ${DateFormat.yMMMd().add_jm().format(last)}';
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Icon(sync.enabled ? Icons.cloud_done_outlined : Icons.cloud_outlined, size: 32, color: scheme.primary),
              const SizedBox(width: 12),
              Expanded(
                child: Text(sync.enabled ? 'Sync is on' : 'Use Quiz me on your phone and PC',
                    style: t.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
              ),
            ]),
            const SizedBox(height: 10),
            const Text('Your question banks, progress, review schedule, quiz history, bookmarks, notes and goals '
                'are kept in a private Quiz me folder in your Google Drive and updated on every device where you '
                'turn sync on. Sync runs automatically when the app opens, a few seconds after you change something, '
                'and every few minutes while the app is open. Appearance and other settings stay per device.'),
            const SizedBox(height: 6),
            Text('Quiz me can only see its own folder, not your other Drive files.',
                style: t.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
          ]),
        ),
      ),
      const SizedBox(height: 12),
      if (!sync.available)
        Card(
          child: ListTile(
            leading: const Icon(Icons.info_outline),
            title: const Text('Google sign-in is not set up in this version of the app'),
            subtitle: const Text('This build was made without the Google sign-in keys. Install a newer build.'),
          ),
        )
      else if (!sync.enabled)
        GradientButton(
          label: _working ? 'Connecting…' : 'Sign in with Google and turn on sync',
          icon: Icons.login,
          onPressed: _working ? null : _connect,
        )
      else ...[
        Card(
          child: Column(children: [
            ListTile(
              leading: const Icon(Icons.account_circle_outlined),
              title: Text(sync.email ?? 'Google account'),
              subtitle: const Text('Google Drive'),
            ),
            ListTile(
              leading: sync.busy
                  ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2.5))
                  : Icon(sync.error == null ? Icons.check_circle_outline : Icons.error_outline,
                      color: sync.error == null ? scheme.primary : scheme.error),
              title: Text(sync.busy ? 'Syncing…' : (sync.error == null ? 'Up to date' : 'Sync problem')),
              subtitle: Text(sync.error ?? lastText),
            ),
          ]),
        ),
        const SizedBox(height: 12),
        if (sync.needsSignIn)
          FilledButton.icon(onPressed: _reauth, icon: const Icon(Icons.login), label: const Text('Sign in again'))
        else
          FilledButton.icon(
            onPressed: sync.busy ? null : _syncNow,
            icon: const Icon(Icons.sync),
            label: const Text('Sync now'),
          ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: _working || sync.busy ? null : _disconnect,
          icon: const Icon(Icons.cloud_off_outlined),
          label: const Text('Turn off sync on this device'),
        ),
      ],
      const SizedBox(height: 16),
      Text('Tips', style: t.titleSmall),
      const SizedBox(height: 4),
      const Text('• Turn sync on first on the device that has your data, then on the other one '
          'and choose "Use Google Drive data" there.\n'
          '• If you answer questions on both devices while offline, both sets of answers are kept and '
          'the latest change to each question wins.\n'
          '• Backups (Settings → Backup & restore) still work and are a good extra safety net.'),
    ]);
  }
}
