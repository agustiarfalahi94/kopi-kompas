#!/bin/bash
# The whole validation gate, plus the facts people keep getting wrong.
#
# Run this before every commit and paste the output. It exists because
# "please verify" does not work on an agent that cannot tell reading from
# remembering: a summary can be invented, a pasted run of this cannot.
#
#   ./tool/check.sh
#
# Exits non-zero if anything fails, so it is also usable from CI or a hook.

set -uo pipefail
cd "$(dirname "$0")/.." || exit 1

fail=0
step() { printf '\n\033[1m--- %s ---\033[0m\n' "$1"; }

step "flutter analyze"
flutter analyze 2>&1 | tail -3
flutter analyze >/dev/null 2>&1 || { echo "ANALYZE FAILED"; fail=1; }

step "dart format"
if ! dart format --set-exit-if-changed lib/ test/ 2>&1 | tail -2; then
  echo "FORMAT FAILED — run: dart format lib/ test/"
  fail=1
fi

step "flutter test"
test_out=$(flutter test --reporter compact 2>&1 | tr '\r' '\n' \
  | grep -E "All tests passed|Some tests failed" | tail -1)
echo "${test_out:-no test summary produced}"
case "$test_out" in
  *"All tests passed"*) ;;
  *) echo "TESTS FAILED"; fail=1 ;;
esac

step "worker tests"
if [ -d worker/node_modules ]; then
  worker_out=$( (cd worker && npx vitest run 2>&1) \
    | grep -E "Tests +[0-9]+ (passed|failed)" | tail -1)
  echo "${worker_out:-no worker summary produced}"
  case "$worker_out" in
    *failed*) echo "WORKER TESTS FAILED"; fail=1 ;;
  esac
else
  echo "skipped — run 'cd worker && npm install' first"
fi

# The ground truth, printed rather than remembered. Every one of these has
# been stated wrongly by an assistant working from a directory name or from
# an earlier conversation instead of from the files.
step "facts (read from the files, not from memory)"
printf 'app name        %s\n' \
  "$(grep -m1 '^name:' pubspec.yaml | cut -d' ' -f2-)"
printf 'version         %s\n' \
  "$(grep -m1 '^version:' pubspec.yaml | cut -d' ' -f2-)"
printf 'package id      %s\n' \
  "$(grep -m1 'applicationId' android/app/build.gradle.kts \
     | sed 's/.*"\(.*\)".*/\1/')"
printf 'brew methods    %s\n' \
  "$(python3 -c "import json;print(len(json.load(open('schema/brew_schema.json'))['methods']))")"
printf 'scored methods  %s\n' \
  "$(python3 -c "import json;m=json.load(open('schema/brew_schema.json'))['methods'];print(', '.join(k for k,v in m.items() if v['scored']))")"
if [ -f lib/services/kopi_client.dart ]; then
  printf 'endpoint        %s\n' \
    "$(grep -m1 'kopiEndpointDefault =' lib/services/kopi_client.dart \
       | sed "s/.*'\(.*\)'.*/\1/")"
else
  printf 'endpoint        not written yet\n'
fi
printf 'gemini key      not in the app — it is a Cloudflare Worker secret\n'
printf 'git remote      %s\n' "$(git remote get-url origin 2>/dev/null)"
printf 'branch          %s\n' "$(git branch --show-current 2>/dev/null)"

step "result"
if [ "$fail" -eq 0 ]; then
  echo "PASS — safe to commit"
else
  echo "FAIL — do not commit"
fi
exit "$fail"
