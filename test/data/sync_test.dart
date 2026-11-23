import 'package:flutter_test/flutter_test.dart';
import 'package:quiz_me/app/services.dart';
import 'package:quiz_me/core/models.dart';
import 'package:quiz_me/sync/sync_store.dart';

import 'database_test.dart' show mc, openServices, playSession, withBank;

Future<int> _count(AppServices s, String table) async =>
    (await s.db.rawQuery('SELECT COUNT(*) AS n FROM $table')).first['n'] as int;

/// One sync round between two devices through a shared "cloud" copy.
Future<void> _roundTrip(AppServices a, AppServices b) async {
  final cloudFromA = SyncSnapshot.decode((await SyncStore(a.db).snapshot()).encode());
  await SyncStore(b.db).merge(cloudFromA);
  final cloudFromB = SyncSnapshot.decode((await SyncStore(b.db).snapshot()).encode());
  await SyncStore(a.db).merge(cloudFromB);
}

Future<void> _expectSame(AppServices a, AppServices b) async {
  final sa = await SyncStore(a.db).snapshot();
  final sb = await SyncStore(b.db).snapshot();
  expect(sa.canonical(), sb.canonical());
}

void main() {
  test('every write is recorded in the change log, deletions included', () async {
    final (s, _, bankId) = await withBank(3);
    final meta = await s.db.query('sync_meta', where: "tbl = 'questions'");
    expect(meta.length, 3);
    expect(meta.every((r) => r['deleted'] == 0 && (r['modified_at'] as int) > 1000), isTrue);
    final ids = meta.map((r) => r['pk'] as String).toList();
    await s.questions.delete([ids.first]);
    final del = await s.db.query('sync_meta', where: 'tbl = ? AND pk = ?', whereArgs: ['questions', ids.first]);
    expect(del.single['deleted'], 1);
    // Options were removed by the cascade and are logged as deleted too.
    final opts = await s.db.rawQuery(
        "SELECT COUNT(*) AS n FROM sync_meta WHERE tbl = 'options' AND deleted = 1");
    expect(opts.first['n'], 4);
    expect(bankId, isNotEmpty);
  });

  test('snapshot survives encode/decode unchanged', () async {
    final (s, _, _) = await withBank(5);
    final snap = await SyncStore(s.db).snapshot(deviceName: 'test');
    final back = SyncSnapshot.decode(snap.encode());
    expect(back.canonical(), snap.canonical());
    expect(back.deviceName, 'test');
  });

  test('a new device receives everything, then both devices converge', () async {
    final (a, _, bankId) = await withBank(6);
    final b = await openServices();
    await SyncStore(b.db).merge(await SyncStore(a.db).snapshot());
    expect(await _count(b, 'questions'), 6);
    expect(await _count(b, 'banks'), 1);
    expect(await _count(b, 'categories'), 2);
    await _expectSame(a, b);

    // Device B takes a quiz; device A adds a question and deletes another.
    final cfg = QuizConfig(bankIds: [bankId], questionCount: 3, selection: SelectionMode.newQuestions);
    await playSession(b, await b.sessions.create(cfg));
    await a.questions.saveQuestion(mc(bankId, 'Added on A'));
    final victim = (await a.db.query('questions', where: "text = 'Question 0'")).single['id'] as String;
    await a.questions.delete([victim]);

    await _roundTrip(a, b);
    await _roundTrip(a, b);
    expect(await _count(a, 'questions'), 6);
    expect(await _count(b, 'questions'), 6);
    expect(await _count(a, 'sessions'), 1);
    expect(await _count(a, 'attempts'), greaterThan(0));
    expect((await a.db.query('questions', where: 'id = ?', whereArgs: [victim])), isEmpty);
    expect((await b.db.query('questions', where: 'id = ?', whereArgs: [victim])), isEmpty);
    await _expectSame(a, b);
  });

  test('the latest edit of the same question wins on both devices', () async {
    final (a, _, _) = await withBank(2);
    final b = await openServices();
    await SyncStore(b.db).merge(await SyncStore(a.db).snapshot());
    final id = (await a.db.query('questions', where: "text = 'Question 1'")).single['id'] as String;

    await a.db.update('questions', {'text': 'Edited on A'}, where: 'id = ?', whereArgs: [id]);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    await b.db.update('questions', {'text': 'Edited on B (later)'}, where: 'id = ?', whereArgs: [id]);

    await _roundTrip(a, b);
    for (final s in [a, b]) {
      final q = await s.db.query('questions', where: 'id = ?', whereArgs: [id]);
      expect(q.single['text'], 'Edited on B (later)');
    }
    await _expectSame(a, b);
  });

  test('replaceWith makes a device an exact copy of the cloud', () async {
    final (a, _, _) = await withBank(4);
    final (b, _, _) = await withBank(2);
    await SyncStore(b.db).replaceWith(await SyncStore(a.db).snapshot());
    expect(await _count(b, 'questions'), 4);
    expect(await _count(b, 'banks'), 1);
    await _expectSame(a, b);
    // Writes after the replace are tracked again.
    final before = await _count(b, 'sync_meta');
    final bankId = (await b.db.query('banks')).single['id'] as String;
    await b.questions.saveQuestion(mc(bankId, 'New after replace'));
    expect(await _count(b, 'sync_meta'), greaterThan(before));
  });

  test('applying remote changes does not mark them as local changes', () async {
    final (a, _, _) = await withBank(3);
    final b = await openServices();
    final snap = await SyncStore(a.db).snapshot();
    await SyncStore(b.db).merge(snap);
    final ma = {for (final r in await a.db.query('sync_meta')) '${r['tbl']}/${r['pk']}': r['modified_at']};
    final mb = {for (final r in await b.db.query('sync_meta')) '${r['tbl']}/${r['pk']}': r['modified_at']};
    expect(mb, ma);
    final control = await b.db.query('sync_control');
    expect(control.single['applying'], 0);
  });
}
