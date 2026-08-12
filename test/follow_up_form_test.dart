import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kopi_kompas/data/brew_schema.dart';
import 'package:kopi_kompas/widgets/follow_up_form.dart';

late BrewSchema schema;

void main() {
  setUpAll(() {
    schema = BrewSchema.parse(
      File('schema/brew_schema.json').readAsStringSync(),
    );
  });

  group('missingFields', () {
    test('asks only for required fields that are absent', () {
      final missing = missingFields(
        schema,
        'espresso',
        {'doseGrams': 18, 'beanOrigin': 'Honduras', 'roastLevel': 'medium'},
        {'yieldGrams': 36, 'brewTimeSeconds': 28},
      );
      final names = missing.map((f) => f.name);
      expect(names, contains('puckPrepWdt'));
      expect(names, contains('machine'));
      expect(names, isNot(contains('yieldGrams')));
      expect(names, isNot(contains('doseGrams')));
    });

    test('never asks for an optional field', () {
      final missing = missingFields(schema, 'espresso', {}, {});
      final names = missing.map((f) => f.name);
      expect(names, isNot(contains('basketType')));
      expect(names, isNot(contains('waterTempC')));
      expect(names, isNot(contains('grindSize')));
    });

    test('treats false as answered, not missing', () {
      // "no wdt today" is an answer, and the rubric deducts for it.
      final missing = missingFields(schema, 'espresso', {}, {
        'puckPrepWdt': false,
      });
      expect(missing.map((f) => f.name), isNot(contains('puckPrepWdt')));
    });

    test('treats a blank string as missing', () {
      final missing = missingFields(schema, 'espresso', {
        'beanOrigin': '  ',
      }, {});
      expect(missing.map((f) => f.name), contains('beanOrigin'));
    });

    test('asks nothing when everything required is present', () {
      final missing = missingFields(
        schema,
        'kopiJoss',
        {'beanOrigin': 'local', 'roastLevel': 'dark', 'doseGrams': 20},
        {'waterGrams': 200, 'charcoalUsed': true, 'sugarAdded': true},
      );
      expect(missing, isEmpty);
    });

    test('returns fields in schema order, core before method', () {
      final missing = missingFields(schema, 'espresso', {}, {});
      expect(missing.first.name, 'beanOrigin');
      expect(missing.map((f) => f.name), contains('yieldGrams'));
    });
  });

  group('FollowUpForm', () {
    Future<void> pump(
      WidgetTester tester,
      List<FieldSpec> fields, [
      ValueChanged<Map<String, Object?>>? onChanged,
    ]) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: FollowUpForm(fields: fields, onChanged: onChanged ?? (_) {}),
          ),
        ),
      );
    }

    testWidgets('renders a row per missing field', (tester) async {
      await pump(tester, missingFields(schema, 'espresso', {}, {}));
      expect(find.text('Dose (g)'), findsOneWidget);
      expect(find.text('WDT'), findsOneWidget);
      expect(find.byType(Switch), findsWidgets);
    });

    testWidgets('reports a number as a double, not a string', (tester) async {
      Map<String, Object?> latest = {};
      await pump(
        tester,
        missingFields(schema, 'espresso', {}, {}),
        (v) => latest = v,
      );

      await tester.enterText(
        find
            .ancestor(
              of: find.text('Dose (g)'),
              matching: find.byType(TextField),
            )
            .first,
        '18.5',
      );
      await tester.pump();
      expect(latest['doseGrams'], 18.5);
      expect(latest['doseGrams'], isA<double>());
    });

    testWidgets('reports an integer field as an int', (tester) async {
      Map<String, Object?> latest = {};
      await pump(
        tester,
        missingFields(schema, 'v60', {}, {}),
        (v) => latest = v,
      );

      await tester.enterText(
        find
            .ancestor(
              of: find.text('Number of pours'),
              matching: find.byType(TextField),
            )
            .first,
        '3',
      );
      await tester.pump();
      expect(latest['pourCount'], 3);
      expect(latest['pourCount'], isA<int>());
    });

    testWidgets('roast level renders as a dropdown of its enum values', (
      tester,
    ) async {
      await pump(tester, missingFields(schema, 'espresso', {}, {}));
      expect(find.byType(DropdownButtonFormField<String>), findsOneWidget);
    });

    testWidgets('a boolean reports false without being touched', (
      tester,
    ) async {
      // The switch defaults off, and that is the answer: the user is being
      // asked precisely because the text did not mention the step.
      Map<String, Object?> latest = {};
      await pump(
        tester,
        missingFields(schema, 'espresso', {}, {}),
        (v) => latest = v,
      );
      await tester.tap(find.byType(Switch).first);
      await tester.pump();
      await tester.tap(find.byType(Switch).first);
      await tester.pump();
      expect(latest['puckPrepWdt'], false);
    });
  });
}
