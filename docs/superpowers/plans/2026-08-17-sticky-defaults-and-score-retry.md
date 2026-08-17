# Remembered fields and a score retry — implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Carry every unspoken field forward from earlier brews, and give a
failed score an actual retry button instead of a sentence telling you to tap
text that has no tap handler.

**Architecture:** `stickyFor(schema, method, history)` becomes a pure function
over the brews already in SQLite — three layers, method over category over
core, filtered to what the target method asks and validated against its field
specs. The SharedPreferences store is deleted. Separately, `ScoreReveal` gains
a real retry button and the `KopiError` that `_save` currently discards.

**Tech Stack:** Flutter/Dart, `sqflite` (+ `sqflite_common_ffi` for headless
tests), `flutter_test`. No new packages.

**Spec:** `docs/superpowers/specs/2026-08-17-sticky-defaults-and-score-retry-design.md`

## Global Constraints

- **Run `./tool/check.sh` before every commit and paste its output.** Gate the
  commit on its exit code: `if ./tool/check.sh; then git commit …; fi`. Never
  pipe it into `grep` and chain with `&&`.
- Work stays on branch `feature/sticky-defaults-and-score-retry`. Never commit
  to `develop` or `main`, never tag, never cut a release.
- **Every user-facing string goes through `AppStrings`, in both languages**,
  and must be added to `AppStrings.all` or `test/language_test.dart` will not
  see it. That test also requires the Indonesian to differ from the English.
- `schema/brew_schema.json` is the only place brew fields are defined. Never
  restate a field list in Dart.
- Assert that a string replacement actually matched. An edit written against
  an anchor that no longer exists silently does nothing.
- No new dependencies.
- The edit screen is out of scope and must not pre-fill from history.

## File Structure

| File | Responsibility after this plan |
|---|---|
| `lib/services/sticky_defaults.dart` | One pure function, `stickyFor`. No I/O, no prefs, no database. |
| `lib/screens/new_entry_screen.dart` | Loads history, resolves sticky per method, keeps the score error, owns the reveal's retry. |
| `lib/widgets/follow_up_form.dart` | Renders `FieldSource` as a helper line; tracks which fields have been touched. |
| `lib/widgets/score_reveal.dart` | Shows the retry button and the failure reason. Owns no scoring logic. |
| `lib/screens/settings_screen.dart` | Its "Remembered for next time" list reads the core layer from history and labels rows from the schema. |
| `lib/screens/entry_detail_screen.dart` | Stateful only to show retry progress and a failure message. |
| `lib/screens/home_screen.dart` | Supplies the detail screen's rescore, reporting failure as a message. |
| `lib/strings.dart` | Three new strings; `scoreFailed` reworded; `stickyLabel` deleted. |

---

### Task 1: `stickyFor` — the pure function

**Files:**
- Rewrite: `lib/services/sticky_defaults.dart`
- Rewrite: `test/sticky_defaults_test.dart`
- Modify: `test/brew_schema_test.dart` (append one test)

**Interfaces:**
- Consumes: `BrewSchema`, `MethodSpec`, `FieldSpec`, `FieldType` from
  `lib/data/brew_schema.dart`; `BrewEntry` from `lib/models/brew_entry.dart`.
- Produces: `Map<String, Object?> stickyFor(BrewSchema schema, String method,
  List<BrewEntry> history)`. `history` is newest-first, as
  `BrewDatabase.liveEntries()` already returns. Task 2 calls this.
- Produces: `Map<String, Object?> rememberedCore(List<BrewEntry> history)` —
  the core layer alone, for the Settings screen, which has no method to
  resolve against. Task 2 calls this.
- Deletes: `stickyFieldNames`, `loadStickyDefaults()`, `rememberSticky()`.
  Task 2 removes their last call sites, which are in **two** screens:
  `new_entry_screen.dart` and `settings_screen.dart`.

- [ ] **Step 1: Write the failing tests**

Replace the whole of `test/sticky_defaults_test.dart` with:

```dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kopi_kompas/data/brew_schema.dart';
import 'package:kopi_kompas/models/brew_entry.dart';
import 'package:kopi_kompas/services/sticky_defaults.dart';

late BrewSchema schema;

/// Newest first, the order `liveEntries()` returns.
BrewEntry entry(
  String method, {
  String? beanOrigin,
  String? roaster,
  String? grinder,
  String? grindSetting,
  String? waterType,
  String? roastLevel,
  double? doseGrams,
  String? notes,
  DateTime? roastDate,
  Map<String, Object?> methodData = const {},
}) => BrewEntry(
  id: 'e-$method-${methodData.hashCode}',
  brewMethod: method,
  brewDate: DateTime(2026, 8, 12, 7),
  rawInputText: 'x',
  methodData: methodData,
  scoreStatus: ScoreStatus.scored,
  createdAt: DateTime(2026, 8, 12, 7),
  updatedAt: DateTime(2026, 8, 12, 7),
  beanOrigin: beanOrigin,
  roaster: roaster,
  grinder: grinder,
  grindSetting: grindSetting,
  waterType: waterType,
  roastLevel: roastLevel,
  doseGrams: doseGrams,
  notes: notes,
  roastDate: roastDate,
);

void main() {
  setUpAll(() {
    schema = BrewSchema.parse(
      File('schema/brew_schema.json').readAsStringSync(),
    );
  });

  test('an empty history remembers nothing', () {
    expect(stickyFor(schema, 'espresso', const []), isEmpty);
  });

  test('the core fields carry across a change of method', () {
    // The whole point: you told it once that you grind on an EM2 at 3 with
    // filtered water, and a french press should not ask again.
    final sticky = stickyFor(schema, 'frenchPress', [
      entry(
        'espresso',
        beanOrigin: 'Ethiopian',
        roaster: 'Common Grounds',
        grinder: 'Russell Taylors EM2',
        grindSetting: '3',
        waterType: 'filtered',
        methodData: const {'machine': 'Russell Taylors EM2', 'yieldGrams': 36},
      ),
    ]);
    expect(sticky['beanOrigin'], 'Ethiopian');
    expect(sticky['roaster'], 'Common Grounds');
    expect(sticky['grinder'], 'Russell Taylors EM2');
    expect(sticky['grindSetting'], '3');
    expect(sticky['waterType'], 'filtered');
  });

  test('a field the target method does not have is dropped', () {
    // `machine` and `yieldGrams` belong to espresso. A french press has
    // neither, and offering them would invent fields the form cannot show.
    final sticky = stickyFor(schema, 'frenchPress', [
      entry(
        'espresso',
        methodData: const {'machine': 'Russell Taylors EM2', 'yieldGrams': 36},
      ),
    ]);
    expect(sticky.containsKey('machine'), isFalse);
    expect(sticky.containsKey('yieldGrams'), isFalse);
  });

  test('the category carries what the method has not seen yet', () {
    // First ever Kalita, after months of V60. Both are `filter`, so the
    // temperature and ratio are worth having.
    final sticky = stickyFor(schema, 'flatBottomDripper', [
      entry(
        'coneDripper',
        methodData: const {'waterTempC': 93.0, 'ratio': 16.0, 'brewer': 'v60'},
      ),
    ]);
    expect(sticky['waterTempC'], 93.0);
    expect(sticky['ratio'], 16.0);
  });

  test('an enum value the target method does not offer is dropped', () {
    // `brewer` exists on coneDripper, flatBottomDripper and smartDripper with
    // value lists that share nothing: v60/origami/kono, kalitaWave/staggX/
    // orea/april, clever/switch. The first two are both `filter`, so the
    // category layer really does offer a V60 to a Kalita form. The dropdown
    // would render blank and BrewForm would save the invalid id anyway.
    final sticky = stickyFor(schema, 'flatBottomDripper', [
      entry('coneDripper', methodData: const {'brewer': 'v60'}),
    ]);
    expect(sticky.containsKey('brewer'), isFalse);
  });

  test('a valid enum value for the target method is kept', () {
    final sticky = stickyFor(schema, 'flatBottomDripper', [
      entry('flatBottomDripper', methodData: const {'brewer': 'kalitaWave'}),
    ]);
    expect(sticky['brewer'], 'kalitaWave');
  });

  test('the method beats the category for the same field', () {
    // Your own last V60 temperature is worth more than yesterday's Kalita.
    final sticky = stickyFor(schema, 'coneDripper', [
      entry('flatBottomDripper', methodData: const {'waterTempC': 96.0}),
      entry('coneDripper', methodData: const {'waterTempC': 92.0}),
    ]);
    expect(sticky['waterTempC'], 92.0);
  });

  test('the newest entry in a layer wins', () {
    final sticky = stickyFor(schema, 'espresso', [
      entry('espresso', grinder: 'EK43'),
      entry('espresso', grinder: 'Niche'),
    ]);
    expect(sticky['grinder'], 'EK43');
  });

  test('a field absent from the newest entry is taken from an older one', () {
    // Not mentioning the grinder today does not mean you sold it.
    final sticky = stickyFor(schema, 'espresso', [
      entry('espresso', waterType: 'tap'),
      entry('espresso', grinder: 'Niche'),
    ]);
    expect(sticky['grinder'], 'Niche');
    expect(sticky['waterType'], 'tap');
  });

  test('notes are never carried', () {
    // Prose about one specific cup. Stapling "tasted sharp, a bit thin" onto
    // tomorrow's coffee is worse than an empty box.
    final sticky = stickyFor(schema, 'espresso', [
      entry('espresso', notes: 'tasted sharp, a bit thin'),
    ]);
    expect(sticky.containsKey('notes'), isFalse);
  });

  test('a core field the method hides is never offered', () {
    // Kopi tubruk is made from pre-ground packaged coffee. It hides the
    // grinder however many espresso shots precede it.
    final sticky = stickyFor(schema, 'kopiTubruk', [
      entry('espresso', grinder: 'Niche', grindSetting: '3', roaster: 'Anomali'),
    ]);
    expect(sticky.containsKey('grinder'), isFalse);
    expect(sticky.containsKey('grindSetting'), isFalse);
    expect(sticky.containsKey('roaster'), isFalse);
  });

  test('a value whose type does not match the field is dropped', () {
    // A methodData blob written by an older schema version.
    final sticky = stickyFor(schema, 'espresso', [
      entry('espresso', methodData: const {'yieldGrams': 'thirty-six'}),
    ]);
    expect(sticky.containsKey('yieldGrams'), isFalse);
  });

  test('a roast date is offered as the YYYY-MM-DD the form expects', () {
    final sticky = stickyFor(schema, 'espresso', [
      entry('espresso', roastDate: DateTime(2026, 8, 1)),
    ]);
    expect(sticky['roastDate'], '2026-08-01');
  });

  test('the core layer alone is available without a method', () {
    // Settings shows what carries everywhere, and has no method to resolve
    // against.
    final core = rememberedCore([
      entry('espresso', grinder: 'Niche', methodData: const {'machine': 'x'}),
    ]);
    expect(core['grinder'], 'Niche');
    expect(core.containsKey('machine'), isFalse);
    expect(core.containsKey('notes'), isFalse);
  });

  test('booleans and numbers carry, not just strings', () {
    final sticky = stickyFor(schema, 'espresso', [
      entry(
        'espresso',
        doseGrams: 18,
        methodData: const {'puckPrepWdt': true, 'basketSizeGrams': 18.0},
      ),
    ]);
    expect(sticky['doseGrams'], 18.0);
    expect(sticky['puckPrepWdt'], true);
    expect(sticky['basketSizeGrams'], 18.0);
  });
}
```

- [ ] **Step 2: Write the schema invariant test**

The three-layer merge assumes core field names never collide with method
field names. Pin it rather than believe it. Append to
`test/brew_schema_test.dart`, inside its existing `main()`:

```dart
  test('no core field name is also a method field name', () {
    // stickyFor merges a core layer with a method layer into one map. If a
    // name ever appeared in both, one would silently shadow the other and
    // the form would show a value from the wrong bucket.
    final core = schema.core.map((f) => f.name).toSet();
    for (final id in schema.methodIds) {
      for (final f in schema.method(id).fields) {
        expect(
          core.contains(f.name),
          isFalse,
          reason: '$id.${f.name} collides with the core field of that name',
        );
      }
    }
  });
```

`test/brew_schema_test.dart` declares `late BrewSchema schema` inside `main()`
and fills it in `setUpAll`, so this test goes inside `main()` alongside the
others and needs no setup of its own.

- [ ] **Step 3: Run the tests to verify they fail**

Run: `flutter test test/sticky_defaults_test.dart test/brew_schema_test.dart`
Expected: the sticky tests FAIL to compile — "The function 'stickyFor' isn't
defined". The schema invariant test should PASS immediately; it documents an
invariant that already holds.

- [ ] **Step 4: Rewrite the implementation**

Replace the whole of `lib/services/sticky_defaults.dart` with:

