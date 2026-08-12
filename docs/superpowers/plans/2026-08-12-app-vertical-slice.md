# Kopi Kompas Phase 2 — App Vertical Slice Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** An installable Android APK where you type a brew in free text, watch it get parsed, fill the gaps, see it scored with confetti, and find it in a list — the whole spine working end to end on the phone.

**Architecture:** A Flutter app talking to the Phase 1 Worker over two HTTP calls, storing entries in SQLite. `schema/brew_schema.json` — the same file the Worker reads — is bundled as an asset and drives the follow-up form, so adding a brew method never means editing a form. Every layer below the widgets is a plain Dart class with injected dependencies, so the database, the clients and the entry-completion logic all test headless on a CI runner.

**Tech Stack:** Flutter 3.41.6 · Dart 3.11.4 · sqflite · sqflite_common_ffi (tests) · shared_preferences · confetti

## Global Constraints

- Package id **`com.inkpebble.kopi_kompas`**, app name **Kopi Kompas**, version **0.1.0+1**.
- Endpoint via `--dart-define=KOPI_ENDPOINT=...`, defaulting to
  `https://kopi-kompas.inkpebble.workers.dev`. **No API key in the app, ever.**
- `schema/brew_schema.json` is the only place brew fields are defined. Never
  restate a field list in Dart.
- Palette from the logo: tan `#DDBC8E`, mid brown `#9A6B4A`, dark brown
  `#5A3825`, bean `#2E1A0F`.
- The master logo `assets/branding/kopi-kompas-logo.png` is **build-time only
  and must never be listed in `pubspec.yaml`** — only generated icon resources
  ship.
- Scored methods are espresso, v60, aeropress. The other five save with
  `scoreStatus = notApplicable` and never call `/score`.
- A failed parse or a failed score **must never lose what the user typed**.
- `./tool/check.sh` must pass before every commit; paste its output.
- Work on branch `feature/app-vertical-slice` off `develop`.
- English only in this slice. Indonesian is Phase 3 — but **every user-facing
  string goes through `AppStrings` from Task 1**, never a bare literal in a
  widget, so Phase 3 is adding a file rather than touching every screen.

## Out of scope for this slice

Entry detail screen · full log · deleted entries · settings · daily reminder ·
Indonesian · CI workflow. All Phase 3. This slice exists to put the spine on
the phone.

---

## File Structure

| File | Responsibility |
|---|---|
| `pubspec.yaml` | Deps, version, the schema asset |
| `lib/main.dart` | App entry, theme, routes |
| `lib/theme.dart` | The logo palette as a `ThemeData` |
| `lib/strings.dart` | `AppStrings` — every user-facing string, one place |
| `lib/data/brew_schema.dart` | Loads and models `brew_schema.json` |
| `lib/models/brew_entry.dart` | `BrewEntry`, `ScoreStatus`, JSON/row mapping |
| `lib/services/brew_database.dart` | sqflite: schema, insert, query |
| `lib/services/kopi_client.dart` | `/parse` and `/score` over `HttpClient` |
| `lib/services/install_id.dart` | The per-install uuid |
| `lib/screens/home_screen.dart` | Reverse-chronological list |
| `lib/screens/new_entry_screen.dart` | The three-stage flow |
| `lib/widgets/follow_up_form.dart` | Schema-driven missing-field form |
| `lib/widgets/score_reveal.dart` | Score, reasons, confetti |
| `tool/check.sh` | The validation gate |
| `tool/generate_icon.dart` | Launcher icons from the master logo |

---

### Task 1: Scaffold, theme, strings and the check gate

**Files:**
- Create: the Flutter project, `lib/theme.dart`, `lib/strings.dart`, `tool/check.sh`
- Modify: `pubspec.yaml`, `android/app/build.gradle.kts`, `lib/main.dart`
- Test: `test/theme_test.dart`

**Interfaces:**
- Produces: `AppStrings` (static getters), `kopiTheme(Brightness)`, and a
  running app showing an empty Home.

- [ ] **Step 1: Create the project in place**

The repository already has `docs/`, `schema/`, `worker/`, `assets/branding/`,
so create the Flutter project into the existing directory:

```bash
cd /Users/lilianyoctoria/Documents/kopi-kompas
flutter create --org com.inkpebble --project-name kopi_kompas \
  --platforms=android,ios --overwrite .
```

`--overwrite` is safe here: `flutter create` only writes files it owns and
will not touch `docs/`, `schema/`, `worker/` or `assets/`. Verify afterwards
with `git status` that nothing under those four directories changed.

- [ ] **Step 2: Set the version, description and dependencies**

In `pubspec.yaml`, set `name: kopi_kompas`, `description: "Kopi Kompas — a
personal coffee-brewing logbook."`, `version: 0.1.0+1`, `publish_to: 'none'`,
and:

```yaml
dependencies:
  flutter:
    sdk: flutter
  sqflite: ^2.4.1
  path: ^1.9.0
  shared_preferences: ^2.3.3
  confetti: ^0.8.0

dev_dependencies:
  flutter_test:
    sdk: flutter
  flutter_lints: ^5.0.0
  sqflite_common_ffi: ^2.3.4

flutter:
  uses-material-design: true
  assets:
    - schema/brew_schema.json
```

**`assets/branding/` is deliberately absent from that list.** The master logo
is build-time input for the icon generator; listing it would ship a megabyte
of PNG inside the APK, which is exactly what happened to Tiny Tapsters.

- [ ] **Step 3: Confirm the package id**

`flutter create --org com.inkpebble --project-name kopi_kompas` produces
`com.inkpebble.kopi_kompas`. Verify in `android/app/build.gradle.kts` that
both `namespace` and `applicationId` read `com.inkpebble.kopi_kompas`, and fix
them if not.

- [ ] **Step 4: Write the failing test**

`test/theme_test.dart`:

```dart
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
    expect(kopiArchiveColor(Brightness.light),
        isNot(kopiTheme(Brightness.light).colorScheme.onSurface));
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
```

- [ ] **Step 5: Run it to verify it fails**

```bash
flutter test test/theme_test.dart
```

Expected: FAIL — `lib/theme.dart` and `lib/strings.dart` do not exist.

- [ ] **Step 6: Write `lib/theme.dart`**

```dart
import 'package:flutter/material.dart';

/// Taken from the logo: beans on a warm tan ground.
const kTan = Color(0xFFDDBC8E);
const kMidBrown = Color(0xFF9A6B4A);
const kDarkBrown = Color(0xFF5A3825);
const kBean = Color(0xFF2E1A0F);

ThemeData kopiTheme(Brightness brightness) {
  final isLight = brightness == Brightness.light;
  final scheme = ColorScheme.fromSeed(
    seedColor: kDarkBrown,
    brightness: brightness,
  ).copyWith(
    primary: isLight ? kDarkBrown : kTan,
    secondary: kMidBrown,
    surface: isLight ? const Color(0xFFFBF3E8) : kBean,
  );

  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
    scaffoldBackgroundColor: scheme.surface,
  );
}

/// The muted ink the Phase 3 full log reads in. Kept here rather than in that
/// screen so the archive treatment is a property of the design, not of one
/// widget that could drift from it.
Color kopiArchiveColor(Brightness brightness) =>
    brightness == Brightness.light
        ? kMidBrown.withValues(alpha: 0.75)
        : kTan.withValues(alpha: 0.55);
```

- [ ] **Step 7: Write `lib/strings.dart`**

```dart
/// Every user-facing string in the app.
///
/// Static getters rather than a map, so a string that does not exist fails to
/// compile instead of rendering as an empty box. Phase 3 turns this into an
/// EN/ID pair; keeping widgets off bare literals now is what makes that a new
/// file rather than an edit to every screen.
class AppStrings {
  const AppStrings._();

  static String get appName => 'Kopi Kompas';
  static String get newEntryTitle => 'What did you brew?';
  static String get describeHint =>
      'e.g. 18g in, 36g out in 28 seconds, wdt and tamp, honduras medium';
  static String get parseButton => 'Continue';
  static String get parsing => 'Reading your brew…';
  static String get scoring => 'Scoring…';
  static String get saveButton => 'Save';
  static String get emptyLog => 'No brews yet. Tap + to log one.';
  static String get notScored => 'Not scored';
  static String get scoreFailed => 'Not scored yet — tap to retry';
  static String get fillGapsTitle => 'A few more things';
  static String get parseFailed =>
      'Could not read that. Your text is safe — retry, or fill it in by hand.';
  static String get retry => 'Retry';
  static String get byHand => 'Fill in by hand';
}
```

- [ ] **Step 8: Write a minimal `lib/main.dart`**

```dart
import 'package:flutter/material.dart';

import 'screens/home_screen.dart';
import 'strings.dart';
import 'theme.dart';

void main() => runApp(const KopiKompasApp());

class KopiKompasApp extends StatelessWidget {
  const KopiKompasApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: AppStrings.appName,
        theme: kopiTheme(Brightness.light),
        darkTheme: kopiTheme(Brightness.dark),
        home: const HomeScreen(),
      );
}
```

And a placeholder `lib/screens/home_screen.dart` that Task 8 replaces:

```dart
import 'package:flutter/material.dart';

import '../strings.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(AppStrings.appName)),
        body: Center(child: Text(AppStrings.emptyLog)),
      );
}
```

