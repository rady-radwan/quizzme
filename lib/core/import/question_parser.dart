import '../ids.dart';
import '../models.dart';
import '../xlsx/xlsx_reader.dart';
import 'fingerprint.dart';

/// Columns understood by the importer. Header matching ignores case, spaces
/// and punctuation, and accepts common synonyms, so "Correct Answer",
/// "correct_answer" and "Answer" all work.
enum ImportColumn {
  questionId,
  type,
  question,
  correct,
  accepted,
  caseSensitive,
  hint,
  correctFeedback,
  incorrectFeedback,
  explanation,
  difficulty,
  tags,
  category,
  bank,
  image,
  audio,
  shuffle,
  source,
  notes,
}

const int maxOptions = 10; // Option A .. Option J

const Map<ImportColumn, List<String>> _aliases = {
  ImportColumn.questionId: ['questionid', 'id', 'externalid', 'qid'],
  ImportColumn.type: ['type', 'questiontype', 'format'],
  ImportColumn.question: ['question', 'questiontext', 'prompt', 'front', 'statement'],
  ImportColumn.correct: [
    'correctanswer', 'correctanswers', 'answer', 'answers', 'correct', 'back', 'correctoption', 'correctoptions'
  ],
  ImportColumn.accepted: ['acceptedanswers', 'alternativeanswers', 'alternatives', 'acceptedalternatives'],
  ImportColumn.caseSensitive: ['casesensitive', 'matchcase'],
  ImportColumn.hint: ['hint', 'hints', 'clue'],
  ImportColumn.correctFeedback: ['correctfeedback', 'feedbackcorrect', 'correctmessage', 'correctanswerfeedback'],
  ImportColumn.incorrectFeedback: [
    'incorrectfeedback', 'feedbackincorrect', 'incorrectmessage', 'wrongfeedback', 'incorrectanswerfeedback'
  ],
  ImportColumn.explanation: ['explanation', 'generalexplanation', 'detailedexplanation'],
  ImportColumn.difficulty: ['difficulty', 'level', 'difficultylevel'],
  ImportColumn.tags: ['tags', 'tag', 'keywords'],
  ImportColumn.category: ['category', 'questioncategory', 'topic'],
  ImportColumn.bank: ['bank', 'questionbank', 'bankname'],
  ImportColumn.image: ['image', 'imagereference', 'imagefile', 'picture'],
  ImportColumn.audio: ['audio', 'audioreference', 'audiofile', 'sound'],
  ImportColumn.shuffle: ['shuffleanswers', 'shuffle', 'shuffleoptions', 'answershuffling'],
  ImportColumn.source: ['source', 'reference', 'sourcereference', 'sourceorreference'],
  ImportColumn.notes: ['studynotes', 'notes', 'studynote'],
};

String _norm(String h) => h.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');

/// Maps header cells to columns for one sheet.
class HeaderMap {
  HeaderMap(this.columns, this.options, this.optionExplanations);
  final Map<ImportColumn, int> columns;

  /// option index (0 = A) -> column index
  final Map<int, int> options;
  final Map<int, int> optionExplanations;

  static HeaderMap? detect(XlsxRow row) {
    final cols = <ImportColumn, int>{};
    final opts = <int, int>{};
    final optEx = <int, int>{};
    for (var i = 0; i < row.cells.length; i++) {
      final h = _norm(row.cells[i]);
      if (h.isEmpty) continue;
      final opt = _optionHeader(h);
      if (opt != null) {
        opts.putIfAbsent(opt, () => i);
        continue;
      }
      final ex = _optionExplanationHeader(h);
      if (ex != null) {
        optEx.putIfAbsent(ex, () => i);
        continue;
      }
      for (final e in _aliases.entries) {
        if (e.value.contains(h)) {
          cols.putIfAbsent(e.key, () => i);
          break;
        }
      }
    }
    if (!cols.containsKey(ImportColumn.question)) return null;
    return HeaderMap(cols, opts, optEx);
  }

  static final _optRe = RegExp(r'^(?:option|answer|choice)([a-j]|10|[1-9])$');
  static final _optExRe = RegExp(
      r'^(?:option([a-j])explanation|explanation([a-j])|why([a-j])(?:wrong|incorrect)?|option([a-j])feedback)$');

