"""Generates the Excel templates bundled with the app (assets/templates/).

Run:  python3 tool/make_templates.py
Requires: pip install openpyxl
The column names here must stay compatible with lib/core/import/question_parser.dart.
"""
import pathlib

from openpyxl import Workbook
from openpyxl.styles import Alignment, Font, PatternFill
from openpyxl.worksheet.datavalidation import DataValidation

OUT = pathlib.Path(__file__).resolve().parent.parent / 'assets' / 'templates'
OUT.mkdir(parents=True, exist_ok=True)

HEADER_FILL = PatternFill('solid', fgColor='DCE6F2')
REQUIRED_FILL = PatternFill('solid', fgColor='FCE4D6')

SIMPLE = ['Question', 'Option A', 'Option B', 'Option C', 'Option D', 'Correct Answer', 'Hint',
          'Correct Feedback', 'Incorrect Feedback', 'Explanation', 'Difficulty', 'Tags']
SIMPLE_REQUIRED = {'Question', 'Option A', 'Option B', 'Correct Answer'}

LETTERS = 'ABCDEF'
ADVANCED = (['Question ID', 'Type', 'Question'] + [f'Option {l}' for l in LETTERS] +
            ['Correct Answer', 'Accepted Answers', 'Case Sensitive', 'Hint', 'Correct Feedback',
             'Incorrect Feedback', 'Explanation'] + [f'Option {l} Explanation' for l in LETTERS] +
            ['Difficulty', 'Tags', 'Category', 'Bank', 'Image', 'Audio', 'Shuffle Answers', 'Source',
             'Study Notes'])

TYPES = ['single', 'multiple', 'true_false', 'fill_blank', 'matching', 'short_answer', 'flashcard',
         'image', 'audio', 'identify']


def style_sheet(ws, headers, required=frozenset(), widths=None):
    for i, h in enumerate(headers, start=1):
        c = ws.cell(row=1, column=i, value=h)
        c.font = Font(bold=True)
        c.fill = REQUIRED_FILL if h in required else HEADER_FILL
        c.alignment = Alignment(wrap_text=True, vertical='center')
        ws.column_dimensions[c.column_letter].width = (widths or {}).get(h, 22)
    ws.freeze_panes = 'A2'
    ws.row_dimensions[1].height = 30


def add_rows(ws, headers, rows):
    for r in rows:
        ws.append([r.get(h, '') for h in headers])
    for row in ws.iter_rows(min_row=2):
        for c in row:
            c.alignment = Alignment(wrap_text=True, vertical='top')


def add_validations(ws, headers, max_row=5000):
    def col(h):
        return ws.cell(row=1, column=headers.index(h) + 1).column_letter
    dv = DataValidation(type='list', formula1='"Easy,Medium,Hard,Expert"', allow_blank=True)
    ws.add_data_validation(dv)
    dv.add(f'{col("Difficulty")}2:{col("Difficulty")}{max_row}')
    if 'Type' in headers:
        tv = DataValidation(type='list', formula1='"' + ','.join(TYPES) + '"', allow_blank=True)
        ws.add_data_validation(tv)
        tv.add(f'{col("Type")}2:{col("Type")}{max_row}')


def instructions(wb, lines):
    ws = wb.create_sheet('How to use')
    ws.column_dimensions['A'].width = 120
    for i, line in enumerate(lines, start=1):
        c = ws.cell(row=i, column=1, value=line)
        c.alignment = Alignment(wrap_text=True, vertical='top')
        if i == 1:
            c.font = Font(bold=True, size=14)