- [ ] **Step 9: Write `tool/check.sh`**

```bash
#!/bin/bash
# The whole validation gate, plus the facts people keep getting wrong.
#
# Run this before every commit and paste the output. A summary can be
# invented; a pasted run of this cannot.

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
(cd worker && npx vitest run 2>&1 | grep -E "Tests +[0-9]" | tail -1)

step "facts (read from the files, not from memory)"
printf 'app name        %s\n' "$(grep -m1 '^name:' pubspec.yaml | cut -d' ' -f2-)"
printf 'version         %s\n' "$(grep -m1 '^version:' pubspec.yaml | cut -d' ' -f2-)"
printf 'package id      %s\n' \
  "$(grep -m1 'applicationId' android/app/build.gradle.kts | sed 's/.*"\(.*\)".*/\1/')"
printf 'brew methods    %s\n' \
  "$(python3 -c "import json;print(len(json.load(open('schema/brew_schema.json'))['methods']))")"
printf 'scored methods  %s\n' \
  "$(python3 -c "import json;m=json.load(open('schema/brew_schema.json'))['methods'];print(', '.join(k for k,v in m.items() if v['scored']))")"
printf 'endpoint        %s\n' \
  "$(grep -m1 'kopiEndpointDefault' lib/services/kopi_client.dart 2>/dev/null \
     | sed "s/.*'\(.*\)'.*/\1/" || echo 'not written yet')"
printf 'gemini key      not in the app — it is a Cloudflare Worker secret\n'
printf 'git remote      %s\n' "$(git remote get-url origin 2>/dev/null)"
printf 'branch          %s\n' "$(git branch --show-current 2>/dev/null)"

step "result"
if [ "$fail" -eq 0 ]; then echo "PASS — safe to commit"; else echo "FAIL — do not commit"; fi
exit "$fail"
```

Then `chmod +x tool/check.sh`.

- [ ] **Step 10: Run the tests and the gate**

```bash
flutter test test/theme_test.dart
./tool/check.sh
```

Expected: 3 tests pass; `check.sh` prints `PASS` and shows app name
`kopi_kompas`, version `0.1.0+1`, package id `com.inkpebble.kopi_kompas`,
8 brew methods, 3 scored.

- [ ] **Step 11: Commit**

```bash
git add -A
git commit -m "feat: Flutter scaffold, the logo palette, and the check gate

Strings go through AppStrings from the first screen rather than as bare
literals, because Phase 3 adds Indonesian and the difference between
those two choices is one new file versus an edit to every widget.

The master logo is deliberately not in pubspec.yaml: it is build-time
input for the icon generator, and listing it would ship a megabyte of
PNG in the APK."
```

---

### Task 2: Launcher icon from the logo

**Files:**
- Create: `tool/generate_icon.dart`
- Create: `android/app/src/main/res/mipmap-*/ic_launcher.png`, `android/app/src/main/res/mipmap-anydpi-v26/ic_launcher.xml`, `android/app/src/main/res/values/ic_launcher_background.xml`
- Test: `test/icon_test.dart`

**Interfaces:**
- Consumes: `assets/branding/kopi-kompas-logo.png`.
- Produces: launcher icon resources; no Dart API.

The master is 2000×2000 with the wordmark in the bottom third and a stray
superscript "R". The icon must use **the compass mark only** — the wordmark is
illegible at 48 dp — cropped from the upper portion and padded into the
adaptive-icon safe zone.

- [ ] **Step 1: Write the failing test**

`test/icon_test.dart`:

```dart
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('every launcher density exists and is the right size', () {
    const sizes = {
      'mdpi': 48, 'hdpi': 72, 'xhdpi': 96, 'xxhdpi': 144, 'xxxhdpi': 192,
    };
    sizes.forEach((density, _) {
      final f = File('android/app/src/main/res/mipmap-$density/ic_launcher.png');
      expect(f.existsSync(), isTrue, reason: 'missing $density icon');
      expect(f.lengthSync(), greaterThan(0));
    });
  });

  test('the adaptive icon is configured', () {
    final xml =
        File('android/app/src/main/res/mipmap-anydpi-v26/ic_launcher.xml');
    expect(xml.existsSync(), isTrue);
    final s = xml.readAsStringSync();
    expect(s, contains('<background'));
    expect(s, contains('<foreground'));
  });

  test('the master logo is not shipped as an app asset', () {
    // A megabyte of PNG in the APK, for artwork only the build needs.
    final pubspec = File('pubspec.yaml').readAsStringSync();
    expect(pubspec, isNot(contains('assets/branding')));
  });
}
```

- [ ] **Step 2: Run it to verify it fails**

```bash
flutter test test/icon_test.dart
```

Expected: FAIL — the default Flutter icons exist but the adaptive-icon XML
does not.

- [ ] **Step 3: Write `tool/generate_icon.dart`**

A pure-Dart generator, like Tiny Tapsters' — no Flutter engine, no packages,
so it runs with plain `dart run`. It decodes the master PNG, crops the compass
mark, scales it into the safe zone, and writes each mipmap.

```dart
// Generates launcher icons from assets/branding/kopi-kompas-logo.png.
//
//   dart run tool/generate_icon.dart
//
// The master is build-time only and never ships. Two things it constrains:
// the wordmark occupies the bottom third and is illegible at 48 dp, so only
// the compass mark is used; and the foreground must sit inside the adaptive
// icon safe zone (the centre 66 of 108 units) or the system mask clips a
// point off the star.
import 'dart:io';
import 'dart:typed_data';
import 'dart:convert';
import 'dart:zlib';

// Fraction of the master occupied by the compass mark, measured from the
// artwork: it spans roughly x 0.22-0.78, y 0.17-0.70.
const markLeft = 0.22, markRight = 0.78, markTop = 0.17, markBottom = 0.70;

void main() {
  final master = File('assets/branding/kopi-kompas-logo.png');
  if (!master.existsSync()) {
    stderr.writeln('missing ${master.path}');
    exit(1);
  }
  final image = PngImage.decode(master.readAsBytesSync());
  final mark = image.crop(markLeft, markRight, markTop, markBottom);

  const densities = {
    'mdpi': 48, 'hdpi': 72, 'xhdpi': 96, 'xxhdpi': 144, 'xxxhdpi': 192,
  };
  densities.forEach((density, size) {
    final dir = Directory('android/app/src/main/res/mipmap-$density')
      ..createSync(recursive: true);
    // Legacy icon: the mark on the tan ground, small margin.
    File('${dir.path}/ic_launcher.png')
        .writeAsBytesSync(mark.fitInto(size, 0.90, background: tan).encode());
    // Adaptive foreground: 108dp canvas, mark inside the 66dp safe zone.
    File('${dir.path}/ic_launcher_foreground.png').writeAsBytesSync(
        mark.fitInto((size * 108 / 48).round(), 66 / 108,
            background: transparent).encode());
  });

  Directory('android/app/src/main/res/mipmap-anydpi-v26')
      .createSync(recursive: true);
  File('android/app/src/main/res/mipmap-anydpi-v26/ic_launcher.xml')
      .writeAsStringSync('''
<?xml version="1.0" encoding="utf-8"?>
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
    <background android:drawable="@color/ic_launcher_background"/>
    <foreground android:drawable="@mipmap/ic_launcher_foreground"/>
</adaptive-icon>
''');

  Directory('android/app/src/main/res/values').createSync(recursive: true);
  File('android/app/src/main/res/values/ic_launcher_background.xml')
      .writeAsStringSync('''
<?xml version="1.0" encoding="utf-8"?>
<resources>
    <color name="ic_launcher_background">#DDBC8E</color>
</resources>
''');

  stdout.writeln('icons written');
}
```

The implementer writes `PngImage` (decode, `crop`, `fitInto`, `encode`) using
`dart:zlib` for the IDAT stream — Tiny Tapsters' `tool/generate_icon.dart` is
a working reference for the PNG codec; read it rather than reinventing the
filters. If that proves slow going, an acceptable alternative is adding
`image: ^4.3.0` to `dev_dependencies` and using it in the tool only — it is a
dev dependency, so it does not ship.

- [ ] **Step 4: Generate and verify**

```bash
dart run tool/generate_icon.dart
flutter test test/icon_test.dart
```

Expected: all three tests pass.

- [ ] **Step 5: Commit**

```bash
./tool/check.sh
git add -A
git commit -m "feat: launcher icons from the compass mark

Only the mark, never the wordmark: 'Kopi Kompas' is illegible at 48 dp.
The foreground sits inside the adaptive safe zone so the system mask
cannot clip a point off the star, and the tan becomes the background
layer. A test asserts the master never enters pubspec.yaml."
```

---

### Task 3: The brew schema loader

**Files:**
- Create: `lib/data/brew_schema.dart`
- Test: `test/brew_schema_test.dart`

**Interfaces:**
- Consumes: `schema/brew_schema.json` as a bundled asset.
- Produces:
  - `enum FieldType { number, integer, string, boolean, enumerated }`
  - `class FieldSpec { final String name; final FieldType type; final String? unit; final List<String> values; final bool required; final String label; }`
  - `class MethodSpec { final String id; final bool scored; final String label; final List<FieldSpec> fields; }`
  - `class BrewSchema { List<FieldSpec> get core; List<String> get methodIds; MethodSpec method(String id); List<String> get scoredMethodIds; static Future<BrewSchema> load(); static BrewSchema parse(String json); }`

