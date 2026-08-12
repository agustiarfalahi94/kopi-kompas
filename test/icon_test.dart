import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('every launcher density exists', () {
    for (final density in ['mdpi', 'hdpi', 'xhdpi', 'xxhdpi', 'xxxhdpi']) {
      final f = File(
        'android/app/src/main/res/mipmap-$density/ic_launcher.png',
      );
      expect(f.existsSync(), isTrue, reason: 'missing $density icon');
      expect(f.lengthSync(), greaterThan(0));
    }
  });

  test('every adaptive foreground exists', () {
    for (final density in ['mdpi', 'hdpi', 'xhdpi', 'xxhdpi', 'xxxhdpi']) {
      final f = File(
        'android/app/src/main/res/mipmap-$density/ic_launcher_foreground.png',
      );
      expect(f.existsSync(), isTrue, reason: 'missing $density foreground');
    }
  });

  test('the adaptive icon is configured with the tan background', () {
    final xml = File(
      'android/app/src/main/res/mipmap-anydpi-v26/ic_launcher.xml',
    );
    expect(xml.existsSync(), isTrue);
    final s = xml.readAsStringSync();
    expect(s, contains('<background'));
    expect(s, contains('<foreground'));

    final colors = File(
      'android/app/src/main/res/values/ic_launcher_background.xml',
    );
    expect(colors.existsSync(), isTrue);
    expect(colors.readAsStringSync(), contains('#DDBC8E'));
  });

  test('the master logo is not shipped as an app asset', () {
    // A megabyte of PNG in the APK, for artwork only the build needs.
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final assetLines = pubspec
        .split('\n')
        .where((l) => l.trimLeft().startsWith('- '))
        .join('\n');
    expect(assetLines, isNot(contains('assets/branding')));
  });
}
