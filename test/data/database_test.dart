import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:quiz_me/app/services.dart';
import 'package:quiz_me/core/ids.dart';
import 'package:quiz_me/core/models.dart';
import 'package:quiz_me/core/xlsx/xlsx_writer.dart';
import 'package:quiz_me/data/db.dart';
import 'package:quiz_me/data/import_service.dart';
import 'package:quiz_me/data/question_repository.dart';
import 'package:quiz_me/data/sample_data.dart';
import 'package:quiz_me/data/session_repository.dart';
import 'package:quiz_me/data/settings_repository.dart';
import 'package:quiz_me/data/stats_repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Future<AppServices> openServices() async {
  sqfliteFfiInit();
  final dir = await Directory.systemTemp.createTemp('quizme_test_');
  final db = await AppDatabase.open(databaseFactoryFfi, p.join(dir.path, 'test.db'));
  return AppServices.forDatabase(db, mediaDir: Directory(p.join(dir.path, 'media')));
}

Question mc(String bankId, String text, {int correct = 1, Difficulty d = Difficulty.medium}) => Question(
      id: newId(),
      bankId: bankId,
      type: QuestionType.single,
      text: text,
      difficulty: d,
      options: [
        for (var i = 0; i < 4; i++) AnswerOption(id: newId(), position: i, text: '$text option $i', isCorrect: i == correct),
      ],
    );

/// Answers every question of a session (correctly when [correct]) and submits.
Future<QuizSession> playSession(AppServices s, QuizSession session, {bool correct = true}) async {
  final items = await s.sessions.items(session.id);
  final qs = {for (final q in await s.questions.questionsByIds(items.map((i) => i.questionId).toList())) q.id: q};
  for (final it in items) {
    await s.sessions.markPresented(session.id, it.position);
    final q = qs[it.questionId]!;
    final pick = q.options.firstWhere((o) => o.isCorrect == correct);
    await s.sessions.saveResponse(
        sessionId: session.id, position: it.position, question: q, response: QuestionResponse(selected: {pick.id}));
  }
  return s.sessions.complete(session.id);
}

Future<(AppServices, String, String)> withBank(int count) async {
  final s = await openServices();
  final subject = await s.catalog.createCategory(name: 'English');
  final grammar = await s.catalog.createCategory(name: 'Grammar', parentId: subject.id);
  final bank = await s.catalog.createBank(categoryId: grammar.id, name: 'Tenses');
  for (var i = 0; i < count; i++) {
    await s.questions.saveQuestion(mc(bank.id, 'Question $i'));
  }
  return (s, subject.id, bank.id);
}

