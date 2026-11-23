import '../core/ids.dart';
import '../core/import/fingerprint.dart';
import '../core/models.dart';
import 'catalog_repository.dart';
import 'question_repository.dart';

/// Creates a small example subject so a new user can try every feature
/// immediately. Safe to delete afterwards like any other subject.
class SampleData {
  static Future<void> create(CatalogRepository catalog, QuestionRepository questions) async {
    final english = await catalog.createCategory(
        name: 'English (sample)', iconKey: 'language', color: 0xFF3F51B5,
        description: 'Example questions — delete this subject whenever you like.');
    final grammar = await catalog.createCategory(name: 'Grammar', parentId: english.id, iconKey: 'grammar');
    final tenses = await catalog.createBank(categoryId: grammar.id, name: 'Tenses', iconKey: 'quiz');
    final vocab = await catalog.createCategory(name: 'Vocabulary', parentId: english.id, iconKey: 'book');
    final idioms = await catalog.createBank(categoryId: vocab.id, name: 'Idioms', iconKey: 'chat');

    AnswerOption o(String t, [bool c = false, String? why]) =>
        AnswerOption(id: newId(), text: t, isCorrect: c, explanation: why);

    final list = <Question>[
      Question(
        id: newId(),
        bankId: tenses.id,
        type: QuestionType.single,
        text: 'Which sentence is grammatically correct?',
        options: [
          o('He go to work every day.', false, '"Go" needs an -s with he/she/it.'),
          o('He goes to work every day.', true),
          o('He going to work every day.', false, 'The -ing form needs a helping verb: "is going".'),
          o('He gone to work every day.', false, '"Gone" is a past participle and needs "has".'),
        ],
        hint: 'Remember the third-person singular rule.',
        correctFeedback: 'Excellent! The verb takes an "-s" with he, she, and it in the simple present tense.',
        incorrectFeedback:
            'Not quite. Remember that third-person singular subjects normally require a verb ending in "-s" in the simple present tense.',
        explanation:
            'In the simple present tense, third-person singular subjects such as he, she, and it require the verb to end in "-s" or "-es" in affirmative statements.',
        difficulty: Difficulty.easy,
        tags: ['present simple'],
      ),
      Question(
        id: newId(),
        bankId: tenses.id,
        type: QuestionType.single,
        text: 'By the time we arrived, the movie ___.',
        options: [o('has started'), o('had started', true), o('starts'), o('was start')],
        explanation: 'Use the past perfect for an action completed before another past action.',
        difficulty: Difficulty.medium,
        tags: ['past perfect'],
      ),
      Question(
        id: newId(),
        bankId: tenses.id,
        type: QuestionType.multiple,
        text: 'Which sentences use the present perfect correctly? (Select all that apply.)',
        options: [
          o('I have lived here since 2020.', true),
          o('I have seen him yesterday.', false, 'A finished time ("yesterday") needs the past simple.'),
          o('She has already finished her report.', true),
          o('They have went home.', false, 'The participle of "go" is "gone".'),
        ],
        explanation: 'The present perfect connects the past to now and is not used with a finished time.',
        difficulty: Difficulty.hard,
        tags: ['present perfect'],
      ),
      Question(
        id: newId(),
        bankId: tenses.id,
        type: QuestionType.trueFalse,
        text: '"I am knowing the answer" is correct standard English.',
        options: [o('True'), o('False', true)],
        explanation: '"Know" is a stative verb and is not normally used in continuous tenses.',
        difficulty: Difficulty.medium,
      ),
      Question(
        id: newId(),
        bankId: tenses.id,
        type: QuestionType.fillBlank,
        text: 'Yesterday I ___ (buy) a new laptop.',
        acceptedAnswers: ['bought'],
        explanation: '"Buy" is irregular: buy – bought – bought.',
        difficulty: Difficulty.easy,
        tags: ['irregular verbs'],
      ),
      Question(
        id: newId(),
        bankId: tenses.id,
        type: QuestionType.matching,
        text: 'Match each sentence with its tense.',
        options: [
          AnswerOption(id: newId(), text: 'She works here.', matchText: 'Present simple', isCorrect: true),
          AnswerOption(id: newId(), text: 'She is working now.', matchText: 'Present continuous', isCorrect: true),
          AnswerOption(id: newId(), text: 'She has worked here for years.', matchText: 'Present perfect', isCorrect: true),
        ],
        difficulty: Difficulty.medium,
      ),
      Question(
        id: newId(),
        bankId: idioms.id,
        type: QuestionType.single,
        text: 'What does "to touch base" mean in business English?',
        options: [
          o('To make brief contact to check in', true),
          o('To start a new project'),
          o('To reduce costs'),
          o('To win an argument'),
        ],
        explanation: '"Let\'s touch base next week" = let\'s talk briefly to share updates.',
        difficulty: Difficulty.easy,
        tags: ['business english'],
      ),
      Question(
        id: newId(),
        bankId: idioms.id,
        type: QuestionType.flashcard,
        text: 'Meaning of "a ballpark figure"',
        acceptedAnswers: ['A rough estimate'],
        explanation: 'Example: "Can you give me a ballpark figure for the budget?"',
        difficulty: Difficulty.easy,
        tags: ['business english'],
      ),
      Question(
        id: newId(),
        bankId: idioms.id,
        type: QuestionType.shortAnswer,
        text: 'Complete the idiom: "Every cloud has a silver ___"',
        acceptedAnswers: ['lining'],
        explanation: 'Something good can come from a bad situation.',
        difficulty: Difficulty.medium,
      ),
    ];
    for (final q in list) {
      await questions.saveQuestion(q.copyWith(fingerprint: questionFingerprint(q)));
    }
  }
}
