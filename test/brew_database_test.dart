import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:kopi_kompas/models/brew_entry.dart';
import 'package:kopi_kompas/services/brew_database.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

BrewEntry entry(String id, DateTime when, {ScoreStatus? status}) => BrewEntry(
  id: id,
  brewMethod: 'espresso',
  brewDate: when,
  rawInputText: 'raw $id',
  methodData: const {'yieldGrams': 36},
  scoreStatus: status ?? ScoreStatus.scored,
  overallScore: 80,
  createdAt: when,
  updatedAt: when,
);

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late BrewDatabase db;
  setUp(() async => db = await BrewDatabase.open(path: inMemoryDatabasePath));
  tearDown(() async => db.close());

  test('stores and reads an entry back', () async {
    await db.insert(entry('a', DateTime(2026, 8, 12, 7)));
    final all = await db.liveEntries();
    expect(all.single.id, 'a');
    expect(all.single.methodData['yieldGrams'], 36);
  });

  test('lists newest first', () async {
    await db.insert(entry('old', DateTime(2026, 8, 10, 7)));
    await db.insert(entry('new', DateTime(2026, 8, 12, 7)));
    expect((await db.liveEntries()).map((e) => e.id), ['new', 'old']);
  });

  test(
    'a soft-deleted entry leaves the live list but stays in the table',
    () async {
      await db.insert(entry('a', DateTime(2026, 8, 12, 7)));
      await db.softDelete('a', DateTime(2026, 8, 12, 8));
      expect(await db.liveEntries(), isEmpty);
      expect((await db.byId('a'))!.deletedAt, isNotNull);
    },
  );

  test('hasBrewOn is true only for a day with a live entry', () async {
    await db.insert(entry('a', DateTime(2026, 8, 12, 7)));
    expect(await db.hasBrewOn(DateTime(2026, 8, 12, 23)), isTrue);
    expect(await db.hasBrewOn(DateTime(2026, 8, 11, 7)), isFalse);
  });

  test(
    'a shot after midnight counts for that new day, not the day before',
    () async {
      // The reason brewDate is stored as local wall-clock time, not as an
      // instant: as UTC this row would file under the 11th for anyone east of
      // Greenwich.
      await db.insert(entry('a', DateTime(2026, 8, 12, 0, 30)));
      expect(await db.hasBrewOn(DateTime(2026, 8, 12, 9)), isTrue);
      expect(await db.hasBrewOn(DateTime(2026, 8, 11, 9)), isFalse);
    },
  );

  test('a deleted entry stops counting for hasBrewOn', () async {
    final when = DateTime(2026, 8, 12, 7);
    await db.insert(entry('a', when));
    await db.softDelete('a', when);
    expect(await db.hasBrewOn(when), isFalse);
  });

  test('update replaces the row and can clear a score', () async {
    final when = DateTime(2026, 8, 12, 7);
    await db.insert(entry('a', when));
    await db.update(
      (await db.byId('a'))!.copyWith(scoreStatus: ScoreStatus.failed),
    );
    final back = (await db.byId('a'))!;
    expect(back.scoreStatus, ScoreStatus.failed);
    expect(back.overallScore, isNull);
  });

  group('upgrading a v1 database', () {
    // The Phase 2 schema, verbatim, so the migration is exercised against
    // what is actually on the phone rather than against a guess at it.
    const v1Sql = '''
      CREATE TABLE brews (
        id TEXT PRIMARY KEY, brewMethod TEXT NOT NULL, beanOrigin TEXT,
        roastLevel TEXT, doseGrams REAL, grindSize TEXT,
        brewDate TEXT NOT NULL, notes TEXT, rawInputText TEXT NOT NULL,
        methodData TEXT NOT NULL, overallScore INTEGER, scoreReasons TEXT,
        scoreStatus TEXT NOT NULL, scoreRubric TEXT, scoreModel TEXT,
        scoredAt TEXT, createdAt TEXT NOT NULL, updatedAt TEXT NOT NULL,
        deletedAt TEXT
      )
    ''';

    late String path;

    Future<void> seedV1(List<Map<String, Object?>> rows) async {
      path = '${Directory.systemTemp.createTempSync().path}/v1.db';
      final db = await openDatabase(
        path,
        version: 1,
        onCreate: (db, _) async => db.execute(v1Sql),
      );
      for (final r in rows) {
        await db.insert('brews', r);
      }
      await db.close();
    }

    Map<String, Object?> v1Row(String id, String method, String data) => {
      'id': id,
      'brewMethod': method,
      'beanOrigin': 'Honduras',
      'roastLevel': 'medium',
      'doseGrams': 18.0,
      'brewDate': '2026-08-12T07:00:00.000',
      'rawInputText': 'raw $id',
      'methodData': data,
      'overallScore': 93,
      'scoreReasons': '["Ratio on target"]',
      'scoreStatus': 'scored',
      'scoreRubric': 'r1',
      'scoreModel': 'gemini-3.5-flash',
      'createdAt': '2026-08-12T07:00:00.000',
      'updatedAt': '2026-08-12T07:00:00.000',
    };

    test('keeps every entry and its score', () async {
      await seedV1([v1Row('a', 'espresso', '{"yieldGrams":36}')]);
      final db = await BrewDatabase.open(path: path);
      final back = (await db.byId('a'))!;
      expect(back.rawInputText, 'raw a');
      expect(back.overallScore, 93);
      expect(back.methodData['yieldGrams'], 36);
      await db.close();
    });

    test('migrates a v60 entry to a coneDripper with brewer v60', () async {
      await seedV1([v1Row('a', 'v60', '{"waterGrams":250,"pourCount":3}')]);
      final db = await BrewDatabase.open(path: path);
      final back = (await db.byId('a'))!;
      expect(back.brewMethod, 'coneDripper');
      expect(back.methodData['brewer'], 'v60');
      expect(back.methodData['waterGrams'], 250);
      await db.close();
    });

    test('leaves an r1 score labelled r1', () async {
      // The whole point of scoreRubric. Relabelling it r2 would destroy the
      // provenance the column exists for.
      await seedV1([v1Row('a', 'espresso', '{}')]);
      final db = await BrewDatabase.open(path: path);
      expect((await db.byId('a'))!.scoreRubric, 'r1');
      await db.close();
    });

    test('the new columns arrive null, not empty', () async {
      await seedV1([v1Row('a', 'espresso', '{}')]);
      final db = await BrewDatabase.open(path: path);
      final back = (await db.byId('a'))!;
      expect(back.roaster, isNull);
      expect(back.process, isNull);
      expect(back.grinder, isNull);
      expect(back.myRating, isNull);
      await db.close();
    });

    test('is idempotent — opening twice does not double-migrate', () async {
      await seedV1([v1Row('a', 'v60', '{}')]);
      final first = await BrewDatabase.open(path: path);
      await first.close();
      final second = await BrewDatabase.open(path: path);
      expect((await second.byId('a'))!.brewMethod, 'coneDripper');
      await second.close();
    });
  });

  test('myRating round-trips', () async {
    final when = DateTime(2026, 8, 12, 7);
    await db.insert(entry('a', when).copyWith(myRating: 4));
    expect((await db.byId('a'))!.myRating, 4);
  });
}
