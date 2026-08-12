import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kopi_kompas/data/brew_schema.dart';
import 'package:kopi_kompas/models/brew_entry.dart';
import 'package:kopi_kompas/screens/edit_entry_screen.dart';

late BrewSchema schema;

BrewEntry original({
  String method = 'espresso',
  ScoreStatus status = ScoreStatus.scored,
}) => BrewEntry(
  id: 'keep-me',
  brewMethod: method,
  beanOrigin: 'Honduras',
  doseGrams: 18,
  brewDate: DateTime(2026, 8, 12, 7),
  rawInputText: 'the sentence I first typed',
  methodData: const {'yieldGrams': 36.0, 'puckPrepWdt': true},
  scoreStatus: status,
  overallScore: status == ScoreStatus.scored ? 93 : null,
  scoreReasons: const ['Ratio on target'],
  scoreRubric: status == ScoreStatus.scored ? 'r2' : null,
  scoreModel: status == ScoreStatus.scored ? 'gemini-3.5-flash' : null,
  myRating: 4,
  createdAt: DateTime(2026, 8, 12, 7),
  updatedAt: DateTime(2026, 8, 12, 7),
);

void main() {
  setUpAll(() {
    schema = BrewSchema.parse(
      File('schema/brew_schema.json').readAsStringSync(),
    );
  });

  test('keeps the identity of the entry', () {
    final e = applyEdits(
      original(),
      {'doseGrams': 19.0},
      schema,
      DateTime(2026, 8, 13, 9),
    );
    expect(e.id, 'keep-me');
    expect(e.createdAt, DateTime(2026, 8, 12, 7));
    expect(e.brewDate, DateTime(2026, 8, 12, 7));
    // The original words are the record of what was said. Editing the
    // numbers must never rewrite them.
    expect(e.rawInputText, 'the sentence I first typed');
  });

  test('applies the change and bumps updatedAt', () {
    final e = applyEdits(
      original(),
      {'doseGrams': 19.0},
      schema,
      DateTime(2026, 8, 13, 9),
    );
    expect(e.doseGrams, 19);
    expect(e.updatedAt, DateTime(2026, 8, 13, 9));
  });

  test('keeps your rating', () {
    final e = applyEdits(original(), {'doseGrams': 19.0}, schema, DateTime(0));
    expect(e.myRating, 4);
  });

  test('routes an answer to core or methodData by schema', () {
    final e = applyEdits(
      original(),
      {'roaster': 'Common Grounds', 'yieldGrams': 40.0},
      schema,
      DateTime(0),
    );
    expect(e.roaster, 'Common Grounds');
    expect(e.methodData['yieldGrams'], 40.0);
    expect(e.methodData.containsKey('roaster'), isFalse);
  });

  test('a field cleared in the form is removed, not left stale', () {
    // The form reports a cleared row as absent. An edit that drops the
    // machine has to actually drop it, or the entry keeps a value the user
    // deliberately erased.
    final e = applyEdits(original(), {'doseGrams': 18.0}, schema, DateTime(0));
    expect(e.methodData.containsKey('yieldGrams'), isFalse);
  });

  test('a scored method goes back to pending, ready to re-score', () {
    final e = applyEdits(original(), {'doseGrams': 19.0}, schema, DateTime(0));
    expect(e.scoreStatus, ScoreStatus.pending);
  });

  test('an unscored method stays notApplicable', () {
    final e = applyEdits(
      original(method: 'kopiJoss', status: ScoreStatus.notApplicable),
      {'doseGrams': 19.0},
      schema,
      DateTime(0),
    );
    expect(e.scoreStatus, ScoreStatus.notApplicable);
  });

  test('the old score survives until a new one replaces it', () {
    // A network blip while re-scoring must not destroy a number you already
    // had. This is the opposite of the first save, where there was nothing to
    // lose.
    final e = applyEdits(original(), {'doseGrams': 19.0}, schema, DateTime(0));
    expect(e.overallScore, 93);
    expect(e.scoreRubric, 'r2');
  });
}
