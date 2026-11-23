import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:sqflite_common/sqlite_api.dart';

import '../data/db.dart';

/// When a row of a synchronised table was last written, and whether that
/// write was a deletion.
class SyncEntry {
  const SyncEntry(this.ts, {this.deleted = false});
  final int ts;
  final bool deleted;
}

/// Everything that is synchronised: the rows of every synchronised table and
/// the change log (including deletions). Stored in Google Drive as one
/// gzip-compressed JSON file.
class SyncSnapshot {
  SyncSnapshot({required this.rows, required this.meta, this.deviceName = '', int? createdAt})
      : createdAt = createdAt ?? DateTime.now().millisecondsSinceEpoch;

  static const format = 'quizme-sync';
  static const formatVersion = 1;

  /// table -> key -> row.
  final Map<String, Map<String, Map<String, Object?>>> rows;

  /// table -> key -> last change.
  final Map<String, Map<String, SyncEntry>> meta;
  final String deviceName;
  final int createdAt;

  bool get isEmpty => meta.values.every((m) => m.isEmpty);

  int get rowCount => rows.values.fold(0, (a, m) => a + m.length);

  /// Data part only, with sorted keys: equal for equal content.
  String canonical() {
    final b = StringBuffer();
    for (final t in (meta.keys.toList()..sort())) {
      final m = meta[t]!;
      for (final k in (m.keys.toList()..sort())) {
        final e = m[k]!;
        b
          ..write(t)
          ..write('\u0001')
          ..write(k)
          ..write('\u0001')
          ..write(e.ts)
          ..write(e.deleted ? 'D' : 'L')
          ..write(e.deleted ? '' : canonicalRow(rows[t]?[k]))
          ..write('\n');
      }
    }
    return b.toString();
  }

  List<int> encode() {
    final json = jsonEncode({
      'format': format,
      'formatVersion': formatVersion,
      'schemaVersion': AppDatabase.schemaVersion,
      'device': deviceName,
      'createdAt': createdAt,
      'tables': {for (final e in rows.entries) e.key: e.value.values.toList()},
      'meta': [
        for (final t in meta.entries)
          for (final e in t.value.entries) [t.key, e.key, e.value.ts, e.value.deleted ? 1 : 0],
      ],
    });
    return GZipEncoder().encode(utf8.encode(json))!;
  }

  static SyncSnapshot decode(List<int> bytes) {
    final Map<String, Object?> m;
    try {
      m = jsonDecode(utf8.decode(GZipDecoder().decodeBytes(bytes))) as Map<String, Object?>;
    } catch (_) {
      throw const SyncFormatException('The sync file in Google Drive could not be read.');
    }
    if (m['format'] != format) throw const SyncFormatException('The file in Google Drive is not a Quiz me sync file.');
    if (((m['formatVersion'] as num?)?.toInt() ?? 0) > formatVersion ||
        ((m['schemaVersion'] as num?)?.toInt() ?? 0) > AppDatabase.schemaVersion) {
      throw const SyncFormatException(
          'Your data in Google Drive was saved by a newer version of Quiz me. Update the app on this device first.');
    }
    final rows = <String, Map<String, Map<String, Object?>>>{};
    final tables = (m['tables'] as Map?) ?? const {};
    for (final e in tables.entries) {
      final t = e.key as String;
      if (!AppDatabase.syncKeys.containsKey(t)) continue;
      final byKey = <String, Map<String, Object?>>{};
      for (final r in (e.value as List)) {
        final row = Map<String, Object?>.from(r as Map);
        byKey[SyncStore.keyOf(t, row)] = row;
      }
      rows[t] = byKey;
    }
    final meta = <String, Map<String, SyncEntry>>{};
    for (final r in (m['meta'] as List? ?? const [])) {
      final l = r as List;
      final t = l[0] as String;
      if (!AppDatabase.syncKeys.containsKey(t)) continue;
      meta.putIfAbsent(t, () => {})[l[1] as String] =
          SyncEntry((l[2] as num).toInt(), deleted: (l[3] as num).toInt() == 1);
    }
    return SyncSnapshot(
      rows: rows,
      meta: meta,
      deviceName: m['device'] as String? ?? '',
      createdAt: (m['createdAt'] as num?)?.toInt(),
    );
  }
}

