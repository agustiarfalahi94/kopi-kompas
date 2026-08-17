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

  BrewFormField at(List<BrewFormField> f, String name) =>
      f.firstWhere((x) => x.spec.name == name);

  group('formFields', () {
    test('returns every field, not only the missing ones', () {
      // The change that matters: a field nobody is shown is a field nobody
      // knows exists.
      final f = formFields(
        schema,
        'espresso',
        {'doseGrams': 18},
        {'yieldGrams': 36},
        {},
      );
      final names = f.map((x) => x.spec.name);
      expect(names, contains('doseGrams'));
      expect(names, contains('basketSizeGrams'));
      expect(names, contains('preInfusionSeconds'));
      expect(names, contains('puckScreen'));
      expect(f.length, greaterThan(15));
    });

    test('marks where each value came from', () {
      final f = formFields(
        schema,
        'espresso',
        {'doseGrams': 18},
        {},
        {'grinder': 'Niche'},
      );
      expect(at(f, 'doseGrams').source, FieldSource.parsed);
      expect(at(f, 'doseGrams').value, 18);
      expect(at(f, 'grinder').source, FieldSource.sticky);
      expect(at(f, 'grinder').value, 'Niche');
      expect(at(f, 'pressureBars').source, FieldSource.empty);
      expect(at(f, 'pressureBars').value, isNull);
    });

    test('a parsed value beats a sticky default', () {
      // "on the ek43 today" must win over the remembered grinder.
      final f = formFields(
        schema,
        'espresso',
        {'grinder': 'EK43'},
        {},
        {'grinder': 'Niche'},
      );
      expect(at(f, 'grinder').value, 'EK43');
      expect(at(f, 'grinder').source, FieldSource.parsed);
    });

    test('core fields come before method fields', () {
      final f = formFields(schema, 'espresso', {}, {}, {});
      expect(f.first.spec.name, 'beanOrigin');
    });

    test('an unknown method throws rather than rendering an empty form', () {
      expect(
        () => formFields(schema, 'pourover', {}, {}, {}),
        throwsArgumentError,
      );
    });
  });

  group('groupedFields', () {
    test('sections in a fixed order', () {
      final g = groupedFields(formFields(schema, 'espresso', {}, {}, {}));
      expect(g.keys.toList(), [
        FieldGroup.coffee,
        FieldGroup.grind,
        FieldGroup.brew,
        FieldGroup.water,
      ]);
    });

    test('omits a group with no fields', () {
      // kopiSaring has no grind-specific field beyond the shared ones, but
      // core always contributes grinder — so every group should be present
      // here. The guard is that empty groups never render a bare header.
      final g = groupedFields(formFields(schema, 'kopiSaring', {}, {}, {}));
      for (final entry in g.entries) {
        expect(entry.value, isNotEmpty, reason: '${entry.key} is empty');
      }
    });

    test('puts dose in brew and roast level in coffee', () {
      final g = groupedFields(formFields(schema, 'espresso', {}, {}, {}));
      expect(
        g[FieldGroup.brew]!.map((f) => f.spec.name),
        contains('doseGrams'),
      );
      expect(
        g[FieldGroup.coffee]!.map((f) => f.spec.name),
        contains('roastLevel'),
      );
    });
  });

  group('BrewForm', () {
    Future<Map<String, Object?>> pumpAndRead(
      WidgetTester tester,
      String method, {
      Map<String, Object?> core = const {},
      Map<String, Object?> methodData = const {},
      Map<String, Object?> sticky = const {},
    }) async {
      var latest = <String, Object?>{};
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: BrewForm(
              schema: schema,
              fields: formFields(schema, method, core, methodData, sticky),
              onChanged: (v) => latest = v,
            ),
          ),
        ),
      );
      await tester.pump();
      return latest;
    }

    testWidgets('reports booleans as false before anything is touched', (
      tester,
    ) async {
      // A switch drawn off is already the answer. This regressed once, when
      // the form seeded its own state without telling the parent, and the
      // rubric read "not recorded" where the truth was "skipped".
      final latest = await pumpAndRead(tester, 'espresso');
      expect(latest['puckPrepWdt'], false);
      expect(latest['puckPrepDistribution'], false);
      expect(latest['puckPrepTamp'], false);
    });

    testWidgets('reports parsed and sticky values without being touched', (
      tester,
    ) async {
      final latest = await pumpAndRead(
        tester,
        'espresso',
        core: {'doseGrams': 18},
        sticky: {'grinder': 'Niche'},
      );
      expect(latest['doseGrams'], 18);
      expect(latest['grinder'], 'Niche');
    });

    testWidgets('never invents a value for an untouched text field', (
      tester,
    ) async {
      final latest = await pumpAndRead(tester, 'espresso');
      expect(latest.containsKey('beanOrigin'), isFalse);
      expect(latest.containsKey('pressureBars'), isFalse);
    });

    testWidgets('renders a section header per group', (tester) async {
      // Coffee and brew render expanded, so on a phone-sized surface the
      // later headers sit below the fold. A tall surface checks that all
      // four exist at all; the collapsed-state test below checks the rest.
      tester.view.physicalSize = const Size(1200, 6000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await pumpAndRead(tester, 'espresso');
      for (final g in ['Coffee', 'Grind', 'Brew', 'Water']) {
        expect(find.text(g), findsOneWidget, reason: 'missing $g header');
      }
    });

    testWidgets('shows brew and coffee expanded, grind and water collapsed', (
      tester,
    ) async {
      await pumpAndRead(tester, 'espresso');
      // An expanded group shows its rows; a collapsed one does not.
      expect(find.text('Roast level'), findsOneWidget);
      expect(find.text('Grinder'), findsNothing);
    });

    testWidgets('a collapsed group opens on tap', (tester) async {
      await pumpAndRead(tester, 'espresso');
      await tester.tap(find.text('Grind'));
      await tester.pumpAndSettle();
      expect(find.text('Grinder'), findsOneWidget);
    });

    testWidgets('a remembered value says so', (tester) async {
      await pumpAndRead(tester, 'espresso', sticky: {'doseGrams': 18.0});
      expect(find.text('remembered'), findsWidgets);
    });

    testWidgets('a parsed value says where it came from', (tester) async {
      await pumpAndRead(tester, 'espresso', core: {'beanOrigin': 'Ethiopian'});
      expect(find.text('from your text'), findsWidgets);
    });

    testWidgets('an untouched empty field claims nothing', (tester) async {
      await pumpAndRead(tester, 'espresso');
      expect(find.text('remembered'), findsNothing);
      expect(find.text('from your text'), findsNothing);
    });

    testWidgets('editing a field clears its marker', (tester) async {
      // The marker means "nobody has confirmed this". Once you have typed in
      // the box, somebody has.
      await pumpAndRead(tester, 'espresso', sticky: {'doseGrams': 18.0});
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Dose (g)'),
        '20',
      );
      await tester.pump();
      expect(find.text('remembered'), findsNothing);
    });

    testWidgets('a remembered dropdown value shows the marker', (tester) async {
      await pumpAndRead(tester, 'espresso', sticky: {'roastLevel': 'medium'});
      expect(find.text('remembered'), findsWidgets);
    });

    testWidgets('a remembered date value shows the marker', (tester) async {
      await pumpAndRead(
        tester,
        'espresso',
        sticky: {'roastDate': '2026-08-01'},
      );
      expect(find.text('remembered'), findsWidgets);
    });

    testWidgets('a remembered switch value shows the marker', (tester) async {
      await pumpAndRead(tester, 'espresso', sticky: {'puckPrepWdt': true});
      expect(find.text('remembered'), findsWidgets);
    });
  });
}
