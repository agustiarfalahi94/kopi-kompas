# Kopi Kompas Phase 3 — Brew Taxonomy Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the eight flat brew methods with sixteen methods in five categories, add the new shared and per-method fields, move the rubric to `r2`, and capture your own 1–5 rating on the score reveal — migrating existing entries rather than losing them.

**Architecture:** `schema/brew_schema.json` grows a `categories` block and a `date` field type; variants stay *fields* (`shotStyle`, `brewer`) rather than becoming methods, so one field set and one rubric serve a whole family. The Worker gains a rubric per scored method. The app gains a category-grouped picker, seven new core columns, and a database migration. Nothing else about the flow changes.

**Tech Stack:** unchanged — Flutter 3.41.6, sqflite, TypeScript Worker, Gemini 3.5 Flash / Flash-Lite.

## Global Constraints

- **Sixteen methods, five categories**, exactly as section 2a of the design spec lists them. Do not invent methods.
- **Variants are fields.** `espresso.shotStyle` ∈ {ristretto, normale, lungo}; `coneDripper.brewer` ∈ {v60, origami, kono}; `flatBottomDripper.brewer` ∈ {kalitaWave, staggX, orea, april}; `smartDripper.brewer` ∈ {clever, switch}. They shift rubric targets; they never duplicate a field set.
- **Kopi luwak and wet-hulled are `process` values**, never methods.
- **Scored: `espresso`, `coneDripper`, `flatBottomDripper`, `chemex`, `batchBrewer`, `aeropress`.** Everything else is `notApplicable` and never calls `/score`.
- **`RUBRIC_VERSION` becomes `r2`.** Non-negotiable: basket size, pre-infusion, pressure, agitation and drawdown all change the verdict, and pour-over targets now vary by brewer. Existing `r1` rows keep their number and their `r1` label.
- **Every field is shown; nothing is compulsory.** The form renders all of a method's fields, pre-filled from the parse and from sticky defaults, and **Save works with any number of them blank**. `required` no longer means "must answer" — it means **"show expanded, above the fold"**. A field never shown is a field nobody knows exists, which is how `grinder` would have stayed empty forever.
- **Fields carry a `group`**: `coffee` · `grind` · `brew` · `water`. Coffee and brew render expanded; grind and water collapse to a header with a count.
- **Sticky defaults** for `grinder`, `machine`, `basketType`, `waterType`: remembered from the last entry, pre-filled, always overridable — and always overwritten by the free text when it says something different.
- `roastLevel` includes **`medium-light`** (already shipped ahead of this plan).
- **No data loss.** Existing `v60` rows migrate to `coneDripper` with `brewer: v60`. The migration is tested against a v1 database.
- `./tool/check.sh` must pass before every commit; paste its output.
- Branch `feature/brew-taxonomy` off `develop`.

## Out of scope

Entry detail screen · full log · deleted-entries page · settings · daily reminder · Indonesian localisation · CI workflow. Those are Phase 4, unchanged by this work.

---

## File Structure

| File | Change |
|---|---|
| `schema/brew_schema.json` | Rewritten: categories, 14 methods, new fields, `date` type |
| `worker/src/schema.ts` | Category support; `BrewMethod` union widened |
| `worker/src/prompts.ts` | `r2`; six rubrics; variant-aware targets |
| `lib/data/brew_schema.dart` | `CategorySpec`; `FieldType.date`; category lookup |
| `lib/models/brew_entry.dart` | Seven new core fields + `myRating` |
| `lib/services/brew_database.dart` | Schema v2 + migration |
| `lib/screens/new_entry_screen.dart` | Category-grouped manual picker; rating plumbed through |
| `lib/widgets/score_reveal.dart` | 1–5 rating control |
| `lib/screens/home_screen.dart` | Method label via category |
| `lib/strings.dart` | New strings |

---

### Task 1: The new schema

**Files:**
- Rewrite: `schema/brew_schema.json`
- Modify: `worker/src/schema.ts`
- Test: `worker/test/schema.test.ts`, `worker/test/gemini_schema.test.ts`

