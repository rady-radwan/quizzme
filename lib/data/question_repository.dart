import 'package:sqflite_common/sqlite_api.dart';

import '../core/dates.dart';
import '../core/ids.dart';
import '../core/import/fingerprint.dart';
import '../core/models.dart';
import 'db.dart';

/// Search and filter criteria for the question browser. Every field narrows
/// the result; all of them can be combined.
class QuestionFilter {
  const QuestionFilter({
    this.text = '',
    this.bankIds,
    this.types = const {},
    this.difficulties = const {},
    this.masteryLevels = const {},
    this.tag,
    this.importId,
    this.bookmarkedOnly = false,
    this.neverAttempted = false,
    this.previouslyIncorrect = false,
    this.correctOnLast = false,
    this.incorrectMultiple = false,
    this.dueForRevision = false,
    this.overdue = false,
    this.mastered = false,
    this.notStudied30Days = false,
    this.includeArchived = false,
    this.archivedOnly = false,
  });

  final String text;

  /// Null = all banks.
  final List<String>? bankIds;
  final Set<QuestionType> types;
  final Set<Difficulty> difficulties;
  final Set<MasteryLevel> masteryLevels;
  final String? tag;
  final String? importId;
  final bool bookmarkedOnly;
  final bool neverAttempted;
  final bool previouslyIncorrect;
  final bool correctOnLast;
  final bool incorrectMultiple;
  final bool dueForRevision;
  final bool overdue;
  final bool mastered;
  final bool notStudied30Days;
  final bool includeArchived;
  final bool archivedOnly;

  int get activeCount =>
      (text.trim().isNotEmpty ? 1 : 0) +
      (types.isNotEmpty ? 1 : 0) +
      (difficulties.isNotEmpty ? 1 : 0) +
      (masteryLevels.isNotEmpty ? 1 : 0) +
      (tag != null ? 1 : 0) +
      (importId != null ? 1 : 0) +
      [
        bookmarkedOnly,
        neverAttempted,
        previouslyIncorrect,
        correctOnLast,
        incorrectMultiple,
        dueForRevision,
        overdue,
        mastered,
        notStudied30Days,
        archivedOnly,
      ].where((b) => b).length;

  QuestionFilter copyWith({
    String? text,
    List<String>? bankIds,
    Set<QuestionType>? types,
    Set<Difficulty>? difficulties,
    Set<MasteryLevel>? masteryLevels,
    String? tag,
    bool clearTag = false,
    String? importId,
    bool clearImport = false,
    bool? bookmarkedOnly,
    bool? neverAttempted,
    bool? previouslyIncorrect,
    bool? correctOnLast,
    bool? incorrectMultiple,
    bool? dueForRevision,
    bool? overdue,
    bool? mastered,
    bool? notStudied30Days,
    bool? includeArchived,
    bool? archivedOnly,
  }) =>
      QuestionFilter(
        text: text ?? this.text,
        bankIds: bankIds ?? this.bankIds,
        types: types ?? this.types,
        difficulties: difficulties ?? this.difficulties,
        masteryLevels: masteryLevels ?? this.masteryLevels,
        tag: clearTag ? null : (tag ?? this.tag),
        importId: clearImport ? null : (importId ?? this.importId),
        bookmarkedOnly: bookmarkedOnly ?? this.bookmarkedOnly,
        neverAttempted: neverAttempted ?? this.neverAttempted,
        previouslyIncorrect: previouslyIncorrect ?? this.previouslyIncorrect,
        correctOnLast: correctOnLast ?? this.correctOnLast,
        incorrectMultiple: incorrectMultiple ?? this.incorrectMultiple,
        dueForRevision: dueForRevision ?? this.dueForRevision,
        overdue: overdue ?? this.overdue,
        mastered: mastered ?? this.mastered,
        notStudied30Days: notStudied30Days ?? this.notStudied30Days,
        includeArchived: includeArchived ?? this.includeArchived,
        archivedOnly: archivedOnly ?? this.archivedOnly,
      );

