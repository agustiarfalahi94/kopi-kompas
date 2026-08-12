import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kopi_kompas/data/brew_schema.dart';
import 'package:kopi_kompas/models/brew_entry.dart';
import 'package:kopi_kompas/screens/home_screen.dart';

late BrewSchema schema;

BrewEntry entry(String method, Map<String, Object?> data) => BrewEntry(
  id: 'a',
  brewMethod: method,
  brewDate: DateTime(2026, 8, 12, 7),
  rawInputText: 'x',
  methodData: data,
  scoreStatus: ScoreStatus.scored,
  overallScore: 90,
  createdAt: DateTime(2026, 8, 12, 7),
  updatedAt: DateTime(2026, 8, 12, 7),
);

void main() {
  setUpAll(() {
    schema = BrewSchema.parse(
      File('schema/brew_schema.json').readAsStringSync(),
    );
  });

  test('a dripper reads as its brewer, not its method', () {
    // "V60" is what you call it. "Cone dripper" is a category of hardware,
    // and showing that in a list of your own brews reads as an evasion.
    expect(
      displayLabel(schema, entry('coneDripper', {'brewer': 'v60'})),
      'V60',
    );
    expect(
      displayLabel(
        schema,
        entry('flatBottomDripper', {'brewer': 'kalitaWave'}),
      ),
      'Kalita Wave',
    );
    expect(
      displayLabel(schema, entry('smartDripper', {'brewer': 'switch'})),
      'Hario Switch',
    );
  });

  test('a shot reads as its style', () {
    expect(
      displayLabel(schema, entry('espresso', {'shotStyle': 'ristretto'})),
      'Ristretto',
    );
  });

  test('a normale shot reads as Espresso, not Normale', () {
    // Nobody calls it a normale out loud.
    expect(
      displayLabel(schema, entry('espresso', {'shotStyle': 'normale'})),
      'Espresso',
    );
  });

  test('falls back to the method label when no variant is recorded', () {
    expect(displayLabel(schema, entry('coneDripper', {})), 'Cone dripper');
    expect(displayLabel(schema, entry('chemex', {})), 'Chemex');
    expect(displayLabel(schema, entry('kopiJoss', {})), 'Kopi joss');
  });

  test('an unknown variant falls back rather than showing a raw id', () {
    expect(
      displayLabel(schema, entry('coneDripper', {'brewer': 'nonsense'})),
      'Cone dripper',
    );
  });
}
