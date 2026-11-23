import 'dart:isolate';

import 'package:path/path.dart' as p;
import 'package:sqflite_common/sqlite_api.dart';

import '../core/dates.dart';
import '../core/grading.dart';
import '../core/ids.dart';
import '../core/import/fingerprint.dart';
import '../core/import/question_parser.dart';
import '../core/models.dart';
import '../core/xlsx/xlsx_reader.dart';
import 'catalog_repository.dart';
import 'db.dart';
import 'media_store.dart';
import 'question_repository.dart';

enum DuplicatePolicy {
  skip('Skip duplicates'),
  update('Update existing questions'),
  importAnyway('Import as new questions');

  const DuplicatePolicy(this.label);
  final String label;
}

/// Everything the preview screen needs before the user confirms an import.
class ImportPreview {
  ImportPreview({
    required this.fileName,
    required this.parsed,
    required this.media,
    required this.existingMatches,
    required this.missingMedia,
  });

  final String fileName;
  final ParsedWorkbook parsed;

  /// Media files found inside a .zip bundle (lower-case file name -> bytes).
  final Map<String, List<int>> media;

  /// question number -> id of the existing question in the target bank that
  /// this row duplicates (same Question ID or same content).
  final Map<int, String> existingMatches;
  final Set<String> missingMedia;

  bool get hasBankColumn => parsed.rows.any((r) => r.bankName != null);
  int get validCount => parsed.valid.length;
  int get errorCount => parsed.invalid.length;
  int get duplicateCount => existingMatches.length;
}

class ImportResult {
  ImportResult({
    required this.importId,
    required this.imported,
    required this.updated,
    required this.skipped,
    required this.errors,
    required this.messages,
  });
  final String importId;
  final int imported;
  final int updated;
  final int skipped;
  final int errors;
  final List<String> messages;
}

/// Reads Excel workbooks (or .zip bundles with a workbook and media files),
/// validates them, and copies the questions permanently into the database.
/// After a successful import the original file is no longer needed.
class ImportService {
  ImportService(this.db, this.catalog, this.questions, this.media);
  final Database db;
  final CatalogRepository catalog;
  final QuestionRepository questions;
  final MediaStore media;

  static const int maxFileBytes = 100 * 1024 * 1024;

  /// Parses the file (in a background isolate, so large files do not freeze
  /// the interface) and compares it with the target bank.
  Future<ImportPreview> prepare({
    required String fileName,
    required List<int> bytes,
    required String bankId,
  }) async {
    if (bytes.length > maxFileBytes) {
      throw XlsxFormatException('The file is larger than 100 MB and cannot be imported.');
    }
    final bundle = await Isolate.run(() => _readBundle(bytes));
    final parsed = bundle.$1;
    final mediaFiles = bundle.$2;

    final existing = await _existingIndex([bankId]);
    final matches = <int, String>{};
    for (final r in parsed.valid) {
      final q = r.question!;
      if (r.bankName != null) continue; // routed rows are matched at commit time
      final id = _match(existing, q, bankId);
      if (id != null) matches[r.questionNumber] = id;
    }

    final missing = <String>{};
    for (final r in parsed.valid) {
      for (final ref in [r.imageRef, r.audioRef]) {
        if (ref == null) continue;
        if (!mediaFiles.containsKey(p.basename(ref).toLowerCase())) missing.add(p.basename(ref));
      }
    }
    return ImportPreview(
      fileName: fileName,
      parsed: parsed,
      media: mediaFiles,
      existingMatches: matches,
      missingMedia: missing,
    );
  }

  /// Runs in an isolate: unzips a bundle if needed, then parses every workbook.
  static (ParsedWorkbook, Map<String, List<int>>) _readBundle(List<int> bytes) {
    final zip = XlsxReader.decodeZip(bytes);
    final isWorkbook = zip.findFile('xl/workbook.xml') != null;
    if (isWorkbook) {
      return (QuestionParser.parse(XlsxReader.read(bytes)), <String, List<int>>{});
    }
    // A .zip bundle: workbooks + media files in any folder.
    final sheets = <XlsxSheet>[];
    final mediaFiles = <String, List<int>>{};
    for (final f in zip.files) {
      if (!f.isFile) continue;
      final name = p.basename(f.name);
      if (name.startsWith('.') || f.name.contains('__MACOSX')) continue;
      final lower = name.toLowerCase();
      if (lower.endsWith('.xlsx')) {
        sheets.addAll(XlsxReader.read(f.content as List<int>));
      } else if (MediaStore.isImage(lower) || MediaStore.isAudio(lower)) {
        mediaFiles[lower] = f.content as List<int>;
      }
    }
    if (sheets.isEmpty) {
      throw XlsxFormatException('The .zip file does not contain an Excel workbook (.xlsx).');
    }
    return (QuestionParser.parse(sheets), mediaFiles);
  }