Field order matters and must follow the JSON, because the follow-up form and
the detail view both render in that order.

- [ ] **Step 1: Write the failing test**

`test/brew_schema_test.dart`:

```dart
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:kopi_kompas/data/brew_schema.dart';

void main() {
  late BrewSchema schema;

  setUpAll(() {
    schema = BrewSchema.parse(
        File('schema/brew_schema.json').readAsStringSync());
  });

  test('loads all eight methods in file order', () {
    expect(schema.methodIds, [
      'espresso', 'v60', 'aeropress', 'frenchPress',
      'kopiTubruk', 'kopiJoss', 'kopiTalua', 'kopiKhop',
    ]);
  });

  test('knows which three are scored', () {
    expect(schema.scoredMethodIds, ['espresso', 'v60', 'aeropress']);
  });

  test('maps field types, units and labels', () {
    final espresso = schema.method('espresso');
    final yield_ = espresso.fields.firstWhere((f) => f.name == 'yieldGrams');
    expect(yield_.type, FieldType.number);
    expect(yield_.unit, 'g');
    expect(yield_.required, isTrue);
    expect(yield_.label, 'Yield');

    final wdt = espresso.fields.firstWhere((f) => f.name == 'puckPrepWdt');
    expect(wdt.type, FieldType.boolean);
  });

  test('maps integer separately from number, for the keyboard', () {
    final pours =
        schema.method('v60').fields.firstWhere((f) => f.name == 'pourCount');
    expect(pours.type, FieldType.integer);
  });

  test('carries enum values for roast level', () {
    final roast = schema.core.firstWhere((f) => f.name == 'roastLevel');
    expect(roast.type, FieldType.enumerated);
    expect(roast.values, ['light', 'medium', 'medium-dark', 'dark']);
  });

  test('preserves field order, which the form renders in', () {
    expect(schema.method('espresso').fields.first.name, 'yieldGrams');
    expect(schema.method('espresso').fields.last.name, 'waterTempC');
  });

  test('an unknown method id throws rather than returning empty', () {
    expect(() => schema.method('pourover'), throwsArgumentError);
  });
}
```

- [ ] **Step 2: Run it to verify it fails**

```bash
flutter test test/brew_schema_test.dart
```

Expected: FAIL — `lib/data/brew_schema.dart` does not exist.

- [ ] **Step 3: Write `lib/data/brew_schema.dart`**

```dart
import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

enum FieldType { number, integer, string, boolean, enumerated }

FieldType _fieldType(String raw) => switch (raw) {
      'number' => FieldType.number,
      'integer' => FieldType.integer,
      'boolean' => FieldType.boolean,
      'enum' => FieldType.enumerated,
      'string' => FieldType.string,
      _ => throw ArgumentError('unknown field type: $raw'),
    };

class FieldSpec {
  const FieldSpec({
    required this.name,
    required this.type,
    required this.required,
    required this.label,
    this.unit,
    this.values = const [],
  });

  final String name;
  final FieldType type;
  final String? unit;
  final List<String> values;
  final bool required;
  final String label;

  factory FieldSpec.fromJson(String name, Map<String, dynamic> j) => FieldSpec(
        name: name,
        type: _fieldType(j['type'] as String),
        unit: j['unit'] as String?,
        values: ((j['values'] as List?) ?? const []).cast<String>(),
        required: j['required'] as bool,
        // Phase 3 switches this to the locale's label.
        label: (j['label'] as Map<String, dynamic>)['en'] as String,
      );
}

class MethodSpec {
  const MethodSpec({
    required this.id,
    required this.scored,
    required this.label,
    required this.fields,
  });

  final String id;
  final bool scored;
  final String label;
  final List<FieldSpec> fields;
}

/// The eight brew methods and their fields, read from the same
/// `schema/brew_schema.json` the Worker uses. Nothing else in the app may
/// restate a field list.
class BrewSchema {
  BrewSchema._(this._core, this._methods);

  final List<FieldSpec> _core;
  final Map<String, MethodSpec> _methods;

  List<FieldSpec> get core => List.unmodifiable(_core);
  List<String> get methodIds => List.unmodifiable(_methods.keys);
  List<String> get scoredMethodIds =>
      _methods.values.where((m) => m.scored).map((m) => m.id).toList();

  MethodSpec method(String id) {
    final m = _methods[id];
    if (m == null) throw ArgumentError('unknown brew method: $id');
    return m;
  }

  bool isScored(String id) => method(id).scored;

  static Future<BrewSchema> load() async =>
      parse(await rootBundle.loadString('schema/brew_schema.json'));

  static BrewSchema parse(String source) {
    final root = jsonDecode(source) as Map<String, dynamic>;

    final core = <FieldSpec>[];
    (root['core'] as Map<String, dynamic>).forEach((name, spec) {
      core.add(FieldSpec.fromJson(name, spec as Map<String, dynamic>));
    });

    final methods = <String, MethodSpec>{};
    (root['methods'] as Map<String, dynamic>).forEach((id, raw) {
      final m = raw as Map<String, dynamic>;
      final fields = <FieldSpec>[];
      (m['fields'] as Map<String, dynamic>).forEach((name, spec) {
        fields.add(FieldSpec.fromJson(name, spec as Map<String, dynamic>));
      });
      methods[id] = MethodSpec(
        id: id,
        scored: m['scored'] as bool,
        label: (m['label'] as Map<String, dynamic>)['en'] as String,
        fields: fields,
      );
    });

    return BrewSchema._(core, methods);
  }
}
```

Dart preserves insertion order in `Map` literals decoded from JSON, which is
what keeps field order aligned with the file.

- [ ] **Step 4: Run it to verify it passes**

```bash
flutter test test/brew_schema_test.dart
```

Expected: 7 passing.

- [ ] **Step 5: Commit**

```bash
./tool/check.sh
git add lib/data/brew_schema.dart test/brew_schema_test.dart
git commit -m "feat: read the shared brew schema in the app

The same schema/brew_schema.json the Worker uses, bundled as an asset.
Field order is preserved because the follow-up form and the detail view
both render in it, and an unknown method id throws rather than quietly
returning an empty field list."
```

---

### Task 4: The BrewEntry model

**Files:**
- Create: `lib/models/brew_entry.dart`
- Test: `test/brew_entry_test.dart`

**Interfaces:**
- Produces:
  - `enum ScoreStatus { scored, notApplicable, pending, failed }`
  - `class BrewEntry` with fields `id, brewMethod, beanOrigin, roastLevel, doseGrams, grindSize, brewDate, notes, rawInputText, methodData (Map<String,Object?>), overallScore, scoreReasons (List<String>), scoreStatus, scoreRubric, scoreModel, scoredAt, createdAt, updatedAt, deletedAt`
  - `Map<String, Object?> toRow()`, `factory BrewEntry.fromRow(Map<String, Object?>)`, `BrewEntry copyWith({...})`
  - `String newUuid()`

- [ ] **Step 1: Write the failing test**

`test/brew_entry_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:kopi_kompas/models/brew_entry.dart';

BrewEntry sample() => BrewEntry(
      id: 'abc',
      brewMethod: 'espresso',
      beanOrigin: 'Honduras',
      roastLevel: 'medium',
      doseGrams: 18,
      grindSize: null,
      brewDate: DateTime.parse('2026-08-12T07:30:00+07:00'),
      notes: 'syrupy',
      rawInputText: '18g in 36g out',
      methodData: const {'yieldGrams': 36, 'puckPrepWdt': false},
      overallScore: 82,
      scoreReasons: const ['Ratio on target'],
      scoreStatus: ScoreStatus.scored,
      scoreRubric: 'r1',
      scoreModel: 'gemini-3.5-flash',
      scoredAt: DateTime.parse('2026-08-12T07:31:00+07:00'),
      createdAt: DateTime.parse('2026-08-12T07:31:00+07:00'),
      updatedAt: DateTime.parse('2026-08-12T07:31:00+07:00'),
    );

void main() {
  test('survives a round trip through a database row', () {
    final entry = sample();
    final back = BrewEntry.fromRow(entry.toRow());
    expect(back.id, entry.id);
    expect(back.brewMethod, 'espresso');
    expect(back.doseGrams, 18);
    expect(back.methodData['yieldGrams'], 36);
    expect(back.scoreReasons, ['Ratio on target']);
    expect(back.scoreStatus, ScoreStatus.scored);
    expect(back.scoreRubric, 'r1');
    expect(back.deletedAt, isNull);
  });

  test('keeps a false methodData value distinct from a missing one', () {
    final back = BrewEntry.fromRow(sample().toRow());
    expect(back.methodData['puckPrepWdt'], false);
    expect(back.methodData.containsKey('puckPrepTamp'), isFalse);
  });

  test('preserves the local offset in brewDate', () {
    // A shot pulled at 00:30 belongs to the day the brewer was awake for,
    // so the offset has to survive storage.
    final entry = sample().copyWith(
        brewDate: DateTime.parse('2026-08-12T00:30:00+07:00'));
    final row = entry.toRow();
    expect(row['brewDate'], contains('+07:00'));
    expect(BrewEntry.fromRow(row).brewDate.hour, 0);
  });

  test('an unscored method stores no score', () {
    final entry = sample().copyWith(
      brewMethod: 'kopiJoss',
      scoreStatus: ScoreStatus.notApplicable,
      overallScore: null,
      scoreReasons: const [],
    );
    final back = BrewEntry.fromRow(entry.toRow());
    expect(back.overallScore, isNull);
    expect(back.scoreStatus, ScoreStatus.notApplicable);
  });

  test('newUuid produces distinct v4-shaped ids', () {
    final a = newUuid(), b = newUuid();
    expect(a, isNot(b));
    expect(a.length, 36);
    expect(a[14], '4');
  });
}
```

