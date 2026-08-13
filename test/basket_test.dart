import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kopi_kompas/data/brew_schema.dart';
import 'package:kopi_kompas/strings.dart';
import 'package:kopi_kompas/widgets/follow_up_form.dart';

late BrewSchema schema;

FieldSpec field(String name) =>
    schema.method('espresso').fields.firstWhere((f) => f.name == name);

void main() {
  setUpAll(() {
    schema = BrewSchema.parse(
      File('schema/brew_schema.json').readAsStringSync(),
    );
  });

  tearDown(() => AppStrings.language = 'en');

  test('capacity is grams and says so', () {
    // Grams is the spec that interacts with dose — 18 g in a 22 g basket
    // channels — and it is what the rubric judges. "Basket size" read as
    // diameter to anyone who has bought one.
    final f = field('basketSizeGrams');
    expect(f.type, FieldType.number);
    expect(f.unit, 'g');
    expect(f.label, 'Basket capacity');
  });

  test('diameter is a picker of the sizes that exist', () {
    // Fixed by the portafilter, not chosen per shot, so it is a short list
    // rather than a free number.
    final f = field('basketDiameterMm');
    expect(f.type, FieldType.enumerated);
    expect(f.values, ['mm51', 'mm53', 'mm54', 'mm58']);
    expect(schema.valueLabel('mm58'), '58 mm');
  });

  test('basket type is two options, not a textbox', () {
    final f = field('basketType');
    expect(f.type, FieldType.enumerated);
    expect(f.values, ['pressurised', 'nonPressurised']);
    expect(schema.valueLabel('pressurised'), 'Pressurised');
    AppStrings.language = 'id';
    expect(schema.valueLabel('nonPressurised'), 'Non-pressurized');
  });

  testWidgets('choosing a pressurised basket explains what stops mattering', (
    tester,
  ) async {
    // Tall enough that the ListView builds every field. Espresso has more
    // rows than a phone screen, and a lazily-built row cannot be tapped.
    tester.view.physicalSize = const Size(1200, 4000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BrewForm(
            schema: schema,
            fields: formFields(
              schema,
              'espresso',
              const {},
              const {},
              const {},
            ),
            onChanged: (_) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text(AppStrings.pressurisedNote), findsNothing);

    final dropdown = find.byWidgetPredicate(
      (w) =>
          w is DropdownButtonFormField<String> && _labelOf(w) == 'Basket type',
    );
    expect(dropdown, findsOneWidget);
    await tester.tap(dropdown);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Pressurised').last);
    await tester.pumpAndSettle();

    expect(find.text(AppStrings.pressurisedNote), findsOneWidget);
  });
}

String? _labelOf(DropdownButtonFormField<String> w) => w.decoration.labelText;