  /// Existing questions of [bankIds]: maps "ext:<id>" and "fp:<fingerprint>"
  /// and "id:<id>" keys to question ids.
  Future<Map<String, String>> _existingIndex(List<String> bankIds, [DatabaseExecutor? ex]) async {
    final rows = await (ex ?? db).rawQuery(
        'SELECT id, external_id, fingerprint, bank_id FROM questions WHERE bank_id IN ${sqlInList(bankIds)}');
    final out = <String, String>{};
    for (final r in rows) {
      final id = r['id'] as String;
      final bank = r['bank_id'] as String;
      out['id:$id'] = id;
      final ext = r['external_id'] as String?;
      if (ext != null && ext.isNotEmpty) out['ext:$bank:${ext.toLowerCase()}'] = id;
      out['fp:$bank:${r['fingerprint']}'] = id;
    }
    return out;
  }

  String? _match(Map<String, String> index, Question q, String bank) {
    final ext = q.externalId?.toLowerCase();
    if (ext != null && ext.isNotEmpty) {
      final byExt = index['ext:$bank:$ext'] ?? index['id:${q.externalId}'];
      if (byExt != null) return byExt;
    }
    return index['fp:$bank:${q.fingerprint}'];
  }

  /// Saves the previewed questions permanently. Runs in one transaction: if
  /// the app is closed mid-import nothing is half-written, and the import is
  /// shown as "interrupted" in the import history.
  Future<ImportResult> commit(
    ImportPreview pv, {
    required String bankId,
    DuplicatePolicy policy = DuplicatePolicy.skip,
    bool useBankColumn = false,
    Map<String, List<int>> extraMedia = const {},
    void Function(int done, int total)? onProgress,
  }) async {
    final target = await catalog.bank(bankId);
    if (target == null) throw StateError('The selected question bank no longer exists.');
    final importId = newId();
    final now = DateTime.now();
    await db.insert('imports', {
      'id': importId,
      'bank_id': bankId,
      'file_name': pv.fileName,
      'imported_at': toMs(now),
      'status': 'in_progress',
      'sheets': pv.parsed.sheetsRead,
      'total_rows': pv.parsed.rows.length,
    });

    final allMedia = <String, List<int>>{...pv.media};
    extraMedia.forEach((k, v) => allMedia[k.toLowerCase()] = v);
    final messages = <String>[...pv.parsed.notices];
    var imported = 0, updated = 0, skipped = 0;
    final errors = pv.parsed.invalid.length;
    for (final r in pv.parsed.invalid) {
      messages.addAll(r.errors);
    }

    try {
      await db.transaction((txn) async {
        final bankCache = <String, String>{};
        final indexes = <String, Map<String, String>>{};
        Future<Map<String, String>> indexFor(String b) async =>
            indexes[b] ??= await _existingIndex([b], txn);

        final savedMedia = <String, String>{};
        Future<String?> storeMedia(String? ref, String label) async {
          if (ref == null) return null;
          final key = p.basename(ref).toLowerCase();
          if (savedMedia.containsKey(key)) return savedMedia[key];
          final bytes = allMedia[key];
          if (bytes == null) {
            messages.add('$label: media file "${p.basename(ref)}" was not found and was not attached.');
            return null;
          }
          try {
            final rel = await media.save(bytes, key);
            savedMedia[key] = rel;
            return rel;
          } catch (e) {
            messages.add('$label: $e');
            return null;
          }
        }

        var batch = txn.batch();
        var pending = 0;
        final valid = pv.parsed.valid;
        for (var i = 0; i < valid.length; i++) {
          final row = valid[i];
          if (row.duplicateInFile) {
            skipped++;
            continue;
          }
          var q = row.question!;
          var destBank = bankId;
          if (useBankColumn && row.bankName != null) {
            destBank = bankCache[row.bankName!.toLowerCase()] ??=
                (await catalog.findOrCreateBank(txn, target.categoryId, row.bankName!)).id;
          }
          final index = await indexFor(destBank);
          final existingId = _match(index, q, destBank);

          final label = 'Question ${row.questionNumber} (${row.location})';
          final image = await storeMedia(row.imageRef, label);
          final audio = await storeMedia(row.audioRef, label);
          q = q.copyWith(bankId: destBank, importId: importId, imagePath: image, audioPath: audio);

          if (existingId != null && policy == DuplicatePolicy.skip) {
            skipped++;
          } else if (existingId != null && policy == DuplicatePolicy.update) {
            await batch.commit(noResult: true);
            batch = txn.batch();
            pending = 0;
            final changed = await _updateExisting(txn, existingId, q);
            updated++;
            if (changed) {
              messages.add('$label: the correct answer changed, so its review schedule was reset '
                  '(answer history kept).');
            }
          } else {
            final row0 = q.toRow();
            batch.insert('questions', row0);
            for (final o in q.options) {
              batch.insert('options', o.toRow(q.id));
            }
            index['fp:$destBank:${q.fingerprint}'] = q.id;
            if (q.externalId != null) index['ext:$destBank:${q.externalId!.toLowerCase()}'] = q.id;
            imported++;
            pending++;
          }
          for (final w in row.warnings) {
            messages.add(w.startsWith('Question') ? w : '$label: $w');
          }
          if (pending >= 400) {
            await batch.commit(noResult: true);
            batch = txn.batch();
            pending = 0;
          }
          if (onProgress != null && i % 50 == 0) onProgress(i, valid.length);
        }
        await batch.commit(noResult: true);
        await txn.update(
          'imports',
          {
            'status': 'completed',
            'imported_count': imported,
            'updated_count': updated,
            'skipped_count': skipped,
            'error_count': errors,
            'log': messages.take(1000).join('\n'),
          },
          where: 'id = ?',
          whereArgs: [importId],
        );
      });
    } catch (e) {
      await db.update('imports', {'status': 'failed', 'log': 'Import failed: $e'},
          where: 'id = ?', whereArgs: [importId]);
      rethrow;
    }
    onProgress?.call(pv.parsed.valid.length, pv.parsed.valid.length);
    return ImportResult(
      importId: importId,
      imported: imported,
      updated: updated,
      skipped: skipped,
      errors: errors,
      messages: messages,
    );
  }