- [ ] **Step 2: Run it to verify it fails**

```bash
flutter test test/brew_entry_test.dart
```

Expected: FAIL — `lib/models/brew_entry.dart` does not exist.

- [ ] **Step 3: Write `lib/models/brew_entry.dart`**

```dart
import 'dart:convert';
import 'dart:math';

enum ScoreStatus { scored, notApplicable, pending, failed }

ScoreStatus _statusFrom(String raw) => ScoreStatus.values.firstWhere(
      (s) => s.name == raw,
      orElse: () => ScoreStatus.failed,
    );

/// A v4 uuid from `Random.secure`, so no package is needed for the one place
/// the app generates ids.
String newUuid() {
  final r = Random.secure();
  final b = List<int>.generate(16, (_) => r.nextInt(256));
  b[6] = (b[6] & 0x0f) | 0x40;
  b[8] = (b[8] & 0x3f) | 0x80;
  final h = b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
  return '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}'
      '-${h.substring(16, 20)}-${h.substring(20)}';
}

class BrewEntry {
  const BrewEntry({
    required this.id,
    required this.brewMethod,
    required this.brewDate,
    required this.rawInputText,
    required this.methodData,
    required this.scoreStatus,
    required this.createdAt,
    required this.updatedAt,
    this.beanOrigin,
    this.roastLevel,
    this.doseGrams,
    this.grindSize,
    this.notes,
    this.overallScore,
    this.scoreReasons = const [],
    this.scoreRubric,
    this.scoreModel,
    this.scoredAt,
    this.deletedAt,
  });

  final String id;
  final String brewMethod;
  final String? beanOrigin;
  final String? roastLevel;
  final double? doseGrams;
  final String? grindSize;
  final DateTime brewDate;
  final String? notes;
  final String rawInputText;
  final Map<String, Object?> methodData;
  final int? overallScore;
  final List<String> scoreReasons;
  final ScoreStatus scoreStatus;
  final String? scoreRubric;
  final String? scoreModel;
  final DateTime? scoredAt;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;

  Map<String, Object?> toRow() => {
        'id': id,
        'brewMethod': brewMethod,
        'beanOrigin': beanOrigin,
        'roastLevel': roastLevel,
        'doseGrams': doseGrams,
        'grindSize': grindSize,
        // toIso8601String() on a DateTime parsed with an offset keeps that
        // offset only if the value is not converted to UTC first. Never call
        // .toUtc() here — see the brewDate note in the design.
        'brewDate': brewDate.toIso8601String(),
        'notes': notes,
        'rawInputText': rawInputText,
        'methodData': jsonEncode(methodData),
        'overallScore': overallScore,
        'scoreReasons': jsonEncode(scoreReasons),
        'scoreStatus': scoreStatus.name,
        'scoreRubric': scoreRubric,
        'scoreModel': scoreModel,
        'scoredAt': scoredAt?.toIso8601String(),
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
        'deletedAt': deletedAt?.toIso8601String(),
      };

  factory BrewEntry.fromRow(Map<String, Object?> row) => BrewEntry(
        id: row['id'] as String,
        brewMethod: row['brewMethod'] as String,
        beanOrigin: row['beanOrigin'] as String?,
        roastLevel: row['roastLevel'] as String?,
        doseGrams: (row['doseGrams'] as num?)?.toDouble(),
        grindSize: row['grindSize'] as String?,
        brewDate: DateTime.parse(row['brewDate'] as String),
        notes: row['notes'] as String?,
        rawInputText: row['rawInputText'] as String,
        methodData: (jsonDecode(row['methodData'] as String? ?? '{}')
                as Map<String, dynamic>)
            .cast<String, Object?>(),
        overallScore: (row['overallScore'] as num?)?.toInt(),
        scoreReasons:
            (jsonDecode(row['scoreReasons'] as String? ?? '[]') as List)
                .cast<String>(),
        scoreStatus: _statusFrom(row['scoreStatus'] as String),
        scoreRubric: row['scoreRubric'] as String?,
        scoreModel: row['scoreModel'] as String?,
        scoredAt: _date(row['scoredAt']),
        createdAt: DateTime.parse(row['createdAt'] as String),
        updatedAt: DateTime.parse(row['updatedAt'] as String),
        deletedAt: _date(row['deletedAt']),
      );

  static DateTime? _date(Object? v) =>
      v == null ? null : DateTime.parse(v as String);

  BrewEntry copyWith({
    String? brewMethod,
    String? beanOrigin,
    String? roastLevel,
    double? doseGrams,
    String? grindSize,
    DateTime? brewDate,
    String? notes,
    Map<String, Object?>? methodData,
    int? overallScore,
    List<String>? scoreReasons,
    ScoreStatus? scoreStatus,
    String? scoreRubric,
    String? scoreModel,
    DateTime? scoredAt,
    DateTime? updatedAt,
    DateTime? deletedAt,
  }) =>
      BrewEntry(
        id: id,
        brewMethod: brewMethod ?? this.brewMethod,
        beanOrigin: beanOrigin ?? this.beanOrigin,
        roastLevel: roastLevel ?? this.roastLevel,
        doseGrams: doseGrams ?? this.doseGrams,
        grindSize: grindSize ?? this.grindSize,
        brewDate: brewDate ?? this.brewDate,
        notes: notes ?? this.notes,
        rawInputText: rawInputText,
        methodData: methodData ?? this.methodData,
        overallScore: overallScore,
        scoreReasons: scoreReasons ?? this.scoreReasons,
        scoreStatus: scoreStatus ?? this.scoreStatus,
        scoreRubric: scoreRubric ?? this.scoreRubric,
        scoreModel: scoreModel ?? this.scoreModel,
        scoredAt: scoredAt ?? this.scoredAt,
        createdAt: createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
        deletedAt: deletedAt ?? this.deletedAt,
      );
}
```

Note `overallScore` in `copyWith` is deliberately *not* `?? this.overallScore`
— clearing a score when a re-score fails must be expressible.

- [ ] **Step 4: Run it to verify it passes**

```bash
flutter test test/brew_entry_test.dart
```

Expected: 5 passing.

- [ ] **Step 5: Commit**

```bash
./tool/check.sh
git add lib/models/brew_entry.dart test/brew_entry_test.dart
git commit -m "feat: the BrewEntry model and its row mapping

brewDate keeps its local offset through storage, because a shot pulled
at 00:30 belongs to the day the brewer was awake for. copyWith clears
overallScore rather than defaulting it, so a failed re-score can drop a
stale number."
```

---

### Task 5: The database

**Files:**
- Create: `lib/services/brew_database.dart`
- Test: `test/brew_database_test.dart`

**Interfaces:**
- Consumes: `BrewEntry`, `ScoreStatus` (Task 4).
- Produces: `class BrewDatabase` with `static Future<BrewDatabase> open({String? path})`, `Future<void> insert(BrewEntry)`, `Future<void> update(BrewEntry)`, `Future<List<BrewEntry>> liveEntries()`, `Future<BrewEntry?> byId(String)`, `Future<bool> hasBrewOn(DateTime day)`, `Future<void> softDelete(String id, DateTime when)`, `Future<void> close()`.

- [ ] **Step 1: Write the failing test**

