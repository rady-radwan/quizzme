# Development summary

_Last updated: 22 November 2026 — initial implementation._

## Status at a glance

| | |
|---|---|
| Source code | Phases 1–4 implemented, Phase 5 partly (see below). ~14,000 lines of Dart plus ~1,700 lines of tests. |
| Compiled / tested | **Not yet.** The code was written in an environment without the Flutter SDK. The first real compile, `flutter analyze`, `flutter test` and APK build happen in GitHub Actions (`ci.yml`) on the first push. Expect a short round of fixes after the first CI run. |
| What was verified locally | Every Dart file parses (syntax check with a Dart grammar); every relative import resolves; every repository/service method called from the UI exists; the spaced-repetition numbers in the tests were cross-checked with an independent Python implementation; the Excel templates were generated and validated against the importer's rules; the Android configuration script was tested on template files (valid XML, idempotent). |

## Phase 1 — Core application ✅ implemented

Project setup, SQLite schema + migrations, subject/category/bank management (unlimited nesting), Excel import (simple template), multiple-choice questions, manual creation and editing, question and answer shuffling (id-based), New Questions mode with persistent non-repetition, custom quiz lengths, immediate and end-of-quiz feedback, results, quiz history, session persistence/resume, basic progress, light/dark themes, Android build workflow.

## Phase 2 — Advanced learning ✅ implemented

SM-2 spaced repetition with confidence ratings, five mastery levels with explanations and decay, Mistakes Notebook, flashcards, all review modes (Review, Mistakes, Spaced, Random, Mastery Test, Bookmarked, Quick Review; Practice/Exam/Flashcard styles), daily goals and streaks, statistics, progress dashboard, bookmarks, personal notes, study reminders.

## Phase 3 — Advanced question management ✅ implemented

All question types (single, multiple, true/false, fill-in, matching, short answer with manual review, flashcard, image, audio, image identification), advanced Excel template, media import (.zip or attach), duplicate management (import policies + duplicates screen), search with combinable filters, multi-bank and category quizzes with exclusions and manual distribution, import history, Excel export, full backup/restore, advanced editing (move, duplicate, archive, per-option explanations, reset on answer change).

## Phase 4 — User experience ✅ implemented

Six themes incl. AMOLED, Minimal and Sepia + custom accent, font family/size/line spacing, high contrast, reduced motion, screen-reader labels, RTL content detection and RTL layout option, text-to-speech, audio playback with speed, charts and study-calendar heatmap, responsive layouts (navigation rail on wide screens), pagination and background parsing for performance.

## Phase 5 — Intelligent features ◑ partly

| Feature | Status |
|---|---|
| Adaptive difficulty | ✅ implemented (preference by recent accuracy; can be disabled; difficulty ≠ mastery) |
| Weakness identification | ✅ implemented (weakest banks + "Practice my weak topics") |
| Smart recommendations | ✅ implemented, offline (due/overdue, repeated mistakes, declining accuracy, subjects not studied recently, weak topics, new questions) |
| Achievements | ✅ implemented, optional |
| AI question generation | ⏳ not implemented — design in ARCHITECTURE.md |
| Cloud synchronisation | ⏳ not implemented — architecture prepared (UUIDs, timestamps, append-only history), design in ARCHITECTURE.md |

## Tests

`test/core/srs_mastery_test.dart`, `test/core/grading_shuffle_test.dart`, `test/core/excel_import_test.dart`, `test/data/database_test.dart` — about 80 tests covering the 20 areas requested (Excel parsing/validation, correct-answer mapping, shuffling, non-repetition, quiz generation and distribution, scoring, session save/resume, mastery, scheduling, duplicates, persistence, backup/restore, editing, deletion, statistics, theme settings, invalid input) and the listed edge cases (empty bank, three-question bank, 100 requested from 20, re-importing the same file, missing optional fields, interrupted quiz, interrupted import, changing a correct answer after attempts, large import).

Results: _pending the first CI run._

## Known limitations

- Not compiled yet (see above).
- The app's own menus are in English; Arabic content is displayed correctly right-to-left.
- Reminders are scheduled up to 14 days ahead and refreshed whenever the app is opened or a quiz is finished.
- Text-to-speech quality and offline availability depend on the voices installed on the phone.
- Search uses SQL `LIKE` (fast enough for typical libraries; full-text indexing is a possible improvement).
- The CI APK is signed with the debug key (see README → Testing APK vs signed production release).
- Windows/iOS builds are prepared by the shared code but have not been built or tested.
