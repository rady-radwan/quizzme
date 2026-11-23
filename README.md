# Quiz me

**A personal learning, quiz and long-term knowledge-retention app.**
Learn with quizzes and flashcards, revise efficiently with spaced repetition, and remember what you learn for years.

- **Offline first.** Everything works without internet, accounts or subscriptions. Your data stays on your device.
- **Excel import.** Write questions in Excel, import them, and they are stored permanently in the app.
- **Spaced repetition.** An SM-2 based scheduler brings questions back just before you would forget them.
- **Android first** (Flutter), with the same code base ready for Windows and iOS.

---

## Contents

1. [Features](#features)
2. [Install on your Android phone](#install-on-your-android-phone)
3. [Build from source](#build-from-source)
4. [Project structure](#project-structure)
5. [Excel templates](#excel-templates)
6. [Database](#database)
7. [Testing](#testing)
8. [Continuous integration and releases](#continuous-integration-and-releases)
9. [Documentation](#documentation)

---

## Features

| Area | What you get |
|---|---|
| Organisation | Unlimited Subjects → Categories (any depth) → Question banks → Questions. Name, description, icon, colour, archive, move, delete with confirmation. |
| Question types | Single-answer and multiple-answer multiple choice, true/false, fill in the blank (case sensitivity, alternatives), matching, short written answers (exact match + manual self-review), flashcards, image questions, audio questions, image identification. |
| Excel import | `.xlsx` (all worksheets) or `.zip` (workbook + images/audio). Validation, preview, clear error messages with row numbers, duplicate detection (skip / update keeping history / add anyway), import history with file name and date, filter questions by import, large files parsed in the background, one transaction per import. |
| Quiz generator | Scope = subjects, categories (with excluded sub-categories) or banks. 5/10/25/50/100 or any number. Automatic (proportional) or manual distribution across banks. Difficulty and mastery filters. Never duplicates questions to fill a quiz — tells you how many are available instead. |
| Modes | Learn New Questions (never repeats presented questions, persistent), Review, Mistakes (last answer or ever wrong), Spaced Repetition (due today), Random, Mastery Test, Bookmarked, Quick Review — each combinable with Practice, Exam or Flashcard style. |
| Feedback | Immediate or end-of-quiz. Correct/incorrect indicator, correct answer, custom feedback messages, explanation, per-option "why this is wrong". Hints (recorded, disabled in exam mode). End-of-quiz mode never reveals answers early — not even after restoring a session. |
| Answer shuffling | Display order stored per presentation as option *ids*, so shuffling can never change the correct answer. True/false and "All of the above" keep their order; shuffling can be disabled per question. |
| Sessions | Every answer saved immediately. Resume interrupted quizzes exactly where you left off (questions, order, answers, timer). Previous/next, skip, question grid, review unanswered, submit early with confirmation, optional countdown. |
| Spaced repetition | SM-2 variant with Easy / Medium / Hard / Didn't know ratings; hint use caps the grade; early correct reviews don't inflate intervals; configurable intervals. Revision dashboard: due today, overdue, tomorrow, next 7 days, upcoming chart. |
| Mastery | Not Learned → Learning → Needs Practice → Well Learned → Mastered, with a plain-language reason for every question. Levels move backwards after mistakes or when reviews are long overdue. |
| Mistakes Notebook | Your answer vs the correct answer, explanation, count and date, mastery; filter by subject, repeated, bookmarked; notes; mark understood (history kept); quiz from mistakes. |
| Progress | Dashboard statistics with clear definitions, daily/weekly/monthly charts (answers, accuracy, study time, reviews, mastered), study-calendar heatmap, weakest topics with "Practice my weak topics", per-subject mastery, quiz history with full reopenable results. |
| Habits | Daily goals (questions, minutes, reviews, mastered — optionally per subject) with today/week progress and streaks; optional reminders (time, days, at most one per day); optional, subtle achievements. |
| Questions | Search across text, answers, tags and notes; combinable filters (never attempted, previously incorrect, correct last time, wrong several times, due, overdue, mastered, not studied in 30 days, bookmarked, difficulty, type, mastery, tag, import). Bulk move/archive/delete/quiz. |
| Editor | Every question type, options with per-option explanations, accepted answers, matching pairs, hints, feedback, difficulty, tags, image, audio, source, notes. Changing a correct answer offers to reset that question's schedule while keeping its history. Duplicate and move. |
| Data safety | Complete versioned backup (.zip with all tables and media), validated restore with preview, typed confirmation and an automatic safety copy. Excel export per bank (re-importable). |
| Reading & access | Light, Dark, AMOLED Black, Minimal White, Sepia, six Glassy themes (Blue, Teal, Yellow, Purple, Pink, Midnight), custom accent; font, text size, line spacing; high contrast; reduced motion; screen-reader labels; large touch targets; English + Arabic with right-to-left content detection and an RTL layout option; text-to-speech for questions and answers; imported audio with speed control. |

Not in this version (designed for, see [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)): cloud synchronisation and optional AI question generation; an Arabic translation of the app's own menus (Arabic *content* is fully supported).

## Install on your Android phone

1. Open the repository on GitHub → **Actions** → the latest successful **CI** run.
2. Download the artifact **quiz-me-apk-…** (a .zip containing `app-release.apk`) and unzip it on your phone.
3. Open the `.apk`. Android asks to allow installing apps from this source — allow it once.

For a tagged release (`v1.0.0`, …) the APK is also attached to the GitHub **Releases** page.

### Testing APK vs signed production release

- **CI / testing APK** — signed with Flutter's *debug* key. It installs and works normally for personal use. It cannot be uploaded to Google Play, and an APK signed with a different key cannot update it in place (you would have to uninstall, which deletes app data — **make a backup first**).
- **Production release** — signed with your own upload key, configured as GitHub secrets (see `.github/workflows/release.yml`). Use the same key for every future release so updates install over the old version and keep your data. Never commit the keystore or passwords; `.gitignore` excludes them.

## Build from source

Requirements: Flutter (current stable channel, 3.35 or newer), Android SDK / Android Studio, Java 17.

```bash
git clone https://github.com/rady-radwan/quizzme.git
cd quizzme
# First time only, if android/ios/windows folders are missing:
flutter create --org com.radyradwan --project-name quiz_me --platforms=android,ios,windows .
rm -f test/widget_test.dart
python3 tool/configure_platforms.py   # app name, permissions, desugaring, optional signing

flutter pub get
flutter run                 # on a connected phone or emulator
flutter test                # unit + database tests (needs libsqlite3 on Linux)
flutter build apk --release # build/app/outputs/flutter-apk/app-release.apk
```

Windows: `flutter build windows` (uses `sqflite_common_ffi`). iOS: `flutter build ios` on a Mac.

## Project structure

```
lib/
  core/            Pure Dart, no Flutter: models, spaced repetition (srs.dart), mastery rules,
                   grading, shuffling, distribution, xlsx reader/writer, Excel parser, fingerprints
  data/            SQLite schema + migrations (db.dart) and repositories/services:
                   catalog, questions, study (progress), sessions (quiz engine), stats,
                   settings, import, export, backup, media, sample data
  services/        Device features: notifications, text-to-speech/audio
  app/             Composition root (services.dart), theme system, MaterialApp
  ui/              Screens: home, banks, questions, import, quiz (setup, player, results,
                   flashcards, history), mistakes, progress (+goals), settings (+backup)
test/              Unit tests (core) and integration tests on a real SQLite database (data)
assets/templates/  Excel templates bundled with the app
tool/              make_templates.py (regenerates templates), configure_platforms.py
docs/              User guide, Excel format, database, architecture, development summary
```

Architecture: layered and local-first — UI → repositories/services → SQLite. Business rules live in `lib/core` and are fully unit-tested. See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md).

## Excel templates

Three files are bundled in the app (Import → Templates) and in `assets/templates/`:

- `QuizMe_Simple_Template.xlsx` — Question, Option A–D, Correct Answer, Hint, Correct Feedback, Incorrect Feedback, Explanation, Difficulty, Tags. Only Question, two options and Correct Answer are required.
- `QuizMe_Advanced_Template.xlsx` — every question type, up to 10 options, multiple correct answers, accepted answers, case sensitivity, per-option explanations, category/bank, image/audio references, shuffle setting, source, study notes — with an example row for each type.
- `QuizMe_Examples.xlsx` — ready-to-import example questions (English, engineering/BIM, FAA Part 107, general knowledge, Arabic).

Full column reference: [docs/EXCEL_FORMAT.md](docs/EXCEL_FORMAT.md).

## Database

SQLite with explicit, numbered migrations (`lib/data/db.dart`), foreign keys with cascades, UUID identifiers and indexes for 100,000+ questions. Tables: `categories`, `banks`, `imports`, `questions`, `options`, `progress`, `sessions`, `session_questions`, `attempts`, `presentations`, `bookmarks`, `notes`, `goals`, `achievements`, `settings`. Details: [docs/DATABASE.md](docs/DATABASE.md).

## Testing

`flutter test` runs:

- `test/core/` — spaced repetition maths, mastery rules, grading of every type, answer shuffling integrity (500 randomised trials), distribution across banks, xlsx reading/writing, the Excel parser (validation, aliases, duplicates, every type) and the bundled templates.
- `test/data/` — the real schema on SQLite (via `sqflite_common_ffi`): hierarchy and statistics, New Questions non-repetition across sessions, insufficient questions, scoring, mistakes, resume after interruption, idempotent finalisation, manual review, flashcards, editing without losing history, correct-answer changes, move/duplicate/delete, search filters, import/re-import/update, permanent storage after the file is deleted, interrupted imports, a 2,000-question import, export→import round trip, full backup/restore, settings and dashboard/goals/achievements.

## Continuous integration and releases

- `.github/workflows/ci.yml` — on every push to `main`: analyze, test, build the APK, upload it as an artifact. The first run generates and commits the platform folders. A summary and the logs of each run are published to the `ci-reports` branch.
- `.github/workflows/release.yml` — on a `v*` tag: tests, builds the APK (and an AAB when signing secrets exist) and attaches them to a GitHub Release.

## Documentation

- [User guide](docs/USER_GUIDE.md) — importing, banks, quizzes, review modes, exporting, backups
- [Excel format](docs/EXCEL_FORMAT.md)
- [Database](docs/DATABASE.md)
- [Architecture](docs/ARCHITECTURE.md) — design decisions, sync and AI plans
- [Development summary](docs/DEVELOPMENT_SUMMARY.md) — what is done, test status, limitations

## Privacy

No accounts, analytics, ads or network calls. Data leaves the device only when you export or back up and choose where to save the file.
