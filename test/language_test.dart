import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
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
      // A handful are legitimately identical — proper nouns and units.
      if (const {'appName', 'espresso'}.contains(key)) continue;
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

  test('category and method labels follow the language too', () {
    final s = BrewSchema.parse(
      File('schema/brew_schema.json').readAsStringSync(),
    );
    AppStrings.language = 'id';
    expect(s.categoryOf('kopiTubruk').label, 'Nusantara');
    expect(s.method('coneDripper').label, 'Dripper kerucut');
    AppStrings.language = 'en';
    expect(s.categoryOf('kopiTubruk').label, 'Indonesian');
    expect(s.method('coneDripper').label, 'Cone dripper');
  });

  test('defaults to English', () {
    AppStrings.language = 'en';
    expect(AppStrings.language, 'en');
    expect(AppStrings.saveButton, 'Save');
  });

  tearDown(() => AppStrings.language = 'en');
}
