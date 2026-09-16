import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kopi_kompas/data/brew_schema.dart';
import 'package:kopi_kompas/screens/new_entry_screen.dart';
import 'package:kopi_kompas/widgets/follow_up_form.dart';

void main() {
  late BrewSchema schema;
  setUpAll(() {
    schema = BrewSchema.parse(
      File('schema/brew_schema.json').readAsStringSync(),
    );
  });

  Future<TextEditingController> pumpDate(
    WidgetTester tester, {
    String? initial,
    ValueChanged<Map<String, Object?>>? onChanged,
  }) async {
    final spec = schema.core.firstWhere((f) => f.name == 'roastDate');
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BrewForm(
            schema: schema,
            fields: [
              BrewFormField(
                spec,
                initial,
                initial == null ? FieldSource.empty : FieldSource.sticky,
              ),
            ],
            onChanged: onChanged ?? (_) {},
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.byType(TextFormField));
    return tester.widget<EditableText>(find.byType(EditableText)).controller;
  }

  Future<void> edit(
    WidgetTester tester,
    String text, {
    TextSelection? selection,
    TextRange composing = TextRange.empty,
  }) async {
    tester.testTextInput.updateEditingValue(
      TextEditingValue(
        text: text,
        selection: selection ?? TextSelection.collapsed(offset: text.length),
        composing: composing,
      ),
    );
    await tester.pump();
  }

  // Removing separator insertion or cursor adjustment must break this test.
  testWidgets('typing advances from year to month to day', (tester) async {
    final controller = await pumpDate(tester);
    const expected = [
      '2',
      '20',
      '202',
      '2026-',
      '2026-0',
      '2026-09-',
      '2026-09-1',
      '2026-09-16',
    ];
    for (var i = 0; i < expected.length; i++) {
      await edit(tester, '${controller.text}${'20260916'[i]}');
      expect(controller.text, expected[i]);
      expect(controller.selection.baseOffset, expected[i].length);
    }
  });

  // A missing digit cap would let a pasted value overflow the field.
  testWidgets(
    'pasting accepts compact and ISO dates and caps at eight digits',
    (tester) async {
      final controller = await pumpDate(tester);
      for (final text in ['20260916', '2026-09-16', '202609169999999999']) {
        await tester.enterText(find.byType(TextFormField), text);
        expect(controller.text, '2026-09-16');
      }
      await tester.enterText(find.byType(TextFormField), 'abc2026/09/16xyz');
      expect(controller.text, '2026-09-16');
    },
  );

  // Re-inserting a separator after backspace would trap the user at a boundary.
  testWidgets('backspace crosses both separators and can clear the date', (
    tester,
  ) async {
    final controller = await pumpDate(tester);
    await edit(tester, '20260916');
    for (final expected in [
      '2026-09-1',
      '2026-09-',
      '2026-0',
      '2026-',
      '202',
      '20',
      '2',
      '',
    ]) {
      await edit(
        tester,
        controller.text.substring(0, controller.text.length - 1),
      );
      expect(controller.text, expected);
      expect(controller.selection.baseOffset, expected.length);
    }
  });

  // Always moving the cursor to the end would break editing an existing month.
  testWidgets('replacing the month keeps the cursor at the edited segment', (
    tester,
  ) async {
    final controller = await pumpDate(tester, initial: '2026-09-16');
    await edit(
      tester,
      controller.text,
      selection: const TextSelection(baseOffset: 5, extentOffset: 7),
    );
    await edit(
      tester,
      '2026-08-16',
      selection: const TextSelection.collapsed(offset: 7),
    );
    expect(controller.text, '2026-08-16');
    expect(controller.selection.baseOffset, 8);
    await edit(
      tester,
      controller.text,
      selection: const TextSelection(baseOffset: 7, extentOffset: 5),
    );
    expect(
      controller.selection,
      const TextSelection(baseOffset: 7, extentOffset: 5),
    );
  });

  // Formatting an active IME composition can interfere with the keyboard.
  testWidgets('waits until keyboard composition is committed', (tester) async {
    final controller = await pumpDate(tester);
    await edit(tester, '2026', composing: const TextRange(start: 0, end: 4));
    expect(
      controller.value,
      const TextEditingValue(
        text: '2026',
        selection: TextSelection.collapsed(offset: 4),
        composing: TextRange(start: 0, end: 4),
      ),
    );
    await edit(tester, '2026');
    expect(controller.text, '2026-');
    await edit(
      tester,
      '20260916999',
      composing: const TextRange(start: 0, end: 11),
    );
    expect(
      controller.value,
      const TextEditingValue(
        text: '20260916999',
        selection: TextSelection.collapsed(offset: 11),
        composing: TextRange(start: 0, end: 11),
      ),
    );
    await edit(tester, '20260916999');
    expect(controller.text, '2026-09-16');
    expect(controller.selection.baseOffset, 10);
  });

  // DateTime.tryParse alone rolls February 30 into March; never emit that date.
  testWidgets('reports only complete real calendar dates', (tester) async {
    var latest = <String, Object?>{};
    await pumpDate(tester, onChanged: (value) => latest = value);
    for (final text in ['2026', '202609', '20260230', '20261301', '20260900']) {
      await tester.enterText(find.byType(TextFormField), text);
      expect(latest['roastDate'], isNull, reason: text);
    }
    await tester.enterText(find.byType(TextFormField), '20240229');
    expect(latest['roastDate'], '2024-02-29');
    await tester.enterText(find.byType(TextFormField), '20230229');
    expect(latest['roastDate'], isNull);
    await tester.enterText(find.byType(TextFormField), '20260916');
    expect(latest['roastDate'], '2026-09-16');
    await tester.enterText(find.byType(TextFormField), '');
    expect(latest['roastDate'], isNull);
  });

  testWidgets('preserves a remembered valid date without editing', (
    tester,
  ) async {
    var latest = <String, Object?>{};
    final controller = await pumpDate(
      tester,
      initial: '2026-09-16',
      onChanged: (value) => latest = value,
    );
    expect(controller.text, '2026-09-16');
    expect(latest['roastDate'], '2026-09-16');
    expect(find.text('remembered'), findsOneWidget);
  });

  testWidgets(
    'does not carry an impossible prefilled date into a saved entry',
    (tester) async {
      var latest = <String, Object?>{};
      final controller = await pumpDate(
        tester,
        initial: '2026-02-30',
        onChanged: (value) => latest = value,
      );
      expect(latest['roastDate'], isNull);
      expect(controller.text, isEmpty);
      expect(find.text('remembered'), findsNothing);
    },
  );

  testWidgets('clearing a parsed date does not restore it when saving', (
    tester,
  ) async {
    DateTime? savedDate;
    await pumpDate(
      tester,
      initial: '2026-09-16',
      onChanged: (answers) {
        savedDate = buildEntry(
          brewMethod: 'kopiTubruk',
          core: const {'roastDate': '2026-09-16'},
          methodData: const {},
          answers: answers,
          rawInputText: '',
          schema: schema,
          now: DateTime(2026, 9, 16),
        ).roastDate;
      },
    );
    expect(savedDate, DateTime(2026, 9, 16));
    for (final text in ['', '2026', '20260230']) {
      await tester.enterText(find.byType(TextFormField), text);
      expect(savedDate, isNull, reason: text);
    }
  });
}
