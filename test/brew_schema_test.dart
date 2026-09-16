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

  test('groups sixteen methods into five categories', () {
    expect(schema.methodIds, hasLength(16));
    expect(schema.categories.map((c) => c.id), [
      'espresso',
      'filter',
      'immersion',
      'hybrid',
      'indonesian',
    ]);
  });

  test('puts every method in exactly one category', () {
    final listed = schema.categories.expand((c) => c.methodIds).toList();
    expect(listed..sort(), equals([...schema.methodIds]..sort()));
    expect(listed.toSet().length, listed.length);
    for (final m in schema.methodIds) {
      expect(schema.categoryOf(m).methodIds, contains(m));
    }
  });

  test('scores espresso, the four filter methods and aeropress', () {
    expect(schema.scoredMethodIds, [
      'espresso',
      'coneDripper',
      'flatBottomDripper',
      'chemex',
      'batchBrewer',
      'aeropress',
    ]);
  });

  test('keeps variants as fields rather than methods', () {
    for (final notAMethod in ['v60', 'ristretto', 'lungo', 'kopiLuwak']) {
      expect(schema.methodIds, isNot(contains(notAMethod)));
    }
    final shot = schema
        .method('espresso')
        .fields
        .firstWhere((f) => f.name == 'shotStyle');
    expect(shot.values, ['ristretto', 'normale', 'lungo']);
    final brewer = schema
        .method('coneDripper')
        .fields
        .firstWhere((f) => f.name == 'brewer');
    expect(brewer.values, contains('v60'));
  });

  test('treats luwak and wet-hulled as bean processes', () {
    final process = schema.core.firstWhere((f) => f.name == 'process');
    expect(process.values, contains('luwak'));
    expect(process.values, contains('wet-hulled'));
  });

  test('parses roastDate as a date field', () {
    final d = schema.core.firstWhere((f) => f.name == 'roastDate');
    expect(d.type, FieldType.date);
  });

  test('gives every field a group', () {
    final all = [
      ...schema.core,
      ...schema.methodIds.expand((m) => schema.method(m).fields),
    ];
    for (final f in all) {
      expect(FieldGroup.values, contains(f.group), reason: f.name);
    }
  });

  test('an unknown method has no category and throws', () {
    expect(() => schema.categoryOf('pourover'), throwsArgumentError);
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
        .method('coneDripper')
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
    expect(schema.method('espresso').fields.first.name, 'shotStyle');
    expect(schema.method('espresso').fields.last.name, 'waterTempC');
  });

  test('an unknown method id throws rather than returning empty', () {
    expect(() => schema.method('pourover'), throwsArgumentError);
  });

  test('no core field name is also a method field name', () {
    // stickyFor merges a core layer with a method layer into one map. If a
    // name ever appeared in both, one would silently shadow the other and
    // the form would show a value from the wrong bucket.
    final core = schema.core.map((f) => f.name).toSet();
    for (final id in schema.methodIds) {
      for (final f in schema.method(id).fields) {
        expect(
          core.contains(f.name),
          isFalse,
          reason: '$id.${f.name} collides with the core field of that name',
        );
      }
    }
  });
}
