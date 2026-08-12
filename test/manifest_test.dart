import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Guards the release Android manifest.
///
/// Added after a release APK reached the phone with no network: Flutter's
/// template declares INTERNET only in the debug and profile manifests, so
/// every Worker call failed as "no connection" while debug builds worked
/// perfectly. Nothing in the Dart test suite could see it.
void main() {
  final main = File('android/app/src/main/AndroidManifest.xml');

  test('the release manifest grants INTERNET', () {
    expect(
      main.readAsStringSync(),
      contains('android.permission.INTERNET'),
      reason: 'release builds cannot reach the Worker without it',
    );
  });

  test('the launcher label is the app name, not the package name', () {
    expect(main.readAsStringSync(), contains('android:label="Kopi Kompas"'));
  });

  test('no permission beyond INTERNET is requested', () {
    // The app stores everything on device. If this fails, something pulled in
    // a plugin that wants more than it should.
    final permissions = RegExp(
      r'android:name="android\.permission\.(\w+)"',
    ).allMatches(main.readAsStringSync()).map((m) => m.group(1)).toList();
    expect(permissions, ['INTERNET']);
  });
}