  /// SQL WHERE clause (over `questions q LEFT JOIN progress p`) and arguments.
  (String, List<Object?>) toSql(DateTime now) {
    final where = <String>[];
    final args = <Object?>[];
    if (archivedOnly) {
      where.add('q.archived = 1');
    } else if (!includeArchived) {
      where.add('q.archived = 0');
    }
    if (bankIds != null) where.add('q.bank_id IN ${sqlInList(bankIds!)}');
    final t = text.trim();
    if (t.isNotEmpty) {
      final like = '%${_escapeLike(t)}%';
      where.add('(q.text LIKE ? ESCAPE \'\\\' OR q.explanation LIKE ? ESCAPE \'\\\' '
          'OR q.tags LIKE ? ESCAPE \'\\\' OR q.accepted_answers LIKE ? ESCAPE \'\\\' '
          'OR EXISTS (SELECT 1 FROM options o WHERE o.question_id = q.id AND '
          '(o.text LIKE ? ESCAPE \'\\\' OR o.match_text LIKE ? ESCAPE \'\\\')) '
          'OR EXISTS (SELECT 1 FROM notes n WHERE n.question_id = q.id AND n.text LIKE ? ESCAPE \'\\\'))');
      args.addAll(List.filled(7, like));
    }
    if (types.isNotEmpty) {
      where.add('q.type IN (${types.map((_) => '?').join(',')})');
      args.addAll(types.map((e) => e.key));
    }
    if (difficulties.isNotEmpty) {
      where.add('q.difficulty IN (${difficulties.map((d) => d.index).join(',')})');
    }
    if (masteryLevels.isNotEmpty) {
      where.add('COALESCE(p.mastery, 0) IN (${masteryLevels.map((d) => d.index).join(',')})');
    }
    if (tag != null && tag!.trim().isNotEmpty) {
      where.add('q.tags LIKE ? ESCAPE \'\\\'');
      args.add('%,${_escapeLike(tag!.trim())},%');
    }
    if (importId != null) {
      where.add('q.import_id = ?');
      args.add(importId);
    }
    if (bookmarkedOnly) where.add('q.id IN (SELECT question_id FROM bookmarks)');
    if (neverAttempted) where.add('COALESCE(p.attempt_count, 0) = 0');
    if (previouslyIncorrect) where.add('COALESCE(p.incorrect_count, 0) > 0');
    if (correctOnLast) where.add("p.last_result = 'correct'");
    if (incorrectMultiple) where.add('COALESCE(p.incorrect_count, 0) >= 2');
    if (dueForRevision) {
      where.add('p.due_at IS NOT NULL AND p.due_at <= ?');
      args.add(toMs(endOfDay(now)));
    }
    if (overdue) {
      where.add('p.due_at IS NOT NULL AND p.due_at < ?');
      args.add(toMs(startOfDay(now)));
    }
    if (mastered) where.add('p.mastery = ${MasteryLevel.mastered.index}');
    if (notStudied30Days) {
      where.add('p.last_attempt_at IS NOT NULL AND p.last_attempt_at < ?');
      args.add(toMs(now.subtract(const Duration(days: 30))));
    }
    return (where.isEmpty ? '1 = 1' : where.join(' AND '), args);
  }

  static String _escapeLike(String s) =>
      s.replaceAll('\\', '\\\\').replaceAll('%', '\\%').replaceAll('_', '\\_');
}

/// A lightweight row for question lists (no options loaded).
class QuestionListItem {
  QuestionListItem.fromRow(Map<String, Object?> r)
      : id = r['id'] as String,
        bankId = r['bank_id'] as String,
        bankName = (r['bank_name'] ?? '') as String,
        text = (r['text'] ?? '') as String,
        type = QuestionType.fromKey(r['type'] as String?),
        difficulty = Difficulty.fromIndex(intOf(r['difficulty'])),
        mastery = MasteryLevel.fromIndex(intOf(r['mastery'])),
        lastResult = AttemptResult.fromKey(r['last_result'] as String?),
        attempts = intOf(r['attempt_count']),
        correct = intOf(r['correct_count']),
        incorrect = intOf(r['incorrect_count']),
        dueAt = fromMs(r['due_at']),
        bookmarked = intOf(r['bookmarked']) == 1,
        archived = intOf(r['archived']) == 1,
        tags = decodeTags(r['tags']);

  final String id;
  final String bankId;
  final String bankName;
  final String text;
  final QuestionType type;
  final Difficulty difficulty;
  final MasteryLevel mastery;
  final AttemptResult? lastResult;
  final int attempts;
  final int correct;
  final int incorrect;
  final DateTime? dueAt;
  final bool bookmarked;
  final bool archived;
  final List<String> tags;