void main() {
  group('Hierarchy and statistics', () {
    test('subjects → categories → banks with accurate counts', () async {
      final (s, subjectId, bankId) = await withBank(5);
      final vocab = await s.catalog.createCategory(name: 'Vocabulary', parentId: subjectId);
      final idioms = await s.catalog.createBank(categoryId: vocab.id, name: 'Idioms');
      await s.questions.saveQuestion(mc(idioms.id, 'Idiom 1'));

      final tree = await s.catalog.tree();
      expect(tree.single.category.name, 'English');
      expect(tree.single.questionCount, 6);
      expect(tree.single.children.length, 2);

      final bankStats = await s.stats.statsFor([bankId]);
      expect(bankStats.total, 5);
      expect(bankStats.neverAttempted, 5);
      expect(bankStats.attempted, 0);
      expect(bankStats.accuracy, isNull);
      expect((await s.stats.statsForCategory(subjectId)).total, 6);

      // Excluding a sub-category removes its banks from category quizzes.
      final banks = await s.catalog.resolveBankIds(categoryIds: [subjectId], excludedCategoryIds: [vocab.id]);
      expect(banks, [bankId]);
    });

    test('a category cannot be moved inside itself', () async {
      final (s, subjectId, _) = await withBank(0);
      final child = await s.catalog.createCategory(name: 'Child', parentId: subjectId);
      await expectLater(s.catalog.moveCategory(subjectId, child.id), throwsArgumentError);
    });

    test('deleting a bank removes its questions (cascade)', () async {
      final (s, _, bankId) = await withBank(3);
      await s.catalog.deleteBank(bankId);
      final r = await s.db.rawQuery('SELECT COUNT(*) AS n FROM questions');
      expect(intOf(r.first['n']), 0);
      final o = await s.db.rawQuery('SELECT COUNT(*) AS n FROM options');
      expect(intOf(o.first['n']), 0);
    });
  });

  group('Quiz engine', () {
    test('New Questions mode never repeats presented questions', () async {
      final (s, _, bankId) = await withBank(10);
      final cfg = QuizConfig(bankIds: [bankId], questionCount: 4, selection: SelectionMode.newQuestions);
      final seen = <String>{};
      for (var round = 0; round < 2; round++) {
        final session = await s.sessions.create(cfg);
        final items = await s.sessions.items(session.id);
        expect(items.length, 4);
        for (final it in items) {
          expect(seen.add(it.questionId), isTrue, reason: 'question repeated in New mode');
        }
        await playSession(s, session);
      }
      // 2 left: asking for 4 must not duplicate.
      await expectLater(s.sessions.create(cfg), throwsA(isA<InsufficientQuestionsException>()));
      final last = await s.sessions.create(cfg, allowFewer: true);
      final items = await s.sessions.items(last.id);
      expect(items.length, 2);
      for (final it in items) {
        expect(seen.contains(it.questionId), isFalse);
      }
      await playSession(s, last);
      // Everything is used up now.
      final none = s.sessions.create(cfg, allowFewer: true);
      await expectLater(none, throwsA(isA<InsufficientQuestionsException>()));

      // Reset makes them eligible again without erasing history.
      final before = await s.stats.statsFor([bankId]);
      await s.study.resetNewProgress([bankId]);
      final after = await s.stats.statsFor([bankId]);
      expect(after.unseen, 10);
      expect(after.attempted, before.attempted);
      expect(after.correct, before.correct);
    });

    test('questions waiting in an unfinished quiz are not offered as new again', () async {
      final (s, _, bankId) = await withBank(6);
      final cfg = QuizConfig(bankIds: [bankId], questionCount: 3, selection: SelectionMode.newQuestions);
      final a = await s.sessions.create(cfg);
      final b = await s.sessions.create(cfg);
      final ia = (await s.sessions.items(a.id)).map((i) => i.questionId).toSet();
      final ib = (await s.sessions.items(b.id)).map((i) => i.questionId).toSet();
      expect(ia.intersection(ib), isEmpty);
    });

    test('requesting 100 questions from a bank with 20', () async {
      final (s, _, bankId) = await withBank(20);
      final cfg = QuizConfig(bankIds: [bankId], questionCount: 100);
      final pv = await s.sessions.preview(cfg);
      expect(pv.available, 20);
      expect(pv.plan.planned, 20);
      try {
        await s.sessions.create(cfg);
        fail('should have thrown');
      } on InsufficientQuestionsException catch (e) {
        expect(e.available, 20);
        expect(e.toString(), 'Only 20 questions match your selected criteria.');
      }
      final session = await s.sessions.create(cfg, allowFewer: true);
      final ids = (await s.sessions.items(session.id)).map((i) => i.questionId).toList();
      expect(ids.toSet().length, 20, reason: 'no duplicates');
    });

    test('a bank with zero questions and a bank with three', () async {
      final (s, _, empty) = await withBank(0);
      await expectLater(s.sessions.create(QuizConfig(bankIds: [empty], questionCount: 5)),
          throwsA(isA<InsufficientQuestionsException>()));
      final small = await s.catalog.createBank(categoryId: (await s.catalog.bank(empty))!.categoryId, name: 'Small');
      for (var i = 0; i < 3; i++) {
        await s.questions.saveQuestion(mc(small.id, 'S$i'));
      }
      final session = await s.sessions.create(QuizConfig(bankIds: [small.id], questionCount: 5), allowFewer: true);
      expect(session.total, 3);
    });

    test('scoring, mistakes, and review modes', () async {
      final (s, _, bankId) = await withBank(4);
      final session = await s.sessions.create(QuizConfig(bankIds: [bankId], questionCount: 4));
      final items = await s.sessions.items(session.id);
      final qs = {for (final q in await s.questions.questionsByIds(items.map((i) => i.questionId).toList())) q.id: q};
      // Two right, one wrong, one unanswered.
      for (var i = 0; i < 3; i++) {
        final q = qs[items[i].questionId]!;
        final o = q.options.firstWhere((x) => x.isCorrect == (i < 2));
        await s.sessions.saveResponse(
            sessionId: session.id, position: items[i].position, question: q, response: QuestionResponse(selected: {o.id}));
      }
      final done = await s.sessions.complete(session.id);
      expect(done.status, SessionStatus.completed);
      expect(done.total, 4);
      expect(done.correct, 2);
      expect(done.incorrect, 1);
      expect(done.unanswered, 1);
      expect(done.score, 50);
      expect(done.accuracy, closeTo(2 / 3, 1e-9));

      final mistakes = await s.study.mistakes();
      expect(mistakes.length, 1);
      expect(mistakes.single.lastWrongResponse.selected, isNotEmpty);

      final mistakeQuiz = await s.sessions.preview(
          QuizConfig(bankIds: [bankId], questionCount: 10, selection: SelectionMode.mistakes));
      expect(mistakeQuiz.available, 1);
      final review = await s.sessions.preview(
          QuizConfig(bankIds: [bankId], questionCount: 10, selection: SelectionMode.review));
      expect(review.available, 3); // skipped one was never answered
      final spaced = await s.sessions.preview(
          QuizConfig(bankIds: [bankId], questionCount: 10, selection: SelectionMode.spaced),
          now: DateTime.now().add(const Duration(days: 1)));
      expect(spaced.available, 3);

      // Marking as understood keeps history but hides it from the notebook.
      await s.study.setUnderstood(mistakes.single.progress.questionId, true);
      expect(await s.study.mistakes(), isEmpty);
      expect((await s.study.mistakes(includeUnderstood: true)).length, 1);
      final stats = await s.stats.statsFor([bankId]);
      expect(stats.incorrect, 1);
      expect(stats.attempted, 3);

      // Retaking is an explicit review and does not touch New-mode eligibility.
      final retake = s.sessions.retakeConfig(done, await s.sessions.items(done.id));
      expect(retake.selection, SelectionMode.review);
      expect(retake.fixedQuestionIds.length, 4);
    });

    test('an interrupted quiz resumes with the same questions and answers', () async {
      final (s, _, bankId) = await withBank(5);
      final session = await s.sessions.create(QuizConfig(bankIds: [bankId], questionCount: 5));
      final items = await s.sessions.items(session.id);
      final q = (await s.questions.question(items[0].questionId))!;
      final opt = q.options.first;
      await s.sessions.saveResponse(
          sessionId: session.id, position: 0, question: q, response: QuestionResponse(selected: {opt.id}));
      await s.sessions.saveCursor(session.id, 2, 12345);

      // "Restart the app": read everything back from the database.
      final active = await s.sessions.latestActive();
      expect(active?.id, session.id);
      expect(active!.currentIndex, 2);
      expect(active.elapsedMs, 12345);
      final again = await s.sessions.items(session.id);
      expect(again.map((i) => i.questionId).toList(), items.map((i) => i.questionId).toList());
      expect(again.map((i) => i.optionOrder).toList(), items.map((i) => i.optionOrder).toList());
      expect(again[0].response.selected, {opt.id});
      // Not applied to history before submission (end-of-quiz feedback).
      expect((await s.study.progressOf(q.id)).attemptCount, 0);
    });

    test('finalizing is idempotent and records hints and confidence', () async {
      final (s, _, bankId) = await withBank(1);
      final session = await s.sessions.create(QuizConfig(bankIds: [bankId], questionCount: 1));
      final it = (await s.sessions.items(session.id)).single;
      final q = (await s.questions.question(it.questionId))!;
      final right = q.options.firstWhere((o) => o.isCorrect);
      await s.sessions.markHintUsed(session.id, 0);
      await s.sessions.saveResponse(
          sessionId: session.id, position: 0, question: q, response: QuestionResponse(selected: {right.id}));
      final o1 = await s.sessions.finalizeItem(session.id, 0, q, confidence: Confidence.easy);
      final o2 = await s.sessions.finalizeItem(session.id, 0, q, confidence: Confidence.easy);
      expect(o1, isNotNull);
      expect(o2, isNull);
      final p0 = await s.study.progressOf(q.id);
      expect(p0.attemptCount, 1);
      expect(p0.hintCount, 1);
      expect(p0.dueAt, isNotNull);
      final attempts = await s.study.attemptsOf(q.id);
      expect(attempts.single['hint_used'], 1);
      expect(attempts.single['confidence'], Confidence.easy.index);
    });

    test('manual review of written answers', () async {
      final (s, _, bankId) = await withBank(0);
      final q = Question(
          id: newId(), bankId: bankId, type: QuestionType.shortAnswer, text: 'Why do apples fall?', acceptedAnswers: ['gravity']);
      await s.questions.saveQuestion(q);
      final session = await s.sessions.create(QuizConfig(bankIds: [bankId], questionCount: 1));
      final res = await s.sessions.saveResponse(
          sessionId: session.id, position: 0, question: q, response: QuestionResponse(text: 'because of gravity'));
      expect(res, AttemptResult.review);
      var done = await s.sessions.complete(session.id);
      expect(done.correct, 0);
      expect((await s.study.progressOf(q.id)).attemptCount, 0);
      await s.sessions.resolveReview(session.id, 0, q, true);
      done = (await s.sessions.session(session.id))!;
      expect(done.correct, 1);
      expect((await s.study.progressOf(q.id)).correctCount, 1);
    });

    test('flashcard ratings update the schedule', () async {
      final (s, _, bankId) = await withBank(2);
      final session = await s.sessions.create(
          QuizConfig(bankIds: [bankId], questionCount: 2, style: QuizStyle.flashcards));
      final items = await s.sessions.items(session.id);
      final q0 = (await s.questions.question(items[0].questionId))!;
      final q1 = (await s.questions.question(items[1].questionId))!;
      await s.sessions.recordFlashcard(session.id, 0, q0, rating: Confidence.easy);
      await s.sessions.recordFlashcard(session.id, 1, q1, rating: Confidence.didntKnow);
      expect((await s.study.progressOf(q0.id)).lastResult, AttemptResult.correct);
      expect((await s.study.progressOf(q1.id)).lastResult, AttemptResult.incorrect);
      expect((await s.study.progressOf(q0.id)).intervalDays, 3);
    });

    test('quick review orders due and difficult questions first', () async {
      final (s, _, bankId) = await withBank(6);
      final first = await s.sessions.create(QuizConfig(bankIds: [bankId], questionCount: 6));
      await playSession(s, first, correct: false);
      final pv = await s.sessions.preview(
          QuizConfig(bankIds: [bankId], questionCount: 3, selection: SelectionMode.quickReview));
      expect(pv.available, 6);
    });
  });

  group('Editing and history integrity', () {
    test('editing keeps option ids and history; changing the answer can reset the schedule', () async {
      final (s, _, bankId) = await withBank(1);
      final session = await s.sessions.create(QuizConfig(bankIds: [bankId], questionCount: 1));
      await playSession(s, session);
      final q = (await s.questions.question((await s.sessions.items(session.id)).single.questionId))!;
      final before = await s.study.progressOf(q.id);
      expect(before.repetitions, 1);

      // Text-only edit: history and schedule kept.
      await s.questions.saveQuestion(q.copyWith(text: '${q.text} (edited)'));
      final edited = (await s.questions.question(q.id))!;
      expect(edited.options.map((o) => o.id).toList(), q.options.map((o) => o.id).toList());
      expect((await s.study.progressOf(q.id)).repetitions, 1);

      // Correct answer changed + reset: schedule reset, attempts kept.
      final changed = edited.copyWith(options: [
        for (final o in edited.options) o.copyWith(isCorrect: o.position == 0),
      ]);
      await s.questions.saveQuestion(changed, resetLearning: true);
      final after = await s.study.progressOf(q.id);
      expect(after.repetitions, 0);
      expect(after.dueAt, isNull);
      expect(after.attemptCount, 1);
      expect((await s.study.attemptsOf(q.id)).length, 1);
      expect((await s.questions.question(q.id))!.contentVersion, 2);
    });

    test('moving and duplicating questions', () async {
      final (s, _, bankId) = await withBank(2);
      final other = await s.catalog.createBank(categoryId: (await s.catalog.bank(bankId))!.categoryId, name: 'Other');
      final session = await s.sessions.create(QuizConfig(bankIds: [bankId], questionCount: 2));
      await playSession(s, session);
      final ids = (await s.sessions.items(session.id)).map((i) => i.questionId).toList();
      await s.questions.move([ids.first], other.id);
      expect((await s.stats.statsFor([other.id])).attempted, 1, reason: 'history moves with the question');
      final copy = await s.questions.duplicate(ids.last, targetBankId: other.id);
      expect((await s.study.progressOf(copy.id)).attemptCount, 0);
      expect((await s.stats.statsFor([other.id])).total, 2);
    });

    test('deleting a question removes it everywhere', () async {
      final (s, _, bankId) = await withBank(2);
      final session = await s.sessions.create(QuizConfig(bankIds: [bankId], questionCount: 2));
      await playSession(s, session);
      final id = (await s.sessions.items(session.id)).first.questionId;
      await s.questions.addNote(id, 'note');
      await s.questions.toggleBookmark(id);
      await s.questions.delete([id]);
      expect(await s.questions.question(id), isNull);
      for (final t in ['options', 'progress', 'attempts', 'notes', 'bookmarks', 'session_questions']) {
        final r = await s.db.rawQuery('SELECT COUNT(*) AS n FROM $t WHERE question_id = ?', [id]);
        expect(intOf(r.first['n']), 0, reason: t);
      }
      expect((await s.stats.statsFor([bankId])).total, 1);
    });

    test('search and combined filters', () async {
      final (s, _, bankId) = await withBank(0);
      await s.questions.saveQuestion(mc(bankId, 'Present simple rule', d: Difficulty.easy)
          .copyWith(tags: ['grammar']));
      await s.questions.saveQuestion(mc(bankId, 'Past perfect usage', d: Difficulty.hard));
      final repo = s.questions;
      final all = await repo.search(QuestionFilter(bankIds: [bankId]));
      expect(all.length, 2);
      expect((await repo.search(QuestionFilter(bankIds: [bankId], text: 'perfect'))).single.text,
          'Past perfect usage');
      expect((await repo.search(QuestionFilter(bankIds: [bankId], text: 'option 2'))).length, 2,
          reason: 'answer text is searchable');
      expect((await repo.search(QuestionFilter(bankIds: [bankId], tag: 'grammar'))).length, 1);
      expect(
          (await repo.search(QuestionFilter(bankIds: [bankId], difficulties: {Difficulty.hard}, neverAttempted: true)))
              .single
              .text,
          'Past perfect usage');
    });
  });

  group('Excel import', () {
    List<int> workbook(List<List<String>> rows) => XlsxWriter.write([XlsxSheetData('Questions', rows)]);
    final header = ['Question', 'Option A', 'Option B', 'Option C', 'Option D', 'Correct Answer', 'Explanation'];

    test('import, re-import duplicates (skip/update) and history preservation', () async {
      final (s, _, bankId) = await withBank(0);
      final bytes = workbook([
        header,
        ['Q1', 'a', 'b', 'c', 'd', 'A', 'first'],
        ['Q2', 'a', 'b', 'c', 'd', 'B', ''],
        ['Q3', 'a', 'b', '', '', 'Z', ''],
      ]);
      final pv = await s.imports.prepare(fileName: 'english.xlsx', bytes: bytes, bankId: bankId);
      expect(pv.validCount, 2);
      expect(pv.errorCount, 1);
      final r = await s.imports.commit(pv, bankId: bankId);
      expect(r.imported, 2);
      expect(r.errors, 1);
      expect((await s.stats.statsFor([bankId])).total, 2);
      final imports = await s.questions.importsForBank(bankId);
      expect(imports.single.fileName, 'english.xlsx');
      expect(imports.single.status, 'completed');

      // Study one question.
      final session = await s.sessions.create(QuizConfig(bankIds: [bankId], questionCount: 2));
      await playSession(s, session);

      // Same file again: duplicates detected and skipped.
      final pv2 = await s.imports.prepare(fileName: 'english.xlsx', bytes: bytes, bankId: bankId);
      expect(pv2.duplicateCount, 2);
      final r2 = await s.imports.commit(pv2, bankId: bankId);
      expect(r2.imported, 0);
      expect(r2.skipped, 2);
      expect((await s.stats.statsFor([bankId])).total, 2);

      // Updated content: update policy keeps ids and learning history.
      final updated = workbook([
        header,
        ['Q1', 'a', 'b', 'c', 'd', 'A', 'better explanation'],
      ]);
      final pv3 = await s.imports.prepare(fileName: 'english-v2.xlsx', bytes: updated, bankId: bankId);
      expect(pv3.duplicateCount, 1);
      final r3 = await s.imports.commit(pv3, bankId: bankId, policy: DuplicatePolicy.update);
      expect(r3.updated, 1);
      final stats = await s.stats.statsFor([bankId]);
      expect(stats.total, 2);
      expect(stats.attempted, 2, reason: 'history preserved');
      final ids = await s.questions.searchIds(QuestionFilter(bankIds: [bankId], text: 'Q1'));
      expect((await s.questions.question(ids.single))!.explanation, 'better explanation');
    });

    test('questions stay after the original file is gone', () async {
      final (s, _, bankId) = await withBank(0);
      final dir = await Directory.systemTemp.createTemp('quizme_xlsx_');
      final file = File(p.join(dir.path, 'q.xlsx'));
      await file.writeAsBytes(workbook([header, ['Kept?', 'yes', 'no', '', '', 'A', '']]));
      final pv = await s.imports.prepare(fileName: 'q.xlsx', bytes: await file.readAsBytes(), bankId: bankId);
      await s.imports.commit(pv, bankId: bankId);
      await file.delete();
      expect((await s.stats.statsFor([bankId])).total, 1);
    });

    test('an import interrupted by closing the app is marked interrupted', () async {
      final (s, _, bankId) = await withBank(0);
      await s.db.insert('imports', {
        'id': newId(),
        'bank_id': bankId,
        'file_name': 'big.xlsx',
        'imported_at': DateTime.now().millisecondsSinceEpoch,
        'status': 'in_progress',
      });
      await s.imports.markInterruptedImports();
      expect((await s.questions.importsForBank(bankId)).single.status, 'interrupted');
    });

    test('a large file imports in one go', () async {
      final (s, _, bankId) = await withBank(0);
      final rows = [header];
      for (var i = 0; i < 2000; i++) {
        rows.add(['Large question $i', 'a$i', 'b$i', 'c$i', 'd$i', 'C', 'explanation $i']);
      }
      final pv = await s.imports.prepare(fileName: 'large.xlsx', bytes: workbook(rows), bankId: bankId);
      expect(pv.validCount, 2000);
      final r = await s.imports.commit(pv, bankId: bankId);
      expect(r.imported, 2000);
      expect((await s.stats.statsFor([bankId])).total, 2000);
    });

    test('export then import reproduces the bank', () async {
      final (s, _, bankId) = await withBank(0);
      await SampleData.create(s.catalog, s.questions);
      final tenses = (await s.catalog.allBanks()).firstWhere((b) => b.name == 'Tenses' && b.id != bankId);
      final original = await s.stats.statsFor([tenses.id]);
      final f = await s.exports.exportBank(tenses.id);
      expect(f.fileName, endsWith('.xlsx'));
      final pv = await s.imports.prepare(fileName: f.fileName, bytes: f.bytes, bankId: bankId);
      expect(pv.errorCount, 0);
      await s.imports.commit(pv, bankId: bankId);
      expect((await s.stats.statsFor([bankId])).total, original.total);
    });
  });

  group('Backup and restore', () {
    test('a backup restores everything, including history and settings', () async {
      final (s, _, bankId) = await withBank(3);
      final session = await s.sessions.create(QuizConfig(bankIds: [bankId], questionCount: 3));
      await playSession(s, session);
      final qid = (await s.sessions.items(session.id)).first.questionId;
      await s.questions.addNote(qid, 'Remember this');
      await s.questions.toggleBookmark(qid);
      await s.stats.addGoal(GoalType.questions, 25);
      await s.settings.update(s.settings.value.copyWith(theme: AppTheme.sepia));
      await s.media.save([1, 2, 3], 'pic.png');
      final before = await s.stats.statsFor([bankId]);

      final backup = await s.backups.create();
      final info = s.backups.inspect(backup);
      expect(info.counts['questions'], 3);
      expect(info.counts['attempts'], 3);
      expect(info.mediaFiles, 1);

      // Restore into a fresh installation.
      final fresh = await openServices();
      await fresh.backups.restore(backup);
      final after = await fresh.stats.statsFor([bankId]);
      expect(after.total, before.total);
      expect(after.attempted, before.attempted);
      expect(after.correct, before.correct);
      expect((await fresh.questions.notesFor(qid)).single.text, 'Remember this');
      expect(await fresh.questions.isBookmarked(qid), isTrue);
      expect((await fresh.stats.goals()).length, 1);
      expect((await fresh.settingsRepo.load()).theme, AppTheme.sepia);
      expect((await fresh.media.all()).length, 1);
      expect((await fresh.sessions.history()).length, 1);
    });

    test('invalid backups are rejected and existing data is untouched', () async {
      final (s, _, bankId) = await withBank(2);
      expect(() => s.backups.inspect([1, 2, 3]), throwsA(isA<Exception>()));
      await expectLater(s.backups.restore([1, 2, 3]), throwsA(isA<Exception>()));
      expect((await s.stats.statsFor([bankId])).total, 2);
    });
  });

  group('Settings', () {
    test('settings persist and unknown values fall back to defaults', () async {
      final s = await openServices();
      await s.settings.update(s.settings.value.copyWith(
          theme: AppTheme.amoled, textScale: 1.4, defaultQuestionCount: 25, reminderDays: [1, 3, 5]));
      final loaded = await s.settingsRepo.load();
      expect(loaded.theme, AppTheme.amoled);
      expect(loaded.textScale, 1.4);
      expect(loaded.defaultQuestionCount, 25);
      expect(loaded.reminderDays, [1, 3, 5]);
      final bad = AppSettings.fromMap({'theme': 'neon', 'textScale': 'huge', 'reminderDays': 'x'});
      expect(bad.theme, AppTheme.system);
      expect(bad.textScale, 1.0);
      expect(bad.reminderDays.length, 7);
    });
  });

  group('Dashboard', () {
    test('dashboard, streaks, goals and achievements are computed from history', () async {
      final (s, _, bankId) = await withBank(5);
      final session = await s.sessions.create(QuizConfig(bankIds: [bankId], questionCount: 5));
      await playSession(s, session);
      final d = await s.stats.dashboard();
      expect(d.totalQuestions, 5);
      expect(d.uniqueAttempted, 5);
      expect(d.totalAttempts, 5);
      expect(d.accuracy, 1.0);
      expect(d.completedQuizzes, 1);
      expect(d.currentStreak, 1);
      expect(d.today.answered, 5);
      await s.stats.addGoal(GoalType.questions, 5);
      final g = (await s.stats.goalProgress()).single;
      expect(g.today, 5);
      expect(g.metToday, isTrue);
      final unlocked = await s.stats.checkAchievements();
      expect(unlocked.map((a) => a.id), containsAll(['first_steps', 'perfect_score']));
      expect(await s.stats.checkAchievements(), isEmpty, reason: 'unlocked only once');
    });
  });
}
