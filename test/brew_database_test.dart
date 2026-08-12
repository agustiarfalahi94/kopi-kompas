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
}
