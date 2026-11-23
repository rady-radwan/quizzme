import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:quiz_me/core/distribution.dart';
import 'package:quiz_me/core/grading.dart';
import 'package:quiz_me/core/models.dart';
import 'package:quiz_me/core/shuffle.dart';

Question mcq({List<String> texts = const ['go', 'goes', 'going', 'gone'], Set<int> correct = const {1}, QuestionType type = QuestionType.single, bool shuffle = true}) =>
    Question(
      id: 'q1',
      bankId: 'b',
      type: type,
      text: 'He ___ to work.',
      shuffleOptions: shuffle,
      options: [
        for (var i = 0; i < texts.length; i++)
          AnswerOption(id: 'o$i', position: i, text: texts[i], isCorrect: correct.contains(i)),
      ],
    );

void main() {
  group('Grading', () {
    test('single choice is graded by option id', () {
      final q = mcq();
      expect(grade(q, QuestionResponse(selected: {'o1'})), GradeOutcome.correct);
      expect(grade(q, QuestionResponse(selected: {'o0'})), GradeOutcome.incorrect);
      expect(grade(q, QuestionResponse()), GradeOutcome.unanswered);
    });

    test('multiple answers require the exact set', () {
      final q = mcq(type: QuestionType.multiple, correct: {0, 2});
      expect(grade(q, QuestionResponse(selected: {'o0', 'o2'})), GradeOutcome.correct);
      expect(grade(q, QuestionResponse(selected: {'o0'})), GradeOutcome.incorrect);
      expect(grade(q, QuestionResponse(selected: {'o0', 'o2', 'o3'})), GradeOutcome.incorrect);
    });

    test('fill in the blank: case-insensitive with alternatives', () {
      final q = Question(
          id: 'f', bankId: 'b', type: QuestionType.fillBlank, text: 'Past of buy: ___', acceptedAnswers: ['bought', 'Bought it']);
      expect(grade(q, QuestionResponse(text: '  BOUGHT. ')), GradeOutcome.correct);
      expect(grade(q, QuestionResponse(text: 'bought  it')), GradeOutcome.correct);
      expect(grade(q, QuestionResponse(text: 'buyed')), GradeOutcome.incorrect);
    });

    test('fill in the blank: case sensitive when configured', () {
      final q = Question(
          id: 'f', bankId: 'b', type: QuestionType.fillBlank, text: 'Capital', acceptedAnswers: ['Paris'], caseSensitive: true);
      expect(grade(q, QuestionResponse(text: 'Paris')), GradeOutcome.correct);
      expect(grade(q, QuestionResponse(text: 'paris')), GradeOutcome.incorrect);
    });

    test('short answers that do not match go to manual review', () {
      final q = Question(id: 's', bankId: 'b', type: QuestionType.shortAnswer, text: 'Why?', acceptedAnswers: ['gravity']);
      expect(grade(q, QuestionResponse(text: 'Gravity')), GradeOutcome.correct);
      expect(grade(q, QuestionResponse(text: 'because of gravity')), GradeOutcome.needsReview);
      expect(grade(q, QuestionResponse(text: 'because of gravity', selfGrade: true)), GradeOutcome.correct);
      expect(grade(q, QuestionResponse(text: 'x', selfGrade: false)), GradeOutcome.incorrect);
    });

    test('matching compares pairs', () {
      final q = Question(id: 'm', bankId: 'b', type: QuestionType.matching, text: 'Match', options: [
        AnswerOption(id: 'a', text: 'Dog', matchText: 'Bark', isCorrect: true),
        AnswerOption(id: 'b', text: 'Cat', matchText: 'Meow', isCorrect: true),
      ]);
      expect(grade(q, QuestionResponse(matches: {'a': 'a', 'b': 'b'})), GradeOutcome.correct);
      expect(grade(q, QuestionResponse(matches: {'a': 'b', 'b': 'a'})), GradeOutcome.incorrect);
      expect(grade(q, QuestionResponse(matches: {'a': 'a'})), GradeOutcome.unanswered);
    });

    test('a question with no explanation still describes answers', () {
      final q = mcq();
      expect(describeResponse(q, QuestionResponse(selected: {'o1'})), 'goes');
      expect(q.correctAnswerText, 'goes');
      expect(describeResponse(q, QuestionResponse()), 'No answer');
    });

    test('responses survive JSON round trip', () {
      final r = QuestionResponse(selected: {'a', 'b'}, text: 'x', matches: {'l': 'r'}, selfGrade: true);
      final back = QuestionResponse.decode(r.encode());
      expect(back.selected, {'a', 'b'});
      expect(back.text, 'x');
      expect(back.matches, {'l': 'r'});
      expect(back.selfGrade, isTrue);
      expect(QuestionResponse.decode('not json').isEmpty, isTrue);
    });
  });

  group('Answer shuffling', () {
    test('shuffling never changes which answer is correct', () {
      final q = mcq();
      final rnd = Random(42);
      var sawDifferentOrder = false;
      for (var i = 0; i < 500; i++) {
        final order = displayOrder(q, shuffle: true, random: rnd);
        expect(order.toSet(), {'o0', 'o1', 'o2', 'o3'});
        if (order.first != 'o0' || order[1] != 'o1') sawDifferentOrder = true;
        // The learner taps whatever is displayed at the position of "goes".
        final tapped = order[order.indexOf('o1')];
        expect(grade(q, QuestionResponse(selected: {tapped})), GradeOutcome.correct);
        final wrong = order.firstWhere((id) => id != 'o1');
        expect(grade(q, QuestionResponse(selected: {wrong})), GradeOutcome.incorrect);
      }
      expect(sawDifferentOrder, isTrue);
    });

    test('true/false and "All of the above" keep their order', () {
      final tf = mcq(texts: ['True', 'False'], correct: {0}, type: QuestionType.trueFalse);
      expect(displayOrder(tf, shuffle: true, random: Random(1)), ['o0', 'o1']);
      final all = mcq(texts: ['Red', 'Blue', 'Green', 'All of the above'], correct: {3});
      expect(displayOrder(all, shuffle: true, random: Random(1)), ['o0', 'o1', 'o2', 'o3']);
    });

    test('shuffling can be disabled per question', () {
      final q = mcq(shuffle: false);
      expect(displayOrder(q, shuffle: true, random: Random(3)), ['o0', 'o1', 'o2', 'o3']);
    });

    test('option letters', () {
      expect(optionLetter(0), 'A');
      expect(optionLetter(25), 'Z');
      expect(optionLetter(26), 'AA');
    });
  });

  group('Distribution across banks', () {
    test('automatic distribution is proportional and exact', () {
      final plan = planAutomatic({'a': 100, 'b': 50, 'c': 50}, 20);
      expect(plan.planned, 20);
      expect(plan.allocation['a'], 10);
      expect(plan.allocation['b'], 5);
      expect(plan.allocation['c'], 5);
    });

    test('never takes more than a bank has (100 requested, 20 available)', () {
      final plan = planAutomatic({'a': 20}, 100);
      expect(plan.planned, 20);
      expect(plan.isShort, isTrue);
      expect(plan.available, 20);
    });

    test('a bank with zero questions gets nothing', () {
      final plan = planAutomatic({'a': 0, 'b': 3}, 10);
      expect(plan.allocation['a'], 0);
      expect(plan.allocation['b'], 3);
    });

    test('manual distribution reports shortages', () {
      final plan = planManual({'g': 30, 'v': 10, 'i': 4}, {'g': 20, 'v': 20, 'i': 10});
      expect(plan.allocation, {'g': 20, 'v': 10, 'i': 4});
      expect(plan.shortages, {'v': 10, 'i': 6});
      expect(plan.requested, 50);
      expect(plan.isShort, isTrue);
    });

    test('adaptive difficulty targets', () {
      expect(adaptiveDifficultyTarget(null), [0, 1]);
      expect(adaptiveDifficultyTarget(0.9), [2, 3]);
      expect(adaptiveDifficultyTarget(0.7), [1, 2]);
      expect(adaptiveDifficultyTarget(0.4), [0, 1]);
    });
  });
}
