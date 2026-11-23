# Architecture

## Choices

| Decision | Choice | Why |
|---|---|---|
| Framework | Flutter + Dart | One code base for Android now, Windows and iOS later. |
| Storage | SQLite via `sqflite` (mobile) / `sqflite_common_ffi` (desktop, tests) | Proven, offline, transactional. The same SQL runs on every platform and in CI tests against a real database. |
| Persistence layer | Hand-written SQL repositories with numbered migrations (instead of Drift) | No code-generation step, explicit and reviewable SQL, identical behaviour in tests. Drift remains a drop-in option later because all access goes through repositories. |
| State management | `ChangeNotifier` + a small `Reloadable` widget that refreshes when data changes | Minimal dependencies, easy to follow; screens reload their numbers after any change. |
| Excel | Own `.xlsx` reader/writer on `archive` + `xml` | Predictable, handles shared/inline strings, multiple sheets, big files in a background isolate; no third-party Excel package. |
| Charts | `CustomPainter` | No chart dependency; screen-reader summaries for every chart. |
| Optional device features | `flutter_local_notifications`, `flutter_tts`, `audioplayers`, `file_picker` | All free, local, and the app works fully when they are unavailable or disabled. |

## Layers

```
ui/        widgets & screens ──────────────┐
app/       composition root, theme          │  depends on ↓
data/      repositories & services (SQL)    │
services/  notifications, speech            │
core/      pure Dart rules (no Flutter)  ◄──┘  unit-tested in isolation
```

`lib/core` holds every rule that must be correct: spaced repetition (`srs.dart`), mastery (`mastery.dart`), grading (`grading.dart`), shuffling (`shuffle.dart`), distribution and adaptive difficulty (`distribution.dart`), the Excel parser and fingerprints (`import/`) and the xlsx reader/writer (`xlsx/`).

## Quiz engine invariants

1. **Correct-answer integrity** — options have stable ids; a session stores the display order as a list of ids; grading compares ids. Shuffling can't change correctness.
2. **No repetition in New Questions mode** — presenting a question sets `progress.seen`; New mode selects `seen = 0` and excludes questions held by other unfinished quizzes. Only an explicit reset clears `seen`, never the history.
3. **Persistence** — a session's questions, option order, answers, cursor and timer are written to SQLite as they change, so a killed app resumes exactly.
4. **Hidden answers stay hidden** — in end-of-quiz mode results are stored but never rendered until submission; restoring a session uses the same rule.
5. **History is append-only** — editing, moving or resetting a question never deletes `attempts`. A major change can reset only the schedule/mastery (and bumps `content_version`).
6. **Apply once** — an answer is applied to the learning state exactly once (`session_questions.applied`), inside the same transaction as the attempt row.

## Spaced repetition

SM-2 with four grades (again / hard / good / easy). Correct + "Didn't know" counts as *again*; using a hint caps the grade at *hard*; a correct answer before the due date is recorded but doesn't extend the schedule. Defaults give 1 → 3 → ~8 → ~20 → ~50 days for consistent "Medium" answers, capped at three years. Parameters are configurable in Settings. Due dates are local midnights, so "due today" is stable all day and DST-safe.

## Performance

Indexed queries, paginated lists, aggregate statistics in SQL, large imports parsed in a background isolate and written in batches inside one transaction. Designed for 100,000 questions.

## Future: cloud synchronisation (optional, not implemented)

The schema is already sync-friendly: UUIDs everywhere, `updated_at` on mutable rows, append-only `attempts`. A Supabase (or any backend) sync can be added as a separate `SyncService` without changing screens:

1. Optional sign-in (Supabase Auth; credentials never in source code — configured at build time or entered by the user).
2. Push local changes since the last sync (`updated_at > last_sync`), pull remote changes.
3. Conflicts: last-writer-wins per row for content (categories, banks, questions, options, notes, settings); `attempts` and `presentations` are append-only and merged by id; `progress` is recomputed from merged attempts so schedules never diverge.
4. Offline changes queue locally and sync later; local data remains the source of truth.

## Future: AI question generation (optional, not implemented)

A separate, clearly optional feature: the user supplies study material (text, PDF, Word) and their own API key, chooses types, difficulty and count, reviews and edits every suggestion, and only approved questions are saved into a bank. No key is embedded in the app; source references are only shown if they come from the material itself. Quiz features never depend on it.

## Recommended next improvements

- Arabic translation of the app's own interface (content is already RTL-aware).
- Home-screen widget showing due reviews.
- Full-text search (SQLite FTS) for very large libraries.
- Automatic periodic backup to a user-chosen folder.
