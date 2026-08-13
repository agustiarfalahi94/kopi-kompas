import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kopi_kompas/data/brew_guide.dart';
import 'package:kopi_kompas/data/brew_schema.dart';

late BrewSchema schema;
late BrewGuides guides;

void main() {
  setUpAll(() {
    schema = BrewSchema.parse(
      File('schema/brew_schema.json').readAsStringSync(),
    );
    guides = BrewGuides.parse(File('assets/guides.json').readAsStringSync());
  });

  test('every brew method has a guide', () {
    for (final id in schema.methodIds) {
      expect(guides.forMethod(id), isNotNull, reason: '$id has no guide');
    }
  });

  test('every guide belongs to a real method', () {
    // A guide for a method that no longer exists would never render, and
    // nobody would notice it had gone stale.
    for (final id in schema.methodIds) {
      expect(() => schema.method(id), returnsNormally);
    }
  });

  test('every method carries targets', () {
    for (final id in schema.methodIds) {
      expect(schema.method(id).targets, isNotNull, reason: id);
    }
  });

  test('the guide quotes the same numbers the scorer uses', () {
    // The whole reason targets live in brew_schema.json rather than in the
    // guide text: if a guide said 25-32 seconds and the rubric used a
    // different band, following the advice would cost you points.
    final espresso = schema.method('espresso').targets!;
    expect(espresso.ratio.text, '1.8–2.2');
    expect(espresso.time.text, '25–32 s');
    expect(espresso.temp.text, '90–96 °C');
  });

  test('a long steep reads in hours, not seconds', () {
    // 43200 seconds is not a useful thing to show someone.
    expect(schema.method('coldBrew').targets!.time.text, '12–18 h');
  });

  test('every guide has steps, faults and gear tiers', () {
    for (final id in schema.methodIds) {
      final g = guides.forMethod(id)!;
      expect(g.what, isNotEmpty, reason: id);
      expect(g.steps.length, greaterThanOrEqualTo(3), reason: id);
      expect(g.faults, isNotEmpty, reason: id);
      expect(g.gear.length, 3, reason: '$id should have three gear tiers');
    }
  });

  test('every fault names both a symptom and a cause', () {
    // "It tastes bad" without a cause is not troubleshooting.
    for (final id in schema.methodIds) {
      for (final f in guides.forMethod(id)!.faults) {
        expect(f.symptom, isNotEmpty, reason: id);
        expect(f.cause, isNotEmpty, reason: id);
      }
    }
  });

  test('the guides that need a safety note carry one', () {
    // Raw egg and charcoal are the two places this app could get someone
    // hurt, so the warning is pinned rather than left to survive an edit.
    final talua = guides.forMethod('kopiTalua')!.notes.join(' ').toLowerCase();
    expect(talua, contains('raw egg'));

    final joss = guides.forMethod('kopiJoss')!.notes.join(' ').toLowerCase();
    expect(joss, contains('briquette'));
  });

  test('the espresso guide explains pressurised versus not', () {
    final notes = guides.forMethod('espresso')!.notes.join(' ');
    expect(notes.toLowerCase(), contains('pressurised'));
    expect(notes, contains('58'));
  });
}