  /// Updates an existing question in place, keeping its id (and therefore its
  /// history). Options are matched by text so they keep their ids too.
  /// Returns true when the set of correct answers changed.
  Future<bool> _updateExisting(Transaction txn, String existingId, Question incoming) async {
    final current = (await questions.questionsByIds([existingId], txn)).firstOrNull;
    if (current == null) return false;
    final byText = <String, AnswerOption>{
      for (final o in current.options) normalizeAnswer(o.text): o,
    };
    final used = <String>{};
    final opts = <AnswerOption>[];
    for (final o in incoming.options) {
      final prev = byText[normalizeAnswer(o.text)];
      final id = (prev != null && used.add(prev.id)) ? prev.id : o.id;
      opts.add(AnswerOption(
        id: id,
        text: o.text,
        position: o.position,
        isCorrect: o.isCorrect,
        matchText: o.matchText,
        explanation: o.explanation,
      ));
    }
    String correctKey(Question q) {
      final c = q.options.where((o) => o.isCorrect).map((o) => normalizeAnswer('${o.text}=${o.matchText ?? ''}')).toList()
        ..sort();
      final a = q.acceptedAnswers.map(normalizeAnswer).toList()..sort();
      return '${c.join('|')}#${a.join('|')}';
    }

    final merged = incoming.copyWith(
      id: existingId,
      bankId: current.bankId,
      options: opts,
      importId: current.importId ?? incoming.importId,
      imagePath: incoming.imagePath ?? current.imagePath,
      audioPath: incoming.audioPath ?? current.audioPath,
      contentVersion: current.contentVersion,
    );
    final changed = correctKey(current) != correctKey(merged);
    final finalQ = merged.copyWith(
      fingerprint: questionFingerprint(merged),
      contentVersion: changed ? current.contentVersion + 1 : current.contentVersion,
    );
    final row = finalQ.toRow();
    row['created_at'] = toMs(current.createdAt);
    await txn.update('questions', row, where: 'id = ?', whereArgs: [existingId]);
    await questions.writeOptions(txn, existingId, finalQ.options);
    if (changed) {
      await txn.update(
        'progress',
        {
          'ease': 2.5,
          'interval_days': 0,
          'repetitions': 0,
          'due_at': null,
          'mastery': 0,
          'mastery_reason': 'Reset because the correct answer changed.',
          'last_result': null,
          'consecutive_correct': 0,
        },
        where: 'question_id = ?',
        whereArgs: [existingId],
      );
    }
    return changed;
  }

  /// Marks imports left "in progress" by an app shutdown as interrupted.
  Future<void> markInterruptedImports() => db.update(
      'imports', {'status': 'interrupted', 'log': 'The app was closed before the import finished. No questions from this import were saved.'},
      where: 'status = ?', whereArgs: ['in_progress']);

  Future<void> deleteImportRecord(String id) => db.delete('imports', where: 'id = ?', whereArgs: [id]);
}