```dart
import '../data/brew_schema.dart';
import '../models/brew_entry.dart';

/// The fields a new form should arrive already knowing, taken from the brews
/// already logged.
///
/// Three layers, most specific first: what this method recorded, then what
/// anything in its category recorded, then the core fields from anything at
/// all. So espresso to french press keeps the beans, the roaster and the
/// grinder and drops the machine — and a first-ever Kalita still inherits a
/// water temperature from months of V60.
///
/// [history] is newest-first, as `BrewDatabase.liveEntries()` returns it. A
/// value is taken from the newest entry that has one, which means a field you
/// did not mention today keeps yesterday's answer. It also means clearing a
/// field does not clear it for good: tomorrow the scan walks past the null
/// and finds the older value. That is deliberate — see section 3.1 of the
/// design — because pre-filling everything means a field only goes null when
/// somebody deliberately empties it.
///
/// This is a pure function on purpose. It replaced a SharedPreferences store,
/// which was a second copy of facts the database already held and could
/// disagree with it: an edit did not update it, a Firestore restore did not
/// populate it, and deleting a brew left its values behind.
Map<String, Object?> stickyFor(
  BrewSchema schema,
  String method,
  List<BrewEntry> history,
) {
  final spec = schema.method(method);
  final siblings = schema.categoryOf(method).methodIds.toSet();

  final found = <String, Object?>{};
  // putIfAbsent makes the first writer win, so the layers must run
  // most-specific first and each must run to completion before the next.
  void take(Map<String, Object?> from) {
    from.forEach((name, value) {
      if (value != null) found.putIfAbsent(name, () => value);
    });
  }

  for (final e in history) {
    if (e.brewMethod == method) take(e.methodData);
  }
  for (final e in history) {
    if (siblings.contains(e.brewMethod)) take(e.methodData);
  }
  take(rememberedCore(history));

  // Only what this method actually asks, and only values it can honestly
  // hold. hideCore is respected here so kopi tubruk keeps hiding the grinder
  // however many espresso shots precede it.
  final asked = <String, FieldSpec>{
    for (final f in schema.core)
      if (!spec.hideCore.contains(f.name)) f.name: f,
    for (final f in spec.fields) f.name: f,
  };

  final out = <String, Object?>{};
  found.forEach((name, value) {
    final field = asked[name];
    if (field != null && value != null && _fits(field, value)) {
      out[name] = value;
    }
  });
  return out;
}

/// The fields that carry to every method, whatever you brew next.
///
/// Settings shows these, and has no method to resolve against. Newest entry
/// with a value for a field wins.
Map<String, Object?> rememberedCore(List<BrewEntry> history) {
  final out = <String, Object?>{};
  for (final e in history) {
    _coreOf(e).forEach((name, value) {
      if (value != null) out.putIfAbsent(name, () => value);
    });
  }
  return out;
}

/// The core fields by name, as the form and the schema know them.
///
/// `notes` is deliberately absent: it is prose about one specific cup, and
/// carrying it forward staples yesterday's tasting note onto today's coffee.
///
/// `roastDate` is emitted as `YYYY-MM-DD` rather than a DateTime because that
/// is the shape a `FieldType.date` control renders and `buildEntry` accepts.
Map<String, Object?> _coreOf(BrewEntry e) => {
  'beanOrigin': e.beanOrigin,
  'roaster': e.roaster,
  'process': e.process,
  'roastLevel': e.roastLevel,
  'roastDate': e.roastDate?.toIso8601String().substring(0, 10),
  'doseGrams': e.doseGrams,
  'grinder': e.grinder,
  'grindSetting': e.grindSetting,
  'grindSize': e.grindSize,
  'waterType': e.waterType,
};

/// Whether a remembered value can honestly be offered for this field.
///
/// The load-bearing case is [FieldType.enumerated]. `brewer` exists on
/// coneDripper, flatBottomDripper and smartDripper with value lists that
/// share nothing at all, and the first two are in the same category — so the
/// category layer really will offer a V60 `brewer` to a Kalita form. The
/// dropdown would render blank, because `initialValue` already guards with
/// `f.values.contains`, and `BrewForm.initState` would then seed `_values`
/// from the field value regardless and save the invalid id behind an
/// empty-looking control.
bool _fits(FieldSpec f, Object value) => switch (f.type) {
  FieldType.enumerated => value is String && f.values.contains(value),
  FieldType.boolean => value is bool,
  FieldType.integer => value is int,
  FieldType.number => value is num,
  FieldType.string => value is String,
  FieldType.date => value is String && DateTime.tryParse(value) != null,
};
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `flutter test test/sticky_defaults_test.dart test/brew_schema_test.dart`
Expected: PASS.

`flutter analyze` will now report `lib/screens/new_entry_screen.dart` calling
the deleted `loadStickyDefaults` and `rememberSticky`. That is expected and
Task 2 fixes it — do not patch it here, and do not commit until Task 2 is
green, since `check.sh` gates on analyze.

- [ ] **Step 6: Hold the commit**

This task and Task 2 share one commit, because the repository does not
analyze cleanly between them. Proceed to Task 2.

---

### Task 2: Feed the form from history

**Files:**
- Modify: `lib/screens/new_entry_screen.dart`

**Interfaces:**
- Consumes: `stickyFor` from Task 1; `BrewDatabase.liveEntries()`, which
  exists and returns `Future<List<BrewEntry>>` newest-first by `brewDate`,
  excluding soft-deleted rows.
- Produces: nothing new. Later tasks modify this file further.

- [ ] **Step 1: Replace the sticky import**

In `lib/screens/new_entry_screen.dart` the import line is already
`import '../services/sticky_defaults.dart';` — it stays. Confirm it is
present rather than assuming; if the edit anchor does not match, stop.

- [ ] **Step 2: Swap the state field**

Replace:

```dart
  Map<String, Object?> _sticky = const {};
```

with:

```dart
  /// Every live brew, newest first, for the remembered-field layers. Loaded
  /// once: the form is filled and saved long before this could go stale.
  List<BrewEntry> _history = const [];
```

- [ ] **Step 3: Swap the load in initState**

Replace:

```dart
    loadStickyDefaults().then((d) {
      if (mounted) setState(() => _sticky = d);
    });
```

with:

```dart
    widget.db.liveEntries().then((h) {
      if (mounted) setState(() => _history = h);
    });
```

- [ ] **Step 4: Resolve sticky per method at form-build time**

The method is not known until the parse returns or the picker is used, so
this cannot be resolved in `initState`. In `_fillGaps()`, replace:

```dart
          fields: formFields(
            widget.schema,
            _brewMethod,
            _core,
            _methodData,
            _sticky,
          ),
