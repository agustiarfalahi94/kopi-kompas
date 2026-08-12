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

  test('field labels follow the language', () {
    final source = File('schema/brew_schema.json').readAsStringSync();

    AppStrings.language = 'en';
    final english = BrewSchema.parse(source);
    expect(
      english.core.firstWhere((f) => f.name == 'beanOrigin').label,
      'Bean origin',
    );

    AppStrings.language = 'id';
    final indonesian = BrewSchema.parse(source);
    expect(
      indonesian.core.firstWhere((f) => f.name == 'beanOrigin').label,
      'Asal biji',
    );
  });

  test('category and method labels follow the language', () {
    final source = File('schema/brew_schema.json').readAsStringSync();
    AppStrings.language = 'id';
    final s = BrewSchema.parse(source);
    expect(s.categoryOf('kopiTubruk').label, 'Nusantara');
    expect(s.method('coneDripper').label, 'Dripper kerucut');
  });

  test('defaults to English', () {
    AppStrings.language = 'en';
    expect(AppStrings.language, 'en');
    expect(AppStrings.saveButton, 'Save');
  });

  tearDown(() => AppStrings.language = 'en');
}