String canonicalRow(Map<String, Object?>? row) {
  if (row == null) return '';
  final keys = row.keys.toList()..sort();
  return jsonEncode({for (final k in keys) k: row[k]});
}

class SyncFormatException implements Exception {
  const SyncFormatException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Result of merging the cloud copy into this device.
class MergeResult {
  MergeResult({this.updated = 0, this.deleted = 0, this.skipped = 0});
  int updated;
  int deleted;
  int skipped;
  bool get changedLocal => updated > 0 || deleted > 0;
}

/// Reads and writes the synchronised part of the local database.
class SyncStore {
  SyncStore(this.db);
  final Database db;

  /// Key of [row] in [table], e.g. `id` or `session_id|position`.
  static String keyOf(String table, Map<String, Object?> row) =>
      AppDatabase.syncKeys[table]!.map((c) => '${row[c]}').join('|');

  static (String, List<Object?>) _where(String table, String key) {
    final cols = AppDatabase.syncKeys[table]!;
    final parts = cols.length == 1 ? [key] : key.split('|');
    if (parts.length != cols.length) throw ArgumentError('Bad sync key $key for $table');
    return (cols.map((c) => '$c = ?').join(' AND '), parts);
  }

  Future<bool> hasLocalData() async {
    for (final t in ['categories', 'questions', 'attempts']) {
      final r = await db.rawQuery('SELECT 1 FROM $t LIMIT 1');
      if (r.isNotEmpty) return true;
    }
    return false;
  }

  /// The current synchronised data of this device.
  Future<SyncSnapshot> snapshot({String deviceName = ''}) async {
    final rows = <String, Map<String, Map<String, Object?>>>{};
    final meta = <String, Map<String, SyncEntry>>{};
    await db.transaction((txn) async {
      for (final t in AppDatabase.syncTables) {
        final byKey = <String, Map<String, Object?>>{};
        for (final r in await txn.query(t)) {
          final row = Map<String, Object?>.from(r);
          byKey[keyOf(t, row)] = row;
        }
        rows[t] = byKey;
      }
      for (final r in await txn.query('sync_meta')) {
        final t = r['tbl'] as String;
        if (!AppDatabase.syncKeys.containsKey(t)) continue;
        meta.putIfAbsent(t, () => {})[r['pk'] as String] =
            SyncEntry(intOf(r['modified_at']), deleted: intOf(r['deleted']) == 1);
      }
    });
    // Rows that somehow have no change record still have to travel.
    for (final t in rows.keys) {
      final m = meta.putIfAbsent(t, () => {});
      for (final k in rows[t]!.keys) {
        m.putIfAbsent(k, () => const SyncEntry(1));
      }
    }
    return SyncSnapshot(rows: rows, meta: meta, deviceName: deviceName);
  }

  /// Whether the remote change for one row wins over the local one: the
  /// later change wins; exact ties are broken by content so that every
  /// device makes the same choice.
  static bool remoteWins(SyncEntry r, Map<String, Object?>? rRow, SyncEntry? l, Map<String, Object?>? lRow) {
    if (l == null) return true;
    if (r.ts != l.ts) return r.ts > l.ts;
    final rs = r.deleted ? '' : canonicalRow(rRow);
    final ls = l.deleted ? '' : canonicalRow(lRow);
    return rs.compareTo(ls) > 0;
  }

