import 'package:flutter_test/flutter_test.dart';
import 'package:kopi_kompas/models/brew_entry.dart';

BrewEntry sample() => BrewEntry(
  id: 'abc',
  brewMethod: 'espresso',
  beanOrigin: 'Honduras',
  roastLevel: 'medium',
  doseGrams: 18,
  brewDate: DateTime(2026, 8, 12, 7, 30),
  notes: 'syrupy',
  rawInputText: '18g in 36g out',
  methodData: const {'yieldGrams': 36, 'puckPrepWdt': false},
  overallScore: 82,
  scoreReasons: const ['Ratio on target'],
  scoreStatus: ScoreStatus.scored,
  scoreRubric: 'r1',
  scoreModel: 'gemini-3.5-flash',
  scoredAt: DateTime.parse('2026-08-12T07:31:00+07:00'),
  createdAt: DateTime.parse('2026-08-12T07:31:00+07:00'),
  updatedAt: DateTime.parse('2026-08-12T07:31:00+07:00'),
);

void main() {
  test('survives a round trip through a database row', () {
    final entry = sample();
    final back = BrewEntry.fromRow(entry.toRow());
    expect(back.id, entry.id);
    expect(back.brewMethod, 'espresso');
    expect(back.doseGrams, 18);
    expect(back.methodData['yieldGrams'], 36);
    expect(back.scoreReasons, ['Ratio on target']);
    expect(back.scoreStatus, ScoreStatus.scored);
    expect(back.scoreRubric, 'r1');
    expect(back.scoreModel, 'gemini-3.5-flash');
    expect(back.deletedAt, isNull);
  });

  test('keeps a false methodData value distinct from a missing one', () {
    final back = BrewEntry.fromRow(sample().toRow());
    expect(back.methodData['puckPrepWdt'], false);
    expect(back.methodData.containsKey('puckPrepTamp'), isFalse);
  });

  test('stores brewDate as local wall-clock time, never as a UTC instant', () {
    // A shot pulled at 00:30 belongs to the day the brewer was awake for.
    // Stored as an instant, it would file under the previous day for anyone
    // east of Greenwich, and hasBrewOn buckets on the first ten characters.
    final entry = sample().copyWith(brewDate: DateTime(2026, 8, 12, 0, 30));
    final row = entry.toRow();
    expect(row['brewDate'], startsWith('2026-08-12T00:30'));
    expect(row['brewDate'], isNot(contains('Z')));
    expect(BrewEntry.fromRow(row).brewDate.hour, 0);
  });

  test('a UTC brewDate is converted to local rather than stored as-is', () {
    // Dart's DateTime cannot carry an offset, so anything arriving as UTC
    // has to be pinned to the device's wall clock before it is written.
    final utc = DateTime(2026, 8, 12, 0, 30).toUtc();
    final row = sample().copyWith(brewDate: utc).toRow();
    expect(row['brewDate'], startsWith('2026-08-12T00:30'));
  });

  test('an unscored method stores no score', () {
    final entry = sample().copyWith(
      brewMethod: 'kopiJoss',
      scoreStatus: ScoreStatus.notApplicable,
      clearScore: true,
    );
    final back = BrewEntry.fromRow(entry.toRow());
    expect(back.overallScore, isNull);
    expect(back.scoreStatus, ScoreStatus.notApplicable);
  });

  test('copyWith preserves the score and its provenance', () {
    // Rating a brew must not erase what it scored. copyWith used to null the
    // score fields unless they were passed, so entry.copyWith(myRating: 4)
    // silently dropped overallScore, scoreRubric, scoreModel and scoredAt.
    final rated = sample().copyWith(myRating: 4);
    expect(rated.myRating, 4);
    expect(rated.overallScore, 82);
    expect(rated.scoreRubric, 'r1');
    expect(rated.scoreModel, 'gemini-3.5-flash');
    expect(rated.scoredAt, isNotNull);
    expect(rated.scoreReasons, ['Ratio on target']);
  });

  test('clearScore drops the number and its provenance together', () {
    // A failed re-score has to be able to drop a stale number — but that has
    // to be asked for, not be the default for every other edit.
    final cleared = sample().copyWith(
      scoreStatus: ScoreStatus.failed,
      clearScore: true,
    );
    expect(cleared.overallScore, isNull);
    expect(cleared.scoreRubric, isNull);
    expect(cleared.scoreReasons, isEmpty);
    expect(cleared.scoreStatus, ScoreStatus.failed);
  });

  test('newUuid produces distinct v4-shaped ids', () {
    final a = newUuid(), b = newUuid();
    expect(a, isNot(b));
    expect(a.length, 36);
    expect(a[14], '4');
  });
}