`test/brew_database_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:kopi_kompas/models/brew_entry.dart';
import 'package:kopi_kompas/services/brew_database.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

BrewEntry entry(String id, DateTime when, {ScoreStatus? status}) => BrewEntry(
      id: id,
      brewMethod: 'espresso',
      brewDate: when,
      rawInputText: 'raw $id',
      methodData: const {'yieldGrams': 36},
      scoreStatus: status ?? ScoreStatus.scored,
      overallScore: 80,
      createdAt: when,
      updatedAt: when,
    );

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late BrewDatabase db;
  setUp(() async => db = await BrewDatabase.open(path: inMemoryDatabasePath));
  tearDown(() async => db.close());

  test('stores and reads an entry back', () async {
    await db.insert(entry('a', DateTime.parse('2026-08-12T07:00:00+07:00')));
    final all = await db.liveEntries();
    expect(all.single.id, 'a');
    expect(all.single.methodData['yieldGrams'], 36);
  });

  test('lists newest first', () async {
    await db.insert(entry('old', DateTime.parse('2026-08-10T07:00:00+07:00')));
    await db.insert(entry('new', DateTime.parse('2026-08-12T07:00:00+07:00')));
    expect((await db.liveEntries()).map((e) => e.id), ['new', 'old']);
  });

  test('a soft-deleted entry leaves the live list but stays in the table',
      () async {
    await db.insert(entry('a', DateTime.parse('2026-08-12T07:00:00+07:00')));
    await db.softDelete('a', DateTime.parse('2026-08-12T08:00:00+07:00'));
    expect(await db.liveEntries(), isEmpty);
    expect((await db.byId('a'))!.deletedAt, isNotNull);
  });

  test('hasBrewOn is true only for a day with a live entry', () async {
    await db.insert(entry('a', DateTime.parse('2026-08-12T07:00:00+07:00')));
    expect(await db.hasBrewOn(DateTime.parse('2026-08-12T23:00:00+07:00')),
        isTrue);
    expect(await db.hasBrewOn(DateTime.parse('2026-08-11T07:00:00+07:00')),
        isFalse);
  });

  test('a shot after midnight counts for that new day, not the day before',
      () async {
    // The reason brewDate keeps its offset instead of being stored as UTC.
    await db.insert(entry('a', DateTime.parse('2026-08-12T00:30:00+07:00')));
    expect(await db.hasBrewOn(DateTime.parse('2026-08-12T09:00:00+07:00')),
        isTrue);
    expect(await db.hasBrewOn(DateTime.parse('2026-08-11T09:00:00+07:00')),
        isFalse);
  });

  test('a deleted entry stops counting for hasBrewOn', () async {
    final when = DateTime.parse('2026-08-12T07:00:00+07:00');
    await db.insert(entry('a', when));
    await db.softDelete('a', when);
    expect(await db.hasBrewOn(when), isFalse);
  });

  test('update replaces the row and can clear a score', () async {
    final when = DateTime.parse('2026-08-12T07:00:00+07:00');
    await db.insert(entry('a', when));
    await db.update((await db.byId('a'))!
        .copyWith(scoreStatus: ScoreStatus.failed, overallScore: null));
    final back = (await db.byId('a'))!;
    expect(back.scoreStatus, ScoreStatus.failed);
    expect(back.overallScore, isNull);
  });
}
```

- [ ] **Step 2: Run it to verify it fails**

```bash
flutter test test/brew_database_test.dart
```

Expected: FAIL — `lib/services/brew_database.dart` does not exist.

- [ ] **Step 3: Write `lib/services/brew_database.dart`**

```dart
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../models/brew_entry.dart';

/// Every brew, live and deleted. Core fields are columns because they are
/// what the app filters and sorts by; method-specific fields are a JSON blob
/// because eight methods would otherwise make a sixty-column sparse table.
class BrewDatabase {
  BrewDatabase._(this._db);

  final Database _db;

  static const _createSql = '''
    CREATE TABLE brews (
      id            TEXT PRIMARY KEY,
      brewMethod    TEXT NOT NULL,
      beanOrigin    TEXT,
      roastLevel    TEXT,
      doseGrams     REAL,
      grindSize     TEXT,
      brewDate      TEXT NOT NULL,
      notes         TEXT,
      rawInputText  TEXT NOT NULL,
      methodData    TEXT NOT NULL,
      overallScore  INTEGER,
      scoreReasons  TEXT,
      scoreStatus   TEXT NOT NULL,
      scoreRubric   TEXT,
      scoreModel    TEXT,
      scoredAt      TEXT,
      createdAt     TEXT NOT NULL,
      updatedAt     TEXT NOT NULL,
      deletedAt     TEXT
    )
  ''';

  static Future<BrewDatabase> open({String? path}) async {
    final dbPath = path ?? p.join(await getDatabasesPath(), 'kopi_kompas.db');
    final db = await openDatabase(
      dbPath,
      version: 1,
      onCreate: (db, _) async {
        await db.execute(_createSql);
        await db.execute('CREATE INDEX idx_brewDate ON brews(brewDate)');
        await db.execute('CREATE INDEX idx_deletedAt ON brews(deletedAt)');
      },
    );
    return BrewDatabase._(db);
  }

  Future<void> insert(BrewEntry e) async => _db.insert('brews', e.toRow());

  Future<void> update(BrewEntry e) async =>
      _db.update('brews', e.toRow(), where: 'id = ?', whereArgs: [e.id]);

  Future<List<BrewEntry>> liveEntries() async {
    final rows = await _db.query('brews',
        where: 'deletedAt IS NULL', orderBy: 'brewDate DESC');
    return rows.map(BrewEntry.fromRow).toList();
  }

  Future<BrewEntry?> byId(String id) async {
    final rows = await _db.query('brews', where: 'id = ?', whereArgs: [id]);
    return rows.isEmpty ? null : BrewEntry.fromRow(rows.first);
  }

  Future<void> softDelete(String id, DateTime when) async => _db.update(
        'brews',
        {'deletedAt': when.toIso8601String()},
        where: 'id = ?',
        whereArgs: [id],
      );

  /// Whether a live brew exists on [day]'s local calendar date.
  ///
  /// Compared on the local date string rather than an instant range, because
  /// "did I log a coffee today" is a question about the wall clock in front of
  /// the brewer. Stored dates keep their offset, so their first ten
  /// characters are already the local date.
  Future<bool> hasBrewOn(DateTime day) async {
    final key = day.toIso8601String().substring(0, 10);
    final rows = await _db.query(
      'brews',
      columns: ['id'],
      where: "deletedAt IS NULL AND substr(brewDate, 1, 10) = ?",
      whereArgs: [key],
      limit: 1,
    );
    return rows.isNotEmpty;
  }

  Future<void> close() => _db.close();
}
```

- [ ] **Step 4: Run it to verify it passes**

```bash
flutter test test/brew_database_test.dart
```

Expected: 7 passing.

- [ ] **Step 5: Commit**

```bash
./tool/check.sh
git add lib/services/brew_database.dart test/brew_database_test.dart
git commit -m "feat: the brews table

hasBrewOn compares local date strings rather than an instant range,
which is what makes a 00:30 shot count for the day the brewer was awake
for. Deleting is soft: the row survives with deletedAt set, leaves the
live list, and stops counting for the reminder Phase 3 adds."
```

---

### Task 6: The Worker client

**Files:**
- Create: `lib/services/kopi_client.dart`, `lib/services/install_id.dart`
- Test: `test/kopi_client_test.dart`

**Interfaces:**
- Produces:
  - `const kopiEndpointDefault = 'https://kopi-kompas.inkpebble.workers.dev';`
  - `sealed class ParseResult` → `ParseOk(Map<String,Object?> core, String brewMethod, Map<String,Object?> methodData)` · `ParseFailed(KopiError kind, String detail)`
  - `sealed class ScoreResult` → `ScoreOk(int score, List<String> reasons, String rubric, String model)` · `ScoreFailed(KopiError kind, String detail)`
  - `enum KopiError { network, rateLimited, notScored, badRequest, upstream }`
  - `class KopiClient { KopiClient({String? endpoint, HttpClient? http, required String installId}); Future<ParseResult> parse(String text, {String locale}); Future<ScoreResult> score(BrewEntry entry, {String locale}); }`

Tests run against a **real local `HttpServer`**, not a mock, so the JSON
encoding, headers and status handling are all genuinely exercised.

- [ ] **Step 1: Write the failing test**

`test/kopi_client_test.dart`:

```dart
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kopi_kompas/models/brew_entry.dart';
import 'package:kopi_kompas/services/kopi_client.dart';

late HttpServer server;
late List<Map<String, dynamic>> received;
late int status;
late Object body;

Future<void> startServer() async {
  received = [];
  status = 200;
  body = {};
  server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  server.listen((req) async {
    received.add({
      'path': req.uri.path,
      'body': jsonDecode(await utf8.decoder.bind(req).join()),
    });
    req.response.statusCode = status;
    req.response.headers.contentType = ContentType.json;
    req.response.write(jsonEncode(body));
    await req.response.close();
  });
}

KopiClient client() => KopiClient(
      endpoint: 'http://${server.address.host}:${server.port}',
      installId: 'install-test',
    );

BrewEntry espresso() => BrewEntry(
      id: 'a',
      brewMethod: 'espresso',
      brewDate: DateTime.now(),
      rawInputText: 'x',
      methodData: const {'yieldGrams': 36},
      scoreStatus: ScoreStatus.pending,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );

void main() {
  setUp(startServer);
  tearDown(() => server.close(force: true));

  test('parse sends text, locale and installId', () async {
    body = {'brewMethod': 'espresso', 'methodData': {}};
    await client().parse('18g in 36g out');
    expect(received.single['path'], '/parse');
    expect(received.single['body']['text'], '18g in 36g out');
    expect(received.single['body']['locale'], 'en');
    expect(received.single['body']['installId'], 'install-test');
  });

  test('parse returns the method and its data', () async {
    body = {
      'brewMethod': 'espresso',
      'doseGrams': 18,
      'methodData': {'yieldGrams': 36, 'puckPrepWdt': false},
    };
    final r = await client().parse('x') as ParseOk;
    expect(r.brewMethod, 'espresso');
    expect(r.core['doseGrams'], 18);
    expect(r.methodData['yieldGrams'], 36);
    expect(r.methodData['puckPrepWdt'], false);
  });

  test('parse maps 429 to rateLimited', () async {
    status = 429;
    body = {'error': 'daily limit reached'};
    final r = await client().parse('x') as ParseFailed;
    expect(r.kind, KopiError.rateLimited);
  });

  test('parse maps 502 to upstream', () async {
    status = 502;
    body = {'error': 'gemini unreachable'};
    expect((await client().parse('x') as ParseFailed).kind,
        KopiError.upstream);
  });

  test('parse maps an unreachable server to network', () async {
    await server.close(force: true);
    expect((await client().parse('x') as ParseFailed).kind,
        KopiError.network);
  });

  test('parse maps a non-JSON body to upstream', () async {
    body = 'not json at all';
    status = 200;
    final r = await client().parse('x');
    expect(r, isA<ParseFailed>());
  });

  test('score returns the number, reasons, rubric and model', () async {
    body = {
      'score': 88,
      'reasons': ['Ratio on target'],
      'rubric': 'r1',
      'model': 'gemini-3.5-flash',
    };
    final r = await client().score(espresso()) as ScoreOk;
    expect(r.score, 88);
    expect(r.reasons, ['Ratio on target']);
    expect(r.rubric, 'r1');
    expect(r.model, 'gemini-3.5-flash');
  });

  test('score posts the whole entry, including methodData', () async {
    body = {'score': 1, 'reasons': [], 'rubric': 'r1', 'model': 'm'};
    await client().score(espresso());
    final sent = received.single['body']['entry'];
    expect(sent['brewMethod'], 'espresso');
    expect(sent['methodData']['yieldGrams'], 36);
  });

  test('score maps 422 to notScored', () async {
    status = 422;
    body = {'error': 'kopiJoss is not scored'};
    expect((await client().score(espresso()) as ScoreFailed).kind,
        KopiError.notScored);
  });

  test('score rejects a number outside 0-100 rather than trusting it',
      () async {
    body = {'score': 140, 'reasons': [], 'rubric': 'r1', 'model': 'm'};
    expect(await client().score(espresso()), isA<ScoreFailed>());
  });
}
```

