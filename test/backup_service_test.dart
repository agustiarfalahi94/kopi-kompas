import 'package:flutter_test/flutter_test.dart';
import 'package:kopi_kompas/models/brew_entry.dart';
import 'package:kopi_kompas/services/backup_service.dart';
import 'package:kopi_kompas/services/brew_database.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class FakeRemote implements RemoteStore {
  final docs = <String, Map<String, Object?>>{};
  bool throwOnWrite = false;
  bool throwOnRead = false;
  int puts = 0;

  @override
  Future<void> put(String uid, String id, Map<String, Object?> data) async {
    if (throwOnWrite) throw Exception('network');
    puts++;
    docs['$uid/$id'] = data;
  }

  @override
  Future<List<Map<String, Object?>>> all(String uid) async {
    if (throwOnRead) throw Exception('network');
    return docs.entries
        .where((e) => e.key.startsWith('$uid/'))
        .map((e) => e.value)
        .toList();
  }

  @override
  Future<void> delete(String uid, String id) async => docs.remove('$uid/$id');
}

BrewEntry brew(String id, {DateTime? when, DateTime? updated, int score = 90}) {
  final t = when ?? DateTime(2026, 8, 12, 7);
  return BrewEntry(
    id: id,
    brewMethod: 'espresso',
    beanOrigin: 'Honduras',
    brewDate: t,
    rawInputText: 'raw $id',
    methodData: const {'yieldGrams': 36.0, 'puckPrepWdt': false},
    scoreStatus: ScoreStatus.scored,
    overallScore: score,
    scoreReasons: const ['Ratio on target'],
    scoreRubric: 'r2',
    scoreModel: 'gemini-3.5-flash',
    myRating: 4,
    createdAt: t,
    updatedAt: updated ?? t,
  );
}

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late BrewDatabase db;
  late FakeRemote remote;
  String? user;

  setUp(() async {
    db = await BrewDatabase.open(path: inMemoryDatabasePath);
    remote = FakeRemote();
    user = 'uid-1';
  });
  tearDown(() => db.close());

  BackupService service() =>
      BackupService(db: db, remote: remote, uid: () => user);

  test('a signed-out user never touches the network', () async {
    user = null;
    await db.insert(brew('a'));
    final r = await service().pushAll();
    expect(r.outcome, BackupOutcome.notSignedIn);
    expect(remote.puts, 0);
  });

  test('a failed push leaves the local entry untouched', () async {
    // The phone is the source of truth. A backup failure is not data loss.
    await db.insert(brew('a'));
    remote.throwOnWrite = true;
    final r = await service().push(brew('a'));
    expect(r.outcome, BackupOutcome.failed);
    expect((await db.byId('a'))!.overallScore, 90);
  });

  test('pushing the same entry twice writes one document', () async {
    final s = service();
    await s.push(brew('a'));
    await s.push(brew('a'));
    expect(remote.docs.length, 1);
  });

  test('a soft-deleted entry is mirrored as deleted, not skipped', () async {
    // Dropping it would make a restore silently empty the Deleted entries
    // page, turning a recoverable delete into a permanent one.
    await db.insert(brew('a'));
    await db.softDelete('a', DateTime(2026, 8, 12, 9));
    final r = await service().pushAll();
    expect(r.count, 1);
    expect(remote.docs['uid-1/a']!['deletedAt'], isNotNull);
  });

  test('restore writes entries that are missing locally', () async {
    await remote.put('uid-1', 'a', brew('a').toRow());
    final r = await service().restore();
    expect(r.count, 1);
    final back = (await db.byId('a'))!;
    expect(back.overallScore, 90);
    expect(back.scoreRubric, 'r2');
    expect(back.myRating, 4);
    expect(back.methodData['yieldGrams'], 36.0);
    expect(back.methodData['puckPrepWdt'], false);
  });

  test('restore never overwrites a newer local entry', () async {
    // An edit made on this phone while offline must survive a restore.
    await db.insert(brew('a', updated: DateTime(2026, 8, 13), score: 55));
    await remote.put(
      'uid-1',
      'a',
      brew('a', updated: DateTime(2026, 8, 12), score: 90).toRow(),
    );
    await service().restore();
    expect((await db.byId('a'))!.overallScore, 55);
  });

  test('restore does overwrite an older local entry', () async {
    await db.insert(brew('a', updated: DateTime(2026, 8, 12), score: 55));
    await remote.put(
      'uid-1',
      'a',
      brew('a', updated: DateTime(2026, 8, 13), score: 90).toRow(),
    );
    await service().restore();
    expect((await db.byId('a'))!.overallScore, 90);
  });

  test('restoring twice does not duplicate', () async {
    await remote.put('uid-1', 'a', brew('a').toRow());
    await service().restore();
    await service().restore();
    expect((await db.liveEntries()).length, 1);
  });

  test('a half-finished pushAll reports how far it got', () async {
    await db.insert(brew('a'));
    await db.insert(brew('b', when: DateTime(2026, 8, 11, 7)));
    final s = service();
    await s.push(brew('a'));
    remote.throwOnWrite = true;
    final r = await s.pushAll();
    expect(r.outcome, BackupOutcome.failed);
    expect(r.count, 0);
  });

  test('a failed read reports failure rather than emptying the log', () async {
    await db.insert(brew('a'));
    remote.throwOnRead = true;
    final r = await service().restore();
    expect(r.outcome, BackupOutcome.failed);
    expect((await db.liveEntries()).length, 1);
  });

  test('restore survives Firestore returning maps instead of json', () async {
    // Firestore gives back a Map where the SQLite row holds a JSON string.
    final row = brew('a').toRow();
    row['methodData'] = {'yieldGrams': 36.0};
    row['scoreReasons'] = ['Ratio on target'];
    await remote.put('uid-1', 'a', row);
    await service().restore();
    expect((await db.byId('a'))!.methodData['yieldGrams'], 36.0);
  });

  test('a successful push records when it happened', () async {
    final s = service();
    expect(s.lastSuccess, isNull);
    await s.push(brew('a'));
    expect(s.lastSuccess, isNotNull);
  });
}