```

with:

```dart
          fields: formFields(
            widget.schema,
            _brewMethod,
            _core,
            _methodData,
            stickyFor(widget.schema, _brewMethod, _history),
          ),
```

- [ ] **Step 5: Delete the write path**

The entry now *is* the memory. In `_save`, remove the line:

```dart
    await rememberSticky(entry);
```

Leave the `await widget.db.insert(entry);` above it alone.

- [ ] **Step 6: Fix Settings, the other consumer**

`lib/screens/settings_screen.dart` has a read-only "Remembered for next time"
section — the second call site of the deleted functions, and easy to miss.
At line 45, replace:

```dart
  late Future<Map<String, Object?>> _sticky = loadStickyDefaults();
```

with:

```dart
  late Future<Map<String, Object?>> _sticky = _loadRemembered();

  Future<Map<String, Object?>> _loadRemembered() async =>
      rememberedCore(await widget.db.liveEntries());
```

and at line 267, replace:

```dart
            if (mounted) setState(() => _sticky = loadStickyDefaults());
```

with:

```dart
            if (mounted) setState(() => _sticky = _loadRemembered());
```

That refresh sits after a visit to the deleted-entries screen, and it only
now does anything: restoring or deleting a brew genuinely changes the answer,
which it never could while the values lived in a separate prefs store.

- [ ] **Step 7: Let the schema label the rows**

Still in `settings_screen.dart`, replace:

```dart
                  for (final name in stickyFieldNames)
                    if (d[name] != null)
                      ListTile(
                        dense: true,
                        title: Text(AppStrings.stickyLabel(name)),
                        trailing: Text('${d[name]}'),
                      ),
```

with:

```dart
                  // Labelled from the schema, which already holds both
                  // languages for every core field. The hand-written list
                  // this replaces could only name four of them.
                  for (final f in widget.schema.core)
                    if (d[f.name] != null)
                      ListTile(
                        dense: true,
                        title: Text(f.label),
                        trailing: Text(
                          f.type == FieldType.enumerated
                              ? widget.schema.valueLabel(d[f.name] as String)
                              : '${d[f.name]}',
                        ),
                      ),
```

Add `FieldType` to the `brew_schema.dart` import in that file if analyze asks.

Then delete `AppStrings.stickyLabel` from `lib/strings.dart` entirely — it
restated a field list, which the schema is meant to be the only source of. It
is a method rather than a getter, so it is not in `all` and needs no other
edit.

Note `machine` disappears from this section: it is a method field, not a core
one, and per-method memory has no single value to show. What the section
promises — the things filled in automatically whatever you brew next — is
exactly the core layer.

- [ ] **Step 8: Verify the whole suite**

Run: `flutter analyze && flutter test`
Expected: "No issues found!" and all tests pass. If analyze still names
`loadStickyDefaults`, `rememberSticky`, `stickyFieldNames` or `stickyLabel`,
an edit above did not match its anchor — find the real call site rather than
adding the function back.

- [ ] **Step 9: Commit**

```bash
if ./tool/check.sh; then
  git add lib/services/sticky_defaults.dart lib/screens/new_entry_screen.dart \
          lib/screens/settings_screen.dart lib/strings.dart \
          test/sticky_defaults_test.dart test/brew_schema_test.dart
  git commit -m "feat: a new brew remembers every field from the last one

Three layers, most specific first: what this method recorded, then its
category, then the core fields from anything at all. Derived from the
brews in SQLite rather than a parallel SharedPreferences store, which
could disagree with them — an edit never updated it, a restore never
populated it, and deleting a brew left its values behind.

Values are validated against the target method's field specs before
being offered. Without that, the category layer hands a V60 'brewer' to
a Kalita form, where the dropdown renders blank and BrewForm saves the
invalid id anyway.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
fi
```

Paste the `check.sh` output into the session.

---

### Task 3: Show which values were remembered

**Files:**
- Modify: `lib/strings.dart`
- Modify: `lib/widgets/follow_up_form.dart`
- Modify: `test/follow_up_form_test.dart`

**Interfaces:**
- Consumes: `FieldSource` and `BrewFormField`, both already in
  `follow_up_form.dart` and already carrying the right values.
- Produces: `AppStrings.remembered`, `AppStrings.fromYourText`.

- [ ] **Step 1: Write the failing tests**

Append inside the existing `group('BrewForm', ...)` in
`test/follow_up_form_test.dart`. That group already defines

```dart
Future<Map<String, Object?>> pumpAndRead(
  WidgetTester tester,
  String method, {
  Map<String, Object?> core = const {},
  Map<String, Object?> methodData = const {},
  Map<String, Object?> sticky = const {},
})
```

— note `method` is **positional** and the helper returns the reported values.
Reuse it; do not add a second helper.

**Pick fields in an expanded group.** `_section` opens only `coffee` and
`brew`; a collapsed `ExpansionTile` does not build its children, so a marker
on `grinder` (group `grind`) is genuinely absent from the tree and
`find.text` will not see it. `doseGrams` is core, group `brew`, labelled
"Dose (g)"; `beanOrigin` is core, group `coffee`.

```dart
    testWidgets('a remembered value says so', (tester) async {
      await pumpAndRead(tester, 'espresso', sticky: {'doseGrams': 18.0});
      expect(find.text('remembered'), findsWidgets);
    });

    testWidgets('a parsed value says where it came from', (tester) async {
      await pumpAndRead(
        tester,
        'espresso',
        core: {'beanOrigin': 'Ethiopian'},
      );
      expect(find.text('from your text'), findsWidgets);
    });

    testWidgets('an untouched empty field claims nothing', (tester) async {
      await pumpAndRead(tester, 'espresso');
      expect(find.text('remembered'), findsNothing);
      expect(find.text('from your text'), findsNothing);
    });

    testWidgets('editing a field clears its marker', (tester) async {
      // The marker means "nobody has confirmed this". Once you have typed in
      // the box, somebody has.
      await pumpAndRead(tester, 'espresso', sticky: {'doseGrams': 18.0});
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Dose (g)'),
        '20',
      );
      await tester.pump();
      expect(find.text('remembered'), findsNothing);
    });
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `flutter test test/follow_up_form_test.dart`
Expected: FAIL — "Expected: exactly one matching candidate / Actual: no
matching nodes", because nothing renders the source today.

- [ ] **Step 3: Add the strings**

In `lib/strings.dart`, after `static String get scoreThisBrew`, add:

```dart
  /// Shown under a field the app filled in from an earlier brew.
  ///
  /// A remembered value is saved data that nobody has confirmed. With four
  /// fields that was survivable; with forty it is not, and it must not look
  /// identical to something you typed.
  static String get remembered => _s('remembered', 'diingat');
  static String get fromYourText => _s('from your text', 'dari teks kamu');
```