  static int? _optionHeader(String h) {
    final m = _optRe.firstMatch(h);
    if (m == null) return null;
    return _letterOrNumber(m.group(1)!);
  }

  static int? _optionExplanationHeader(String h) {
    final m = _optExRe.firstMatch(h);
    if (m == null) return null;
    for (var g = 1; g <= m.groupCount; g++) {
      final v = m.group(g);
      if (v != null) return _letterOrNumber(v);
    }
    return null;
  }

  static int? _letterOrNumber(String v) {
    final n = int.tryParse(v);
    if (n != null) return (n >= 1 && n <= maxOptions) ? n - 1 : null;
    final c = v.codeUnitAt(0) - 97;
    return (c >= 0 && c < maxOptions) ? c : null;
  }
}

/// One parsed spreadsheet row.
class ImportRow {
  ImportRow({
    required this.sheet,
    required this.rowNumber,
    required this.questionNumber,
    this.question,
    List<String>? errors,
    List<String>? warnings,
    this.bankName,
    this.categoryName,
    this.imageRef,
    this.audioRef,
  })  : errors = errors ?? [],
        warnings = warnings ?? [];

  final String sheet;
  final int rowNumber;

  /// 1-based position among the data rows of the whole workbook.
  final int questionNumber;
  final Question? question;
  final List<String> errors;
  final List<String> warnings;
  final String? bankName;
  final String? categoryName;
  final String? imageRef;
  final String? audioRef;

  /// Same question appears earlier in the same file.
  bool duplicateInFile = false;

  bool get isValid => errors.isEmpty && question != null;
  String get location => '$sheet row $rowNumber';
}

class ParsedWorkbook {
  ParsedWorkbook(this.rows, this.notices, this.sheetsRead);
  final List<ImportRow> rows;

  /// Sheet-level notices (e.g. "Sheet 'Instructions' has no Question column").
  final List<String> notices;
  final int sheetsRead;

  List<ImportRow> get valid => rows.where((r) => r.isValid).toList();
  List<ImportRow> get invalid => rows.where((r) => !r.isValid).toList();
  int get duplicatesInFile => rows.where((r) => r.duplicateInFile).length;
}

/// Converts worksheets into validated question drafts. Pure Dart; safe to run
/// in a background isolate for very large files.
class QuestionParser {
  static ParsedWorkbook parse(List<XlsxSheet> sheets) {
    final rows = <ImportRow>[];
    final notices = <String>[];
    final seen = <String>{};
    var qNo = 0;
    var sheetsRead = 0;

    for (final sheet in sheets) {
      HeaderMap? header;
      var headerIndex = -1;
      for (var i = 0; i < sheet.rows.length && i < 15; i++) {
        if (sheet.rows[i].isBlank) continue;
        header = HeaderMap.detect(sheet.rows[i]);
        if (header != null) {
          headerIndex = i;
          break;
        }
      }
      if (header == null) {
        notices.add('Sheet "${sheet.name}" was skipped: no "Question" column header was found.');
        continue;
      }
      sheetsRead++;
      for (var i = headerIndex + 1; i < sheet.rows.length; i++) {
        final row = sheet.rows[i];
        if (row.isBlank) continue;
        qNo++;
        final parsed = _parseRow(sheet.name, row, header, qNo);
        final q = parsed.question;
        if (q != null && parsed.errors.isEmpty) {
          if (!seen.add(q.fingerprint)) {
            parsed.duplicateInFile = true;
            parsed.warnings.add('Duplicate of an earlier question in this file.');
          }
        }
        rows.add(parsed);
      }
    }
    return ParsedWorkbook(rows, notices, sheetsRead);
  }