EXAMPLE_SIMPLE = [
    {'Question': 'Which sentence is grammatically correct?',
     'Option A': 'He go to work every day.', 'Option B': 'He goes to work every day.',
     'Option C': 'He going to work every day.', 'Option D': 'He gone to work every day.',
     'Correct Answer': 'B', 'Hint': 'Remember the third-person singular rule.',
     'Correct Feedback': 'Excellent! The verb takes an "-s" with he, she, and it in the simple present tense.',
     'Incorrect Feedback': 'Not quite. Remember that third-person singular subjects normally require a verb '
                           'ending in "-s" in the simple present tense.',
     'Explanation': 'In the simple present tense, third-person singular subjects such as he, she, and it '
                    'require the verb to end in "-s" or "-es" in affirmative statements.',
     'Difficulty': 'Easy', 'Tags': 'grammar, present simple'},
    {'Question': 'Choose the correct preposition: "I have lived here ___ 2020."',
     'Option A': 'for', 'Option B': 'since', 'Option C': 'from', 'Option D': 'at',
     'Correct Answer': 'B', 'Explanation': 'Use "since" with a starting point in time and "for" with a duration.',
     'Difficulty': 'Medium', 'Tags': 'prepositions'},
    {'Question': 'What is the maximum allowable altitude for a small UAS under Part 107 (without a waiver, '
                 'away from structures)?',
     'Option A': '200 feet AGL', 'Option B': '400 feet AGL', 'Option C': '500 feet AGL', 'Option D': '1,000 feet MSL',
     'Correct Answer': 'B', 'Difficulty': 'Easy', 'Tags': 'FAA Part 107, regulations'},
]

SIMPLE_HELP = [
    'Quiz me — Simple question template',
    'Fill in the "Questions" sheet. Each row is one multiple-choice question.',
    'Required columns (orange): Question, Option A, Option B and Correct Answer. Options C and D are optional.',
    'Correct Answer: the letter of the right option (A, B, C or D). You may also type the exact option text.',
    'For several correct answers write the letters separated by commas, e.g. "A, C".',
    'Everything else is optional: Hint, Correct Feedback (shown after a right answer), Incorrect Feedback '
    '(shown after a wrong answer), Explanation, Difficulty (Easy, Medium, Hard or Expert) and Tags '
    '(keywords separated by commas).',
    'You can add more rows, more worksheets, and import several files into the same bank over time. '
    'Duplicate questions are detected when you import.',
    'In the app: Banks → open a bank → Import from Excel → choose this file → check the preview → Import.',
    'After importing, the questions are stored permanently inside the app — you can delete this file.',
    'Do not rename the header row. Delete the three example rows before importing your own questions.',
]