  /// Applies the changes of [remote] that are newer than this device's.
  Future<MergeResult> merge(SyncSnapshot remote) async {
    final local = await snapshot();
    final result = MergeResult();
    await db.transaction((txn) async {
      await txn.update('sync_control', {'applying': 1}, where: 'id = 1');
      try {
        // Deletions first, children before parents.
        for (final t in AppDatabase.syncTables.reversed) {
          final rm = remote.meta[t] ?? const {};
          for (final e in rm.entries) {
            if (!e.value.deleted) continue;
            final l = local.meta[t]?[e.key];
            if (!remoteWins(e.value, null, l, local.rows[t]?[e.key])) continue;
            final (where, args) = _where(t, e.key);
            result.deleted += await txn.delete(t, where: where, whereArgs: args);
            await _setMeta(txn, t, e.key, e.value);
          }
        }
        // Then new and changed rows, parents before children.
        for (final t in AppDatabase.syncTables) {
          final rm = remote.meta[t] ?? const {};
          final pending = <String>[];
          for (final e in rm.entries) {
            if (e.value.deleted) continue;
            final row = remote.rows[t]?[e.key];
            if (row == null) continue;
            if (!remoteWins(e.value, row, local.meta[t]?[e.key], local.rows[t]?[e.key])) continue;
            pending.add(e.key);
          }
          final cols = (await txn.rawQuery('PRAGMA table_info($t)')).map((r) => r['name'] as String).toSet();
          // Several passes: a sub-category may arrive before its parent.
          for (var pass = 0; pass < 8 && pending.isNotEmpty; pass++) {
            final failed = <String>[];
            for (final k in pending) {
              final row = remote.rows[t]![k]!;
              final values = {
                for (final c in row.entries)
                  if (cols.contains(c.key)) c.key: c.value
              };
              try {
                final (where, args) = _where(t, k);
                final n = await txn.update(t, values, where: where, whereArgs: args);
                if (n == 0) await txn.insert(t, values);
                await _setMeta(txn, t, k, rm[k]!);
                result.updated++;
              } on DatabaseException {
                // Usually a missing parent (deleted on this device later).
                failed.add(k);
              }
            }
            if (failed.length == pending.length) break;
            pending
              ..clear()
              ..addAll(failed);
          }
          result.skipped += pending.length;
        }
        // Rows removed by cascades while applying: mark them deleted.
        for (final t in AppDatabase.syncTables) {
          final cols = AppDatabase.syncKeys[t]!;
          final keyExpr = cols.join(" || '|' || ");
          await txn.rawUpdate(
              "UPDATE sync_meta SET deleted = 1 WHERE tbl = ? AND deleted = 0 AND pk NOT IN (SELECT $keyExpr FROM $t)",
              [t]);
        }
      } finally {
        await txn.update('sync_control', {'applying': 0}, where: 'id = 1');
      }
    });
    return result;
  }

  /// Replaces all synchronised data of this device with [remote].
  Future<void> replaceWith(SyncSnapshot remote) async {
    await db.transaction((txn) async {
      await txn.update('sync_control', {'applying': 1}, where: 'id = 1');
      try {
        for (final t in AppDatabase.syncTables.reversed) {
          await txn.delete(t);
        }
        await txn.delete('sync_meta');
        for (final t in AppDatabase.syncTables) {
          final cols = (await txn.rawQuery('PRAGMA table_info($t)')).map((r) => r['name'] as String).toSet();
          var pending = (remote.rows[t] ?? const {}).keys.where((k) => remote.meta[t]?[k]?.deleted != true).toList();
          for (var pass = 0; pass < 8 && pending.isNotEmpty; pass++) {
            final failed = <String>[];
            for (final k in pending) {
              final row = remote.rows[t]![k]!;
              try {
                await txn.insert(t, {
                  for (final c in row.entries)
                    if (cols.contains(c.key)) c.key: c.value
                });
              } on DatabaseException {
                failed.add(k);
              }
            }
            if (failed.length == pending.length) break;
            pending = failed;
          }
        }
        final batch = txn.batch();
        for (final t in remote.meta.entries) {
          for (final e in t.value.entries) {
            batch.insert('sync_meta', {
              'tbl': t.key,
              'pk': e.key,
              'modified_at': e.value.ts,
              'deleted': e.value.deleted ? 1 : 0,
            });
          }
        }
        await batch.commit(noResult: true);
      } finally {
        await txn.update('sync_control', {'applying': 0}, where: 'id = 1');
      }
    });
  }

  Future<void> _setMeta(Transaction txn, String t, String key, SyncEntry e) async {
    await txn.delete('sync_meta', where: 'tbl = ? AND pk = ?', whereArgs: [t, key]);
    await txn.insert('sync_meta', {'tbl': t, 'pk': key, 'modified_at': e.ts, 'deleted': e.deleted ? 1 : 0});
  }
}