  static ImportRow _parseRow(String sheet, XlsxRow row, HeaderMap h, int qNo) {
    String col(ImportColumn c) {
      final i = h.columns[c];
      return i == null ? '' : row.cell(i).trim();
    }

    final errors = <String>[];
    final warnings = <String>[];
    final label = 'Question $qNo ($sheet row ${row.rowNumber})';

    final text = col(ImportColumn.question);
    if (text.isEmpty) {
      errors.add('$label has no question text.');
    }

    // Raw option cells in A..J order, keeping their letter index.
    final rawOptions = <int, String>{};
    for (final e in h.options.entries) {
      final v = row.cell(e.value).trim();
      if (v.isNotEmpty) rawOptions[e.key] = v;
    }
    final rawExplanations = <int, String>{};
    for (final e in h.optionExplanations.entries) {
      final v = row.cell(e.value).trim();
      if (v.isNotEmpty) rawExplanations[e.key] = v;
    }

    final correctRaw = col(ImportColumn.correct);
    final typeRaw = col(ImportColumn.type);
    final imageRef = _nullIfEmpty(col(ImportColumn.image));
    final audioRef = _nullIfEmpty(col(ImportColumn.audio));

    var type = parseType(typeRaw);
    if (typeRaw.isNotEmpty && type == null) {
      warnings.add('Unknown question type "$typeRaw"; it was detected automatically.');
    }
    type ??= _inferType(rawOptions, correctRaw, text);

    var difficulty = Difficulty.medium;
    final dRaw = col(ImportColumn.difficulty);
    if (dRaw.isNotEmpty) {
      final d = Difficulty.tryParse(dRaw);
      if (d == null) {
        warnings.add('Unknown difficulty "$dRaw"; Medium was used.');
      } else {
        difficulty = d;
      }
    }

    final shuffleRaw = col(ImportColumn.shuffle);
    final shuffle = shuffleRaw.isEmpty ? true : _parseBool(shuffleRaw) ?? true;
    final caseSensitive = _parseBool(col(ImportColumn.caseSensitive)) ?? false;

    final options = <AnswerOption>[];
    var accepted = <String>[];

    switch (type) {
      case QuestionType.single:
      case QuestionType.multiple:
        if (rawOptions.length < 2) {
          errors.add('$label needs at least two answer options.');
        }
        final choiceKeys = rawOptions.keys.toList()..sort();
        final idxs = _resolveCorrect(correctRaw, choiceKeys, rawOptions);
        if (idxs == null || idxs.isEmpty) {
          errors.add('$label does not have a valid correct answer.');
        } else if (type == QuestionType.single && idxs.length > 1) {
          type = QuestionType.multiple;
        }
        var choicePos = 0;
        for (final k in choiceKeys) {
          options.add(AnswerOption(
            id: newId(),
            position: choicePos++,
            text: rawOptions[k]!,
            isCorrect: idxs?.contains(k) ?? false,
            explanation: rawExplanations[k],
          ));
        }
        break;
      case QuestionType.trueFalse:
        final tfKeys = rawOptions.keys.toList()..sort();
        final tText = tfKeys.isNotEmpty ? rawOptions[tfKeys[0]]! : 'True';
        final fText = tfKeys.length > 1 ? rawOptions[tfKeys[1]]! : 'False';
        final tfValue = _trueFalseValue(correctRaw, tText, fText);
        if (tfValue == null) {
          errors.add('$label does not have a valid correct answer (use True or False).');
        }
        options.add(AnswerOption(
            id: newId(), position: 0, text: tText, isCorrect: tfValue == true,
            explanation: tfKeys.isNotEmpty ? rawExplanations[tfKeys[0]] : null));
        options.add(AnswerOption(
            id: newId(), position: 1, text: fText, isCorrect: tfValue == false,
            explanation: tfKeys.length > 1 ? rawExplanations[tfKeys[1]] : null));
        break;
      case QuestionType.fillBlank:
      case QuestionType.shortAnswer:
        accepted = _splitAlternatives(correctRaw);
        accepted.addAll(_splitAlternatives(col(ImportColumn.accepted)));
        accepted = accepted.toSet().toList();
        if (accepted.isEmpty) {
          errors.add('$label does not have a valid correct answer.');
        }
        break;
      case QuestionType.matching:
        final pairKeys = rawOptions.keys.toList()..sort();
        var pairPos = 0;
        for (final k in pairKeys) {
          final pair = _splitPair(rawOptions[k]!);
          if (pair == null) {
            errors.add('$label: option ${String.fromCharCode(65 + k)} must look like "Item => Match".');
            continue;
          }
          options.add(AnswerOption(
            id: newId(),
            position: pairPos++,
            text: pair.$1,
            matchText: pair.$2,
            isCorrect: true,
          ));
        }
        if (options.length < 2 && errors.isEmpty) {
          errors.add('$label needs at least two matching pairs.');
        }
        break;
      case QuestionType.flashcard:
        final back = correctRaw.isNotEmpty ? correctRaw : col(ImportColumn.explanation);
        if (back.isEmpty) {
          errors.add('$label (flashcard) needs an answer for the back of the card.');
        } else {
          accepted = [back];
        }
        break;
    }

    if ((typeRaw.toLowerCase().contains('image') || typeRaw.toLowerCase().contains('identif')) &&
        imageRef == null) {
      warnings.add('$label is an image question but has no image reference.');
    }
    if (typeRaw.toLowerCase().contains('audio') && audioRef == null) {
      warnings.add('$label is an audio question but has no audio reference.');
    }

    if (errors.isNotEmpty) {
      return ImportRow(
        sheet: sheet,
        rowNumber: row.rowNumber,
        questionNumber: qNo,
        errors: errors,
        warnings: warnings,
      );
    }

    final q = Question(
      id: newId(),
      bankId: '',
      type: type,
      text: text,
      options: options,
      externalId: _nullIfEmpty(col(ImportColumn.questionId)),
      hint: _nullIfEmpty(col(ImportColumn.hint)),
      explanation: _nullIfEmpty(col(ImportColumn.explanation)),
      correctFeedback: _nullIfEmpty(col(ImportColumn.correctFeedback)),
      incorrectFeedback: _nullIfEmpty(col(ImportColumn.incorrectFeedback)),
      difficulty: difficulty,
      tags: splitTagInput(col(ImportColumn.tags)),
      shuffleOptions: shuffle,
      caseSensitive: caseSensitive,
      acceptedAnswers: accepted,
      source: _nullIfEmpty(col(ImportColumn.source)),
      studyNotes: _nullIfEmpty(col(ImportColumn.notes)),
    );
    final withFp = q.copyWith(fingerprint: questionFingerprint(q));
    return ImportRow(
      sheet: sheet,
      rowNumber: row.rowNumber,
      questionNumber: qNo,
      question: withFp,
      warnings: warnings,
      bankName: _nullIfEmpty(col(ImportColumn.bank)),
      categoryName: _nullIfEmpty(col(ImportColumn.category)),
      imageRef: imageRef,
      audioRef: audioRef,
    );
  }