  double? get accuracy =>
      correct + incorrect == 0 ? null : correct / (correct + incorrect);
}

class Note {
  Note(this.id, this.questionId, this.text, this.createdAt, this.updatedAt);
  final String id;
  final String questionId;
  final String text;
  final DateTime createdAt;
  final DateTime updatedAt;

  factory Note.fromRow(Map<String, Object?> r) => Note(
        r['id'] as String,
        r['question_id'] as String,
        r['text'] as String,
        fromMs(r['created_at']) ?? DateTime.now(),
        fromMs(r['updated_at']) ?? DateTime.now(),
      );
}

class ImportRecord {
  ImportRecord.fromRow(Map<String, Object?> r)
      : id = r['id'] as String,
        bankId = r['bank_id'] as String?,
        fileName = r['file_name'] as String,
        importedAt = fromMs(r['imported_at']) ?? DateTime.now(),
        status = r['status'] as String,
        imported = intOf(r['imported_count']),
        updated = intOf(r['updated_count']),
        skipped = intOf(r['skipped_count']),
        errors = intOf(r['error_count']),
        totalRows = intOf(r['total_rows']),
        log = (r['log'] ?? '') as String;

  final String id;
  final String? bankId;
  final String fileName;
  final DateTime importedAt;
  final String status;
  final int imported;
  final int updated;
  final int skipped;
  final int errors;
  final int totalRows;
  final String log;
}

class QuestionRepository {
  QuestionRepository(this.db);
  final Database db;

  static const _listColumns = '''
q.id, q.bank_id, q.text, q.type, q.difficulty, q.tags, q.archived, b.name AS bank_name,
COALESCE(p.mastery, 0) AS mastery, p.last_result, COALESCE(p.attempt_count, 0) AS attempt_count,
COALESCE(p.correct_count, 0) AS correct_count, COALESCE(p.incorrect_count, 0) AS incorrect_count,
p.due_at, CASE WHEN bm.question_id IS NULL THEN 0 ELSE 1 END AS bookmarked''';

  static const _listFrom = '''
FROM questions q
JOIN banks b ON b.id = q.bank_id
LEFT JOIN progress p ON p.question_id = q.id
LEFT JOIN bookmarks bm ON bm.question_id = q.id''';

  Future<List<QuestionListItem>> search(QuestionFilter f,
      {int limit = 50, int offset = 0, DateTime? now}) async {
    final (where, args) = f.toSql(now ?? DateTime.now());
    final rows = await db.rawQuery(
      'SELECT $_listColumns $_listFrom WHERE $where '
      'ORDER BY q.created_at, q.rowid LIMIT ? OFFSET ?',
      [...args, limit, offset],
    );
    return rows.map(QuestionListItem.fromRow).toList();
  }

  Future<int> count(QuestionFilter f, {DateTime? now}) async {
    final (where, args) = f.toSql(now ?? DateTime.now());
    final rows = await db.rawQuery(
        'SELECT COUNT(*) AS n $_listFrom WHERE $where', args);
    return intOf(rows.first['n']);
  }

  Future<List<String>> searchIds(QuestionFilter f, {int limit = 5000, DateTime? now}) async {
    final (where, args) = f.toSql(now ?? DateTime.now());
    final rows = await db.rawQuery(
        'SELECT q.id $_listFrom WHERE $where ORDER BY q.created_at LIMIT ?',
        [...args, limit]);
    return rows.map((r) => r['id'] as String).toList();
  }

  Future<Question?> question(String id) async {
    final list = await questionsByIds([id]);
    return list.isEmpty ? null : list.first;
  }

  /// Loads full questions (with options) preserving the order of [ids].
  Future<List<Question>> questionsByIds(List<String> ids,
      [DatabaseExecutor? ex]) async {
    final e = ex ?? db;
    final out = <String, Question>{};
    for (var i = 0; i < ids.length; i += 500) {
      final chunk = ids.sublist(i, i + 500 > ids.length ? ids.length : i + 500);
      final qRows = await e.rawQuery('SELECT * FROM questions WHERE id IN ${sqlInList(chunk)}');
      final oRows = await e.rawQuery(
          'SELECT * FROM options WHERE question_id IN ${sqlInList(chunk)} ORDER BY position');
      final byQ = <String, List<AnswerOption>>{};
      for (final r in oRows) {
        byQ.putIfAbsent(r['question_id'] as String, () => []).add(AnswerOption.fromRow(r));
      }
      for (final r in qRows) {
        final q = Question.fromRow(r, byQ[r['id']] ?? const []);
        out[q.id] = q;
      }
    }
    return [for (final id in ids) if (out[id] != null) out[id]!];
  }

