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

  test('declares only INTERNET, and removes what libraries add', () {
    // Firebase's dependencies request USE_BIOMETRIC and USE_FINGERPRINT for
    // reauthentication flows this app does not use. They are stripped rather
    // than shipped because a library asked, and this pins that.
    //
    // The merged manifest also ends up with POST_NOTIFICATIONS (the reminder)
    // and ACCESS_NETWORK_STATE and VIBRATE (Firebase and notifications).
    // Those four are the whole list; anything else appearing is a regression
    // worth arguing about rather than absorbing.
    final text = main.readAsStringSync();
    final granted = RegExp(
      r'<uses-permission android:name="android\.permission\.(\w+)"\s*/>',
    ).allMatches(text).map((m) => m.group(1)).toList();
    expect(granted, ['INTERNET']);

    for (final removed in ['USE_BIOMETRIC', 'USE_FINGERPRINT']) {
      expect(
        text,
        contains('android.permission.$removed'),
        reason: '$removed must still be listed, to be removed',
      );
    }
    expect(RegExp('tools:node="remove"').allMatches(text).length, 2);
  });
}