ADV_ROWS = [
    {'Question ID': 'GR-001', 'Type': 'single', 'Question': 'Which sentence is grammatically correct?',
     'Option A': 'He go to work every day.', 'Option B': 'He goes to work every day.',
     'Option C': 'He going to work every day.', 'Option D': 'He gone to work every day.',
     'Correct Answer': 'B', 'Hint': 'Remember the third-person singular rule.',
     'Correct Feedback': 'Excellent!', 'Incorrect Feedback': 'Not quite.',
     'Explanation': 'Third-person singular subjects take -s in the simple present.',
     'Option A Explanation': '"Go" needs an -s after "he".',
     'Option C Explanation': 'The -ing form needs "is": "He is going".',
     'Option D Explanation': '"Gone" needs "has": "He has gone".',
     'Difficulty': 'Easy', 'Tags': 'grammar, present simple', 'Category': 'English > Grammar',
     'Bank': 'Tenses', 'Shuffle Answers': 'Yes', 'Source': 'Personal notes'},
    {'Question ID': 'GR-002', 'Type': 'multiple',
     'Question': 'Which sentences use the present perfect correctly? (Select all that apply.)',
     'Option A': 'I have lived here since 2020.', 'Option B': 'I have seen him yesterday.',
     'Option C': 'She has already finished.', 'Option D': 'They have went home.',
     'Correct Answer': 'A, C', 'Explanation': 'The present perfect is not used with a finished time like "yesterday".',
     'Option B Explanation': 'Use the past simple with "yesterday".',
     'Option D Explanation': 'The participle of "go" is "gone".',
     'Difficulty': 'Hard', 'Bank': 'Tenses'},
    {'Question ID': 'GR-003', 'Type': 'true_false', 'Question': '"I am knowing the answer" is correct standard English.',
     'Option A': 'True', 'Option B': 'False', 'Correct Answer': 'False',
     'Explanation': '"Know" is a stative verb and is rarely used in continuous tenses.', 'Difficulty': 'Medium',
     'Bank': 'Tenses', 'Shuffle Answers': 'No'},
    {'Question ID': 'GR-004', 'Type': 'fill_blank', 'Question': 'Yesterday I ___ (buy) a new laptop.',
     'Correct Answer': 'bought', 'Case Sensitive': 'No', 'Explanation': 'buy – bought – bought', 'Bank': 'Tenses'},
    {'Question ID': 'GR-005', 'Type': 'matching', 'Question': 'Match each sentence with its tense.',
     'Option A': 'She works here. => Present simple', 'Option B': 'She is working now. => Present continuous',
     'Option C': 'She has worked here for years. => Present perfect', 'Bank': 'Tenses'},
    {'Question ID': 'VO-001', 'Type': 'short_answer', 'Question': 'Complete the idiom: "Every cloud has a silver ___"',
     'Correct Answer': 'lining', 'Accepted Answers': 'Lining | silver lining',
     'Explanation': 'Something good can come out of a bad situation.', 'Bank': 'Idioms'},
    {'Question ID': 'VO-002', 'Type': 'flashcard', 'Question': 'Meaning of "a ballpark figure"',
     'Correct Answer': 'A rough estimate', 'Explanation': '"Can you give me a ballpark figure for the budget?"',
     'Bank': 'Idioms'},
    {'Question ID': 'IMG-001', 'Type': 'image', 'Question': 'What does the symbol in the picture indicate?',
     'Option A': 'Class B airspace', 'Option B': 'Class C airspace', 'Option C': 'Class D airspace',
     'Correct Answer': 'C', 'Image': 'sectional_symbol.png',
     'Study Notes': 'Put the image file next to this workbook in a .zip, or add it in the import preview.'},
    {'Question ID': 'AUD-001', 'Type': 'audio', 'Question': 'Listen. Which word did the speaker say?',
     'Option A': 'ship', 'Option B': 'sheep', 'Correct Answer': 'B', 'Audio': 'ship_sheep.mp3',
     'Tags': 'pronunciation', 'Bank': 'Listening'},
    {'Question ID': 'IMG-002', 'Type': 'identify', 'Question': 'Name the structural element marked in red.',
     'Correct Answer': 'Cantilever beam', 'Accepted Answers': 'cantilever', 'Image': 'beam.jpg',
     'Bank': 'Structures'},
]

ADV_HELP = [
    'Quiz me — Advanced question template',
    'One row per question. Only "Question" and the answer columns needed by the question type are required.',
    'Type: single (one correct option), multiple (several correct options), true_false, fill_blank, matching, '
    'short_answer, flashcard, image (choice question with an image), audio (choice question with audio), '
    'identify (image identification, typed answer). Leave empty to detect automatically.',
    'Options: up to six here (Option A … Option F); the app accepts up to ten (add "Option G" … "Option J").',
    'Correct Answer: choice questions — letter(s) such as "B" or "A, C" (or the exact option text); '
    'true_false — True or False; fill_blank / short_answer — the answer, alternatives separated by "|"; '
    'flashcard — the back of the card; matching — leave empty.',
    'Matching: write each pair in an option cell as "Item => Match".',
    'Accepted Answers: extra accepted answers for typed questions, separated by "|". Case Sensitive: Yes/No.',
    'Option X Explanation: why that option is right or wrong — shown when the learner picks it.',
    'Category and Bank: informational. When importing you can choose to place each row into the bank named in '
    'the Bank column (banks are created next to the bank you import into).',
    'Image / Audio: a file name. Put the files together with this workbook in a .zip file and import the .zip, '
    'or attach the files in the import preview. Media are copied into the app permanently.',
    'Shuffle Answers: No keeps the option order (e.g. for "All of the above").',
    'Question ID: your own identifier. Re-importing a row with the same Question ID can update that question '
    'while keeping its learning history.',
]

