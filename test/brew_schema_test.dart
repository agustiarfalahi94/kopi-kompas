import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kopi_kompas/data/brew_schema.dart';

void main() {
  late BrewSchema schema;

  setUpAll(() {
    schema = BrewSchema.parse(
      File('schema/brew_schema.json').readAsStringSync(),
    );
  });

  test('loads all eight methods in file order', () {
    expect(schema.methodIds, [
      'espresso',
      'v60',
      'aeropress',
      'frenchPress',
      'kopiTubruk',
      'kopiJoss',
      'kopiTalua',
      'kopiKhop',
    ]);
  });

  test('knows which three are scored', () {
    expect(schema.scoredMethodIds, ['espresso', 'v60', 'aeropress']);
    expect(schema.isScored('espresso'), isTrue);
    expect(schema.isScored('kopiJoss'), isFalse);
  });

  test('maps field types, units and labels', () {
    final espresso = schema.method('espresso');
    final yieldG = espresso.fields.firstWhere((f) => f.name == 'yieldGrams');
    expect(yieldG.type, FieldType.number);
    expect(yieldG.unit, 'g');
    expect(yieldG.required, isTrue);
    expect(yieldG.label, 'Yield');

    final wdt = espresso.fields.firstWhere((f) => f.name == 'puckPrepWdt');
    expect(wdt.type, FieldType.boolean);
  });

  test('maps integer separately from number, for the keyboard', () {
    final pours = schema
        .method('v60')
        .fields
        .firstWhere((f) => f.name == 'pourCount');
    expect(pours.type, FieldType.integer);
  });

  test('carries enum values for roast level', () {
    final roast = schema.core.firstWhere((f) => f.name == 'roastLevel');
    expect(roast.type, FieldType.enumerated);
    expect(roast.values, [
      'light',
      'medium-light',
      'medium',
      'medium-dark',
      'dark',
    ]);
  });

  test('preserves field order, which the form renders in', () {
    expect(schema.method('espresso').fields.first.name, 'yieldGrams');
    expect(schema.method('espresso').fields.last.name, 'waterTempC');
  });

  test('an unknown method id throws rather than returning empty', () {
    expect(() => schema.method('pourover'), throwsArgumentError);
  });
}
