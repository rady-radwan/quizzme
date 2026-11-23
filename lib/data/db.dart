import 'package:sqflite_common/sqlite_api.dart';

/// SQLite schema and migrations.
///
/// Every change to the schema is a new numbered migration appended to
/// [migrations]; existing migrations are never edited after release. On open,
/// sqflite runs the migrations between the stored `user_version` and
/// [schemaVersion] inside one transaction.
class AppDatabase {
  static const int schemaVersion = 1;
  static const String fileName = 'quiz_me.db';

  static Future<Database> open(DatabaseFactory factory, String path) {
    return factory.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: schemaVersion,
        onConfigure: (db) async {
          await db.execute('PRAGMA foreign_keys = ON');
        },
        onCreate: (db, version) => _migrate(db, 0, version),
        onUpgrade: (db, from, to) => _migrate(db, from, to),
      ),
    );
  }

  static Future<void> _migrate(Database db, int from, int to) async {
    for (var v = from + 1; v <= to; v++) {
      final steps = migrations[v];
      if (steps == null) throw StateError('Missing database migration $v');
      for (final sql in steps) {
        await db.execute(sql);
      }
    }
  }

  /// Tables in dependency order (parents before children). Used by backup and
  /// restore so foreign keys are always satisfied.
  static const List<String> tables = [
    'categories',
    'banks',
    'imports',
    'questions',
    'options',
    'progress',
    'sessions',
    'session_questions',
    'attempts',
    'presentations',
    'bookmarks',
    'notes',
    'goals',
    'achievements',
    'settings',
  ];

  static const Map<int, List<String>> migrations = {
    1: [
      '''
CREATE TABLE categories (
  id TEXT PRIMARY KEY,
  parent_id TEXT REFERENCES categories(id) ON DELETE CASCADE,
  name TEXT NOT NULL,
  description TEXT,
  icon TEXT,
  color INTEGER,
  sort_order INTEGER NOT NULL DEFAULT 0,
  archived INTEGER NOT NULL DEFAULT 0,
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL
)''',
      'CREATE INDEX idx_categories_parent ON categories(parent_id)',
      '''
CREATE TABLE banks (
  id TEXT PRIMARY KEY,
  category_id TEXT NOT NULL REFERENCES categories(id) ON DELETE CASCADE,
  name TEXT NOT NULL,
  description TEXT,
  icon TEXT,
  color INTEGER,
  sort_order INTEGER NOT NULL DEFAULT 0,
  archived INTEGER NOT NULL DEFAULT 0,
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL
)''',
      'CREATE INDEX idx_banks_category ON banks(category_id)',
      '''
CREATE TABLE imports (
  id TEXT PRIMARY KEY,
  bank_id TEXT REFERENCES banks(id) ON DELETE CASCADE,
  file_name TEXT NOT NULL,
  imported_at INTEGER NOT NULL,
  status TEXT NOT NULL,
  sheets INTEGER NOT NULL DEFAULT 0,
  total_rows INTEGER NOT NULL DEFAULT 0,
  imported_count INTEGER NOT NULL DEFAULT 0,
  updated_count INTEGER NOT NULL DEFAULT 0,
  skipped_count INTEGER NOT NULL DEFAULT 0,
  error_count INTEGER NOT NULL DEFAULT 0,
  log TEXT
)''',
      'CREATE INDEX idx_imports_bank ON imports(bank_id)',
      '''
CREATE TABLE questions (
  id TEXT PRIMARY KEY,
  bank_id TEXT NOT NULL REFERENCES banks(id) ON DELETE CASCADE,
  external_id TEXT,
  type TEXT NOT NULL,
  text TEXT NOT NULL,
  hint TEXT,
  explanation TEXT,
  correct_feedback TEXT,
  incorrect_feedback TEXT,
  difficulty INTEGER NOT NULL DEFAULT 1,
  tags TEXT NOT NULL DEFAULT '',
  shuffle_options INTEGER NOT NULL DEFAULT 1,
  case_sensitive INTEGER NOT NULL DEFAULT 0,
  accepted_answers TEXT NOT NULL DEFAULT '[]',
  source TEXT,
  study_notes TEXT,
  image_path TEXT,
  audio_path TEXT,
  import_id TEXT REFERENCES imports(id) ON DELETE SET NULL,
  fingerprint TEXT NOT NULL DEFAULT '',
  content_version INTEGER NOT NULL DEFAULT 1,
  archived INTEGER NOT NULL DEFAULT 0,
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL
)''',
      'CREATE INDEX idx_questions_bank ON questions(bank_id, archived)',
      'CREATE INDEX idx_questions_fingerprint ON questions(bank_id, fingerprint)',
      'CREATE INDEX idx_questions_external ON questions(bank_id, external_id)',
      'CREATE INDEX idx_questions_import ON questions(import_id)',
      '''
CREATE TABLE options (
  id TEXT PRIMARY KEY,
  question_id TEXT NOT NULL REFERENCES questions(id) ON DELETE CASCADE,
  position INTEGER NOT NULL,
  text TEXT NOT NULL,
  is_correct INTEGER NOT NULL DEFAULT 0,
  match_text TEXT,
  explanation TEXT
)''',
      'CREATE INDEX idx_options_question ON options(question_id, position)',
      '''
CREATE TABLE progress (
  question_id TEXT PRIMARY KEY REFERENCES questions(id) ON DELETE CASCADE,
  seen INTEGER NOT NULL DEFAULT 0,
  presented_count INTEGER NOT NULL DEFAULT 0,
  attempt_count INTEGER NOT NULL DEFAULT 0,
  correct_count INTEGER NOT NULL DEFAULT 0,
  incorrect_count INTEGER NOT NULL DEFAULT 0,
  skipped_count INTEGER NOT NULL DEFAULT 0,
  hint_count INTEGER NOT NULL DEFAULT 0,
  consecutive_correct INTEGER NOT NULL DEFAULT 0,
  last_result TEXT,
  first_presented_at INTEGER,
  last_presented_at INTEGER,
  last_attempt_at INTEGER,
  ease REAL NOT NULL DEFAULT 2.5,
  interval_days INTEGER NOT NULL DEFAULT 0,
  repetitions INTEGER NOT NULL DEFAULT 0,
  lapses INTEGER NOT NULL DEFAULT 0,
  due_at INTEGER,
  last_review_at INTEGER,
  mastery INTEGER NOT NULL DEFAULT 0,
  mastery_reason TEXT NOT NULL DEFAULT '',
  understood INTEGER NOT NULL DEFAULT 0,
  updated_at INTEGER NOT NULL DEFAULT 0
)''',
      'CREATE INDEX idx_progress_due ON progress(due_at)',
      'CREATE INDEX idx_progress_mastery ON progress(mastery)',
      '''
CREATE TABLE sessions (
  id TEXT PRIMARY KEY,
  title TEXT NOT NULL,
  config TEXT NOT NULL,
  status TEXT NOT NULL,
  created_at INTEGER NOT NULL,
  completed_at INTEGER,
  current_index INTEGER NOT NULL DEFAULT 0,
  elapsed_ms INTEGER NOT NULL DEFAULT 0,
  total INTEGER NOT NULL DEFAULT 0,
  correct INTEGER NOT NULL DEFAULT 0,
  incorrect INTEGER NOT NULL DEFAULT 0,
  unanswered INTEGER NOT NULL DEFAULT 0,
  score REAL,
  scope_label TEXT
)''',
      'CREATE INDEX idx_sessions_status ON sessions(status, created_at)',
      '''
CREATE TABLE session_questions (
  session_id TEXT NOT NULL REFERENCES sessions(id) ON DELETE CASCADE,
  position INTEGER NOT NULL,
  question_id TEXT NOT NULL REFERENCES questions(id) ON DELETE CASCADE,
  option_order TEXT NOT NULL DEFAULT '[]',
  response TEXT,
  result TEXT,
  applied INTEGER NOT NULL DEFAULT 0,
  hint_used INTEGER NOT NULL DEFAULT 0,
  confidence INTEGER,
  presented_at INTEGER,
  answered_at INTEGER,
  duration_ms INTEGER NOT NULL DEFAULT 0,
  mastery_after INTEGER,
  PRIMARY KEY (session_id, position)
)''',
      'CREATE INDEX idx_sq_question ON session_questions(question_id)',
      '''
CREATE TABLE attempts (
  id TEXT PRIMARY KEY,
  question_id TEXT NOT NULL REFERENCES questions(id) ON DELETE CASCADE,
  session_id TEXT REFERENCES sessions(id) ON DELETE SET NULL,
  answered_at INTEGER NOT NULL,
  result TEXT NOT NULL,
  response TEXT,
  hint_used INTEGER NOT NULL DEFAULT 0,
  confidence INTEGER,
  duration_ms INTEGER NOT NULL DEFAULT 0,
  mode TEXT,
  was_due INTEGER NOT NULL DEFAULT 0,
  mastery_before INTEGER NOT NULL DEFAULT 0,
  mastery_after INTEGER NOT NULL DEFAULT 0,
  content_version INTEGER NOT NULL DEFAULT 1
)''',
      'CREATE INDEX idx_attempts_question ON attempts(question_id, answered_at)',
      'CREATE INDEX idx_attempts_time ON attempts(answered_at)',
      '''
CREATE TABLE presentations (
  id TEXT PRIMARY KEY,
  question_id TEXT NOT NULL REFERENCES questions(id) ON DELETE CASCADE,
  session_id TEXT REFERENCES sessions(id) ON DELETE SET NULL,
  presented_at INTEGER NOT NULL
)''',
      'CREATE INDEX idx_presentations_question ON presentations(question_id)',
      '''
CREATE TABLE bookmarks (
  question_id TEXT PRIMARY KEY REFERENCES questions(id) ON DELETE CASCADE,
  created_at INTEGER NOT NULL
)''',
      '''
CREATE TABLE notes (
  id TEXT PRIMARY KEY,
  question_id TEXT NOT NULL REFERENCES questions(id) ON DELETE CASCADE,
  text TEXT NOT NULL,
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL
)''',
      'CREATE INDEX idx_notes_question ON notes(question_id)',
      '''
CREATE TABLE goals (
  id TEXT PRIMARY KEY,
  type TEXT NOT NULL,
  target INTEGER NOT NULL,
  category_id TEXT REFERENCES categories(id) ON DELETE CASCADE,
  active INTEGER NOT NULL DEFAULT 1,
  created_at INTEGER NOT NULL
)''',
      '''
CREATE TABLE achievements (
  id TEXT PRIMARY KEY,
  unlocked_at INTEGER NOT NULL
)''',
      '''
CREATE TABLE settings (
  key TEXT PRIMARY KEY,
  value TEXT
)''',
    ],
  };
}

final RegExp _safeId = RegExp(r'^[A-Za-z0-9_-]{1,64}$');

/// Builds `('id1','id2')` for an SQL IN clause from app-generated ids.
/// Ids are validated so the literal can never inject SQL. Returns `(NULL)`
/// for an empty list (matches nothing).
String sqlInList(Iterable<String> ids) {
  final list = ids.where(_safeId.hasMatch).toSet().toList();
  if (list.isEmpty) return '(NULL)';
  return '(${list.map((i) => "'$i'").join(',')})';
}

int intOf(Object? v) => v is int ? v : (v is num ? v.toInt() : 0);
double doubleOf(Object? v) => v is num ? v.toDouble() : 0;
