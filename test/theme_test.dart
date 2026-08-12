import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kopi_kompas/strings.dart';
import 'package:kopi_kompas/theme.dart';

void main() {
  test('the theme is built from the logo palette', () {
    final light = kopiTheme(Brightness.light);
    expect(light.colorScheme.primary, const Color(0xFF5A3825));
    expect(light.brightness, Brightness.light);

    final dark = kopiTheme(Brightness.dark);
    expect(dark.brightness, Brightness.dark);
  });

  test('the archive style is muted, not just the body style', () {
    // The full log in Phase 3 depends on this being a real, separate ramp.
    expect(
      kopiArchiveColor(Brightness.light),
      isNot(kopiTheme(Brightness.light).colorScheme.onSurface),
    );
  });

  test('strings used by the first screens exist and are not empty', () {
    for (final s in [
      AppStrings.appName,
      AppStrings.newEntryTitle,
      AppStrings.describeHint,
      AppStrings.parseButton,
      AppStrings.emptyLog,
      AppStrings.notScored,
      AppStrings.saveButton,
    ]) {
      expect(s, isNotEmpty);
    }
    expect(AppStrings.appName, 'Kopi Kompas');
  });
}
