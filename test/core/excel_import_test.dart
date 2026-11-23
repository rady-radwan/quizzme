import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quiz_me/core/import/fingerprint.dart';
import 'package:quiz_me/core/import/question_parser.dart';
import 'package:quiz_me/core/models.dart';
import 'package:quiz_me/core/xlsx/xlsx_reader.dart';
import 'package:quiz_me/core/xlsx/xlsx_writer.dart';

const simpleHeader = [
  'Question', 'Option A', 'Option B', 'Option C', 'Option D', 'Correct Answer', 'Hint',
  'Correct Feedback', 'Incorrect Feedback', 'Explanation', 'Difficulty', 'Tags'
];

List<XlsxSheet> sheet(List<List<String>> rows, {String name = 'Questions'}) => [
      XlsxSheet(name, [for (var i = 0; i < rows.length; i++) XlsxRow(i + 1, rows[i])])
    ];

ParsedWorkbook parse(List<List<String>> rows) => QuestionParser.parse(sheet(rows));

void main() {
  group('xlsx reader/writer', () {
    test('round trip keeps text, unicode, empty cells and sheets', () {
      final bytes = XlsxWriter.write([
        XlsxSheetData('Questions', [
          ['Question', 'Option A', 'Option B', 'Correct Answer'],
          ['Which is <correct> & "right"?', 'Yes', '', 'A'],
          ['أي جملة صحيحة؟', 'نعم', 'لا', 'A'],
        ]),
        XlsxSheetData('Second', [
          ['Question', 'Correct Answer'],
          ['2 + 2', '4'],
        ]),
      ]);
      final sheets = XlsxReader.read(bytes);
      expect(sheets.length, 2);
      expect(sheets[0].name, 'Questions');
      expect(sheets[0].rows[1].cell(0), 'Which is <correct> & "right"?');
      expect(sheets[0].rows[1].cell(2), '');
      expect(sheets[0].rows[1].cell(3), 'A');
      expect(sheets[0].rows[2].cell(0), 'أي جملة صحيحة؟');
      expect(sheets[1].rows[1].cell(1), '4');
    });

    test('reads shared strings, numbers and booleans', () {
      final archive = Archive();
      void add(String n, String c) {
        final b = utf8.encode(c);
        archive.addFile(ArchiveFile(n, b.length, b));
      }

      add('xl/workbook.xml',
          '<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><sheets><sheet name="S" sheetId="1" r:id="rId1"/></sheets></workbook>');
      add('xl/_rels/workbook.xml.rels',
          '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="x" Target="worksheets/sheet1.xml"/></Relationships>');
      add('xl/sharedStrings.xml',
          '<sst><si><t>Question</t></si><si><r><t>Rich </t></r><r><t>text</t></r></si></sst>');
      add('xl/worksheets/sheet1.xml',
          '<worksheet><sheetData><row r="1"><c r="A1" t="s"><v>0</v></c><c r="C1" t="s"><v>1</v></c></row>'
          '<row r="3"><c r="A3"><v>3.0</v></c><c r="B3" t="b"><v>1</v></c></row></sheetData></worksheet>');
      final bytes = ZipEncoder().encode(archive)!;
      final s = XlsxReader.read(bytes).single;
      expect(s.rows[0].cell(0), 'Question');
      expect(s.rows[0].cell(1), '');
      expect(s.rows[0].cell(2), 'Rich text');
      expect(s.rows[1].rowNumber, 3);
      expect(s.rows[1].cell(0), '3');
      expect(s.rows[1].cell(1), 'TRUE');
    });

    test('invalid files raise a friendly error', () {
      expect(() => XlsxReader.read(utf8.encode('this is not a workbook')), throwsA(isA<XlsxFormatException>()));
    });

    test('column letters', () {
      expect(XlsxReader.columnIndex('A1'), 0);
      expect(XlsxReader.columnIndex('Z9'), 25);
      expect(XlsxReader.columnIndex('AA10'), 26);
      expect(XlsxWriter.columnName(27), 'AB');
    });
  });

  group('question parser', () {
    test('simple template row with every optional field', () {
      final p = parse([
        simpleHeader,
        [
          'Which sentence is grammatically correct?',
          'He go to work every day.',
          'He goes to work every day.',
          'He going to work every day.',
          'He gone to work every day.',
          'B',
          'Remember the third-person singular rule.',
          'Excellent!',
          'Not quite.',
          'Third-person singular takes -s.',
          'Easy',
          'grammar, present simple',
        ],
      ]);
      expect(p.valid.length, 1);
      final q = p.valid.first.question!;
      expect(q.type, QuestionType.single);
      expect(q.options.length, 4);
      expect(q.options.where((o) => o.isCorrect).single.text, 'He goes to work every day.');
      expect(q.hint, startsWith('Remember'));
      expect(q.correctFeedback, 'Excellent!');
      expect(q.incorrectFeedback, 'Not quite.');
      expect(q.difficulty, Difficulty.easy);
      expect(q.tags, ['grammar', 'present simple']);
      expect(q.fingerprint, isNotEmpty);
    });

    test('only question, options and correct answer are required', () {
      final p = parse([
        ['Question', 'Option A', 'Option B', 'Correct Answer'],
        ['2 + 2 = ?', '3', '4', 'B'],
      ]);
      expect(p.valid.single.question!.explanation, isNull);
      expect(p.valid.single.question!.difficulty, Difficulty.medium);
    });

    test('missing or invalid correct answers are reported with the question number', () {
      final p = parse([
        ['Question', 'Option A', 'Option B', 'Correct Answer'],
        ['Q1', 'a', 'b', ''],
        ['Q2', 'a', 'b', 'D'],
        ['Q3', 'a', 'b', 'A'],
      ]);
      expect(p.invalid.length, 2);
      expect(p.invalid.first.errors.single, contains('Question 1'));
      expect(p.invalid.first.errors.single, contains('does not have a valid correct answer'));
      expect(p.invalid[1].errors.single, contains('Question 2'));
      expect(p.valid.length, 1);
    });

    test('several correct letters become a multiple-answer question', () {
      final p = parse([
        ['Question', 'Option A', 'Option B', 'Option C', 'Correct Answer'],
        ['Pick two', 'x', 'y', 'z', 'A, C'],
        ['Pick two again', 'x', 'y', 'z', 'AC'],
      ]);
      for (final r in p.valid) {
        expect(r.question!.type, QuestionType.multiple);
        expect(r.question!.options.where((o) => o.isCorrect).map((o) => o.text).toSet(), {'x', 'z'});
      }
    });

    test('correct answer can be the option text', () {
      final p = parse([
        ['Question', 'Option A', 'Option B', 'Answer'],
        ['Capital of France', 'Paris', 'Rome', 'paris'],
      ]);
      expect(p.valid.single.question!.correctAnswerText, 'Paris');
    });

    test('advanced types: true/false, fill, matching, short, flashcard', () {
      final p = parse([
        ['Question ID', 'Type', 'Question', 'Option A', 'Option B', 'Option C', 'Correct Answer', 'Accepted Answers', 'Case Sensitive'],
        ['T1', 'True/False', 'The sun is a star.', '', '', '', 'True', '', ''],
        ['F1', 'Fill in the blank', 'Past of go: ___', '', '', '', 'went', 'Went', 'yes'],
        ['M1', 'Matching', 'Match', 'Dog => Bark', 'Cat => Meow', '', '', '', ''],
        ['S1', 'Short answer', 'Why do apples fall?', '', '', '', 'gravity | because of gravity', '', ''],
        ['C1', 'Flashcard', 'Ballpark figure', '', '', '', 'A rough estimate', '', ''],
      ]);
      expect(p.invalid, isEmpty);
      final byId = {for (final r in p.valid) r.question!.externalId: r.question!};
      expect(byId['T1']!.type, QuestionType.trueFalse);
      expect(byId['T1']!.options.firstWhere((o) => o.isCorrect).text, 'True');
      expect(byId['F1']!.acceptedAnswers, ['went', 'Went']);
      expect(byId['F1']!.caseSensitive, isTrue);
      expect(byId['M1']!.type, QuestionType.matching);
      expect(byId['M1']!.options.map((o) => o.matchText).toList(), ['Bark', 'Meow']);
      expect(byId['S1']!.acceptedAnswers, ['gravity', 'because of gravity']);
      expect(byId['C1']!.type, QuestionType.flashcard);
    });

    test('headers are matched flexibly and sheets without questions are skipped', () {
      final sheets = [
        XlsxSheet('Instructions', [XlsxRow(1, ['Fill in the Questions sheet. Each row is one question.'])]),
        XlsxSheet('Data', [
          XlsxRow(1, ['  question text ', 'choice a', 'choice b', 'correct_answer']),
          XlsxRow(2, ['Q', 'a', 'b', 'a']),
        ]),
      ];
      final p = QuestionParser.parse(sheets);
      expect(p.notices.single, contains('Instructions'));
      expect(p.sheetsRead, 1);
      expect(p.valid.single.question!.options.first.isCorrect, isTrue);
    });

    test('duplicates inside a file are flagged', () {
      final p = parse([
        ['Question', 'Option A', 'Option B', 'Correct Answer'],
        ['Same?', 'yes', 'no', 'A'],
        ['  same? ', 'no', 'yes', 'B'],
        ['Different', 'yes', 'no', 'A'],
      ]);
      expect(p.duplicatesInFile, 1);
      expect(p.valid[1].duplicateInFile, isTrue);
    });

    test('unknown difficulty is a warning, not an error', () {
      final p = parse([
        ['Question', 'Option A', 'Option B', 'Correct Answer', 'Difficulty'],
        ['Q', 'a', 'b', 'A', 'Impossible'],
      ]);
      expect(p.valid.single.warnings.single, contains('Unknown difficulty'));
    });

    test('blank rows are ignored and row numbers are reported', () {
      final p = parse([
        ['Question', 'Option A', 'Option B', 'Correct Answer'],
        ['', '', '', ''],
        ['Q', 'a', '', 'A'],
      ]);
      expect(p.rows.length, 1);
      expect(p.invalid.single.errors.first, contains('row 3'));
    });

    test('fingerprint ignores option order, case and punctuation', () {
      final a = Question(id: '1', bankId: 'b', type: QuestionType.single, text: 'Hello, world?', options: [
        AnswerOption(id: 'x', text: 'A'),
        AnswerOption(id: 'y', text: 'B'),
      ]);
      final b = Question(id: '2', bankId: 'b', type: QuestionType.single, text: 'hello world', options: [
        AnswerOption(id: 'z', text: 'b'),
        AnswerOption(id: 'w', text: 'a'),
      ]);
      expect(questionFingerprint(a), questionFingerprint(b));
      expect(questionFingerprint(a).length, 16);
    });
  });

  group('bundled templates', () {
    for (final name in ['QuizMe_Simple_Template', 'QuizMe_Advanced_Template', 'QuizMe_Examples']) {
      test('$name.xlsx imports without errors', () {
        final bytes = File('assets/templates/$name.xlsx').readAsBytesSync();
        final parsed = QuestionParser.parse(XlsxReader.read(bytes));
        expect(parsed.invalid.map((r) => r.errors).toList(), isEmpty);
        expect(parsed.valid, isNotEmpty);
        expect(parsed.notices.single, contains('How to use'));
      });
    }

    test('advanced template covers every question type', () {
      final bytes = File('assets/templates/QuizMe_Advanced_Template.xlsx').readAsBytesSync();
      final types = QuestionParser.parse(XlsxReader.read(bytes)).valid.map((r) => r.question!.type).toSet();
      expect(types, QuestionType.values.toSet());
    });
  });
}