**Interfaces:**
- Produces: `categories: Record<string, {label, methods: BrewMethod[]}>`, `CATEGORIES: string[]`, `categoryOf(method): string`, and a widened `BrewMethod` union of the sixteen ids.

- [ ] **Step 1: Write the schema**

Top level gains `categories`; `core` gains the shared fields; `methods` is rewritten. Field types now include `"date"`.

```json
{
  "schemaVersion": "s2",
  "categories": {
    "espresso":   { "label": { "en": "Espresso", "id": "Espresso" },
                    "methods": ["espresso"] },
    "filter":     { "label": { "en": "Filter coffee", "id": "Kopi saring" },
                    "methods": ["coneDripper", "flatBottomDripper", "chemex", "batchBrewer"] },
    "immersion":  { "label": { "en": "Immersion", "id": "Rendam" },
                    "methods": ["frenchPress", "coldBrew", "turkishIbrik"] },
    "hybrid":     { "label": { "en": "Hybrid", "id": "Hibrida" },
                    "methods": ["aeropress", "smartDripper", "siphon"] },
    "indonesian": { "label": { "en": "Indonesian", "id": "Nusantara" },
                    "methods": ["kopiTubruk", "kopiSaring", "kopiJoss", "kopiTalua", "kopiKhop"] }
  },
  "core": {
    "beanOrigin":   { "type": "string", "group": "coffee", "required": true,  "label": { "en": "Bean origin", "id": "Asal biji" } },
    "roaster":      { "type": "string", "group": "coffee", "required": false, "label": { "en": "Roaster", "id": "Penyangrai" } },
    "process":      { "type": "enum", "group": "coffee", "values": ["washed", "natural", "honey", "anaerobic", "wet-hulled", "luwak"], "required": false, "label": { "en": "Process", "id": "Proses" } },
    "roastLevel":   { "type": "enum", "group": "coffee", "values": ["light", "medium-light", "medium", "medium-dark", "dark"], "required": true, "label": { "en": "Roast level", "id": "Tingkat sangrai" } },
    "roastDate":    { "type": "date", "group": "coffee", "required": false, "label": { "en": "Roast date", "id": "Tanggal sangrai" } },
    "doseGrams":    { "type": "number", "group": "brew", "unit": "g", "required": true, "label": { "en": "Dose", "id": "Dosis" } },
    "grinder":      { "type": "string", "group": "grind", "required": false, "label": { "en": "Grinder", "id": "Penggiling" } },
    "grindSetting": { "type": "string", "group": "grind", "required": false, "label": { "en": "Grind setting", "id": "Setelan giling" } },
    "grindSize":    { "type": "string", "group": "grind", "required": false, "label": { "en": "Grind size", "id": "Kehalusan giling" } },
    "waterType":    { "type": "enum", "group": "water", "values": ["filtered", "bottled", "tap", "mineral"], "required": false, "label": { "en": "Water", "id": "Air" } },
    "notes":        { "type": "string", "group": "coffee", "required": false, "label": { "en": "Notes", "id": "Catatan" } }
  },
  "methods": { … }
}
```

The `methods` block, written in full. Every field also carries a `group`
(`coffee` / `grind` / `brew` / `water`); method-specific fields are `brew`
unless noted, and `waterTempC` is always `water`. `required` here means
**expanded above the fold**, not compulsory — nothing blocks Save.

