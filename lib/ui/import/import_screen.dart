import 'package:flutter/material.dart';

import '../../app/services.dart';
import '../../core/models.dart';
import '../../core/xlsx/xlsx_reader.dart';
import '../../data/import_service.dart';
import '../banks/bank_screen.dart';
import '../banks/node_editor.dart';
import '../common/file_io.dart';
import '../common/widgets.dart';
import '../quiz/quiz_launcher.dart';

enum _Step { choose, parsing, preview, importing, done }

/// Excel import: validate, preview, then store questions permanently.
class ImportScreen extends StatefulWidget {
  const ImportScreen({super.key, this.bankId});
  final String? bankId;

  @override
  State<ImportScreen> createState() => _ImportScreenState();
}

class _ImportScreenState extends State<ImportScreen> {
  final _svc = AppServices.I;
  String? _bankId;
  QuestionBank? _bank;
  _Step _step = _Step.choose;
  ImportPreview? _preview;
  ImportResult? _result;
  DuplicatePolicy _policy = DuplicatePolicy.skip;
  bool _useBankColumn = false;
  final Map<String, List<int>> _extraMedia = {};
  double _progress = 0;

  @override
  void initState() {
    super.initState();
    _setBank(widget.bankId);
  }

  Future<void> _setBank(String? id) async {
    _bankId = id;
    final b = id == null ? null : await _svc.catalog.bank(id);
    if (mounted) setState(() => _bank = b);
  }