  /// Creates or updates a question and its options.
  ///
  /// Options keep their ids, so earlier answers stay linked. When
  /// [resetLearning] is true (a major content change that invalidates earlier
  /// answers) the scheduling and mastery state are reset and the content
  /// version is bumped; the attempt history itself is preserved.
  Future<Question> saveQuestion(Question q, {bool resetLearning = false}) async {
    final existing = await db.query('questions',
        columns: ['id', 'content_version', 'created_at'], where: 'id = ?', whereArgs: [q.id]);
    final opts = <AnswerOption>[];
    for (var i = 0; i < q.options.length; i++) {
      opts.add(q.options[i].copyWith(position: i));
    }
    var saved = q.copyWith(options: opts);
    saved = saved.copyWith(fingerprint: questionFingerprint(saved));
    if (existing.isNotEmpty && resetLearning) {
      saved = saved.copyWith(contentVersion: intOf(existing.first['content_version']) + 1);
    }
    await db.transaction((txn) async {
      final row = saved.toRow();
      if (existing.isEmpty) {
        await txn.insert('questions', row);
      } else {
        row['created_at'] = existing.first['created_at'];
        await txn.update('questions', row, where: 'id = ?', whereArgs: [q.id]);
      }
      await writeOptions(txn, saved.id, saved.options);
      if (resetLearning && existing.isNotEmpty) {
        await txn.update(
          'progress',
          {
            'ease': 2.5,
            'interval_days': 0,
            'repetitions': 0,
            'lapses': 0,
            'due_at': null,
            'mastery': 0,
            'mastery_reason': 'Reset after the question was changed.',
            'consecutive_correct': 0,
            'last_result': null,
            'understood': 0,
            'updated_at': toMs(DateTime.now()),
          },
          where: 'question_id = ?',
          whereArgs: [q.id],
        );
      }
    });
    return saved;
  }

  /// Replaces the options of a question, updating options that kept their id.
  Future<void> writeOptions(
      DatabaseExecutor ex, String questionId, List<AnswerOption> options) async {
    final keep = options.map((o) => o.id).toList();
    await ex.delete('options',
        where: 'question_id = ? AND id NOT IN ${sqlInList(keep)}', whereArgs: [questionId]);
    for (final o in options) {
      await ex.insert('options', o.toRow(questionId),
          conflictAlgorithm: ConflictAlgorithm.replace);
    }
  }

  /// Copies a question (new ids, no learning history) into [targetBankId].
  Future<Question> duplicate(String id, {String? targetBankId}) async {
    final q = await question(id);
    if (q == null) throw StateError('Question not found');
    final copy = q.copyWith(
      id: newId(),
      bankId: targetBankId ?? q.bankId,
      options: q.options.map((o) => AnswerOption(
            id: newId(),
            text: o.text,
            position: o.position,
            isCorrect: o.isCorrect,
            matchText: o.matchText,
            explanation: o.explanation,
          )).toList(),
      contentVersion: 1,
    );
    await saveQuestion(copy);
    return copy;
  }

  /// Moves questions to another bank. Learning history is keyed by question id,
  /// so it moves with them.
  Future<void> move(List<String> ids, String targetBankId) async {
    await db.rawUpdate(
        'UPDATE questions SET bank_id = ?, updated_at = ? WHERE id IN ${sqlInList(ids)}',
        [targetBankId, toMs(DateTime.now())]);
  }

  Future<void> setArchived(List<String> ids, bool archived) async {
    await db.rawUpdate(
        'UPDATE questions SET archived = ?, updated_at = ? WHERE id IN ${sqlInList(ids)}',
        [archived ? 1 : 0, toMs(DateTime.now())]);
  }

  /// Permanently deletes questions with their options and history.
  /// The UI must confirm before calling this.
  Future<void> delete(List<String> ids) async {
    await db.transaction((txn) async {
      for (var i = 0; i < ids.length; i += 500) {
        final chunk = ids.sublist(i, i + 500 > ids.length ? ids.length : i + 500);
        await txn.rawDelete('DELETE FROM questions WHERE id IN ${sqlInList(chunk)}');
      }
    });
  }