- **espresso** (scored): `shotStyle` enum[ristretto, normale, lungo] req · `yieldGrams` g req · `brewTimeSeconds` s req · `puckPrepWdt` bool req · `puckPrepDistribution` bool req · `puckPrepTamp` bool req · `machine` string req · `basketSizeGrams` g opt · `basketType` string opt · `puckScreen` bool opt · `preInfusionSeconds` s opt · `pressureBars` bar opt · `waterTempC` °C opt
- **coneDripper** (scored): `brewer` enum[v60, origami, kono] req · `waterGrams` g req · `ratio` opt · `bloomTimeSeconds` s req · `bloomWaterGrams` g req · `pourCount` integer req · `totalBrewTimeSeconds` s req · `waterTempC` °C req · `drawdownTimeSeconds` s opt · `agitation` enum[none, swirl, stir] opt · `filterType` string opt
- **flatBottomDripper** (scored): `brewer` enum[kalitaWave, staggX, orea, april] req, then identical to `coneDripper`
- **chemex** (scored): identical to `coneDripper` minus `brewer`
- **batchBrewer** (scored): `machine` string req · `waterGrams` g req · `ratio` opt · `waterTempC` °C opt · `totalBrewTimeSeconds` s opt · `filterType` string opt
- **aeropress** (scored): `inverted` bool req · `waterGrams` g req · `steepTimeSeconds` s req · `plungeTimeSeconds` s req · `waterTempC` °C req · `ratio` opt · `agitation` opt · `filterType` opt
- **frenchPress**: `waterGrams` g req · `steepTimeMinutes` min req · `waterTempC` °C req · `ratio` opt · `plungeStyle` string opt
- **coldBrew**: `waterGrams` g req · `steepTimeHours` h req · `ratio` opt · `hotBloom` bool opt · `filterType` opt
- **turkishIbrik**: `waterGrams` g req · `sugarAdded` bool req · `foamRaises` integer opt · `waterTempC` °C opt
- **smartDripper**: `brewer` enum[clever, switch] req · `waterGrams` g req · `steepTimeSeconds` s req · `drawdownTimeSeconds` s opt · `waterTempC` °C req · `ratio` opt · `filterType` opt
- **siphon**: `waterGrams` g req · `brewTimeSeconds` s req · `waterTempC` °C opt · `stirCount` integer opt · `ratio` opt · `filterType` opt
- **kopiTubruk**: unchanged from s1
- **kopiSaring** (new): `waterGrams` g req · `waterTempC` °C opt · `sockPasses` integer opt · `sugarAdded` bool req
- **kopiJoss**, **kopiTalua**, **kopiKhop**: unchanged from s1

- [ ] **Step 2: Write the failing tests**

Extend `worker/test/schema.test.ts`:

```ts
it('groups sixteen methods into five categories', () => {
  expect(METHODS).toHaveLength(16);
  expect(CATEGORIES).toEqual([
    'espresso', 'filter', 'immersion', 'hybrid', 'indonesian',
  ]);
});

it('puts every method in exactly one category', () => {
  const seen = CATEGORIES.flatMap((c) => brewSchema.categories[c].methods);
  expect(seen.sort()).toEqual([...METHODS].sort());
  expect(new Set(seen).size).toBe(seen.length);
});

it('scores espresso, the four filter methods and aeropress', () => {
  expect(SCORED_METHODS).toEqual([
    'espresso', 'coneDripper', 'flatBottomDripper', 'chemex',
    'batchBrewer', 'aeropress',
  ]);
});

it('keeps variants as fields rather than methods', () => {
  expect(METHODS).not.toContain('ristretto');
  expect(METHODS).not.toContain('lungo');
  expect(METHODS).not.toContain('v60');
  expect(brewSchema.methods.espresso.fields.shotStyle.values)
    .toEqual(['ristretto', 'normale', 'lungo']);
  expect(brewSchema.methods.coneDripper.fields.brewer.values)
    .toContain('v60');
});

it('treats luwak as a bean process, not a method', () => {
  expect(METHODS).not.toContain('kopiLuwak');
  expect(brewSchema.core.process.values).toContain('luwak');
  expect(brewSchema.core.process.values).toContain('wet-hulled');
});

it('gives every field a group, so the form can section it', () => {
  const groups = ['coffee', 'grind', 'brew', 'water'];
  const all = [
    ...Object.entries(brewSchema.core),
    ...METHODS.flatMap((m) => Object.entries(brewSchema.methods[m].fields)),
  ];
  for (const [name, spec] of all) {
    expect(groups, name).toContain(spec.group);
  }
});

it('keeps the expanded-by-default set small', () => {
  // required now means "shown above the fold", not "must answer". If a
  // method opens with more than seven rows the form stops being skimmable.
  for (const m of METHODS) {
    const open = Object.values(brewSchema.methods[m].fields)
      .filter((f) => f.required).length;
    expect(open, `${m} opens with ${open} rows`).toBeLessThanOrEqual(7);
  }
});

it('offers medium-light, between light and medium', () => {
  expect(brewSchema.core.roastLevel.values).toEqual([
    'light', 'medium-light', 'medium', 'medium-dark', 'dark',
  ]);
});
```