And in the `all` map, add:

```dart
    'remembered': remembered,
    'fromYourText': fromYourText,
```

- [ ] **Step 4: Track touched fields**

In `_BrewFormState`, after `final _values = <String, Object?>{};` add:

```dart
  /// Fields the user has actually edited. The source marker is only honest
  /// while nobody has touched the value.
  final _touched = <String>{};
```

In `_set`, inside the `setState` callback, add as its first line:

```dart
      _touched.add(name);
```

- [ ] **Step 5: Resolve the marker**

Add to `_BrewFormState`, next to `_noteFor`:

```dart
  /// Where this value came from, or null once the user has touched it.
  String? _sourceNote(BrewFormField field) {
    if (_touched.contains(field.spec.name)) return null;
    return switch (field.source) {
      FieldSource.sticky => AppStrings.remembered,
      FieldSource.parsed => AppStrings.fromYourText,
      FieldSource.empty => null,
    };
  }
```

- [ ] **Step 6: Render it on every control**

In `_control`, add below `final current = _values[f.name];`:

```dart
    final from = _sourceNote(field);
```

Then thread it through all four control shapes:

- `SwitchListTile` — it has no `InputDecoration`, so it takes a subtitle. Add
  after `title: Text(f.label),`:

```dart
        subtitle: from == null ? null : Text(from),
```

- `DropdownButtonFormField` — replace
  `decoration: InputDecoration(labelText: label),` with:

```dart
          decoration: InputDecoration(labelText: label, helperText: from),
```

- The date `TextFormField` — replace
  `decoration: InputDecoration(labelText: label, hintText: 'YYYY-MM-DD'),`
  with:

```dart
          decoration: InputDecoration(
            labelText: label,
            hintText: 'YYYY-MM-DD',
            helperText: from,
          ),
```

- `_text`, used by integer, number and string. Add a `String? note` parameter
  after `Object? current` in its signature, pass `from` at all three call
  sites, and replace its
  `decoration: InputDecoration(labelText: label),` with:

```dart
      decoration: InputDecoration(labelText: label, helperText: note),
```

- [ ] **Step 7: Run the tests to verify they pass**

Run: `flutter test test/follow_up_form_test.dart test/language_test.dart`
Expected: PASS. `language_test` is included because it fails if a new string
is missing from `all` or identical in both languages.

- [ ] **Step 8: Commit**

```bash
if ./tool/check.sh; then
  git add lib/strings.dart lib/widgets/follow_up_form.dart \
          test/follow_up_form_test.dart
  git commit -m "feat: say which fields were remembered and which you typed

FieldSource has been computed for every field since the form existed and
rendered nowhere. That was survivable when four fields could be
remembered. Now that a form arrives pre-filled from history, a value
nobody has confirmed must not look identical to one you typed.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
fi
```

---

### Task 4: A retry that exists

**Files:**
- Modify: `lib/strings.dart`
- Modify: `lib/widgets/score_reveal.dart`
- Modify: `test/score_reveal_test.dart`

**Interfaces:**
- Produces: `ScoreReveal` gains two optional constructor parameters,
  `VoidCallback? onRescore` and `String? failureMessage`. Task 5 supplies
  both from `NewEntryScreen`.
- Produces: `AppStrings.scoreUnavailable`. `AppStrings.scoreFailed` changes
  meaning — it becomes a status, not an instruction.

- [ ] **Step 1: Write the failing tests**

In `test/score_reveal_test.dart`, extend the existing `pump` helper to accept
the new parameters, replacing it with:

```dart
  Future<int?> pump(
    WidgetTester tester,
    BrewEntry entry, {
    VoidCallback? onRescore,
    String? failureMessage,
  }) async {
    int? rated;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ScoreReveal(
            entry: entry,
            schema: schema,
            method: schema.method(entry.brewMethod),
            onRated: (v) => rated = v,
            onDone: () {},
            onRescore: onRescore,
            failureMessage: failureMessage,
          ),
        ),
      ),
    );
    await tester.pump();
    return rated;
  }
```

Then append these tests:

```dart
  testWidgets('a failed score offers a button, not a sentence', (tester) async {
    // The whole bug: "Not scored yet — tap to retry" was a plain Text with no
    // tap handler anywhere in this file, and the only real retry was a
    // differently-named button on another screen.
    await pump(tester, entryWith(status: ScoreStatus.failed), onRescore: () {});
    expect(find.widgetWithText(OutlinedButton, 'Score this brew'), findsOneWidget);
  });

  testWidgets('tapping the retry asks for a rescore', (tester) async {
    var asked = 0;
    await pump(
      tester,
      entryWith(status: ScoreStatus.failed),
      onRescore: () => asked++,
    );
    await tester.tap(find.widgetWithText(OutlinedButton, 'Score this brew'));
    await tester.pump();
    expect(asked, 1);
  });

  testWidgets('a failed score says why', (tester) async {
    await pump(
      tester,
      entryWith(status: ScoreStatus.failed),
      onRescore: () {},
      failureMessage: 'The scorer is busy.',
    );
    expect(find.text('The scorer is busy.'), findsOneWidget);
  });

  testWidgets('a scored brew offers no retry', (tester) async {
    await pump(tester, entryWith(score: 93), onRescore: () {});
    expect(find.widgetWithText(OutlinedButton, 'Score this brew'), findsNothing);
  });

  testWidgets('an unscored method offers no retry', (tester) async {
    // Kopi joss has no rubric. Offering a retry would promise something the
    // Worker refuses.
    await pump(
      tester,
      entryWith(method: 'kopiJoss', status: ScoreStatus.notApplicable),
      onRescore: () {},
    );
    expect(find.widgetWithText(OutlinedButton, 'Score this brew'), findsNothing);
  });

  testWidgets('the status text no longer tells you to tap it', (tester) async {
    // It is rendered in three places and none of them has a tap handler.
    await pump(tester, entryWith(status: ScoreStatus.failed));
    expect(find.textContaining('tap to retry'), findsNothing);
  });
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `flutter test test/score_reveal_test.dart`
Expected: FAIL to compile — "No named parameter with the name 'onRescore'".

- [ ] **Step 3: Reword the status and add the reason**

In `lib/strings.dart`, replace:

```dart
  static String get scoreFailed =>
      _s('Not scored yet — tap to retry', 'Belum dinilai — ketuk untuk ulang');