- [ ] **Step 2: Run it to verify it fails**

```bash
flutter test test/kopi_client_test.dart
```

Expected: FAIL — `lib/services/kopi_client.dart` does not exist.

- [ ] **Step 3: Write `lib/services/install_id.dart`**

```dart
import 'package:shared_preferences/shared_preferences.dart';

import '../models/brew_entry.dart' show newUuid;

/// A random id for this installation, used only to rate-limit the Worker.
/// It means nothing off-device and identifies no person.
Future<String> loadInstallId() async {
  final prefs = await SharedPreferences.getInstance();
  final existing = prefs.getString('installId');
  if (existing != null) return existing;
  final fresh = newUuid();
  await prefs.setString('installId', fresh);
  return fresh;
}
```

- [ ] **Step 4: Write `lib/services/kopi_client.dart`**

```dart
import 'dart:convert';
import 'dart:io';

import '../models/brew_entry.dart';

const kopiEndpointDefault = 'https://kopi-kompas.inkpebble.workers.dev';

/// The endpoint is a build-time constant, overridable for a staging Worker.
/// It is a URL, not a secret — the Gemini key never leaves Cloudflare.
const _endpointFromEnv = String.fromEnvironment(
  'KOPI_ENDPOINT',
  defaultValue: kopiEndpointDefault,
);

enum KopiError { network, rateLimited, notScored, badRequest, upstream }

sealed class ParseResult {
  const ParseResult();
}

class ParseOk extends ParseResult {
  const ParseOk(this.brewMethod, this.core, this.methodData);
  final String brewMethod;
  final Map<String, Object?> core;
  final Map<String, Object?> methodData;
}

class ParseFailed extends ParseResult {
  const ParseFailed(this.kind, this.detail);
  final KopiError kind;
  final String detail;
}

sealed class ScoreResult {
  const ScoreResult();
}

class ScoreOk extends ScoreResult {
  const ScoreOk(this.score, this.reasons, this.rubric, this.model);
  final int score;
  final List<String> reasons;
  final String rubric;
  final String model;
}

class ScoreFailed extends ScoreResult {
  const ScoreFailed(this.kind, this.detail);
  final KopiError kind;
  final String detail;
}

class KopiClient {
  KopiClient({String? endpoint, HttpClient? http, required this.installId})
      : _endpoint = endpoint ?? _endpointFromEnv,
        _http = http ?? HttpClient();

  final String _endpoint;
  final HttpClient _http;
  final String installId;

  static const _timeout = Duration(seconds: 45);

  Future<ParseResult> parse(String text, {String locale = 'en'}) async {
    final r = await _post('/parse', {
      'text': text,
      'locale': locale,
      'installId': installId,
    });
    return switch (r) {
      _Err(:final kind, :final detail) => ParseFailed(kind, detail),
      _Ok(:final body) => _toParseOk(body),
    };
  }

  ParseResult _toParseOk(Map<String, Object?> body) {
    final method = body['brewMethod'];
    if (method is! String) {
      return const ParseFailed(KopiError.upstream, 'no brewMethod');
    }
    final core = <String, Object?>{};
    for (final e in body.entries) {
      if (e.key != 'brewMethod' && e.key != 'methodData') core[e.key] = e.value;
    }
    final md = body['methodData'];
    return ParseOk(
      method,
      core,
      md is Map ? md.cast<String, Object?>() : const {},
    );
  }

  Future<ScoreResult> score(BrewEntry entry, {String locale = 'en'}) async {
    final r = await _post('/score', {
      'entry': {
        'brewMethod': entry.brewMethod,
        'beanOrigin': entry.beanOrigin,
        'roastLevel': entry.roastLevel,
        'doseGrams': entry.doseGrams,
        'grindSize': entry.grindSize,
        'notes': entry.notes,
        'methodData': entry.methodData,
      },
      'locale': locale,
      'installId': installId,
    });
    return switch (r) {
      _Err(:final kind, :final detail) => ScoreFailed(kind, detail),
      _Ok(:final body) => _toScoreOk(body),
    };
  }

  ScoreResult _toScoreOk(Map<String, Object?> body) {
    final score = body['score'];
    // The Worker already bounds this. Checked again because a score is
    // written to the database and shown as fact; two cheap comparisons are
    // worth more than trusting a number end to end.
    if (score is! int || score < 0 || score > 100) {
      return const ScoreFailed(KopiError.upstream, 'score out of range');
    }
    return ScoreOk(
      score,
      ((body['reasons'] as List?) ?? const []).whereType<String>().toList(),
      body['rubric'] as String? ?? 'unknown',
      body['model'] as String? ?? 'unknown',
    );
  }

  Future<_Response> _post(String path, Map<String, Object?> payload) async {
    try {
      final req = await _http
          .postUrl(Uri.parse('$_endpoint$path'))
          .timeout(_timeout);
      req.headers.contentType = ContentType.json;
      req.write(jsonEncode(payload));
      final res = await req.close().timeout(_timeout);
      final text = await utf8.decoder.bind(res).join();

      if (res.statusCode != 200) {
        return _Err(
          switch (res.statusCode) {
            429 => KopiError.rateLimited,
            422 => KopiError.notScored,
            400 => KopiError.badRequest,
            _ => KopiError.upstream,
          },
          text,
        );
      }
      final decoded = jsonDecode(text);
      if (decoded is! Map) {
        return const _Err(KopiError.upstream, 'response was not an object');
      }
      return _Ok(decoded.cast<String, Object?>());
    } catch (e) {
      return _Err(KopiError.network, '$e');
    }
  }
}

sealed class _Response {
  const _Response();
}

class _Ok extends _Response {
  const _Ok(this.body);
  final Map<String, Object?> body;
}

class _Err extends _Response {
  const _Err(this.kind, this.detail);
  final KopiError kind;
  final String detail;
}
```

- [ ] **Step 5: Run it to verify it passes**

```bash
flutter test test/kopi_client_test.dart
```

Expected: 10 passing.

- [ ] **Step 6: Commit**

```bash
./tool/check.sh
git add lib/services/kopi_client.dart lib/services/install_id.dart \
        test/kopi_client_test.dart
git commit -m "feat: the Worker client for /parse and /score

Tested against a real local HttpServer rather than a mock, so the JSON,
the headers and every status code are genuinely exercised. Failures are
a typed enum, not an exception, because the UI has to tell 'retry in a
minute' from 'this method is not scored' and behave differently.

The 0-100 bound is checked again here even though the Worker enforces
it: a score gets written to the database and shown as fact."
```

---

### Task 7: The follow-up form

**Files:**
- Create: `lib/widgets/follow_up_form.dart`
- Test: `test/follow_up_form_test.dart`

**Interfaces:**
- Consumes: `BrewSchema`, `FieldSpec`, `FieldType` (Task 3).
- Produces:
  - `List<FieldSpec> missingFields(BrewSchema schema, String method, Map<String,Object?> core, Map<String,Object?> methodData)`
  - `class FollowUpForm extends StatefulWidget` taking `fields`, `onChanged(Map<String,Object?>)`.

`missingFields` is a pure function and carries most of the logic; the widget
is a renderer over it.

- [ ] **Step 1: Write the failing test**

`test/follow_up_form_test.dart`:

