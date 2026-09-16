import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kopi_kompas/data/brew_schema.dart';
import 'package:kopi_kompas/models/brew_entry.dart';
import 'package:kopi_kompas/screens/new_entry_screen.dart';
import 'package:kopi_kompas/services/kopi_client.dart';
import 'package:kopi_kompas/strings.dart';

late BrewSchema schema;

void main() {
  setUpAll(() {
    schema = BrewSchema.parse(
      File('schema/brew_schema.json').readAsStringSync(),
    );
  });

  test('buildEntry merges the parse with the form answers', () {
    final e = buildEntry(
      brewMethod: 'espresso',
      core: {'doseGrams': 18},
      methodData: {'yieldGrams': 36},
      answers: {'beanOrigin': 'Honduras', 'puckPrepWdt': false},
      rawInputText: '18g in 36g out',
      schema: schema,
      now: DateTime(2026, 8, 12, 7, 30),
    );
    expect(e.doseGrams, 18);
    expect(e.beanOrigin, 'Honduras');
    expect(e.methodData['yieldGrams'], 36);
    expect(e.methodData['puckPrepWdt'], false);
    expect(e.rawInputText, '18g in 36g out');
  });

  test(
    'a form answer routes to core or methodData by schema, not guesswork',
    () {
      final e = buildEntry(
        brewMethod: 'coneDripper',
        core: const {},
        methodData: const {},
        answers: {'roastLevel': 'light', 'pourCount': 3, 'brewer': 'v60'},
        rawInputText: 'x',
        schema: schema,
        now: DateTime(2026, 8, 12, 7),
      );
      expect(e.roastLevel, 'light');
      expect(e.methodData['pourCount'], 3);
      expect(e.methodData['brewer'], 'v60');
      expect(e.methodData.containsKey('roastLevel'), isFalse);
    },
  );

  test('an int dose from the form survives as a double', () {
    // The form yields int for whole numbers typed into a decimal field on
    // some keyboards; doseGrams is a REAL column.
    final e = buildEntry(
      brewMethod: 'espresso',
      core: const {},
      methodData: const {},
      answers: {'doseGrams': 18},
      rawInputText: 'x',
      schema: schema,
      now: DateTime(2026, 8, 12, 7),
    );
    expect(e.doseGrams, 18.0);
  });

  test('a scored method starts pending', () {
    final e = buildEntry(
      brewMethod: 'espresso',
      core: const {},
      methodData: const {},
      answers: const {},
      rawInputText: 'x',
      schema: schema,
      now: DateTime(2026, 8, 12, 7),
    );
    expect(e.scoreStatus, ScoreStatus.pending);
  });

  test('an unscored method is notApplicable and never pending', () {
    final e = buildEntry(
      brewMethod: 'kopiJoss',
      core: const {},
      methodData: const {},
      answers: const {},
      rawInputText: 'x',
      schema: schema,
      now: DateTime(2026, 8, 12, 7),
    );
    expect(e.scoreStatus, ScoreStatus.notApplicable);
    expect(e.overallScore, isNull);
  });

  test('brewDate is the local wall clock', () {
    final e = buildEntry(
      brewMethod: 'espresso',
      core: const {},
      methodData: const {},
      answers: const {},
      rawInputText: 'x',
      schema: schema,
      now: DateTime(2026, 8, 12, 0, 30),
    );
    expect(e.toRow()['brewDate'], startsWith('2026-08-12T00:30'));
  });

  test('a null answer never overwrites a parsed value', () {
    final e = buildEntry(
      brewMethod: 'espresso',
      core: {'beanOrigin': 'Honduras'},
      methodData: const {},
      answers: {'beanOrigin': null},
      rawInputText: 'x',
      schema: schema,
      now: DateTime(2026, 8, 12, 7),
    );
    expect(e.beanOrigin, 'Honduras');
  });

  test('the confetti threshold fires at 90 and not at 89', () {
    expect(shouldCelebrate(90), isTrue);
    expect(shouldCelebrate(100), isTrue);
    expect(shouldCelebrate(89), isFalse);
    expect(shouldCelebrate(null), isFalse);
  });

  test('routes every new core field to core, not to methodData', () {
    // buildEntry decides by asking the schema. If that ever drifts, roaster
    // and grinder would silently land in the method blob and never render.
    final e = buildEntry(
      brewMethod: 'espresso',
      core: const {},
      methodData: const {},
      answers: {
        'roaster': 'Common Grounds',
        'process': 'natural',
        'roastDate': '2026-08-01',
        'grinder': 'Niche',
        'grindSetting': '18',
        'waterType': 'filtered',
        'basketSizeGrams': 18.0,
      },
      rawInputText: 'x',
      schema: schema,
      now: DateTime(2026, 8, 12, 7),
    );
    expect(e.roaster, 'Common Grounds');
    expect(e.process, 'natural');
    expect(e.roastDate, DateTime(2026, 8, 1));
    expect(e.grinder, 'Niche');
    expect(e.grindSetting, '18');
    expect(e.waterType, 'filtered');
    expect(e.methodData['basketSizeGrams'], 18.0);
    for (final coreOnly in ['roaster', 'grinder', 'waterType']) {
      expect(e.methodData.containsKey(coreOnly), isFalse, reason: coreOnly);
    }
  });

  test('scoreMessageFor says offline for a network failure', () {
    expect(scoreMessageFor(KopiError.network), AppStrings.offline);
  });

  test('scoreMessageFor says the daily limit for rateLimited', () {
    expect(scoreMessageFor(KopiError.rateLimited), AppStrings.rateLimited);
  });

  test('scoreMessageFor falls back to scoreUnavailable, not the parse '
      'step\'s "could not read that"', () {
    // The real-world bug: Gemini answered 503, the Worker mapped it to
    // 502, and the client turns that into KopiError.upstream. This must
    // not read as a sentence about unreadable text.
    expect(scoreMessageFor(KopiError.upstream), AppStrings.scoreUnavailable);
    expect(scoreMessageFor(KopiError.notScored), AppStrings.scoreUnavailable);
    expect(scoreMessageFor(KopiError.badRequest), AppStrings.scoreUnavailable);
  });
}