  /// Parses the "Type" column. Returns null for an empty or unknown value.
  static QuestionType? parseType(String raw) {
    final v = _norm(raw);
    if (v.isEmpty) return null;
    const map = {
      'single': QuestionType.single,
      'singleanswer': QuestionType.single,
      'singlechoice': QuestionType.single,
      'mcq': QuestionType.single,
      'multiplechoice': QuestionType.single,
      'choice': QuestionType.single,
      'image': QuestionType.single,
      'imagequestion': QuestionType.single,
      'audio': QuestionType.single,
      'audioquestion': QuestionType.single,
      'listening': QuestionType.single,
      'multiple': QuestionType.multiple,
      'multi': QuestionType.multiple,
      'multipleanswer': QuestionType.multiple,
      'multipleanswers': QuestionType.multiple,
      'multipleresponse': QuestionType.multiple,
      'checkbox': QuestionType.multiple,
      'truefalse': QuestionType.trueFalse,
      'tf': QuestionType.trueFalse,
      'boolean': QuestionType.trueFalse,
      'fill': QuestionType.fillBlank,
      'fillintheblank': QuestionType.fillBlank,
      'fillblank': QuestionType.fillBlank,
      'blank': QuestionType.fillBlank,
      'cloze': QuestionType.fillBlank,
      'matching': QuestionType.matching,
      'match': QuestionType.matching,
      'short': QuestionType.shortAnswer,
      'shortanswer': QuestionType.shortAnswer,
      'written': QuestionType.shortAnswer,
      'shortwrittenanswer': QuestionType.shortAnswer,
      'identify': QuestionType.shortAnswer,
      'identification': QuestionType.shortAnswer,
      'imageidentification': QuestionType.shortAnswer,
      'flashcard': QuestionType.flashcard,
      'card': QuestionType.flashcard,
    };
    return map[v];
  }

