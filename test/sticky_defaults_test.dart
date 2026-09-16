import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kopi_kompas/data/brew_schema.dart';
import 'package:kopi_kompas/models/brew_entry.dart';
import 'package:kopi_kompas/services/sticky_defaults.dart';

late BrewSchema schema;

/// Newest first, the order `liveEntries()` returns.
BrewEntry entry(
  String method, {
  String? beanOrigin,
  String? roaster,
  String? grinder,
  String? grindSetting,
  String? waterType,
  String? roastLevel,
  double? doseGrams,
  String? notes,
  DateTime? roastDate,
  Map<String, Object?> methodData = const {},
}) => BrewEntry(
  id: 'e-$method-${methodData.hashCode}',
  brewMethod: method,
  brewDate: DateTime(2026, 8, 12, 7),
  rawInputText: 'x',
  methodData: methodData,
  scoreStatus: ScoreStatus.scored,
  createdAt: DateTime(2026, 8, 12, 7),
  updatedAt: DateTime(2026, 8, 12, 7),
  beanOrigin: beanOrigin,
  roaster: roaster,
  grinder: grinder,
  grindSetting: grindSetting,
  waterType: waterType,
  roastLevel: roastLevel,
  doseGrams: doseGrams,
  notes: notes,
  roastDate: roastDate,
);