And in `gemini_schema.test.ts`, assert `date` maps to a string with `format: 'date'`, and that `methodData` still unions every method's fields with `nullable: true` and full `required`.

- [ ] **Step 3: Run the tests, confirm they fail, then implement**

Add to `worker/src/schema.ts`:

```ts
export interface CategorySpec {
  label: { en: string; id: string };
  methods: BrewMethod[];
}

export const CATEGORIES = Object.keys(brewSchema.categories);

export function categoryOf(method: BrewMethod): string {
  const hit = CATEGORIES.find(
    (c) => brewSchema.categories[c].methods.includes(method),
  );
  if (!hit) throw new Error(`${method} is in no category`);
  return hit;
}
```

Extend `geminiType` with `case 'date': return { type: 'string', format: 'date' };`.

- [ ] **Step 4: Verify and commit**

```bash
cd worker && npx vitest run && npx tsc --noEmit
git add schema/brew_schema.json worker/src/schema.ts worker/test/
git commit -m "feat(schema): sixteen methods in five categories

Variants stay fields: shotStyle moves the espresso ratio target and
brewer moves the dripper targets, so one field set and one rubric serve
a whole family. Made separate methods, the ratio would stop being
something the rubric could judge because it would be implied by the
name. Luwak and wet-hulled are process values, because you brew a V60
*with* luwak beans.

A test caps required fields per method, because the follow-up form is
the thing most likely to make this app annoying to use."
```

---

### Task 2: Rubric r2

**Files:**
- Modify: `worker/src/prompts.ts`
- Test: `worker/test/prompts.test.ts`

**Interfaces:**
- Consumes: Task 1's schema.
- Produces: `RUBRIC_VERSION = 'r2'` and `TARGETS` keyed by all six scored methods.

- [ ] **Step 1: Write the failing tests**

```ts
it('is r2, because the targets moved', () => {
  expect(RUBRIC_VERSION).toBe('r2');
});

it('has a rubric for every scored method and none for the rest', () => {
  for (const m of SCORED_METHODS) {
    expect(() => scoreInstruction(m, 'en')).not.toThrow();
    expect(scoreInstruction(m, 'en').length).toBeGreaterThan(300);
  }
  expect(() => scoreInstruction('kopiJoss', 'en')).toThrow();
});

it('moves the espresso ratio target with shot style', () => {
  const s = scoreInstruction('espresso', 'en');
  expect(s).toContain('ristretto');
  expect(s).toContain('lungo');
  expect(s).toContain('1.8');   // normale band
});

it('scores the new espresso fields', () => {
  const s = scoreInstruction('espresso', 'en');
  expect(s.toLowerCase()).toContain('pre-infusion');
  expect(s.toLowerCase()).toContain('basket');
});

it('gives chemex a coarser, longer target than a cone dripper', () => {
  expect(scoreInstruction('chemex', 'en')).toContain('thicker');
});

it('varies dripper targets by brewer', () => {
  const s = scoreInstruction('coneDripper', 'en');
  expect(s.toLowerCase()).toContain('brewer');
});
```

- [ ] **Step 2: Write the rubrics**

Six entries in `TARGETS`. The four filter ones share a skeleton — ratio 30, total time 25, bloom 20, temperature 15, technique 10 — with these differences stated explicitly in the text:

- **coneDripper** — ratio 15–17; total 150–210 s at 15 g; conical bed drains fastest, so a long drawdown means the grind is too fine. Targets shift slightly by `brewer`: Origami on a cone filter behaves like a V60, Kono restricts flow and runs longer.
- **flatBottomDripper** — ratio 15–17; total 180–240 s; the flat bed extracts more evenly, so an uneven-tasting brew points at pour technique rather than the dripper. Kalita's three holes restrict flow; Orea and April drain faster.
- **chemex** — ratio 15–17; total 210–270 s; **the thicker filter is the whole point** — it demands a coarser grind and a longer time, so judge a 3-minute Chemex as fast, not as normal.
- **batchBrewer** — ratio 15–17; temperature 92–96; total 240–360 s. No bloom or pour fields exist, so score what is there and say so rather than inventing a deduction.
- **espresso** — as `r1`, plus: ratio band **moves with `shotStyle`** (ristretto 1.0–1.5, normale 1.8–2.2, lungo 2.8–3.5); pre-infusion 3–10 s where recorded; pressure 6–9 bar; `basketSizeGrams` judged against `doseGrams` — a 18 g dose in a 22 g basket is under-dosed and channels.
- **aeropress** — as `r1`, plus agitation.

Every rubric repeats the two rules that matter: a `null` field is not a fault and must not be deducted for, and a `false` boolean is a deliberate omission that does count.

- [ ] **Step 3: Verify and commit**

```bash
cd worker && npx vitest run && npx tsc --noEmit
git commit -am "feat(worker): rubric r2, six scored methods

Bumped rather than edited in place. Basket size, pre-infusion, pressure
and agitation all change the verdict, and the espresso ratio band now
moves with shot style — an r1 score and an r2 score are not the same
measurement, which is exactly what scoreRubric exists to record.

The four filter rubrics share a skeleton and differ where the hardware
does: Chemex's thicker filter wants coarser and longer, Kalita's three
holes restrict flow, a conical bed drains fastest."
```

---

### Task 3: Deploy and verify the Worker

**Files:** none — verification only. **Needs the owner's Cloudflare account.**

- [ ] **Step 1:** `cd worker && npx wrangler deploy`
- [ ] **Step 2:** Verify each category parses to the right method, spaced ≥ 5 s apart to stay inside the free tier:

```bash
E=https://kopi-kompas.inkpebble.workers.dev
p() { curl -sS "$E/parse" -H 'content-type: application/json' -d "$1"; echo; }

p '{"text":"v60, 15g, 250g water at 94, 45s bloom, 3 pours, 3:10","locale":"en","installId":"t"}'
# expect coneDripper, brewer v60

p '{"text":"kalita wave 155, 20g in 320g, 93 degrees, done at 3:40","locale":"en","installId":"t"}'
# expect flatBottomDripper, brewer kalitaWave

p '{"text":"chemex, 30g, 500g water, 4 minutes","locale":"en","installId":"t"}'
# expect chemex, NOT coneDripper

p '{"text":"ristretto, 18g in 20g out in 26 seconds","locale":"en","installId":"t"}'
# expect espresso with shotStyle ristretto — NOT a method called ristretto

p '{"text":"clever dripper, 18g, 300g, steeped 2 min then drained","locale":"en","installId":"t"}'
# expect smartDripper, brewer clever

p '{"text":"cold brew, 100g coffee 800g water, 16 hours in the fridge","locale":"en","installId":"t"}'
# expect coldBrew, steepTimeHours 16

p '{"text":"kopi saring, 25g, air 250ml, gula, disaring dua kali","locale":"id","installId":"t"}'
# expect kopiSaring
```

- [ ] **Step 3:** Score a ristretto and a lungo with identical everything except `shotStyle`, and confirm the ratio reasoning differs. **This is the test that proves variants-as-fields works** — if both score the same on ratio, the rubric is ignoring `shotStyle`.
- [ ] **Step 4:** Confirm `rubric` reads `r2` in every response.
- [ ] **Step 5:** Commit any rubric corrections the real runs expose.

---

### Task 4: The Dart schema loader

**Files:**
- Modify: `lib/data/brew_schema.dart`
- Test: `test/brew_schema_test.dart`

**Interfaces:**
- Produces: `FieldType.date`; `class CategorySpec { String id; String label; List<String> methodIds; }`; `List<CategorySpec> get categories`; `CategorySpec categoryOf(String methodId)`.

