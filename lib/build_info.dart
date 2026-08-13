/// Which build this is, stamped in at compile time.
///
/// Exists because two APKs carrying the same `version:` are otherwise
/// indistinguishable on a phone. Five different builds were handed over in one
/// day, all reporting `0.3.0+4`, all release-signed with the same keystore —
/// there was no honest way to tell which one was installed, and "check whether
/// the cold brew guide has a photo" is not a version check.
///
/// Passed by `tool/build_apk.sh` and by the release workflow. A build made
/// without them says so rather than inventing a number.
library;

const String kAppVersion = String.fromEnvironment(
  'APP_VERSION',
  defaultValue: 'unstamped',
);

/// The short git commit, and `-dirty` when the tree had uncommitted changes.
///
/// The distinguishing fact: `version` tells you which release this claims to
/// be, the commit tells you what is actually in it.
const String kBuildCommit = String.fromEnvironment(
  'BUILD_COMMIT',
  defaultValue: 'unstamped',
);

/// Where the build came from — `github` for a tagged release, `local` for one
/// built on a laptop and copied across.
const String kBuildSource = String.fromEnvironment(
  'BUILD_SOURCE',
  defaultValue: 'local',
);

/// One line, for Settings. `0.3.0+4 · a1b2c3d · local`
String get buildLabel => '$kAppVersion · $kBuildCommit · $kBuildSource';