  static QuestionType _inferType(Map<int, String> opts, String correct, String text) {
    if (opts.isNotEmpty) {
      if (opts.values.where((o) => o.contains('=>') || o.contains('->')).length >= 2) {
        return QuestionType.matching;
      }
      return QuestionType.single;
    }
    if (_trueFalseValue(correct, 'True', 'False') != null &&
        RegExp(r'^(true|false|t|f)$', caseSensitive: false).hasMatch(correct.trim())) {
      return QuestionType.trueFalse;
    }
    if (text.contains('___') || text.contains('…') || text.contains('...')) {
      return QuestionType.fillBlank;
    }
    return QuestionType.shortAnswer;
  }

  /// Resolves "B", "B, D", "BD", "2", or exact option text to option indexes.
  static Set<int>? _resolveCorrect(String raw, List<int> keys, Map<int, String> opts) {
    final v = raw.trim();
    if (v.isEmpty) return null;
    // Exact option text (may itself contain commas).
    for (final k in keys) {
      if (opts[k]!.trim().toLowerCase() == v.toLowerCase()) return {k};
    }
    final out = <int>{};
    final tokens = v
        .split(RegExp(r'\s*(?:,|;|/|\||&|\band\b|\s)\s*', caseSensitive: false))
        .where((t) => t.isNotEmpty)
        .toList();
    for (var t in tokens) {
      t = t.replaceAll(RegExp(r'^option\s*', caseSensitive: false), '');
      t = t.replaceAll(RegExp(r'[.)\]]$'), '');
      final upper = t.toUpperCase();
      if (RegExp(r'^[A-J]$').hasMatch(upper)) {
        out.add(upper.codeUnitAt(0) - 65);
      } else if (RegExp(r'^(10|[1-9])$').hasMatch(t)) {
        out.add(int.parse(t) - 1);
      } else if (RegExp(r'^[A-J]{2,10}$').hasMatch(upper)) {
        for (final c in upper.codeUnits) {
          out.add(c - 65);
        }
      } else {
        // Option text token.
        final match = keys.where((k) => opts[k]!.trim().toLowerCase() == t.toLowerCase());
        if (match.isEmpty) return null;
        out.add(match.first);
      }
    }
    // Every referenced option must exist and be non-empty.
    if (out.any((i) => !opts.containsKey(i))) return null;
    return out;
  }

  static bool? _trueFalseValue(String raw, String tText, String fText) {
    final v = raw.trim().toLowerCase();
    if (v.isEmpty) return null;
    if (v == tText.toLowerCase()) return true;
    if (v == fText.toLowerCase()) return false;
    const yes = ['true', 't', 'yes', 'y', 'correct', '1', 'a', 'صح', 'صحيح'];
    const no = ['false', 'f', 'no', 'n', 'incorrect', '0', 'b', 'خطأ', 'خطا'];
    if (yes.contains(v)) return true;
    if (no.contains(v)) return false;
    return null;
  }

  static bool? _parseBool(String raw) {
    final v = raw.trim().toLowerCase();
    if (v.isEmpty) return null;
    if (['yes', 'y', 'true', 't', '1', 'on'].contains(v)) return true;
    if (['no', 'n', 'false', 'f', '0', 'off'].contains(v)) return false;
    return null;
  }

  static List<String> _splitAlternatives(String raw) => raw
      .split('|')
      .map((s) => s.trim())
      .where((s) => s.isNotEmpty)
      .toList();

  static (String, String)? _splitPair(String raw) {
    for (final sep in ['=>', '->', '→', ' = ', '|']) {
      final i = raw.indexOf(sep);
      if (i > 0) {
        final a = raw.substring(0, i).trim();
        final b = raw.substring(i + sep.length).trim();
        if (a.isNotEmpty && b.isNotEmpty) return (a, b);
      }
    }
    return null;
  }

  static String? _nullIfEmpty(String s) => s.trim().isEmpty ? null : s.trim();
}
