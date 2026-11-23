import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../app/services.dart';
import '../../sync/sync_service.dart';
import '../common/widgets.dart';

/// Settings → Account & sync: Quiz me account (email + password) and sync
/// between the user's devices.
class SyncScreen extends StatefulWidget {
  const SyncScreen({super.key});

  @override
  State<SyncScreen> createState() => _SyncScreenState();
}

class _SyncScreenState extends State<SyncScreen> {
  SyncService? get _sync => AppServices.I.sync;
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _creating = false;
  bool _working = false;
  bool _showPassword = false;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final sync = _sync!;
    setState(() => _working = true);
    try {
      final state = _creating
          ? await sync.createAccount(_email.text, _password.text)
          : await sync.signIn(_email.text, _password.text);
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
        await sync.signOut();
        return;
      }
      await sync.finishConnect(choice);
      _password.clear();
      if (mounted) {
        showMessage(context, _creating ? 'Account created. Sync is on.' : 'Signed in. Sync is on.');
      }
    } catch (e) {
      if (mounted) showErrorDialog(context, _creating ? 'Could not create the account' : 'Could not sign in', '$e');
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _forgotPassword() async {
    final email = _email.text.trim();
    if (!email.contains('@')) {
      showMessage(context, 'Enter your email address first.');
      return;
    }
    try {
      await _sync!.sendPasswordReset(email);
      if (mounted) showMessage(context, 'If $email has an account, a password reset email is on its way.');
    } catch (e) {
      if (mounted) showErrorDialog(context, 'Could not send the email', '$e');
    }
  }

  Future<FirstSyncChoice?> _askFirstSync() => showDialog<FirstSyncChoice>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('Your account already has data'),
          content: const SingleChildScrollView(
            child: Text('This device also has data. What should happen?\n\n'
                '• Combine: keep everything from both. If you imported the same Excel file on both devices, '
                'its questions will appear twice.\n\n'
                '• Use my account\'s data: this device switches to the data in your account. '
                'Data that exists only on this device is removed.\n\n'
                '• Use this device\'s data: your account, and your other devices on their next sync, '
                'switch to this device\'s data.'),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c), child: const Text('Cancel')),
            TextButton(
                onPressed: () => Navigator.pop(c, FirstSyncChoice.useDevice),
                child: const Text("Use this device's data")),
            TextButton(
                onPressed: () => Navigator.pop(c, FirstSyncChoice.useCloud), child: const Text("Use my account's data")),
            FilledButton(onPressed: () => Navigator.pop(c, FirstSyncChoice.merge), child: const Text('Combine')),
          ],
        ),
      );

  Future<void> _signOut() async {
    final ok = await confirm(context,
        title: 'Sign out on this device?',
        message: 'Sync stops on this device. Your data stays on this device and in your account.',
        confirmLabel: 'Sign out');
    if (!ok) return;
    await _sync!.signOut();
  }

  Future<void> _deleteAccount() async {
    final ok = await confirmTyped(context,
        title: 'Delete your Quiz me account?',
        message: 'This permanently deletes your account and all data stored in it. '
            'Data on this device is kept.',
        word: 'DELETE');
    if (!ok || !mounted) return;
    setState(() => _working = true);
    try {
      await _sync!.deleteAccount();
      if (mounted) showMessage(context, 'Your account was deleted.');
    } catch (e) {
      if (mounted) showErrorDialog(context, 'Could not delete the account', '$e');
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _signInAgain() async {
    final ctrl = TextEditingController();
    final pw = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Sign in again'),
        content: TextField(
          controller: ctrl,
          obscureText: true,
          autofocus: true,
          decoration: InputDecoration(labelText: 'Password for ${_sync!.email ?? 'your account'}'),
          onSubmitted: (v) => Navigator.pop(c, v),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(c, ctrl.text), child: const Text('Sign in')),
        ],
      ),
    );
    ctrl.dispose();
    if (pw == null || pw.isEmpty) return;
    try {
      await _sync!.signInAgain(pw);
    } catch (e) {
      if (mounted) showErrorDialog(context, 'Could not sign in', '$e');
    }
  }

  Future<void> _syncNow() async {
    try {
      await _sync!.syncNow(rethrowErrors: true, includeMedia: true);
      if (mounted) showMessage(context, 'Up to date');
    } catch (_) {
      // Shown on the screen.
    }
  }

  @override
  Widget build(BuildContext context) {
    final sync = _sync;
    return Scaffold(
      appBar: AppBar(title: const Text('Account & sync')),
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
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Icon(sync.enabled ? Icons.cloud_done_outlined : Icons.cloud_outlined, size: 32, color: scheme.primary),
              const SizedBox(width: 12),
              Expanded(
                child: Text(sync.enabled ? 'Sync is on' : 'Your learning on every device',
                    style: t.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
              ),
            ]),
            const SizedBox(height: 10),
            const Text('Sign in with the same account on your phone and PC and your question banks, progress, '
                'review schedule, quiz history, bookmarks, notes and goals stay the same everywhere. '
                'Sync runs when the app opens, shortly after you change something and every few minutes. '
                'Appearance and other settings stay per device. An account is optional — '
                'Quiz me keeps working offline without one.'),
            const SizedBox(height: 6),
            Text('Your data is private to your account.', style: t.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
          ]),
        ),
      ),
      const SizedBox(height: 12),
      if (!sync.available)
        const Card(
          child: ListTile(
            leading: Icon(Icons.info_outline),
            title: Text('Accounts are not set up in this version of the app'),
            subtitle: Text('This build was made without the cloud settings. Install a newer build.'),
          ),
        )
      else if (!sync.enabled)
        _signInForm(context)
      else
        _statusCard(context, sync),
    ]);
  }

  Widget _signInForm(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: AutofillGroup(
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(value: false, label: Text('Sign in'), icon: Icon(Icons.login)),
                  ButtonSegment(value: true, label: Text('Create account'), icon: Icon(Icons.person_add_alt)),
                ],
                selected: {_creating},
                onSelectionChanged: (s) => setState(() => _creating = s.first),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                autofillHints: const [AutofillHints.email],
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(labelText: 'Email', prefixIcon: Icon(Icons.mail_outline)),
                validator: (v) => (v ?? '').trim().contains('@') ? null : 'Enter a valid email address',
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _password,
                obscureText: !_showPassword,
                autofillHints: [_creating ? AutofillHints.newPassword : AutofillHints.password],
                textInputAction: TextInputAction.done,
                onFieldSubmitted: (_) => _working ? null : _submit(),
                decoration: InputDecoration(
                  labelText: 'Password',
                  helperText: _creating ? 'At least 6 characters' : null,
                  prefixIcon: const Icon(Icons.lock_outline),
                  suffixIcon: IconButton(
                    tooltip: _showPassword ? 'Hide password' : 'Show password',
                    icon: Icon(_showPassword ? Icons.visibility_off : Icons.visibility),
                    onPressed: () => setState(() => _showPassword = !_showPassword),
                  ),
                ),
                validator: (v) => (v ?? '').length >= 6 ? null : 'At least 6 characters',
              ),
              const SizedBox(height: 16),
              GradientButton(
                label: _working ? 'Please wait…' : (_creating ? 'Create account' : 'Sign in'),
                icon: _creating ? Icons.person_add_alt : Icons.login,
                onPressed: _working ? null : _submit,
              ),
              if (!_creating)
                Align(
                  alignment: Alignment.center,
                  child: TextButton(onPressed: _working ? null : _forgotPassword, child: const Text('Forgot password?')),
                ),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _statusCard(BuildContext context, SyncService sync) {
    final scheme = Theme.of(context).colorScheme;
    final last = sync.lastSync;
    final lastText = last == null ? 'Not synced yet' : 'Last synced ${DateFormat.yMMMd().add_jm().format(last)}';
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Card(
        child: Column(children: [
          ListTile(
            leading: const Icon(Icons.account_circle_outlined),
            title: Text(sync.email ?? 'Signed in'),
            subtitle: const Text('Quiz me account'),
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
        FilledButton.icon(onPressed: _signInAgain, icon: const Icon(Icons.login), label: const Text('Sign in again'))
      else
        FilledButton.icon(
          onPressed: sync.busy ? null : _syncNow,
          icon: const Icon(Icons.sync),
          label: const Text('Sync now'),
        ),
      const SizedBox(height: 8),
      OutlinedButton.icon(
        onPressed: _working || sync.busy ? null : _signOut,
        icon: const Icon(Icons.logout),
        label: const Text('Sign out on this device'),
      ),
      const SizedBox(height: 8),
      TextButton.icon(
        onPressed: _working || sync.busy ? null : _deleteAccount,
        style: TextButton.styleFrom(foregroundColor: scheme.error),
        icon: const Icon(Icons.delete_forever_outlined),
        label: const Text('Delete account'),
      ),
    ]);
  }
}