```

with:

```dart
  /// A status, not an instruction. It used to read "tap to retry" and was
  /// rendered in three places that had no tap handler between them; the
  /// action now lives in a real button, and the full log — an archive with
  /// no honest tap target — simply reports the state.
  static String get scoreFailed => _s('Not scored yet', 'Belum dinilai');
```

Add next to it:

```dart
  /// Why a score failed, when the reason is the Worker rather than the phone.
  ///
  /// The parse step has said "no connection" and "daily limit reached" since
  /// it shipped; the score step discarded the kind and said nothing at all,
  /// so an overloaded Gemini read exactly like being offline.
  static String get scoreUnavailable => _s(
    'The scorer is busy. Your brew is saved — try again in a minute.',
    'Penilai sedang sibuk. Seduhan kamu aman — coba lagi sebentar.',
  );
```

And in the `all` map:

```dart
    'scoreUnavailable': scoreUnavailable,
```

- [ ] **Step 4: Add the parameters to ScoreReveal**

In `lib/widgets/score_reveal.dart`, add to the constructor after
`this.photo,`:

```dart
    this.onRescore,
    this.failureMessage,
```

and to the fields, after `final VoidCallback onDone;`:

```dart
  /// Asks for the score to be tried again. Null where a retry cannot be
  /// offered. The reveal owns no scoring logic — it only asks.
  final VoidCallback? onRescore;

  /// Why the score failed, in the user's language. Null when it did not.
  final String? failureMessage;
```

- [ ] **Step 5: Render the button and the reason**

In `build`, replace:

```dart
            Center(child: _headline(theme, entry)),
            const SizedBox(height: 24),
```

with:

```dart
            Center(child: _headline(theme, entry)),
            // Only a failed score can be retried. An unscored method has no
            // rubric, so offering it would promise something the Worker
            // refuses — the same rule the detail screen follows.
            if (entry.scoreStatus == ScoreStatus.failed) ...[
              if (widget.failureMessage case final why?)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    why,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium,
                  ),
                ),
              if (widget.onRescore case final retry?)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: OutlinedButton(
                    onPressed: retry,
                    child: Text(AppStrings.scoreThisBrew),
                  ),
                ),
            ],
            const SizedBox(height: 24),
```

- [ ] **Step 6: Run the tests to verify they pass**

Run: `flutter test test/score_reveal_test.dart test/language_test.dart test/theme_test.dart`
Expected: PASS. `theme_test.dart` references `AppStrings.notScored` and
`entry_detail_test.dart` may assert on the old wording — run the full suite
and fix any assertion that pinned "tap to retry", since that string is now
deliberately gone.

- [ ] **Step 7: Commit**

```bash
if ./tool/check.sh; then
  git add lib/strings.dart lib/widgets/score_reveal.dart \
          test/score_reveal_test.dart
  git commit -m "fix: the score reveal gets a retry you can actually press

