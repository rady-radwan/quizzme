# Database

SQLite (`quiz_me.db` in the app's private support directory), opened through `sqflite` on Android/iOS and `sqflite_common_ffi` on desktop and in tests. Schema and migrations: `lib/data/db.dart`.

## Principles

- **Stable identifiers** — every row uses a UUID v4 (`lib/core/ids.dart`), so data can later be merged across devices.
- **Relational integrity** — `PRAGMA foreign_keys = ON`; deleting a subject cascades to its categories, banks, questions, options and learning history.
- **Migrations** — `AppDatabase.migrations` maps version → SQL statements. Released migrations are never edited; a schema change appends version N+1 and bumps `schemaVersion`. Settings are key/value rows, so new preferences need no migration.
- **Transactions** — an import, a quiz submission, finalising an answer, and a restore are each one transaction: they either complete or leave no trace.
- **Single source of truth** — all statistics are computed with SQL from `progress` and `attempts`; nothing is kept only in memory.

## Tables

| Table | Purpose |
|---|---|
| `categories` | Subjects (parent_id NULL) and nested categories (self-referencing `parent_id`, any depth) |
| `banks` | Question banks inside a category |
| `imports` | One row per Excel import: file name, date, status (`in_progress`, `completed`, `failed`, `interrupted`), counts, log |
| `questions` | Question content and metadata: type, text, hint, feedback, explanation, difficulty, tags, accepted answers, media paths, fingerprint, content_version, archived, origin import |
| `options` | Answer options with stable ids, position, `is_correct`, `match_text` (matching), per-option explanation |
| `progress` | One row per studied question: `seen` (New-mode eligibility), presentation/attempt/correct/incorrect/skip/hint counters, last result, SM-2 state (`ease`, `interval_days`, `repetitions`, `lapses`, `due_at`), mastery level + reason, `understood` |
| `sessions` | Quizzes (active / completed / abandoned): JSON configuration, cursor, elapsed time, totals, score |
| `session_questions` | The exact questions of a quiz in order, the shuffled option order (by id), the saved response, result, hint use, confidence, presentation and answer times, `applied` flag |
| `attempts` | Every submitted answer: result, response, hint, confidence, duration, whether it was a due review, mastery before/after, question content version |
| `presentations` | Every time a question was shown |
| `bookmarks` | Bookmarked questions |
| `notes` | Personal notes per question |
| `goals` | Daily goals (type, target, optional category) |
| `achievements` | Unlocked achievements |
| `settings` | Key/value preferences |

Indexes cover bank lookups, fingerprints, external ids, due dates, mastery and attempt times, so lists, filters and statistics stay fast with 100,000+ questions; lists are paginated.

## Key definitions

- **Never presented** — `progress.seen = 0` or no progress row. New Questions mode selects only these, and also excludes questions waiting in another unfinished quiz.
- **Presented but unanswered / skipped / attempted / correct / incorrect** — from `presented_count`, `skipped_count`, `attempt_count`, `last_result`.
- **Not yet scheduled** vs **never studied** — `due_at IS NULL` means no schedule yet; `attempt_count = 0` means never answered. They are different states.
- **Due today** — `due_at <= end of today` (includes overdue). **Overdue** — `due_at < start of today`.
- **Accuracy** — correct ÷ (correct + incorrect) over all graded answers.
- **Mastered %** of a subject — mastered questions ÷ all questions in the subject.

## Backup format (version 1)

A `.zip` with `quizme-backup.json` (format name, format version, schema version, app version, date, row counts), `tables/<table>.json` (all rows) and `media/` (images/audio). Restore validates the manifest and required tables, refuses backups from a newer app version, and runs in one transaction with deferred foreign-key checks. Unknown columns are ignored, so older backups restore into newer schemas.