  /// Groups of questions in [bankIds] that share the same content fingerprint.
  Future<List<List<QuestionListItem>>> duplicateGroups(List<String> bankIds) async {
    final rows = await db.rawQuery('''
SELECT $_listColumns, q.fingerprint AS fp $_listFrom
WHERE q.bank_id IN ${sqlInList(bankIds)} AND q.archived = 0 AND q.fingerprint IN (
  SELECT fingerprint FROM questions WHERE bank_id IN ${sqlInList(bankIds)} AND archived = 0
  GROUP BY fingerprint HAVING COUNT(*) > 1)
ORDER BY q.fingerprint, q.created_at''');
    final groups = <String, List<QuestionListItem>>{};
    for (final r in rows) {
      groups.putIfAbsent(r['fp'] as String, () => []).add(QuestionListItem.fromRow(r));
    }
    return groups.values.toList();
  }

  Future<List<String>> tagsIn(List<String>? bankIds) async {
    final rows = await db.rawQuery(
        "SELECT tags FROM questions WHERE tags != '' AND archived = 0"
        '${bankIds == null ? '' : ' AND bank_id IN ${sqlInList(bankIds)}'} LIMIT 20000');
    final set = <String>{};
    for (final r in rows) {
      set.addAll(decodeTags(r['tags']));
    }
    return set.toList()..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
  }

  // ---------------- Bookmarks ----------------

  Future<bool> isBookmarked(String questionId) async {
    final r = await db.query('bookmarks', where: 'question_id = ?', whereArgs: [questionId]);
    return r.isNotEmpty;
  }

  Future<bool> toggleBookmark(String questionId) async {
    if (await isBookmarked(questionId)) {
      await db.delete('bookmarks', where: 'question_id = ?', whereArgs: [questionId]);
      return false;
    }
    await db.insert('bookmarks', {'question_id': questionId, 'created_at': toMs(DateTime.now())},
        conflictAlgorithm: ConflictAlgorithm.ignore);
    return true;
  }

  Future<int> bookmarkCount() async {
    final r = await db.rawQuery('SELECT COUNT(*) AS n FROM bookmarks');
    return intOf(r.first['n']);
  }

  // ---------------- Notes ----------------

  Future<List<Note>> notesFor(String questionId) async {
    final rows = await db.query('notes',
        where: 'question_id = ?', whereArgs: [questionId], orderBy: 'created_at');
    return rows.map(Note.fromRow).toList();
  }

  Future<Note> addNote(String questionId, String text) async {
    final now = DateTime.now();
    final n = Note(newId(), questionId, text.trim(), now, now);
    await db.insert('notes', {
      'id': n.id,
      'question_id': questionId,
      'text': n.text,
      'created_at': toMs(now),
      'updated_at': toMs(now),
    });
    return n;
  }

  Future<void> updateNote(String id, String text) => db.update(
      'notes', {'text': text.trim(), 'updated_at': toMs(DateTime.now())},
      where: 'id = ?', whereArgs: [id]);

  Future<void> deleteNote(String id) => db.delete('notes', where: 'id = ?', whereArgs: [id]);

  /// Notes matching [query], newest first, with their question text.
  Future<List<(Note, String)>> searchNotes(String query, {int limit = 200}) async {
    final like = '%${QuestionFilter._escapeLike(query.trim())}%';
    final rows = await db.rawQuery('''
SELECT n.*, q.text AS question_text FROM notes n JOIN questions q ON q.id = n.question_id
WHERE n.text LIKE ? ESCAPE '\\' OR q.text LIKE ? ESCAPE '\\'
ORDER BY n.updated_at DESC LIMIT ?''', [like, like, limit]);
    return rows.map((r) => (Note.fromRow(r), (r['question_text'] ?? '') as String)).toList();
  }

  // ---------------- Imports ----------------

  Future<List<ImportRecord>> importsForBank(String bankId) async {
    final rows = await db.query('imports',
        where: 'bank_id = ?', whereArgs: [bankId], orderBy: 'imported_at DESC');
    return rows.map(ImportRecord.fromRow).toList();
  }

  Future<List<ImportRecord>> allImports({int limit = 200}) async {
    final rows = await db.query('imports', orderBy: 'imported_at DESC', limit: limit);
    return rows.map(ImportRecord.fromRow).toList();
  }
}