  Future<void> _chooseBank() async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (c) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            leading: const Icon(Icons.folder_open),
            title: const Text('Choose an existing bank'),
            onTap: () => Navigator.pop(c, 'existing'),
          ),
          ListTile(
            leading: const Icon(Icons.create_new_folder_outlined),
            title: const Text('Create a new bank'),
            onTap: () => Navigator.pop(c, 'new'),
          ),
        ]),
      ),
    );
    if (!mounted || choice == null) return;
    if (choice == 'existing') {
      final id = await pickBank(context, title: 'Import into which bank?');
      if (id != null) await _setBank(id);
      return;
    }
    var catId = await pickCategory(context, title: 'Where should the new bank go?', allowRoot: true);
    if (catId == null || !mounted) return;
    if (catId.isEmpty) {
      final subject = await CategoryActions.create(context);
      if (subject == null) return;
      catId = subject.id;
    }
    if (!mounted) return;
    final b = await BankActions.create(context, catId);
    if (b != null) await _setBank(b.id);
  }

  Future<void> _pick() async {
    if (_bankId == null) {
      showMessage(context, 'Choose the question bank to import into first.');
      return;
    }
    final f = await pickFile(extensions: ['xlsx', 'zip']);
    if (f == null) return;
    setState(() {
      _step = _Step.parsing;
      _extraMedia.clear();
    });
    try {
      final pv = await _svc.imports.prepare(fileName: f.name, bytes: f.bytes, bankId: _bankId!);
      if (!mounted) return;
      setState(() {
        _preview = pv;
        _useBankColumn = false;
        _step = _Step.preview;
      });
    } on XlsxFormatException catch (e) {
      if (!mounted) return;
      setState(() => _step = _Step.choose);
      showErrorDialog(context, 'Invalid Excel file', e.message);
    } catch (e) {
      if (!mounted) return;
      setState(() => _step = _Step.choose);
      showErrorDialog(context, 'Invalid Excel file',
          'The selected file could not be read. Please check that it is a valid Excel workbook.\n\n($e)');
    }
  }

  Future<void> _addMedia() async {
    final files = await pickFiles(extensions: mediaExtensions);
    if (files.isEmpty) return;
    setState(() {
      for (final f in files) {
        _extraMedia[f.name.toLowerCase()] = f.bytes;
      }
    });
  }

  Future<void> _import() async {
    final pv = _preview;
    if (pv == null || _bankId == null) return;
    setState(() {
      _step = _Step.importing;
      _progress = 0;
    });
    try {
      final r = await _svc.imports.commit(
        pv,
        bankId: _bankId!,
        policy: _policy,
        useBankColumn: _useBankColumn,
        extraMedia: _extraMedia,
        onProgress: (done, total) {
          if (mounted && total > 0) setState(() => _progress = done / total);
        },
      );
      _svc.dataChanged();
      if (!mounted) return;
      setState(() {
        _result = r;
        _step = _Step.done;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _step = _Step.preview);
      showErrorDialog(context, 'Import failed', 'Nothing was imported. $e');
    }
  }

  Future<void> _saveTemplate(String asset, String name) async {
    try {
      final bytes = await assetBytes(asset);
      final ok = await saveBytes(name, bytes, title: 'Save template');
      if (ok && mounted) showMessage(context, 'Saved $name');
    } catch (e) {
      if (mounted) showErrorDialog(context, 'Could not save the template', '$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _step != _Step.importing && _step != _Step.parsing,
      child: Scaffold(
        appBar: AppBar(title: const Text('Import from Excel')),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [Readable(child: _body(context))],
        ),
      ),
    );
  }

  Widget _body(BuildContext context) {
    switch (_step) {
      case _Step.choose:
        return _chooseView(context);
      case _Step.parsing:
        return const Padding(
          padding: EdgeInsets.all(48),
          child: Column(children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Reading and checking the workbook…'),
          ]),
        );
      case _Step.preview:
        return _previewView(context);
      case _Step.importing:
        return Padding(
          padding: const EdgeInsets.all(32),
          child: Column(children: [
            LinearProgressIndicator(value: _progress == 0 ? null : _progress),
            const SizedBox(height: 16),
            const Text('Saving questions to your library…'),
            const SizedBox(height: 8),
            const Text('Please keep the app open until the import finishes.'),
          ]),
        );
      case _Step.done:
        return _doneView(context);
    }
  }

  Widget _chooseView(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text('1. Import into', style: t.labelLarge),
      const SizedBox(height: 6),
      Card(
        child: ListTile(
          leading: const Icon(Icons.folder_outlined),
          title: Text(_bank?.name ?? 'No bank selected'),
          subtitle: Text(_bank == null ? 'Choose or create a question bank' : 'Tap to change'),
          trailing: const Icon(Icons.edit_outlined),
          onTap: _chooseBank,
        ),
      ),
      const SizedBox(height: 16),
      Text('2. Choose your Excel file', style: t.labelLarge),
      const SizedBox(height: 6),
      FilledButton.icon(
        onPressed: _pick,
        icon: const Icon(Icons.upload_file),
        label: const Text('Choose .xlsx file'),
      ),
      const SizedBox(height: 6),
      Text('A .zip containing the workbook plus its images/audio also works. '
          'Every worksheet with a "Question" column is read. Nothing is saved until you confirm.',
          style: t.bodySmall),
      const SizedBox(height: 24),
      Text('Templates', style: t.labelLarge),
      const SizedBox(height: 6),
      Card(
        child: Column(children: [
          ListTile(
            leading: const Icon(Icons.table_view_outlined),
            title: const Text('Simple template'),
            subtitle: const Text('Question, Option A–D, Correct Answer, Hint, feedback, Explanation, Difficulty, Tags'),
            trailing: const Icon(Icons.download_outlined),
            onTap: () => _saveTemplate('assets/templates/QuizMe_Simple_Template.xlsx', 'QuizMe_Simple_Template.xlsx'),
          ),
          ListTile(
            leading: const Icon(Icons.table_chart_outlined),
            title: const Text('Advanced template'),
            subtitle: const Text('All question types, up to 10 options, media, per-option explanations'),
            trailing: const Icon(Icons.download_outlined),
            onTap: () =>
                _saveTemplate('assets/templates/QuizMe_Advanced_Template.xlsx', 'QuizMe_Advanced_Template.xlsx'),
          ),
          ListTile(
            leading: const Icon(Icons.auto_stories_outlined),
            title: const Text('Example questions'),
            subtitle: const Text('Ready-to-import examples of every question type'),
            trailing: const Icon(Icons.download_outlined),
            onTap: () => _saveTemplate('assets/templates/QuizMe_Examples.xlsx', 'QuizMe_Examples.xlsx'),
          ),
        ]),
      ),
    ]);
  }

  Widget _previewView(BuildContext context) {
    final pv = _preview!;
    final t = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final valid = pv.parsed.valid;
    final invalid = pv.parsed.invalid;
    final warnings = [for (final r in valid) ...r.warnings.map((w) => '${r.location}: $w')];
    final stillMissing = pv.missingMedia.where((m) => !_extraMedia.containsKey(m.toLowerCase())).toList();
    final willImport = valid.where((r) => !r.duplicateInFile).length -
        (_policy == DuplicatePolicy.importAnyway ? 0 : pv.duplicateCount);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text(pv.fileName, style: t.titleMedium),
      Text('Into: ${_bank?.name ?? ''}', style: t.bodySmall),
      const SizedBox(height: 12),
      StatGrid(children: [
        StatTile(label: 'Questions found', value: '${pv.parsed.rows.length}', icon: Icons.list_alt),
        StatTile(label: 'Ready to import', value: '${valid.length}', icon: Icons.check_circle_outline),
        StatTile(
            label: 'With errors (skipped)',
            value: '${invalid.length}',
            icon: Icons.error_outline,
            color: invalid.isEmpty ? null : scheme.error),
        StatTile(
            label: 'Already in this bank',
            value: '${pv.duplicateCount}',
            icon: Icons.content_copy_outlined),
        StatTile(label: 'Repeated in the file', value: '${pv.parsed.duplicatesInFile}', icon: Icons.copy_all),
        StatTile(label: 'Worksheets read', value: '${pv.parsed.sheetsRead}', icon: Icons.tab_outlined),
      ]),
      for (final n in pv.parsed.notices)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(n, style: t.bodySmall),
        ),
      if (pv.duplicateCount > 0) ...[
        const SizedBox(height: 16),
        Text('${pv.duplicateCount} questions already exist in this bank', style: t.labelLarge),
        const SizedBox(height: 6),
        SegmentedButton<DuplicatePolicy>(
          showSelectedIcon: false,
          segments: const [
            ButtonSegment(value: DuplicatePolicy.skip, label: Text('Skip')),
            ButtonSegment(value: DuplicatePolicy.update, label: Text('Update')),
            ButtonSegment(value: DuplicatePolicy.importAnyway, label: Text('Add anyway')),
          ],
          selected: {_policy},
          onSelectionChanged: (s) => setState(() => _policy = s.first),
        ),
        const SizedBox(height: 4),
        Text(
          switch (_policy) {
            DuplicatePolicy.skip => 'Existing questions are left unchanged.',
            DuplicatePolicy.update =>
              'Existing questions are updated with the new content. Their learning history is kept.',
            DuplicatePolicy.importAnyway => 'Duplicates are added as separate new questions.',
          },
          style: t.bodySmall,
        ),
      ],
      if (pv.hasBankColumn) ...[
        const SizedBox(height: 8),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Use the "Bank" column'),
          subtitle: Text('Put rows into banks named in the file (created next to "${_bank?.name ?? ''}" if needed)'),
          value: _useBankColumn,
          onChanged: (v) => setState(() => _useBankColumn = v),
        ),
      ],
      if (pv.missingMedia.isNotEmpty) ...[
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(stillMissing.isEmpty
                  ? 'All referenced media files are attached.'
                  : '${stillMissing.length} media files referenced in the sheet were not found: '
                      '${stillMissing.take(8).join(', ')}${stillMissing.length > 8 ? '…' : ''}'),
              const SizedBox(height: 6),
              OutlinedButton.icon(
                onPressed: _addMedia,
                icon: const Icon(Icons.perm_media_outlined),
                label: const Text('Add media files'),
              ),
              Text('Questions import without the missing files if you continue.', style: t.bodySmall),
            ]),
          ),
        ),
      ],
      if (invalid.isNotEmpty) ...[
        const SizedBox(height: 12),
        Card(
          child: ExpansionTile(
            initiallyExpanded: invalid.length <= 5,
            leading: Icon(Icons.error_outline, color: scheme.error),
            title: Text('${invalid.length} rows have errors'),
            childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            expandedCrossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final r in invalid.take(200))
                for (final e in r.errors)
                  Padding(padding: const EdgeInsets.only(bottom: 4), child: Text('• $e')),
              if (invalid.length > 200) Text('…and ${invalid.length - 200} more'),
            ],
          ),
        ),
      ],
      if (warnings.isNotEmpty) ...[
        const SizedBox(height: 8),
        Card(
          child: ExpansionTile(
            leading: const Icon(Icons.info_outline),
            title: Text('${warnings.length} warnings'),
            childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            expandedCrossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final w in warnings.take(200))
                Padding(padding: const EdgeInsets.only(bottom: 4), child: Text('• $w')),
            ],
          ),
        ),
      ],
      if (valid.isNotEmpty) ...[
        const SectionHeader('Preview'),
        for (final r in valid.take(5))
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Card(
              child: ListTile(
                title: ContentText(r.question!.text, maxLines: 2),
                subtitle: Text('${r.question!.type.label} · Answer: ${r.question!.correctAnswerText}',
                    maxLines: 2, overflow: TextOverflow.ellipsis),
              ),
            ),
          ),
        if (valid.length > 5) Text('…and ${valid.length - 5} more', style: t.bodySmall),
      ],
      const SizedBox(height: 20),
      Row(children: [
        TextButton(onPressed: () => setState(() => _step = _Step.choose), child: const Text('Choose another file')),
        const Spacer(),
        FilledButton.icon(
          onPressed: valid.isEmpty ? null : _import,
          icon: const Icon(Icons.download_done),
          label: Text(_policy == DuplicatePolicy.update && pv.duplicateCount > 0
              ? 'Import & update'
              : 'Import ${willImport < 0 ? 0 : willImport}'),
        ),
      ]),
    ]);
  }

  Widget _doneView(BuildContext context) {
    final r = _result!;
    final t = Theme.of(context).textTheme;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const Icon(Icons.check_circle, size: 56),
      const SizedBox(height: 8),
      Text('Import complete', textAlign: TextAlign.center, style: t.headlineSmall),
      const SizedBox(height: 16),
      StatGrid(children: [
        StatTile(label: 'Imported', value: '${r.imported}', icon: Icons.add_circle_outline),
        StatTile(label: 'Updated', value: '${r.updated}', icon: Icons.sync),
        StatTile(label: 'Skipped', value: '${r.skipped}', icon: Icons.skip_next),
        StatTile(label: 'Errors', value: '${r.errors}', icon: Icons.error_outline),
      ]),
      const SizedBox(height: 16),
      const Card(
        child: ListTile(
          leading: Icon(Icons.lock_outline),
          title: Text('Saved permanently'),
          subtitle: Text('The questions are now stored inside Quiz me. You can delete the Excel file from '
              'your phone — your questions stay here until you delete them in the app.'),
        ),
      ),
      if (r.messages.isNotEmpty) ...[
        const SizedBox(height: 8),
        Card(
          child: ExpansionTile(
            title: Text('${r.messages.length} messages'),
            childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            expandedCrossAxisAlignment: CrossAxisAlignment.start,
            children: [for (final m in r.messages.take(300)) Text('• $m')],
          ),
        ),
      ],
      const SizedBox(height: 20),
      Wrap(spacing: 8, runSpacing: 8, alignment: WrapAlignment.center, children: [
        FilledButton.icon(
          onPressed: () => launchQuiz(context,
              defaultConfig(title: _bank?.name ?? 'Quiz', bankIds: [_bankId!], selection: SelectionMode.newQuestions)),
          icon: const Icon(Icons.play_arrow),
          label: const Text('Start learning'),
        ),
        OutlinedButton(
          onPressed: () => Navigator.pushReplacement(
              context, MaterialPageRoute<void>(builder: (_) => BankScreen(bankId: _bankId!))),
          child: const Text('Open bank'),
        ),
        TextButton(
          onPressed: () => setState(() {
            _step = _Step.choose;
            _preview = null;
            _result = null;
          }),
          child: const Text('Import another file'),
        ),
      ]),
    ]);
  }
}
