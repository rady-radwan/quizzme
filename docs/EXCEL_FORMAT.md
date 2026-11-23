# Excel question format

Quiz me reads `.xlsx` workbooks. Every worksheet whose header row (within the first 15 rows) contains a **Question** column is imported; other sheets (such as "How to use") are skipped with a notice. Header names ignore case, spaces and punctuation, and common synonyms are accepted (`Correct Answer`, `Answer`, `correct_answer` …).

You can also import a **.zip** containing one or more workbooks plus the image/audio files they reference.

## Simple template

| Column | Required | Notes |
|---|---|---|
| Question | yes | The question text |
| Option A, Option B | yes | At least two options |
| Option C, Option D | no | More options are allowed (up to Option J) |
| Correct Answer | yes | Letter(s): `B` or `A, C` (also `AC`, `A;C`, `1`, or the exact option text) |
| Hint | no | Shown only when the learner asks for it (never in exam mode) |
| Correct Feedback | no | Message after a correct answer |
| Incorrect Feedback | no | Message after an incorrect answer |
| Explanation | no | Detailed explanation |
| Difficulty | no | Easy, Medium, Hard or Expert (or 1–4). Unknown values → Medium with a warning |
| Tags | no | Keywords separated by commas |

Several correct letters automatically make the question a *multiple-answer* question.

## Advanced template

All simple columns, plus:

| Column | Notes |
|---|---|
| Question ID | Your identifier. Re-importing a row with the same ID into the same bank is recognised as the same question (choose *Update* to refresh it while keeping its history). Exported files use it too. |
| Type | `single`, `multiple`, `true_false`, `fill_blank`, `matching`, `short_answer`, `flashcard`, `image`, `audio`, `identify`. Empty = detected automatically. Synonyms such as "True/False", "MCQ", "Fill in the blank" work. |
| Option A … Option J | Up to ten options. For **matching** write `Item => Match` in each option cell. |
| Accepted Answers | Typed questions: extra accepted answers separated by `|` |
| Case Sensitive | Yes/No (typed questions) |
| Option A Explanation … | Why that option is right or wrong; shown when the learner picks it |
| Category, Bank | Informational. In the import preview you can choose **Use the Bank column** to place rows into the named banks (created next to the target bank). |
| Image, Audio | File name of a picture/recording. Include the files in a .zip with the workbook, or attach them in the import preview. They are copied into the app. |
| Shuffle Answers | `No` keeps the authored order (e.g. "All of the above"). Default Yes. |
| Source | Reference or source of the question |
| Study Notes | Extra notes shown on the question page |

### Correct Answer by type

| Type | Correct Answer |
|---|---|
| single / image / audio | One letter, e.g. `C` |
| multiple | Several letters, e.g. `A, C, D` |
| true_false | `True` or `False` (Option A/B may rename them) |
| fill_blank | The answer; alternatives with `|`, e.g. `colour | color` |
| short_answer / identify | Accepted answers with `|`. Answers that don't match exactly are judged by the learner (manual review). |
| flashcard | The back of the card |
| matching | Leave empty |

## Validation

Before anything is saved the preview shows: questions found, ready to import, rows with errors (skipped, with messages such as *"Question 15 (Questions row 16) does not have a valid correct answer."*), questions already in the bank, duplicates within the file, warnings (unknown difficulty, missing media) and a sample of the questions.

Duplicates are detected by **content fingerprint** (type + normalised text + options, independent of option order, case and punctuation) or by **Question ID**.

## Permanent storage

Imported questions, options and media are copied into the app's database and private storage. The original Excel file is no longer needed and may be deleted. Each import is recorded (file name, date, counts and messages) in *Import history*, and you can list the questions that came from a particular import.

## Exporting

*Bank → Export to Excel* writes the bank in the advanced format (and a .zip with a `media/` folder when questions have images or audio). The exported file can be edited and re-imported.

## Regenerating the templates

```bash
pip install openpyxl
python3 tool/make_templates.py
```