EXAMPLES = [
    # English
    {'Type': 'single', 'Question': 'Choose the correct form: "If I ___ you, I would accept the offer."',
     'Option A': 'am', 'Option B': 'was', 'Option C': 'were', 'Option D': 'be', 'Correct Answer': 'C',
     'Explanation': 'The second conditional uses "were" for all persons in formal English.',
     'Difficulty': 'Medium', 'Tags': 'conditionals', 'Bank': 'Grammar'},
    {'Type': 'single', 'Question': 'Which word is closest in meaning to "postpone"?',
     'Option A': 'cancel', 'Option B': 'delay', 'Option C': 'announce', 'Option D': 'confirm',
     'Correct Answer': 'B', 'Difficulty': 'Easy', 'Tags': 'business english', 'Bank': 'Vocabulary'},
    {'Type': 'fill_blank', 'Question': 'She is interested ___ learning Spanish.', 'Correct Answer': 'in',
     'Explanation': 'interested in + noun / -ing', 'Difficulty': 'Easy', 'Tags': 'prepositions', 'Bank': 'Grammar'},
    {'Type': 'true_false', 'Question': '"Fewer" is used with countable nouns.', 'Correct Answer': 'True',
     'Explanation': 'fewer books, less water.', 'Bank': 'Grammar'},
    {'Type': 'flashcard', 'Question': 'touch base', 'Correct Answer': 'To make brief contact to share updates',
     'Bank': 'Vocabulary'},
    {'Type': 'matching', 'Question': 'Match the phrasal verb with its meaning.',
     'Option A': 'put off => postpone', 'Option B': 'look into => investigate', 'Option C': 'carry out => perform',
     'Bank': 'Vocabulary'},
    # Engineering / BIM
    {'Type': 'single', 'Question': 'In BIM, what does "LOD" commonly stand for?',
     'Option A': 'Level of Development', 'Option B': 'Length of Drawing', 'Option C': 'Layer of Detail',
     'Option D': 'List of Deliverables', 'Correct Answer': 'A', 'Difficulty': 'Easy', 'Tags': 'BIM',
     'Bank': 'BIM Coordination'},
    {'Type': 'multiple', 'Question': 'Which are Autodesk Navisworks capabilities? (Select all that apply.)',
     'Option A': 'Clash detection', 'Option B': '4D construction simulation', 'Option C': 'Structural analysis design codes',
     'Option D': 'Model aggregation and review', 'Correct Answer': 'A, B, D', 'Difficulty': 'Medium',
     'Tags': 'Navisworks', 'Bank': 'BIM Coordination'},
    {'Type': 'single', 'Question': 'A beam fixed at one end and free at the other is called a…',
     'Option A': 'simply supported beam', 'Option B': 'cantilever beam', 'Option C': 'continuous beam',
     'Option D': 'fixed-fixed beam', 'Correct Answer': 'B', 'Difficulty': 'Easy', 'Bank': 'Structural Engineering'},
    {'Type': 'short_answer', 'Question': 'What does RFI stand for in construction?',
     'Correct Answer': 'Request for Information', 'Accepted Answers': 'request for info',
     'Bank': 'Construction Management'},
    # FAA Part 107
    {'Type': 'single', 'Question': 'Under Part 107, what is the maximum groundspeed of a small unmanned aircraft?',
     'Option A': '87 knots (100 mph)', 'Option B': '100 knots', 'Option C': '60 knots', 'Option D': '120 mph',
     'Correct Answer': 'A', 'Difficulty': 'Easy', 'Tags': 'regulations', 'Bank': 'Regulations'},
    {'Type': 'single', 'Question': 'What is the minimum flight visibility required for Part 107 operations?',
     'Option A': '1 statute mile', 'Option B': '3 statute miles', 'Option C': '5 statute miles',
     'Option D': '3 nautical miles', 'Correct Answer': 'B', 'Tags': 'weather', 'Bank': 'Weather'},
    {'Type': 'single', 'Question': 'What is the minimum distance a small UA must remain below clouds?',
     'Option A': '500 feet', 'Option B': '1,000 feet', 'Option C': '2,000 feet', 'Option D': '250 feet',
     'Correct Answer': 'A', 'Explanation': 'Part 107: 500 ft below and 2,000 ft horizontally from clouds.',
     'Tags': 'weather', 'Bank': 'Weather'},
    {'Type': 'single', 'Question': 'Small unmanned aircraft must weigh less than…',
     'Option A': '25 lb', 'Option B': '55 lb', 'Option C': '100 lb', 'Option D': '250 g',
     'Correct Answer': 'B', 'Tags': 'regulations', 'Bank': 'Regulations'},
    {'Type': 'true_false', 'Question': 'Operations in Class G airspace require ATC authorization under Part 107.',
     'Correct Answer': 'False', 'Explanation': 'Class G is uncontrolled; Class B, C, D and surface-area E need authorization.',
     'Tags': 'airspace', 'Bank': 'Airspace'},
    {'Type': 'fill_blank', 'Question': 'Recurrent training must be completed every ___ calendar months.',
     'Correct Answer': '24', 'Tags': 'regulations', 'Bank': 'Regulations'},
    # General knowledge
    {'Type': 'single', 'Question': 'Which is the largest ocean on Earth?',
     'Option A': 'Atlantic', 'Option B': 'Indian', 'Option C': 'Pacific', 'Option D': 'Arctic',
     'Correct Answer': 'C', 'Bank': 'Geography'},
    {'Type': 'single', 'Question': 'ما هي عاصمة مصر؟',
     'Option A': 'الإسكندرية', 'Option B': 'القاهرة', 'Option C': 'أسوان', 'Option D': 'الأقصر',
     'Correct Answer': 'B', 'Explanation': 'القاهرة هي عاصمة مصر.', 'Tags': 'arabic', 'Bank': 'Geography'},
    {'Type': 'true_false', 'Question': 'Water boils at 100 °C at sea level.', 'Correct Answer': 'True',
     'Bank': 'Science'},
]


