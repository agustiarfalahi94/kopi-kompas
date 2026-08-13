import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kopi_kompas/data/brew_schema.dart';
import 'package:kopi_kompas/models/brew_entry.dart';
import 'package:kopi_kompas/screens/edit_entry_screen.dart';
import 'package:kopi_kompas/screens/new_entry_screen.dart';
import 'package:kopi_kompas/widgets/brew_date_field.dart';

late BrewSchema schema;

void main() {
  setUpAll(() {
    schema = BrewSchema.parse(
      File('schema/brew_schema.json').readAsStringSync(),
    );
  });

  group('a new entry', () {
    test('is stamped with when it was brewed, not when it was saved', () {
      // The bug this exists for: brewDate and createdAt were both `now`, so
      // "I brewed this yesterday at 11.30" was thrown away and the row
      // claimed a time the coffee was never made at.
      final e = buildEntry(
        brewMethod: 'espresso',
        core: const {},
        methodData: const {},
        answers: const {},
        rawInputText: 'espresso kemarin jam setengah 12 siang',
        schema: schema,
        now: DateTime(2026, 8, 13, 14),
        brewedAt: DateTime(2026, 8, 12, 11, 30),
      );
      expect(e.brewDate, DateTime(2026, 8, 12, 11, 30));
      // The second meaning keeps its own column, untouched.
      expect(e.createdAt, DateTime(2026, 8, 13, 14));
    });

    test('falls back to now when the text said nothing about when', () {
      final e = buildEntry(
        brewMethod: 'espresso',
        core: const {},
        methodData: const {},
        answers: const {},
        rawInputText: 'espresso, 18g in 36g out',
        schema: schema,
        now: DateTime(2026, 8, 13, 14),
      );
      expect(e.brewDate, DateTime(2026, 8, 13, 14));
    });

    test('a back-dated brew survives the database round trip intact', () {
      // brewDate is stored as a local wall clock with no zone. A UTC
      // conversion here would file an 00:30 brew under the previous day.
      final e = buildEntry(
        brewMethod: 'espresso',
        core: const {},
        methodData: const {},
        answers: const {},
        rawInputText: 'x',
        schema: schema,
        now: DateTime(2026, 8, 13, 14),
        brewedAt: DateTime(2026, 8, 12, 0, 30),
      );
      final back = BrewEntry.fromRow(e.toRow());
      expect(back.brewDate, DateTime(2026, 8, 12, 0, 30));
    });
  });

  group('editing', () {
    BrewEntry existing() => BrewEntry(
      id: 'a',
      brewMethod: 'espresso',
      doseGrams: 18,
      brewDate: DateTime(2026, 8, 12, 11, 30),
      rawInputText: 'x',
      methodData: const {'yieldGrams': 36},
      overallScore: 88,
      scoreStatus: ScoreStatus.scored,
      scoreRubric: 'r2',
      createdAt: DateTime(2026, 8, 12, 11, 31),
      updatedAt: DateTime(2026, 8, 12, 11, 31),
    );

    test('moves the brew time when asked', () {
      final out = applyEdits(
        existing(),
        {'doseGrams': 18.0, 'yieldGrams': 36},
        schema,
        DateTime(2026, 8, 13, 15),
        brewDate: DateTime(2026, 8, 11, 7),
      );
      expect(out.brewDate, DateTime(2026, 8, 11, 7));
      // createdAt is the record of when this was written down and is never
      // rewritten by an edit.
      expect(out.createdAt, DateTime(2026, 8, 12, 11, 31));
    });

    test('keeps the brew time when the edit does not mention it', () {
      final out = applyEdits(
        existing(),
        {'doseGrams': 19.0},
        schema,
        DateTime(2026, 8, 13, 15),
      );
      expect(out.brewDate, DateTime(2026, 8, 12, 11, 30));
    });

    test('changing only the time does not queue a re-score', () {
      // No rubric looks at when a coffee was brewed. Re-running the model
      // would spend a request to reach the same number with a newer scoredAt.
      final out = applyEdits(
        existing(),
        {'doseGrams': 18.0, 'yieldGrams': 36},
        schema,
        DateTime(2026, 8, 13, 15),
        brewDate: DateTime(2026, 8, 11, 7),
        rescore: false,
      );
      expect(out.scoreStatus, ScoreStatus.scored);
      expect(out.overallScore, 88);
    });

    test('changing a parameter still queues a re-score', () {
      final out = applyEdits(
        existing(),
        {'doseGrams': 20.0, 'yieldGrams': 36},
        schema,
        DateTime(2026, 8, 13, 15),
      );
      expect(out.scoreStatus, ScoreStatus.pending);
    });
  });

  test('the timestamp reads the same in both languages', () {
    // Numeric on purpose: no month name to translate, and 12/08 means the
    // same thing to both readers.
    expect(formatBrewedAt(DateTime(2026, 8, 12, 11, 30)), '12/08/2026 11:30');
    expect(formatBrewedAt(DateTime(2026, 12, 1, 7, 5)), '01/12/2026 07:05');
  });
}
