#!/usr/bin/env bash
# Build a release APK that can identify itself.
#
# Hand-rolling `flutter build apk` is how five APKs went out in one day all
# claiming to be 0.3.0+4 with different code inside. This stamps the version,
# the commit and where it was built, so Settings can say which one you have.
set -euo pipefail
cd "$(dirname "$0")/.."

version=$(grep -m1 '^version:' pubspec.yaml | awk '{print $2}')
commit=$(git rev-parse --short HEAD)
if ! git diff --quiet || ! git diff --cached --quiet; then
  commit="$commit-dirty"
fi
source_label="${BUILD_SOURCE:-local}"

echo "version $version | commit $commit | source $source_label"

flutter build apk --release "$@" \
  --dart-define=APP_VERSION="$version" \
  --dart-define=BUILD_COMMIT="$commit" \
  --dart-define=BUILD_SOURCE="$source_label"