- [ ] **Step 1: Write the failing tests** — mirror Task 1's Worker tests in Dart: sixteen methods, five categories, every method in exactly one, scored list, `shotStyle`/`brewer` present as fields, `v60` absent as a method, `process` carrying `luwak` and `wet-hulled`, `roastDate` parsing as `FieldType.date`, and categories preserving file order.
- [ ] **Step 2: Implement** — add the `date` case to `_fieldType`, parse `categories`, and expose `categoryOf`. A method in no category throws, matching the Worker.
- [ ] **Step 3:** `flutter test test/brew_schema_test.dart` then `./tool/check.sh`, and commit.

---

### Task 5: Database migration to v2

**Files:**
- Modify: `lib/services/brew_database.dart`, `lib/models/brew_entry.dart`
- Test: `test/brew_database_test.dart`, `test/brew_entry_test.dart`

**Interfaces:**
- Produces: seven new columns — `roaster`, `process`, `roastDate`, `grinder`, `grindSetting`, `waterType`, `myRating` — and `BrewEntry` fields to match; `onUpgrade` handling v1 → v2.

- [ ] **Step 1: Write the failing tests**

```dart
test('a v1 database upgrades without losing entries', () async {
  // Build a real v1 database, then reopen at v2.
  final db = await openDatabase(path, version: 1, onCreate: v1Schema);
  await db.insert('brews', v1Row(id: 'a', brewMethod: 'v60'));
  await db.close();

  final upgraded = await BrewDatabase.open(path: path);
  final back = (await upgraded.byId('a'))!;
  expect(back.rawInputText, isNotNull);
  expect(back.overallScore, 80);
});

test('a v60 entry becomes a coneDripper with brewer v60', () async {
  // …same setup…
  final back = (await upgraded.byId('a'))!;
  expect(back.brewMethod, 'coneDripper');
  expect(back.methodData['brewer'], 'v60');
});

test('an r1 score keeps its r1 label after upgrade', () async {
  // The whole point of scoreRubric: an old score stays readable as what
  // it was, and must not be relabelled r2 by the migration.
  expect((await upgraded.byId('a'))!.scoreRubric, 'r1');
});

test('the new columns default to null, not to empty strings', () async {
  final back = (await upgraded.byId('a'))!;
  expect(back.roaster, isNull);
  expect(back.myRating, isNull);
});

test('myRating round-trips and is bounded 1-5', () {
  expect(entry.copyWith(myRating: 4).toRow()['myRating'], 4);
});
```

- [ ] **Step 2: Implement**

`onUpgrade` runs `ALTER TABLE brews ADD COLUMN …` seven times, then rewrites `v60` rows **in Dart** — read, transform `methodData`, write back. Doing it in Dart rather than with `json_set` avoids depending on the SQLite build's JSON1 extension, which varies by Android version and is exactly the kind of thing that works on the test runner and fails on a phone.

- [ ] **Step 3:** `./tool/check.sh` and commit.

---

### Task 6: The full form, the groups, and the picker

**Files:**
- Modify: `lib/widgets/follow_up_form.dart`, `lib/screens/new_entry_screen.dart`, `lib/strings.dart`
- Create: `lib/services/sticky_defaults.dart`
- Test: `test/follow_up_form_test.dart`, `test/new_entry_flow_test.dart`, `test/sticky_defaults_test.dart`

This is the biggest behavioural change in the plan. `missingFields` is replaced by `formFields`, which returns **every** field for the method, carrying its current value and where that value came from.

**Interfaces:**
- `enum FieldSource { parsed, sticky, empty }`
- `class FormField { FieldSpec spec; Object? value; FieldSource source; }`
- `List<FormField> formFields(BrewSchema, String method, Map core, Map methodData, Map stickyDefaults)`
- `Map<String, List<FormField>> groupedFields(List<FormField>)` — keyed `coffee`/`grind`/`brew`/`water`, in that order
- `lib/services/sticky_defaults.dart`: `Future<Map<String,Object?>> loadStickyDefaults()`, `Future<void> rememberSticky(BrewEntry)` over `shared_preferences`, covering `grinder`, `machine`, `basketType`, `waterType` only.

