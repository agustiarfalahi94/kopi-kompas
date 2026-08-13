import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kopi_kompas/data/brew_guide.dart';
import 'package:kopi_kompas/data/brew_schema.dart';
import 'package:kopi_kompas/strings.dart';

void main() {
  test('every string is translated, and none was left in English', () {
    // The failure this catches: a string copied into the Indonesian map and
    // never actually translated. A map lookup could not promise this; static
    // getters can, because the list below has to compile.
    AppStrings.language = 'en';
    final en = AppStrings.all;
    AppStrings.language = 'id';
    final id = AppStrings.all;

    expect(en.keys, id.keys);
    for (final key in en.keys) {
      expect(id[key], isNotEmpty, reason: '$key is empty in Indonesian');
      // A handful are legitimately identical — proper nouns and loanwords
      // that Indonesian uses unchanged.
      if (const {'appName', 'espresso', 'emailLabel'}.contains(key)) continue;
      expect(id[key], isNot(en[key]), reason: '$key was never translated');
    }
  });

  test('labels follow the language without re-parsing the schema', () {
    // The schema is parsed once at startup. Resolving labels at parse time
    // froze them in whichever language happened to be set then, and left
    // them stale forever after a switch — which is exactly what shipped and
    // showed up as an Indonesian form with English field names.
    final schema = BrewSchema.parse(
      File('schema/brew_schema.json').readAsStringSync(),
    );
    final origin = schema.core.firstWhere((f) => f.name == 'beanOrigin');

    AppStrings.language = 'en';
    expect(origin.label, 'Bean origin');

    AppStrings.language = 'id';
    expect(origin.label, 'Asal biji');

    AppStrings.language = 'en';
    expect(origin.label, 'Bean origin', reason: 'must switch back too');
  });

  test('method names stay in English in both languages', () {
    // Names of techniques and equipment are not translated. "Dripper dasar
    // rata" is a phrase nobody says, and "Kopi saring" as the filter category
    // collided with kopiSaring the method, which is a different thing.
    final s = BrewSchema.parse(
      File('schema/brew_schema.json').readAsStringSync(),
    );
    for (final id in s.methodIds) {
      AppStrings.language = 'en';
      final en = s.method(id).label;
      AppStrings.language = 'id';
      expect(s.method(id).label, en, reason: '$id was translated');
    }
  });

  test('categories keep English names except Nusantara', () {
    final s = BrewSchema.parse(
      File('schema/brew_schema.json').readAsStringSync(),
    );
    AppStrings.language = 'id';
    expect(s.categoryOf('kopiTubruk').label, 'Nusantara');
    expect(s.categoryOf('coneDripper').label, 'Filter');
    expect(s.categoryOf('aeropress').label, 'Hybrid');
  });

  test('defaults to English', () {
    AppStrings.language = 'en';
    expect(AppStrings.language, 'en');
    expect(AppStrings.saveButton, 'Save');
  });

  tearDown(() => AppStrings.language = 'en');

  test('every guide is written in both languages', () {
    // The bug this catches actually shipped: the headings switched to
    // Indonesian and the guide text stayed English, because only the
    // headings went through AppStrings.
    final guides = BrewGuides.parse(
      File('assets/guides.json').readAsStringSync(),
    );
    final schema = BrewSchema.parse(
      File('schema/brew_schema.json').readAsStringSync(),
    );

    for (final id in schema.methodIds) {
      final g = guides.forMethod(id)!;

      AppStrings.language = 'en';
      final en = [
        g.what,
        ...g.steps,
        ...g.notes,
        for (final f in g.faults) ...[f.symptom, f.cause],
        for (final t in g.gear) ...[t.tier, t.what],
      ];

      AppStrings.language = 'id';
      final id_ = [
        g.what,
        ...g.steps,
        ...g.notes,
        for (final f in g.faults) ...[f.symptom, f.cause],
        for (final t in g.gear) ...[t.tier, t.what],
      ];

      expect(id_.length, en.length, reason: id);
      for (var i = 0; i < en.length; i++) {
        expect(id_[i], isNotEmpty, reason: '$id piece $i is empty');
        expect(id_[i], isNot(en[i]), reason: '$id piece $i not translated');
      }
    }
  });

  test('every enum value has a label in both languages', () {
    // Dropdowns used to render the raw id, so a form offered "kalitaWave"
    // and "wet-hulled" and neither changed with the language.
    final schema = BrewSchema.parse(
      File('schema/brew_schema.json').readAsStringSync(),
    );
    final values = <String>{
      for (final f in schema.core)
        if (f.type == FieldType.enumerated) ...f.values,
      for (final m in schema.methodIds)
        for (final f in schema.method(m).fields)
          if (f.type == FieldType.enumerated) ...f.values,
    };
    expect(values, isNotEmpty);
    for (final v in values) {
      AppStrings.language = 'en';
      final en = schema.valueLabel(v);
      AppStrings.language = 'id';
      final id = schema.valueLabel(v);
      expect(en, isNot(v), reason: '$v has no human label');
      expect(id, isNotEmpty, reason: '$v has no Indonesian label');
    }
  });

  test('grind advice follows the language', () {
    final schema = BrewSchema.parse(
      File('schema/brew_schema.json').readAsStringSync(),
    );
    AppStrings.language = 'en';
    expect(schema.method('espresso').targets!.grind, contains('table salt'));
    AppStrings.language = 'id';
    expect(schema.method('espresso').targets!.grind, contains('garam meja'));
  });

  test('no screen renders a raw enum id', () {
    // The full log had its own copy of the value-rendering logic and never
    // got the label lookup, so it showed "filtered" and "kalitaWave" on
    // screen in both languages. Any screen that formats a field value has to
    // go through valueLabel, and this is the reminder.
    final source = [
      'lib/screens/full_log_screen.dart',
      'lib/screens/entry_detail_screen.dart',
      'lib/widgets/follow_up_form.dart',
    ];
    for (final path in source) {
      final text = File(path).readAsStringSync();
      expect(
        text,
        contains('valueLabel'),
        reason: '$path formats field values without translating enums',
      );
    }
  });

  test('water types read naturally in Indonesian', () {
    final schema = BrewSchema.parse(
      File('schema/brew_schema.json').readAsStringSync(),
    );
    AppStrings.language = 'id';
    expect(schema.valueLabel('filtered'), 'Air filter');
    expect(schema.valueLabel('bottled'), 'Air botol');
    expect(schema.valueLabel('tap'), 'Air keran');
    expect(schema.valueLabel('mineral'), 'Air mineral');
  });
}
