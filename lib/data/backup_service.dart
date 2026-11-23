import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common/sqlite_api.dart';

import '../core/dates.dart';
import 'db.dart';
import 'media_store.dart';

/// Summary of a backup file, shown before restoring.
class BackupInfo {
  BackupInfo({
    required this.formatVersion,
    required this.schemaVersion,
    required this.createdAt,
    required this.appVersion,
    required this.counts,
    required this.mediaFiles,
  });
  final int formatVersion;
  final int schemaVersion;
  final DateTime? createdAt;
  final String appVersion;
  final Map<String, int> counts;
  final int mediaFiles;
}

class BackupException implements Exception {
  BackupException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Complete, versioned backups: every table (subjects, banks, questions,
/// options, history, schedules, bookmarks, notes, goals, settings) plus all
/// stored media, in one .zip file.
///
/// Format (version 1):
/// ```
/// quizme-backup.json   {"format":"quiz-me-backup","formatVersion":1,
///                       "schemaVersion":N,"appVersion":"…","createdAt":ms,
///                       "counts":{table:n}}
/// tables/<table>.json  [ {column: value, …}, … ]
/// media/<file>         images and audio
/// ```
class BackupService {
  BackupService(this.db, this.media, {this.appVersion = '1.0.0'});
  final Database db;
  final MediaStore media;
  final String appVersion;

  static const String format = 'quiz-me-backup';
  static const int formatVersion = 1;
  static const String manifestName = 'quizme-backup.json';

  Future<List<int>> create() async {
    final archive = Archive();
    final counts = <String, int>{};
    for (final t in AppDatabase.tables) {
      final rows = await db.query(t);
      counts[t] = rows.length;
      final bytes = utf8.encode(jsonEncode(rows));
      archive.addFile(ArchiveFile('tables/$t.json', bytes.length, bytes));
    }
    var mediaCount = 0;
    for (final e in (await media.all()).entries) {
      final bytes = await e.value.readAsBytes();
      archive.addFile(ArchiveFile('media/${e.key}', bytes.length, bytes));
      mediaCount++;
    }
    final manifest = utf8.encode(jsonEncode({
      'format': format,
      'formatVersion': formatVersion,
      'schemaVersion': AppDatabase.schemaVersion,
      'appVersion': appVersion,
      'createdAt': toMs(DateTime.now()),
      'counts': counts,
      'mediaFiles': mediaCount,
    }));
    archive.addFile(ArchiveFile(manifestName, manifest.length, manifest));
    final out = ZipEncoder().encode(archive);
    if (out == null) throw BackupException('The backup could not be created.');
    return out;
  }

  static String suggestedFileName(DateTime t) =>
      'quiz-me-backup-${dayKey(t)}-${t.hour.toString().padLeft(2, '0')}${t.minute.toString().padLeft(2, '0')}.zip';

  /// Validates a backup and returns its summary. Throws [BackupException].
  BackupInfo inspect(List<int> bytes) {
    final (info, _) = _open(bytes);
    return info;
  }

  (BackupInfo, Archive) _open(List<int> bytes) {
    final archive = _decode(bytes);
    final mf = archive.findFile(manifestName);
    if (mf == null) throw BackupException('The selected backup could not be validated.');
    final m = _manifest(mf);
    if (m['format'] != format) {
      throw BackupException('The selected file is not a Quiz me backup.');
    }
    final fv = (m['formatVersion'] as num?)?.toInt() ?? 0;
    final sv = (m['schemaVersion'] as num?)?.toInt() ?? 0;
    if (fv > formatVersion || sv > AppDatabase.schemaVersion) {
      throw BackupException(
          'This backup was made by a newer version of Quiz me. Please update the app first.');
    }
    for (final t in ['categories', 'banks', 'questions', 'options']) {
      if (archive.findFile('tables/$t.json') == null) {
        throw BackupException('The selected backup is incomplete (missing $t).');
      }
    }
    final counts = ((m['counts'] as Map?) ?? {}).map((k, v) => MapEntry(k.toString(), (v as num).toInt()));
    final mediaFiles = archive.files.where((f) => f.isFile && f.name.startsWith('media/')).length;
    return (
      BackupInfo(
        formatVersion: fv,
        schemaVersion: sv,
        createdAt: fromMs(m['createdAt']),
        appVersion: (m['appVersion'] ?? '') as String,
        counts: counts,
        mediaFiles: mediaFiles,
      ),
      archive
    );
  }

  static Archive _decode(List<int> bytes) {
    try {
      return ZipDecoder().decodeBytes(bytes);
    } catch (_) {
      throw BackupException('The selected backup could not be validated.');
    }
  }

  static Map<String, dynamic> _manifest(ArchiveFile f) {
    try {
      return jsonDecode(utf8.decode(f.content as List<int>)) as Map<String, dynamic>;
    } catch (_) {
      throw BackupException('The selected backup could not be validated.');
    }
  }

  /// Replaces ALL current data with the backup. Runs in one transaction, so a
  /// failed restore leaves the existing data untouched. The UI must warn the
  /// user and should create a safety backup first.
  Future<BackupInfo> restore(List<int> bytes) async {
    final (info, archive) = _open(bytes);
    final tables = <String, List<Map<String, Object?>>>{};
    for (final t in AppDatabase.tables) {
      final f = archive.findFile('tables/$t.json');
      if (f == null) {
        tables[t] = const [];
        continue;
      }
      try {
        final list = jsonDecode(utf8.decode(f.content as List<int>)) as List;
        tables[t] = list.map((e) => Map<String, Object?>.from(e as Map)).toList();
      } catch (_) {
        throw BackupException('The selected backup could not be validated (table $t is damaged).');
      }
    }

    await db.transaction((txn) async {
      // Check foreign keys at commit time, so rows can be inserted in any
      // order (e.g. a sub-category stored before its parent).
      await txn.execute('PRAGMA defer_foreign_keys = ON');
      for (final t in AppDatabase.tables.reversed) {
        await txn.delete(t);
      }
      for (final t in AppDatabase.tables) {
        final cols = (await txn.rawQuery('PRAGMA table_info($t)'))
            .map((r) => r['name'] as String)
            .toSet();
        var batch = txn.batch();
        var n = 0;
        for (final row in tables[t]!) {
          final clean = <String, Object?>{
            for (final e in row.entries)
              if (cols.contains(e.key)) e.key: e.value
          };
          if (clean.isEmpty) continue;
          batch.insert(t, clean, conflictAlgorithm: ConflictAlgorithm.replace);
          if (++n % 500 == 0) {
            await batch.commit(noResult: true);
            batch = txn.batch();
          }
        }
        await batch.commit(noResult: true);
      }
    });

    // Media: write after the database commit succeeded.
    await media.ensure();
    for (final f in archive.files) {
      if (!f.isFile || !f.name.startsWith('media/')) continue;
      final name = p.basename(f.name);
      if (name.isEmpty || name.startsWith('.')) continue;
      final target = media.resolve(name);
      if (target == null) continue;
      await target.writeAsBytes(f.content as List<int>, flush: true);
    }
    return info;
  }
}