- [ ] **Step 1: Write the failing tests**

```dart
test('formFields returns every field, not only the missing ones', () {
  final f = formFields(schema, 'espresso',
      {'doseGrams': 18}, {'yieldGrams': 36}, {});
  final names = f.map((x) => x.spec.name);
  expect(names, contains('doseGrams'));      // parsed
  expect(names, contains('basketSizeGrams')); // never mentioned
  expect(names, contains('preInfusionSeconds'));
  expect(f.length, greaterThan(15));
});

test('marks where each value came from', () {
  final f = formFields(schema, 'espresso',
      {'doseGrams': 18}, {}, {'grinder': 'Niche'});
  FormField at(String n) => f.firstWhere((x) => x.spec.name == n);
  expect(at('doseGrams').source, FieldSource.parsed);
  expect(at('grinder').source, FieldSource.sticky);
  expect(at('grinder').value, 'Niche');
  expect(at('pressureBars').source, FieldSource.empty);
});

test('a parsed value beats a sticky default', () {
  // Saying "on the ek43 today" must win over the remembered grinder.
  final f = formFields(schema, 'espresso',
      {'grinder': 'EK43'}, {}, {'grinder': 'Niche'});
  final g = f.firstWhere((x) => x.spec.name == 'grinder');
  expect(g.value, 'EK43');
  expect(g.source, FieldSource.parsed);
});

test('groups render coffee, grind, brew, water in that order', () {
  final g = groupedFields(formFields(schema, 'espresso', {}, {}, {}));
  expect(g.keys.toList(), ['coffee', 'grind', 'brew', 'water']);
});

test('rememberSticky stores only the four sticky fields', () async {
  await rememberSticky(entryWith(grinder: 'Niche', beanOrigin: 'Honduras'));
  final d = await loadStickyDefaults();
  expect(d['grinder'], 'Niche');
  expect(d.containsKey('beanOrigin'), isFalse); // origin changes every bag
});
```

And in `new_entry_flow_test.dart`:

```dart
testWidgets('Save works with the entire form untouched', (tester) async {
  // The point of the whole change: an entry that records only the method
  // and the time is still a valid entry.
});

testWidgets('filling by hand offers five categories and sixteen methods',
    (tester) async { … });
```

- [ ] **Step 2: Implement `formFields`, `groupedFields` and sticky defaults**

Precedence is parsed → sticky → empty, and it must be exactly that order: the free text is the most recent statement of fact and always wins.

- [ ] **Step 3: Rebuild `FollowUpForm` as a grouped, fully-optional form**

One `ExpansionTile` per group, `coffee` and `brew` `initiallyExpanded`, the others showing a count in the header. Rows whose value came from the parse are visually distinct from empty ones, so a glance confirms what the AI got right. **No validation, no required markers, no disabled Save.**

- [ ] **Step 4: Replace `_byHand()`'s silent guess with the category picker**

It currently defaults to `schema.methodIds.first`, which across sixteen methods is a wrong answer dressed as a choice. Grouped `ListView` over `schema.categories`.

- [ ] **Step 5: Call `rememberSticky` after a successful save**

- [ ] **Step 6:** `./tool/check.sh` and commit.

---

### Task 7: Your rating on the score reveal

**Files:**
- Modify: `lib/widgets/score_reveal.dart`, `lib/screens/new_entry_screen.dart`, `lib/strings.dart`
- Test: `test/score_reveal_test.dart` (new)

- [ ] **Step 1: Write the failing tests**