void main() {
  setUpAll(() {
    schema = BrewSchema.parse(
      File('schema/brew_schema.json').readAsStringSync(),
    );
  });

  test('an empty history remembers nothing', () {
    expect(stickyFor(schema, 'espresso', const []), isEmpty);
  });

  test('the core fields carry across a change of method', () {
    // The whole point: you told it once that you grind on an EM2 at 3 with
    // filtered water, and a french press should not ask again.
    final sticky = stickyFor(schema, 'frenchPress', [
      entry(
        'espresso',
        beanOrigin: 'Ethiopian',
        roaster: 'Common Grounds',
        grinder: 'Russell Taylors EM2',
        grindSetting: '3',
        waterType: 'filtered',
        methodData: const {'machine': 'Russell Taylors EM2', 'yieldGrams': 36},
      ),
    ]);
    expect(sticky['beanOrigin'], 'Ethiopian');
    expect(sticky['roaster'], 'Common Grounds');
    expect(sticky['grinder'], 'Russell Taylors EM2');
    expect(sticky['grindSetting'], '3');
    expect(sticky['waterType'], 'filtered');
  });

  test('a field the target method does not have is dropped', () {
    // `machine` and `yieldGrams` belong to espresso. A french press has
    // neither, and offering them would invent fields the form cannot show.
    final sticky = stickyFor(schema, 'frenchPress', [
      entry(
        'espresso',
        methodData: const {'machine': 'Russell Taylors EM2', 'yieldGrams': 36},
      ),
    ]);
    expect(sticky.containsKey('machine'), isFalse);
    expect(sticky.containsKey('yieldGrams'), isFalse);
  });

  test('the category carries what the method has not seen yet', () {
    // First ever Kalita, after months of V60. Both are `filter`, so the
    // temperature and ratio are worth having.
    final sticky = stickyFor(schema, 'flatBottomDripper', [
      entry(
        'coneDripper',
        methodData: const {'waterTempC': 93.0, 'ratio': 16.0, 'brewer': 'v60'},
      ),
    ]);
    expect(sticky['waterTempC'], 93.0);
    expect(sticky['ratio'], 16.0);
  });

  test('an enum value the target method does not offer is dropped', () {
    // `brewer` exists on coneDripper, flatBottomDripper and smartDripper with
    // value lists that share nothing: v60/origami/kono, kalitaWave/staggX/
    // orea/april, clever/switch. The first two are both `filter`, so the
    // category layer really does offer a V60 to a Kalita form. The dropdown
    // would render blank and BrewForm would save the invalid id anyway.
    final sticky = stickyFor(schema, 'flatBottomDripper', [
      entry('coneDripper', methodData: const {'brewer': 'v60'}),
    ]);
    expect(sticky.containsKey('brewer'), isFalse);
  });

  test('a valid enum value for the target method is kept', () {
    final sticky = stickyFor(schema, 'flatBottomDripper', [
      entry('flatBottomDripper', methodData: const {'brewer': 'kalitaWave'}),
    ]);
    expect(sticky['brewer'], 'kalitaWave');
  });

  test('the method beats the category for the same field', () {
    // Your own last V60 temperature is worth more than yesterday's Kalita.
    final sticky = stickyFor(schema, 'coneDripper', [
      entry('flatBottomDripper', methodData: const {'waterTempC': 96.0}),
      entry('coneDripper', methodData: const {'waterTempC': 92.0}),
    ]);
    expect(sticky['waterTempC'], 92.0);
  });

  test('the newest entry in a layer wins', () {
    final sticky = stickyFor(schema, 'espresso', [
      entry('espresso', grinder: 'EK43'),
      entry('espresso', grinder: 'Niche'),
    ]);
    expect(sticky['grinder'], 'EK43');
  });

  test('a field absent from the newest entry is taken from an older one', () {
    // Not mentioning the grinder today does not mean you sold it.
    final sticky = stickyFor(schema, 'espresso', [
      entry('espresso', waterType: 'tap'),
      entry('espresso', grinder: 'Niche'),
    ]);
    expect(sticky['grinder'], 'Niche');
    expect(sticky['waterType'], 'tap');
  });

  test('notes are never carried', () {
    // Prose about one specific cup. Stapling "tasted sharp, a bit thin" onto
    // tomorrow's coffee is worse than an empty box.
    final sticky = stickyFor(schema, 'espresso', [
      entry('espresso', notes: 'tasted sharp, a bit thin'),
    ]);
    expect(sticky.containsKey('notes'), isFalse);
  });

  test('a core field the method hides is never offered', () {
    // Kopi tubruk is made from pre-ground packaged coffee. It hides the
    // grinder however many espresso shots precede it.
    final sticky = stickyFor(schema, 'kopiTubruk', [
      entry(
        'espresso',
        grinder: 'Niche',
        grindSetting: '3',
        roaster: 'Anomali',
      ),
    ]);
    expect(sticky.containsKey('grinder'), isFalse);
    expect(sticky.containsKey('grindSetting'), isFalse);
    expect(sticky.containsKey('roaster'), isFalse);
  });

  test('a value whose type does not match the field is dropped', () {
    // A methodData blob written by an older schema version.
    final sticky = stickyFor(schema, 'espresso', [
      entry('espresso', methodData: const {'yieldGrams': 'thirty-six'}),
    ]);
    expect(sticky.containsKey('yieldGrams'), isFalse);
  });

  test('a roast date is offered as the YYYY-MM-DD the form expects', () {
    final sticky = stickyFor(schema, 'espresso', [
      entry('espresso', roastDate: DateTime(2026, 8, 1)),
    ]);
    expect(sticky['roastDate'], '2026-08-01');
  });

  test('the core layer alone is available without a method', () {
    // Settings shows what carries everywhere, and has no method to resolve
    // against.
    final core = rememberedCore([
      entry('espresso', grinder: 'Niche', methodData: const {'machine': 'x'}),
    ]);
    expect(core['grinder'], 'Niche');
    expect(core.containsKey('machine'), isFalse);
    expect(core.containsKey('notes'), isFalse);
  });

  test('booleans and numbers carry, not just strings', () {
    final sticky = stickyFor(schema, 'espresso', [
      entry(
        'espresso',
        doseGrams: 18,
        methodData: const {'puckPrepWdt': true, 'basketSizeGrams': 18.0},
      ),
    ]);
    expect(sticky['doseGrams'], 18.0);
    expect(sticky['puckPrepWdt'], true);
    expect(sticky['basketSizeGrams'], 18.0);
  });
}