```dart
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kopi_kompas/data/brew_schema.dart';
import 'package:kopi_kompas/widgets/follow_up_form.dart';

late BrewSchema schema;

void main() {
  setUpAll(() {
    schema = BrewSchema.parse(
        File('schema/brew_schema.json').readAsStringSync());
  });

  group('missingFields', () {
    test('asks only for required fields that are absent', () {
      final missing = missingFields(schema, 'espresso',
          {'doseGrams': 18, 'beanOrigin': 'Honduras', 'roastLevel': 'medium'},
          {'yieldGrams': 36, 'brewTimeSeconds': 28});
      final names = missing.map((f) => f.name);
      expect(names, contains('puckPrepWdt'));
      expect(names, contains('machine'));
      expect(names, isNot(contains('yieldGrams')));
      expect(names, isNot(contains('doseGrams')));
    });

    test('never asks for an optional field', () {
      final missing = missingFields(schema, 'espresso', {}, {});
      // basketType and waterTempC are optional on espresso.
      expect(missing.map((f) => f.name), isNot(contains('basketType')));
      expect(missing.map((f) => f.name), isNot(contains('waterTempC')));
    });

    test('treats false as answered, not missing', () {
      // "no wdt today" is an answer, and the rubric deducts for it.
      final missing = missingFields(
          schema, 'espresso', {}, {'puckPrepWdt': false});
      expect(missing.map((f) => f.name), isNot(contains('puckPrepWdt')));
    });

    test('treats an empty string as missing', () {
      final missing =
          missingFields(schema, 'espresso', {'beanOrigin': '  '}, {});
      expect(missing.map((f) => f.name), contains('beanOrigin'));
    });

    test('asks nothing when everything required is present', () {
      final missing = missingFields(schema, 'kopiJoss', {
        'beanOrigin': 'local', 'roastLevel': 'dark', 'doseGrams': 20,
      }, {
        'waterGrams': 200, 'charcoalUsed': true, 'sugarAdded': true,
      });
      expect(missing, isEmpty);
    });

    test('returns fields in schema order, core before method', () {
      final missing = missingFields(schema, 'espresso', {}, {});
      expect(missing.first.name, 'beanOrigin');
      expect(missing.map((f) => f.name).toList(), contains('yieldGrams'));
    });
  });

  group('FollowUpForm', () {
    testWidgets('gives numbers a number keyboard and booleans a switch',
        (tester) async {
      final fields = missingFields(schema, 'espresso', {}, {});
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: FollowUpForm(fields: fields, onChanged: (_) {})),
      ));

      expect(find.text('Dose'), findsOneWidget);
      expect(find.text('WDT'), findsOneWidget);
      expect(find.byType(Switch), findsWidgets);

      final dose = tester.widget<TextField>(find.ancestor(
        of: find.text('Dose'),
        matching: find.byType(TextField),
      ).first);
      expect(dose.keyboardType, TextInputType.numberWithOptions(decimal: true));
    });

    testWidgets('reports typed values as the right Dart types',
        (tester) async {
      Map<String, Object?> latest = {};
      final fields = missingFields(schema, 'espresso', {}, {});
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: FollowUpForm(fields: fields, onChanged: (v) => latest = v),
        ),
      ));

      await tester.enterText(
          find.ancestor(
            of: find.text('Dose'),
            matching: find.byType(TextField),
          ).first,
          '18.5');
      await tester.pump();
      expect(latest['doseGrams'], 18.5);
      expect(latest['doseGrams'], isA<double>());
    });

    testWidgets('roast level renders as a dropdown of its enum values',
        (tester) async {
      final fields = missingFields(schema, 'espresso', {}, {});
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: FollowUpForm(fields: fields, onChanged: (_) {})),
      ));
      expect(find.byType(DropdownButtonFormField<String>), findsOneWidget);
    });
  });
}
```

- [ ] **Step 2: Run it to verify it fails**

```bash
flutter test test/follow_up_form_test.dart
```

Expected: FAIL — `lib/widgets/follow_up_form.dart` does not exist.

- [ ] **Step 3: Write `lib/widgets/follow_up_form.dart`**

```dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/brew_schema.dart';

/// The required fields the parse did not fill.
///
/// `false` counts as answered: "no WDT today" is a statement about the brew
/// and the rubric deducts for it, so re-asking would be wrong. Only null,
/// absent, and blank text count as missing.
List<FieldSpec> missingFields(
  BrewSchema schema,
  String method,
  Map<String, Object?> core,
  Map<String, Object?> methodData,
) {
  bool absent(Object? v) =>
      v == null || (v is String && v.trim().isEmpty);

  return [
    ...schema.core.where((f) => f.required && absent(core[f.name])),
    ...schema
        .method(method)
        .fields
        .where((f) => f.required && absent(methodData[f.name])),
  ];
}

class FollowUpForm extends StatefulWidget {
  const FollowUpForm({
    super.key,
    required this.fields,
    required this.onChanged,
  });

  final List<FieldSpec> fields;
  final ValueChanged<Map<String, Object?>> onChanged;

  @override
  State<FollowUpForm> createState() => _FollowUpFormState();
}

class _FollowUpFormState extends State<FollowUpForm> {
  final _values = <String, Object?>{};

  void _set(String name, Object? value) {
    setState(() => _values[name] = value);
    widget.onChanged(Map.of(_values));
  }

  @override
  Widget build(BuildContext context) => ListView.separated(
        shrinkWrap: true,
        itemCount: widget.fields.length,
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemBuilder: (context, i) => _row(widget.fields[i]),
      );

  Widget _row(FieldSpec f) {
    final label = f.unit == null ? f.label : '${f.label} (${f.unit})';

    return switch (f.type) {
      FieldType.boolean => SwitchListTile(
          title: Text(f.label),
          value: _values[f.name] as bool? ?? false,
          onChanged: (v) => _set(f.name, v),
        ),
      FieldType.enumerated => DropdownButtonFormField<String>(
          decoration: InputDecoration(labelText: f.label),
          initialValue: _values[f.name] as String?,
          items: [
            for (final v in f.values)
              DropdownMenuItem(value: v, child: Text(v)),
          ],
          onChanged: (v) => _set(f.name, v),
        ),
      FieldType.integer => TextField(
          decoration: InputDecoration(labelText: label),
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          onChanged: (t) => _set(f.name, int.tryParse(t)),
        ),
      FieldType.number => TextField(
          decoration: InputDecoration(labelText: label),
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          onChanged: (t) => _set(f.name, double.tryParse(t)),
        ),
      FieldType.string => TextField(
          decoration: InputDecoration(labelText: label),
          onChanged: (t) => _set(f.name, t.trim().isEmpty ? null : t.trim()),
        ),
    };
  }
}
```

A boolean renders as a switch defaulting to `false`, which means the form
answers "skipped" unless toggled. That is the right default for puck prep —
the user is being asked precisely because the text did not say.

- [ ] **Step 4: Run it to verify it passes**

```bash
flutter test test/follow_up_form_test.dart
```

Expected: 9 passing.

- [ ] **Step 5: Commit**

```bash
./tool/check.sh
git add lib/widgets/follow_up_form.dart test/follow_up_form_test.dart
git commit -m "feat: the schema-driven follow-up form

Fields, labels, keyboards and dropdowns all come from
schema/brew_schema.json, so adding a brew method never means editing a
form. missingFields is a pure function and holds the judgement: false
counts as answered, because 'no WDT today' is a statement about the brew
that the rubric deducts for, and re-asking it would be wrong."
```

---

### Task 8: The new entry flow and the home list

**Files:**
- Create: `lib/widgets/score_reveal.dart`
- Rewrite: `lib/screens/home_screen.dart`, `lib/screens/new_entry_screen.dart`
- Modify: `lib/main.dart` (open the database, load the schema, build the client)
- Test: `test/new_entry_flow_test.dart`

**Interfaces:**
- Consumes: everything from Tasks 3–7.
- Produces: `class NewEntryScreen`, `class HomeScreen`, `class ScoreReveal`, and `Future<BrewEntry> buildEntry({...})` assembling a `BrewEntry` from a parse plus form answers.

- [ ] **Step 1: Write the failing test**

`test/new_entry_flow_test.dart`:

```dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kopi_kompas/data/brew_schema.dart';
import 'package:kopi_kompas/models/brew_entry.dart';
import 'package:kopi_kompas/screens/new_entry_screen.dart';

late BrewSchema schema;

void main() {
  setUpAll(() {
    schema = BrewSchema.parse(
        File('schema/brew_schema.json').readAsStringSync());
  });

  test('buildEntry merges the parse with the form answers', () {
    final e = buildEntry(
      brewMethod: 'espresso',
      core: {'doseGrams': 18},
      methodData: {'yieldGrams': 36},
      answers: {'beanOrigin': 'Honduras', 'puckPrepWdt': false},
      rawInputText: '18g in 36g out',
      schema: schema,
      now: DateTime.parse('2026-08-12T07:30:00+07:00'),
    );
    expect(e.doseGrams, 18);
    expect(e.beanOrigin, 'Honduras');
    expect(e.methodData['yieldGrams'], 36);
    expect(e.methodData['puckPrepWdt'], false);
    expect(e.rawInputText, '18g in 36g out');
  });

  test('a form answer routes to core or methodData by schema, not guesswork',
      () {
    final e = buildEntry(
      brewMethod: 'v60',
      core: const {},
      methodData: const {},
      answers: {'roastLevel': 'light', 'pourCount': 3},
      rawInputText: 'x',
      schema: schema,
      now: DateTime.now(),
    );
    expect(e.roastLevel, 'light');
    expect(e.methodData['pourCount'], 3);
    expect(e.methodData.containsKey('roastLevel'), isFalse);
  });

  test('a scored method starts pending', () {
    final e = buildEntry(
      brewMethod: 'espresso', core: const {}, methodData: const {},
      answers: const {}, rawInputText: 'x', schema: schema,
      now: DateTime.now(),
    );
    expect(e.scoreStatus, ScoreStatus.pending);
  });

  test('an unscored method is notApplicable and never pending', () {
    final e = buildEntry(
      brewMethod: 'kopiJoss', core: const {}, methodData: const {},
      answers: const {}, rawInputText: 'x', schema: schema,
      now: DateTime.now(),
    );
    expect(e.scoreStatus, ScoreStatus.notApplicable);
    expect(e.overallScore, isNull);
  });

  test('brewDate carries the local offset', () {
    final e = buildEntry(
      brewMethod: 'espresso', core: const {}, methodData: const {},
      answers: const {}, rawInputText: 'x', schema: schema,
      now: DateTime.parse('2026-08-12T00:30:00+07:00'),
    );
    expect(e.brewDate.toIso8601String(), contains('+07:00'));
  });

  test('the confetti threshold fires at 90 and not at 89', () {
    expect(shouldCelebrate(90), isTrue);
    expect(shouldCelebrate(100), isTrue);
    expect(shouldCelebrate(89), isFalse);
    expect(shouldCelebrate(null), isFalse);
  });
}
```

- [ ] **Step 2: Run it to verify it fails**

```bash
flutter test test/new_entry_flow_test.dart
```

Expected: FAIL — `buildEntry` and `shouldCelebrate` do not exist.

- [ ] **Step 3: Implement `buildEntry` and `shouldCelebrate`**

In `lib/screens/new_entry_screen.dart`, above the widget:

```dart
/// Confetti at 90 or above.
bool shouldCelebrate(int? score) => score != null && score >= 90;

/// Assembles the entry from what the model extracted plus what the user
/// filled in. Which bucket an answer belongs to is decided by the schema, not
/// by a hand-written list that would drift from it.
BrewEntry buildEntry({
  required String brewMethod,
  required Map<String, Object?> core,
  required Map<String, Object?> methodData,
  required Map<String, Object?> answers,
  required String rawInputText,
  required BrewSchema schema,
  required DateTime now,
}) {
  final coreNames = schema.core.map((f) => f.name).toSet();
  final mergedCore = Map<String, Object?>.of(core);
  final mergedMethod = Map<String, Object?>.of(methodData);

  answers.forEach((name, value) {
    if (value == null) return;
    if (coreNames.contains(name)) {
      mergedCore[name] = value;
    } else {
      mergedMethod[name] = value;
    }
  });

  return BrewEntry(
    id: newUuid(),
    brewMethod: brewMethod,
    beanOrigin: mergedCore['beanOrigin'] as String?,
    roastLevel: mergedCore['roastLevel'] as String?,
    doseGrams: (mergedCore['doseGrams'] as num?)?.toDouble(),
    grindSize: mergedCore['grindSize'] as String?,
    notes: mergedCore['notes'] as String?,
    brewDate: now,
    rawInputText: rawInputText,
    methodData: mergedMethod,
    scoreStatus: schema.isScored(brewMethod)
        ? ScoreStatus.pending
        : ScoreStatus.notApplicable,
    createdAt: now,
    updatedAt: now,
  );
}
```

- [ ] **Step 4: Build the three-stage screen**

`NewEntryScreen` holds an enum `_Stage { describe, fillGaps, scoring, revealed }`
and this behaviour:

- **describe** — a multiline `TextField` (the platform keyboard's mic handles
  dictation; no speech package) and a Continue button. On submit, show
  `AppStrings.parsing` and call `KopiClient.parse`.
  - `ParseOk` → compute `missingFields`, go to **fillGaps** (or straight to
    **scoring** when nothing is missing).
  - `ParseFailed` → **keep the text in the controller**, show
    `AppStrings.parseFailed` with Retry and "Fill in by hand". Never clear the
    field: losing what the user typed is the one unacceptable failure.
- **fillGaps** — `FollowUpForm` over the missing fields, plus Save.
- **scoring** — call `buildEntry`, then `KopiClient.score` if the method is
  scored. Show `AppStrings.scoring` with a progress indicator.
  - `ScoreOk` → `copyWith(overallScore:, scoreReasons:, scoreStatus: scored,
    scoreRubric:, scoreModel:, scoredAt:)`.
  - `ScoreFailed` → `copyWith(scoreStatus: failed)`. **Save anyway.**
  - Unscored method → skip the call entirely.
- **revealed** — `ScoreReveal`: the number, the reasons beneath it, confetti
  when `shouldCelebrate`, and Done returning to Home.

The entry is written with `BrewDatabase.insert` before **revealed** is shown,
so a crash at the celebration cannot lose the brew.

- [ ] **Step 5: Build `ScoreReveal` and the home list**

`ScoreReveal` takes `int? score`, `List<String> reasons`, `ScoreStatus status`
and fires a `ConfettiController` in `initState` when `shouldCelebrate(score)`.
For `notApplicable` it shows `AppStrings.notScored`; for `failed`,
`AppStrings.scoreFailed`.

`HomeScreen` becomes a `FutureBuilder` over `BrewDatabase.liveEntries()`
showing method label, bean origin, score (or "Not scored"), and the local
time; `AppStrings.emptyLog` when empty; a `FloatingActionButton` opening
`NewEntryScreen` and refreshing on return.

- [ ] **Step 6: Wire `main.dart`**

Open the database, load the schema and the install id before `runApp`, and
pass them down by constructor. No state-management package: the whole slice is
one list and one flow.

```dart
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final db = await BrewDatabase.open();
  final schema = await BrewSchema.load();
  final client = KopiClient(installId: await loadInstallId());
  runApp(KopiKompasApp(db: db, schema: schema, client: client));
}
```

- [ ] **Step 7: Verify**

```bash
flutter test
./tool/check.sh
```

Expected: every test passes; `check.sh` prints PASS and an endpoint line
reading `https://kopi-kompas.inkpebble.workers.dev`.

- [ ] **Step 8: Commit**

```bash
git add -A
git commit -m "feat: the describe -> fill gaps -> score flow, and the log

The entry is written to SQLite before the score is revealed, so a crash
during the confetti cannot lose a brew, and a failed score still saves
with scoreStatus failed rather than blocking the save. A failed parse
keeps the typed text: losing what someone wrote is the one failure this
flow must never have."
```

---

### Task 9: Build and install on the device

**Files:** none — verification only.

**This task needs the phone.**

- [ ] **Step 1: Confirm "Install via USB" is enabled**

On HyperOS, with it off, **every first-time install fails** —
`adb install`, `-t`, and the `/data/local/tmp` + `pm install` route all return
`INSTALL_FAILED_USER_RESTRICTED` with no prompt. Updates over an existing
install still work. Settings → Additional settings → Developer options →
Install via USB.

- [ ] **Step 2: Confirm the device is visible**

```bash
adb devices -l
flutter devices
```

- [ ] **Step 3: Build the release APK**

```bash
flutter build apk --release
```

Unsigned-by-release is fine here — without `android/key.properties` the build
falls back to debug signing, which installs. Release signing arrives with CI
in Phase 3.

- [ ] **Step 4: Install**

```bash
adb install -r build/app/outputs/flutter-apk/app-release.apk
```

- [ ] **Step 5: Walk the flow on the phone and confirm each**

1. The launcher icon is the compass mark, not the Flutter logo, and no
   wordmark is legible at icon size.
2. Home shows the empty state.
3. Type: `18g in, 36g out in 28 seconds, wdt and tamp, honduras medium`.
4. It parses; the follow-up form asks only for what is genuinely missing
   (distribution, machine — not the dose or yield already stated).
5. Saving scores it, and a score of 90+ produces confetti.
6. The reasons appear under the number.
7. Home lists the brew with its score.
8. Kill and reopen the app: the brew is still there.
9. Turn on airplane mode and submit another: the error appears, **the typed
   text is still in the field**, and "Fill in by hand" completes the entry
   with `Not scored`.

- [ ] **Step 6: Record the result**

```bash
git commit --allow-empty -m "chore: verified the vertical slice on device

Xiaomi 15 / HyperOS. <paste what happened, including anything that
looked wrong>"
```

---

## Definition of done

- `./tool/check.sh` prints PASS, with output pasted.
- An APK is installed on the Xiaomi 15 and all nine device checks above pass.
- A brew typed in free text is parsed, completed, scored and listed, and
  survives an app restart.
- A failed parse never loses typed text; a failed score never blocks a save.
- No Gemini key anywhere in the app or the repository.

## What Phase 3 inherits

- `AppStrings`, ready to become an EN/ID pair.
- `kopiArchiveColor`, ready for the full log's muted treatment.
- `BrewDatabase.hasBrewOn` and `softDelete`, which the daily reminder and the
  deleted-entries page need.
- `scoreStatus == failed` entries, which the detail screen's "Score this brew"
  retry acts on.