'Not scored yet — tap to retry' was a plain Text in all three places it
rendered, with no tap handler in any of them. The only real retry was a
button called 'Score this brew' on the detail screen, two navigations
away. The reveal now carries that button, the status text stops
promising a tap it cannot honour, and the reason for the failure is
shown instead of discarded.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
fi
```

---

### Task 5: Wire the reveal's retry

**Files:**
- Modify: `lib/screens/new_entry_screen.dart`
- Modify: `test/new_entry_flow_test.dart`

**Interfaces:**
- Consumes: `ScoreReveal.onRescore` and `.failureMessage` from Task 4.
- Consumes: `KopiClient.score`, `BrewDatabase.update`, both existing.

- [ ] **Step 1: Write the failing test**

`new_entry_flow_test.dart` currently holds only pure-function tests. Add a
screen-level test using the loopback server pattern from
`test/kopi_client_test.dart` and the ffi setup from
`test/brew_database_test.dart`. Append to `test/new_entry_flow_test.dart`,
adding `dart:convert`, `sqflite_common_ffi`, `flutter/material.dart` and the
`KopiClient`/`BrewDatabase`/`GuidePhotos` imports it needs:

```dart
  testWidgets('a failed score still saves, and the retry works', (
    tester,
  ) async {
    // The upstream failure that produced this: Gemini answered 503 after
    // ~20 seconds, the Worker mapped it to 502, and the reveal showed a
    // sentence telling the user to tap something inert.
    databaseFactory = databaseFactoryFfi;
    var status = 502;
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((req) async {
      await utf8.decoder.bind(req).join();
      req.response.statusCode = status;
      req.response.headers.contentType = ContentType.json;
      req.response.write(
        jsonEncode(
          status == 200
              ? {
                  'score': 88,
                  'reasons': ['Ratio on target'],
                  'rubric': 'r3',
                  'model': 'test',
                }
              : {'error': 'gemini 503'},
        ),
      );
      await req.response.close();
    });
    addTearDown(() => server.close(force: true));

    // open takes a NAMED path, and GuidePhotos has no `empty()` — its
    // constructor takes the map positionally.
    final db = await BrewDatabase.open(path: inMemoryDatabasePath);
    addTearDown(db.close);

    await tester.pumpWidget(
      MaterialApp(
        home: NewEntryScreen(
          db: db,
          schema: schema,
          client: KopiClient(
            endpoint: 'http://${server.address.host}:${server.port}',
            installId: 'install-test',
          ),
          photos: const GuidePhotos({}),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Skip the parse: fill it in by hand, pick espresso, save.
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();

    // ... the flow from here depends on the screen's stages; drive it with
    // the same finders the other widget tests in this repo use.

    expect(find.text('Not scored yet'), findsOneWidget);
    expect(
      find.widgetWithText(OutlinedButton, 'Score this brew'),
      findsOneWidget,
    );

    status = 200;
    await tester.tap(find.widgetWithText(OutlinedButton, 'Score this brew'));
    await tester.pumpAndSettle();
    expect(find.text('88'), findsOneWidget);

    expect((await db.liveEntries()).single.overallScore, 88);
  });
```

**If driving the full screen proves brittle** — the describe stage needs
non-empty text before `_parse` will run, and the method picker is a long
`ListView` — do not fight it. Delete this test and rely on Task 4's widget
tests plus a direct unit test of the rescore behaviour. The retry logic is
four lines; the widget test in Task 4 already proves the button fires the
callback, and `kopi_client_test.dart` already proves a 502 maps to
`KopiError.upstream`. Say in the commit message which you did.

- [ ] **Step 2: Run it to verify it fails**

Run: `flutter test test/new_entry_flow_test.dart`
Expected: FAIL — the reveal renders no retry button, because the screen
passes neither `onRescore` nor `failureMessage`.

- [ ] **Step 3: Keep the failure reason**

In `lib/screens/new_entry_screen.dart`, add to the state fields after
`BrewEntry? _saved;`:

```dart
  /// Why the score failed, kept so the reveal can say. `_save` used to
  /// discard this, which made an overloaded Gemini, being offline and hitting
  /// the daily limit all render as the same nothing.
  KopiError? _scoreError;
```

Add next to `_messageFor`:

```dart
  /// The parse step's messages do not all fit the score step: its fallback
  /// says "could not read that", which is a sentence about text.
  String _scoreMessageFor(KopiError kind) => switch (kind) {
    KopiError.network => AppStrings.offline,
    KopiError.rateLimited => AppStrings.rateLimited,
    _ => AppStrings.scoreUnavailable,
  };
```

In `_save`, replace:

```dart
        case ScoreFailed():
```

with:

```dart
        case ScoreFailed(:final kind):
          _scoreError = kind;
```

keeping the `entry = entry.copyWith(...)` body that follows it.

- [ ] **Step 4: Add the rescore handler**

Add after `_rate`:

```dart
  /// Tries the score again from the reveal, so a brew that failed upstream
  /// does not need two navigations to rescue. Reuses the scoring stage as the
  /// busy state, which is why the reveal needs no spinner of its own.
  Future<void> _rescore() async {
    final entry = _saved;
    if (entry == null) return;
    setState(() => _stage = _Stage.scoring);

    final result = await widget.client.score(entry);
    if (!mounted) return;

    switch (result) {
      case ScoreOk(:final score, :final reasons, :final rubric, :final model):
        final scored = entry.copyWith(
          overallScore: score,
          scoreReasons: reasons,
          scoreStatus: ScoreStatus.scored,
          scoreRubric: rubric,
          scoreModel: model,
          scoredAt: DateTime.now(),
          updatedAt: DateTime.now(),
        );
        await widget.db.update(scored);
        if (!mounted) return;
        setState(() {
          _saved = scored;
          _scoreError = null;
          _stage = _Stage.revealed;
        });
      case ScoreFailed(:final kind):
        setState(() {
          _scoreError = kind;
          _stage = _Stage.revealed;
        });
    }
  }
```

- [ ] **Step 5: Pass them to the reveal**

In `build`, in the `_Stage.revealed` branch, add after `onDone: ...`:

```dart
          onRescore: _rescore,
          failureMessage: _scoreError == null
              ? null
              : _scoreMessageFor(_scoreError!),
```

`ScoreReveal` shows the button only when the status is `failed`, so passing
`_rescore` unconditionally is correct.

- [ ] **Step 6: Run the tests to verify they pass**

Run: `flutter test`
Expected: PASS.

- [ ] **Step 7: Commit**

```bash
if ./tool/check.sh; then
  git add lib/screens/new_entry_screen.dart test/new_entry_flow_test.dart
  git commit -m "feat: retry a failed score without leaving the reveal

_save discarded the KopiError, so 'the scorer is overloaded', 'you are
offline' and 'you have hit the daily limit' all rendered as the same
nothing. The kind is now kept and shown, and the retry reuses the
scoring stage as its busy state.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
fi
```

---

### Task 6: The detail-screen retry stops failing silently

**Files:**
- Modify: `lib/screens/entry_detail_screen.dart`
- Modify: `lib/screens/home_screen.dart`
- Modify: `test/entry_detail_test.dart`

**Interfaces:**
- Changes: `EntryDetailScreen.onRescore` becomes
  `Future<String?> Function()` — null on success, a message on failure —
  and the widget becomes stateful. The only call sites are
  `home_screen.dart:143` and `test/entry_detail_test.dart:101`.

- [ ] **Step 1: Write the failing tests**

`test/entry_detail_test.dart` defines, inside `group('EntryDetailScreen', …)`:

```dart
Future<void> pump(WidgetTester tester, BrewEntry entry) => …
```

with `onRescore: () {}` hard-coded. Give it a parameter, keeping the default
so the existing tests are untouched:

```dart
    Future<void> pump(
      WidgetTester tester,
      BrewEntry entry, {
      Future<String?> Function()? onRescore,
    }) => tester.pumpWidget(
      MaterialApp(
        home: EntryDetailScreen(
          schema: schema,
          entry: entry,
          onEdit: () {},
          onDelete: () {},
          onRescore: onRescore ?? () async => null,
          onRate: (_) {},
        ),
      ),
    );
```

Then append, inside the same group:

```dart
  testWidgets('the retry shows it is working', (tester) async {
    final done = Completer<String?>();
    await pump(
      tester,
      entryWith(status: ScoreStatus.failed),
      onRescore: () => done.future,
    );
    await tester.tap(find.widgetWithText(OutlinedButton, 'Score this brew'));
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    done.complete(null);
    await tester.pumpAndSettle();
  });

  testWidgets('a retry that fails says so', (tester) async {
    // It used to await up to 45 seconds and then do nothing at all: no
    // spinner, no message, the button simply sitting there.
    await pump(
      tester,
      entryWith(status: ScoreStatus.failed),
      onRescore: () async => 'The scorer is busy.',
    );
    await tester.tap(find.widgetWithText(OutlinedButton, 'Score this brew'));
    await tester.pumpAndSettle();
    expect(find.text('The scorer is busy.'), findsOneWidget);
  });
```

Use the file's existing `entryWith` builder — check whether it already takes a
`status` parameter and add one if not. Import `dart:async` for `Completer`.

- [ ] **Step 2: Run them to verify they fail**

Run: `flutter test test/entry_detail_test.dart`
Expected: FAIL — the argument type does not match `VoidCallback`.

- [ ] **Step 3: Make the detail screen stateful**

In `lib/screens/entry_detail_screen.dart`, change the class declaration:

```dart
class EntryDetailScreen extends StatefulWidget {
```

change the field:

```dart
  /// Returns null when the score succeeded, or a message saying why it did
  /// not. A VoidCallback could not report failure, which is why this screen
  /// used to wait up to 45 seconds and then show nothing.
  final Future<String?> Function() onRescore;
```

and add at the end of the class:

```dart
  @override
  State<EntryDetailScreen> createState() => _EntryDetailScreenState();
}

class _EntryDetailScreenState extends State<EntryDetailScreen> {
  bool _scoring = false;
  String? _scoreError;

  Future<void> _rescore() async {
    setState(() {
      _scoring = true;
      _scoreError = null;
    });
    final failure = await widget.onRescore();
    if (!mounted) return;
    setState(() {
      _scoring = false;
      _scoreError = failure;
    });
  }
```

Move the existing `build`, `_score`, `_rating`, `_field` and `_confirmDelete`
members into the new state class, and prefix every reference to `schema`,
`entry`, `onEdit`, `onDelete`, `onRate` with `widget.` inside them. Run
`flutter analyze` after this step alone — it will name every reference you
missed.

- [ ] **Step 4: Render the progress and the message**

Replace the retry block in `build`:

```dart
          if (entry.scoreStatus == ScoreStatus.failed)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: OutlinedButton(
                onPressed: onRescore,
                child: Text(AppStrings.scoreThisBrew),
              ),
            ),
```

with:

```dart
          if (widget.entry.scoreStatus == ScoreStatus.failed)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: _scoring
                  ? const Center(child: CircularProgressIndicator())
                  : OutlinedButton(
                      onPressed: _rescore,
                      child: Text(AppStrings.scoreThisBrew),
                    ),
            ),
          if (_scoreError case final why?)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(
                why,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium,
              ),
            ),
```

- [ ] **Step 5: Report the failure from home_screen**

In `lib/screens/home_screen.dart`, replace the whole `onRescore:` callback at
line 143 with:

```dart
          onRescore: () async {
            final result = await widget.client.score(e);
            switch (result) {
              case ScoreOk(
                :final score,
                :final reasons,
                :final rubric,
                :final model,
              ):
                await widget.db.update(
                  e.copyWith(
                    overallScore: score,
                    scoreReasons: reasons,
                    scoreStatus: ScoreStatus.scored,
                    scoreRubric: rubric,
                    scoreModel: model,
                    scoredAt: DateTime.now(),
                    updatedAt: DateTime.now(),
                  ),
                );
                navigator.pop();
                return null;
              case ScoreFailed(:final kind):
                return switch (kind) {
                  KopiError.network => AppStrings.offline,
                  KopiError.rateLimited => AppStrings.rateLimited,
                  _ => AppStrings.scoreUnavailable,
                };
            }
          },
```

Check that `home_screen.dart` imports `AppStrings` and `KopiError`; add the
imports if analyze asks for them.

- [ ] **Step 6: Run the tests to verify they pass**

Run: `flutter analyze && flutter test`
Expected: "No issues found!" and all tests pass.

- [ ] **Step 7: Commit**

```bash
if ./tool/check.sh; then
  git add lib/screens/entry_detail_screen.dart lib/screens/home_screen.dart \
          test/entry_detail_test.dart
  git commit -m "fix: the detail-screen retry reports what happened

It awaited a score for up to 45 seconds and acted only on success: no
spinner while it waited, no message when it gave up, the button simply
sitting there. onRescore now returns null or a reason.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
fi
```

---

### Task 7: Update the handover ledger

**Files:**
- Modify: `docs/STATE.md`

- [ ] **Step 1: Read what is there**

Read `docs/STATE.md` in full and match its existing sections and table
formats. It has a table of bugs already paid for once — the "tap to retry"
sentence and the discarded `KopiError` both belong in it.

- [ ] **Step 2: Record what changed**

Add, in the file's own voice and its own sections:

- Remembered fields now come from SQLite, not SharedPreferences.
  `stickyFor` is a pure function; `loadStickyDefaults` and `rememberSticky`
  are gone, and the old `sticky.*` prefs keys are abandoned with no
  migration.
- The `beanOrigin` exclusion is deliberately reversed, and why the
  "remembered" marker is what makes that defensible.
- A value never dies: clearing a field does not stop it being found further
  back in the history. Design section 3.1.
- For the bug table: "Not scored yet — tap to retry" was rendered in three
  files with no tap handler between them, and every score failure kind was
  discarded, so an overloaded Gemini read exactly like being offline.
- **Not verified on a phone.** Everything here has only been run in tests.

- [ ] **Step 3: Commit**

```bash
if ./tool/check.sh; then
  git add docs/STATE.md
  git commit -m "docs: update STATE.md for remembered fields and the score retry

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
fi
```

- [ ] **Step 4: Build the APK and say what is unverified**

```bash
flutter build apk --release --split-per-abi
```

A green suite is not proof the app works — the missing `INTERNET`
permission and the dead reminder receivers both passed every test. Install
it and record a brew. If you cannot install it, write "unverified" and say
so plainly rather than implying otherwise.

Two things only a phone can show here: whether a form pre-filled with forty
remembered values is still usable or merely full, and whether the helper
lines under every control make it unreadable.

---

## Self-Review

**Spec coverage.** §1.1 four-fields problem → Tasks 1–2. §1.2 dead retry →
Tasks 4–6. §2 memory lives in SQLite → Task 1 (function) and Task 2 (wiring,
including deleting `rememberSticky`). §3 three layers, relevance filter,
validity filter, `notes` excluded → Task 1, one test each. §3.1 a value never
dies → Task 1's dartdoc and the "absent from the newest entry" test. §4 form
markers → Task 3. §5 the retry, the reworded string, the kept `KopiError`,
the detail screen → Tasks 4, 5, 6. §6 tests → distributed across the tasks
that create the behaviour. §7 files → the File Structure table; `STATE.md` is
Task 7.

**Anchor check.** Every file the plan tells an implementer to edit was opened
and every named helper verified before the plan was committed. Five anchors
were wrong on the first pass and are now corrected: the form test's helper is
`pumpAndRead(tester, method, {...})` with a positional method, not `pumpForm`;
the detail test's is `pump(tester, entry)`, not `pumpDetail`;
`BrewDatabase.open` takes a **named** `path`; `GuidePhotos` has no `empty()`;
and `brew_schema_test.dart` declares its `schema` inside `main()`. A sixth
correction is larger — `settings_screen.dart` is a second consumer of the
deleted functions, which the spec's file list had missed entirely, so Task 2
now fixes it in the same commit that deletes them.

**Placeholder scan.** One deliberate ellipsis remains, in Task 5 Step 1,
where the screen-drive test cannot be written blind — the stage machine's
finders depend on rendering the picker. That step carries an explicit
fallback and an instruction to say which path was taken, rather than leaving
a silent gap.

**Type consistency.** `stickyFor(BrewSchema, String, List<BrewEntry>) →
Map<String, Object?>` is named identically in Tasks 1 and 2.
`ScoreReveal.onRescore` is `VoidCallback?` in Tasks 4 and 5.
`EntryDetailScreen.onRescore` is `Future<String?> Function()` in both places
Task 6 touches. `AppStrings.remembered`, `.fromYourText`, `.scoreUnavailable`
and the reworded `.scoreFailed` are spelled the same in Tasks 3, 4, 5 and 6.
