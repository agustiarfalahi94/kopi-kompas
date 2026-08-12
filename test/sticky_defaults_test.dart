import 'package:flutter_test/flutter_test.dart';
import 'package:kopi_kompas/models/brew_entry.dart';
import 'package:kopi_kompas/services/sticky_defaults.dart';
import 'package:shared_preferences/shared_preferences.dart';

BrewEntry entry({
  String? grinder,
  String? grindSetting,
  String? waterType,
  String? beanOrigin,
  Map<String, Object?> methodData = const {},
}) => BrewEntry(
  id: 'a',
  brewMethod: 'espresso',
  brewDate: DateTime(2026, 8, 12, 7),
  rawInputText: 'x',
  methodData: methodData,
  scoreStatus: ScoreStatus.scored,
  createdAt: DateTime(2026, 8, 12, 7),
  updatedAt: DateTime(2026, 8, 12, 7),
  grinder: grinder,
  grindSetting: grindSetting,
  waterType: waterType,
  beanOrigin: beanOrigin,
);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
    'remembers the grinder, its setting, the water and the machine',
    () async {
      await rememberSticky(
        entry(
          grinder: 'Niche',
          grindSetting: '18',
          waterType: 'filtered',
          methodData: const {'machine': 'Gaggia'},
        ),
      );
      final d = await loadStickyDefaults();
      expect(d['grinder'], 'Niche');
      expect(d['grindSetting'], '18');
      expect(d['waterType'], 'filtered');
      expect(d['machine'], 'Gaggia');
    },
  );

  test('never remembers the bean origin', () async {
    // It changes with every bag, so pre-filling it would be wrong far more
    // often than right.
    await rememberSticky(entry(beanOrigin: 'Honduras', grinder: 'Niche'));
    final d = await loadStickyDefaults();
    expect(d.containsKey('beanOrigin'), isFalse);
  });

  test('a later entry overwrites an earlier default', () async {
    await rememberSticky(entry(grinder: 'Niche'));
    await rememberSticky(entry(grinder: 'EK43'));
    expect((await loadStickyDefaults())['grinder'], 'EK43');
  });

  test('an absent field leaves the previous default alone', () async {
    // Not mentioning the grinder today does not mean you sold it.
    await rememberSticky(entry(grinder: 'Niche'));
    await rememberSticky(entry(waterType: 'tap'));
    final d = await loadStickyDefaults();
    expect(d['grinder'], 'Niche');
    expect(d['waterType'], 'tap');
  });

  test('starts empty', () async {
    expect(await loadStickyDefaults(), isEmpty);
  });
}