def build():
    # Simple
    wb = Workbook()
    ws = wb.active
    ws.title = 'Questions'
    style_sheet(ws, SIMPLE, SIMPLE_REQUIRED,
                {'Question': 50, 'Explanation': 45, 'Correct Feedback': 32, 'Incorrect Feedback': 32,
                 'Correct Answer': 14, 'Difficulty': 12})
    add_rows(ws, SIMPLE, EXAMPLE_SIMPLE)
    add_validations(ws, SIMPLE)
    instructions(wb, SIMPLE_HELP)
    wb.save(OUT / 'QuizMe_Simple_Template.xlsx')

    # Advanced
    wb = Workbook()
    ws = wb.active
    ws.title = 'Questions'
    style_sheet(ws, ADVANCED, {'Question'}, {'Question': 50, 'Explanation': 40, 'Type': 14, 'Question ID': 12})
    add_rows(ws, ADVANCED, ADV_ROWS)
    add_validations(ws, ADVANCED)
    instructions(wb, ADV_HELP)
    wb.save(OUT / 'QuizMe_Advanced_Template.xlsx')

    # Examples (advanced layout, ready to import)
    wb = Workbook()
    ws = wb.active
    ws.title = 'Questions'
    style_sheet(ws, ADVANCED, {'Question'}, {'Question': 50, 'Explanation': 40, 'Type': 14})
    add_rows(ws, ADVANCED, EXAMPLES)
    add_validations(ws, ADVANCED)
    instructions(wb, ['Quiz me — example questions',
                      'Import this file to try every feature. Turn on "Use the Bank column" in the import '
                      'preview to sort the questions into banks automatically.'])
    wb.save(OUT / 'QuizMe_Examples.xlsx')


if __name__ == '__main__':
    build()
    print('templates written to', OUT)
