import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kopi_kompas/build_info.dart';

void main() {
  test('an unstamped build admits it rather than inventing a version', () {
    // These are compile-time constants with no --dart-define in a test run.
    // The default must never be a plausible-looking version, or a build made
    // the wrong way would claim to be a release.
    expect(kAppVersion, 'unstamped');
    expect(kBuildCommit, 'unstamped');
    expect(buildLabel, contains('unstamped'));
  });

  test('a local build is not labelled as coming from GitHub', () {
    // The whole point: telling apart an APK built here from one downloaded
    // off the Releases page, when both carry the same version number.
    expect(kBuildSource, 'local');
  });

  test('the build script stamps all three values', () {
    final script = File('tool/build_apk.sh').readAsStringSync();
    for (final key in ['APP_VERSION', 'BUILD_COMMIT', 'BUILD_SOURCE']) {
      expect(script, contains('--dart-define=$key'), reason: key);
    }
    // A dirty tree must be visible, or a build with uncommitted changes
    // claims to be the commit it was branched from.
    expect(script, contains('-dirty'));
  });

  test('the release workflow stamps them too, and says github', () {
    final ci = File('.github/workflows/release-apk.yml').readAsStringSync();
    for (final key in ['APP_VERSION', 'BUILD_COMMIT', 'BUILD_SOURCE']) {
      expect(ci, contains('--dart-define=$key'), reason: key);
    }
    expect(ci, contains('BUILD_SOURCE=github'));
  });
}