```dart
Future<void> pumpReveal(WidgetTester tester, BrewEntry entry,
    {void Function(int?)? onRated}) async {
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: ScoreReveal(
        entry: entry,
        method: schema.method(entry.brewMethod),
        onRated: onRated ?? (_) {},
        onDone: () {},
      ),
    ),
  ));
}

testWidgets('shows five rating stars under the score', (tester) async {
  await pumpReveal(tester, scored(93));
  expect(find.byIcon(Icons.star_border), findsNWidgets(5));
});

testWidgets('tapping the third star records 3', (tester) async {
  int? rated;
  await pumpReveal(tester, scored(93), onRated: (v) => rated = v);
  await tester.tap(find.byKey(const ValueKey('rating-3')));
  await tester.pump();
  expect(rated, 3);
});

testWidgets('leaving it unrated reports null, not zero', (tester) async {
  // Not rating is a real state. Storing 0 would make "unrated" look like
  // "hated it" in every average the app ever computes.
  int? rated = -1;
  await pumpReveal(tester, scored(93), onRated: (v) => rated = v);
  await tester.pump();
  expect(rated, -1, reason: 'onRated must not fire without a tap');
});

testWidgets('the rating appears for unscored methods too', (tester) async {
  // Kopi joss gets no number, but what you thought of it still matters —
  // arguably more, since nothing else judges it.
  await pumpReveal(tester, unscored('kopiJoss'));
  expect(find.byIcon(Icons.star_border), findsNWidgets(5));
});

testWidgets('a rating already set renders as filled stars', (tester) async {
  await pumpReveal(tester, scored(93).copyWith(myRating: 4));
  expect(find.byIcon(Icons.star), findsNWidgets(4));
  expect(find.byIcon(Icons.star_border), findsNWidgets(1));
});
```

- [ ] **Step 2: Implement** — five tap targets under the number, wired to `BrewEntry.myRating`, written with `db.update` when Done is tapped. It appears for every `scoreStatus`, including `notApplicable` and `failed`.
- [ ] **Step 3:** `./tool/check.sh` and commit.

---

### Task 8: Home list and labels

**Files:** `lib/screens/home_screen.dart`, `test/widget_test.dart`

- [ ] **Step 1: Write the failing tests** — a row shows the method label and its category; a `coneDripper` with `brewer: v60` reads "V60" rather than "Cone dripper"; an entry with `myRating` shows it alongside the score.
- [ ] **Step 2: Implement** — a `displayLabel(entry)` helper preferring the variant (`brewer`, `shotStyle`) over the method label, because "V60" and "Ristretto" are what you actually call them. Keep it a pure function so it is testable without pumping a widget.
- [ ] **Step 3:** `./tool/check.sh` and commit.

---

### Task 9: Device verification

**Needs the phone, unlocked, with "Install via USB" on.**

- [ ] **Step 1:** `flutter build apk --release --split-per-abi && adb install -r build/app/outputs/flutter-apk/app-arm64-v8a-release.apk`
- [ ] **Step 2: Confirm the old entries survived.** The three from Phase 2 must still be listed, with their `r1` scores intact, and the v60 one now reading as a cone dripper. **If this fails, stop** — the migration is wrong and everything after it is noise.
- [ ] **Step 3:** Log a V60 by free text; confirm it resolves to cone dripper / brewer V60.
- [ ] **Step 4:** Log a ristretto; confirm `shotStyle` is set and the score reasons judge the ratio against the *ristretto* band, not 1:2.
- [ ] **Step 5:** Log a kopi saring in Indonesian; confirm it parses and shows "Not scored".
- [ ] **Step 6:** Use the by-hand picker; confirm all five categories and sixteen methods appear.
- [ ] **Step 7:** Rate a brew 4 stars; reopen the app and confirm it persisted.
- [ ] **Step 8:** Commit the result, pasting what actually happened.

---

## Definition of done

- `./tool/check.sh` prints PASS, output pasted.
- Sixteen methods in five categories, everywhere: schema, Worker, app.
- No method named `v60`, `ristretto`, `lungo` or `kopiLuwak` exists.
- Every response carries `rubric: "r2"`; every pre-existing row still reads `r1`.
- The Phase 2 entries survive the upgrade on the real device.
- A ristretto and a lungo with identical numbers score differently on ratio.

## What Phase 4 inherits

The remaining v1 screens — entry detail, full log, deleted entries, settings, the daily reminder — plus Indonesian localisation and the CI workflow. All were designed in the spec and none are touched here.
