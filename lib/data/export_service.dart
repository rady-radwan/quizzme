import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;

import '../core/models.dart';
import '../core/shuffle.dart';
import '../core/xlsx/xlsx_writer.dart';
import 'catalog_repository.dart';
import 'media_store.dart';
import 'question_repository.dart';

/// Column layout of the advanced template. Shared by export and the template
/// generator so exported files can be re-imported without changes.
class ExcelLayout {
  static List<String> headers(int optionCount) => [
        'Question ID',
        'Type',
        'Question',
        for (var i = 0; i < optionCount; i++) 'Option ${optionLetter(i)}',
        'Correct Answer',
        'Accepted Answers',
        'Case Sensitive',
        'Hint',
        'Correct Feedback',
        'Incorrect Feedback',
        'Explanation',
        for (var i = 0; i < optionCount; i++) 'Option ${optionLetter(i)} Explanation',
        'Difficulty',
        'Tags',
        'Category',
        'Bank',
        'Image',
        'Audio',
        'Shuffle Answers',
        'Source',
        'Study Notes',
      ];
}

class ExportFile {
  ExportFile(this.fileName, this.bytes);
  final String fileName;
  final List<int> bytes;
}

class ExportService {
  ExportService(this.catalog, this.questions, this.media);
  final CatalogRepository catalog;
  final QuestionRepository questions;
  final MediaStore media;

  /// Exports one bank in the advanced template format. When questions have
  /// images or audio and [includeMedia] is true, the result is a .zip with the
  /// workbook and a media folder (importable as-is).
  Future<ExportFile> exportBank(String bankId, {bool includeMedia = true}) async {
    final bank = await catalog.bank(bankId);
    if (bank == null) throw StateError('Bank not found');
    final path = await catalog.categoryPath(bank.categoryId);
    final ids = await questions.searchIds(QuestionFilter(bankIds: [bankId], includeArchived: true),
        limit: 1000000);
    final qs = await questions.questionsByIds(ids);
    final maxOpts = qs.fold<int>(4, (m, q) => q.options.length > m ? q.options.length : m);
    final optCount = maxOpts > 10 ? 10 : maxOpts;
    final rows = <List<String>>[ExcelLayout.headers(optCount)];
    final mediaFiles = <String, String>{}; // exported name -> stored relative path
    for (final q in qs) {
      rows.add(_row(q, optCount, path.map((c) => c.name).join(' > '), bank.name, mediaFiles));
    }
    final widths = [
      14.0, 14, 50,
      for (var i = 0; i < optCount; i++) 28.0,
      16, 22, 10, 28, 30, 30, 45,
      for (var i = 0; i < optCount; i++) 26.0,
      11, 20, 22, 20, 18, 18, 10, 22, 28,
    ].map((e) => e.toDouble()).toList();
    final xlsx = XlsxWriter.write([XlsxSheetData('Questions', rows, columnWidths: widths)]);
    final safe = bank.name.replaceAll(RegExp(r'[^\p{L}\p{N} _-]', unicode: true), '').trim();
    final base = safe.isEmpty ? 'question-bank' : safe;
    if (!includeMedia || mediaFiles.isEmpty) return ExportFile('$base.xlsx', xlsx);

    final archive = Archive();
    archive.addFile(ArchiveFile('$base.xlsx', xlsx.length, xlsx));
    for (final e in mediaFiles.entries) {
      final f = media.resolve(e.value);
      if (f == null || !await f.exists()) continue;
      final bytes = await f.readAsBytes();
      archive.addFile(ArchiveFile('media/${e.key}', bytes.length, bytes));
    }
    final zip = ZipEncoder().encode(archive);
    if (zip == null) throw StateError('Could not create the export file.');
    return ExportFile('$base.zip', zip);
  }

  List<String> _row(Question q, int optCount, String category, String bankName,
      Map<String, String> mediaFiles) {
    final opts = [...q.options]..sort((a, b) => a.position.compareTo(b.position));
    String optionCell(int i) {
      if (i >= opts.length) return '';
      final o = opts[i];
      return q.type == QuestionType.matching ? '${o.text} => ${o.matchText ?? ''}' : o.text;
    }

    String correct;
    switch (q.type) {
      case QuestionType.single:
      case QuestionType.multiple:
        correct = [
          for (var i = 0; i < opts.length; i++)
            if (opts[i].isCorrect) optionLetter(i)
        ].join(', ');
        break;
      case QuestionType.trueFalse:
        final c = opts.where((o) => o.isCorrect);
        correct = c.isEmpty ? '' : c.first.text;
        break;
      case QuestionType.fillBlank:
      case QuestionType.shortAnswer:
      case QuestionType.flashcard:
        correct = q.acceptedAnswers.isEmpty ? '' : q.acceptedAnswers.first;
        break;
      case QuestionType.matching:
        correct = '';
        break;
    }
    final accepted = q.type.usesTypedAnswer && q.acceptedAnswers.length > 1
        ? q.acceptedAnswers.skip(1).join(' | ')
        : '';
    String mediaName(String? rel) {
      if (rel == null) return '';
      final name = p.basename(rel);
      mediaFiles[name] = rel;
      return name;
    }

    return [
      q.externalId ?? q.id,
      q.type.key,
      q.text,
      for (var i = 0; i < optCount; i++) optionCell(i),
      correct,
      accepted,
      q.caseSensitive ? 'Yes' : '',
      q.hint ?? '',
      q.correctFeedback ?? '',
      q.incorrectFeedback ?? '',
      q.explanation ?? '',
      for (var i = 0; i < optCount; i++) i < opts.length ? (opts[i].explanation ?? '') : '',
      q.difficulty.label,
      q.tags.join(', '),
      category,
      bankName,
      mediaName(q.imagePath),
      mediaName(q.audioPath),
      q.shuffleOptions ? 'Yes' : 'No',
      q.source ?? '',
      q.studyNotes ?? '',
    ];
  }

  /// Plain-text summary used for sharing a single question (debug/notes).
  static String questionAsText(Question q) => const JsonEncoder.withIndent('  ').convert({
        'question': q.text,
        'type': q.type.key,
        'options': q.options.map((o) => {'text': o.text, 'correct': o.isCorrect}).toList(),
        'answer': q.correctAnswerText,
      });
}
