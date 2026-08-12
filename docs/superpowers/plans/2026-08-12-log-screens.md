# Kopi Kompas Phase 4 — Log Screens Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The screens for reading and managing the log — entry detail, the full history page, soft delete with a recovery page, and a Settings screen to hang them off.

**Architecture:** All four screens read the same `BrewDatabase` and `BrewSchema` already built. Nothing new talks to the network except the "score this brew" retry, which reuses `KopiClient`. The full log's muted treatment comes from `kopiArchiveColor`, which has been sitting in the theme since Phase 2 waiting for it.

**Tech Stack:** unchanged.

## Global Constraints

- **Deleting is soft.** The row survives with `deletedAt` set, leaves Home and the full log, and stops counting for the reminder. Only the Deleted entries page can destroy it permanently.
- **The full log shows live entries only.** Deleted ones live in Settings → Deleted entries, not in the archive.
- **The full log is read-only.** Editing happens in the detail screen.
- **The full log shows `rawInputText` verbatim**, next to what the AI made of it.
- **Editing re-runs scoring**; a `failed` score can be retried from the detail screen.
- Strings go through `AppStrings`. No bare literals in widgets.
- `./tool/check.sh` must pass before every commit — gate the commit on its exit code, not on a grep.
- Branch `feature/log-screens` off `develop`.

## Out of scope

Daily reminder · Indonesian localisation · CI workflow. Those are Phase 5.

---

### Task 1: Entry detail

**Files:**
- Create: `lib/screens/entry_detail_screen.dart`
- Modify: `lib/screens/home_screen.dart` (tap opens it), `lib/strings.dart`
- Test: `test/entry_detail_test.dart`

**Interfaces:**
- `EntryDetailScreen({required db, schema, client, entry})`, popping `true` when anything changed.
- `List<({FieldSpec spec, Object? value})> detailRows(BrewSchema, BrewEntry)` — every field that has a value, in schema order, core before method.

- [ ] **Step 1: Write the failing tests**

```dart
test('detailRows shows only fields that have a value', () {
  final rows = detailRows(schema, entryWith(
    core: {'beanOrigin': 'Honduras'}, methodData: {'yieldGrams': 36}));
  final names = rows.map((r) => r.spec.name);
  expect(names, contains('beanOrigin'));
  expect(names, contains('yieldGrams'));
  expect(names, isNot(contains('pressureBars')));
});

test('detailRows keeps schema order, core before method', () {
  final rows = detailRows(schema, entryWith(
    core: {'roastLevel': 'medium', 'beanOrigin': 'X'},
    methodData: {'yieldGrams': 36}));
  expect(rows.first.spec.name, 'beanOrigin');
  expect(rows.last.spec.name, 'yieldGrams');
});

test('detailRows shows a false boolean, which is a real answer', () {
  final rows = detailRows(schema, entryWith(
    methodData: {'puckPrepWdt': false}));
  expect(rows.map((r) => r.spec.name), contains('puckPrepWdt'));
});

testWidgets('shows the score, its reasons and its rubric', (t) async { … });
testWidgets('shows the original text you typed', (t) async { … });
testWidgets('offers Score this brew only when scoring failed', (t) async { … });
testWidgets('deleting asks first, then pops', (t) async { … });
```

- [ ] **Step 2: Implement**

Sections mirroring the form's groups, the score with its reasons and
`rubric · model` line, the star rating (editable), `rawInputText` in a muted
block, and Edit / Delete. Delete shows a confirmation naming what happens —
"moved to Deleted entries, recoverable" — because the wording is the only
thing telling the user it is not permanent.

- [ ] **Step 3:** `./tool/check.sh`, commit.

---

### Task 2: Editing an entry

**Files:**
- Modify: `lib/screens/entry_detail_screen.dart`, `lib/screens/new_entry_screen.dart`
- Test: `test/entry_edit_test.dart`

The form already exists and already takes pre-filled values. Editing reuses
`BrewForm` with the entry's values as the `parsed` map.

- [ ] **Step 1: Write the failing tests**

```dart
test('editing keeps the id, createdAt and rawInputText', () { … });
test('editing updates updatedAt', () { … });
test('editing a scored method sets status back to pending', () { … });
test('editing an unscored method stays notApplicable', () { … });
test('a re-score that fails keeps the old score rather than clearing it', () {
  // A network blip must not destroy a number you already had. This is the
  // opposite of the save path, where there was no score to lose.
});
```

- [ ] **Step 2: Implement** `applyEdits(BrewEntry, answers, schema, now)` as a pure function, so the merge rules are testable without a widget.
- [ ] **Step 3:** `./tool/check.sh`, commit.

---

### Task 3: The full log

**Files:**
- Create: `lib/screens/full_log_screen.dart`
- Modify: `lib/screens/home_screen.dart` (a way in), `lib/strings.dart`
- Test: `test/full_log_test.dart`

- [ ] **Step 1: Write the failing tests**

```dart
testWidgets('lists every live entry, newest first', (t) async { … });

testWidgets('shows all of an entry expanded, not a summary row', (t) async {
  // The difference from Home. Home is scannable; this is the record.
});

testWidgets('shows the raw text next to the parsed fields', (t) async { … });

testWidgets('does not show deleted entries', (t) async {
  // They live in Settings. The archive is a record of brewing, not of edits.
});

testWidgets('renders in the archive colour, not the body colour', (t) async {
  // kopiArchiveColor exists so this treatment is a property of the design
  // rather than of one widget that could drift.
});

testWidgets('is read-only — no edit or delete controls', (t) async { … });
```

- [ ] **Step 2: Implement** using `kopiArchiveColor(brightness)`, dense type, no score colouring, no icons. Each entry expanded: all fields with values, the score and reasons, then `rawInputText` verbatim.
- [ ] **Step 3:** `./tool/check.sh`, commit.

---

### Task 4: Soft delete and the Deleted entries page

**Files:**
- Create: `lib/screens/settings_screen.dart`, `lib/screens/deleted_entries_screen.dart`
- Modify: `lib/services/brew_database.dart` (`deletedEntries`, `restore`, `purge`), `lib/screens/home_screen.dart`
- Test: `test/deleted_entries_test.dart`, extend `test/brew_database_test.dart`

- [ ] **Step 1: Write the failing tests**

```dart
test('deletedEntries returns only deleted rows, newest deletion first', () { … });
test('restore clears deletedAt and the entry returns to the live list', () { … });
test('purge removes the row for good', () { … });
test('a purged entry is gone from every query', () { … });

testWidgets('Settings routes to Deleted entries', (t) async { … });
testWidgets('the page shows when each entry was deleted', (t) async { … });
testWidgets('permanent delete asks twice, because it cannot be undone',
    (t) async { … });
```

- [ ] **Step 2: Implement.** `restore` sets `deletedAt` to null and bumps `updatedAt`; `purge` is a real `DELETE`. Settings is otherwise a stub in this phase — it exists to hold this page and to be where Phase 5 hangs the reminder.
- [ ] **Step 3:** `./tool/check.sh`, commit.

---

### Task 5: Navigation

**Files:** `lib/screens/home_screen.dart`, `lib/strings.dart`
**Test:** `test/widget_test.dart`

- [ ] **Step 1: Write the failing tests** — Home has a way to the full log and to Settings; tapping a row opens the detail; returning from any of them refreshes the list.
- [ ] **Step 2: Implement.** An app-bar action for the full log and one for Settings. Not a bottom bar: with three destinations and one of them rarely used, two icons cost less screen than a permanent bar.
- [ ] **Step 3:** `./tool/check.sh`, commit.

---

### Task 6: Device verification

**Needs the phone.**

- [ ] Build, install, and check each: tap a brew → detail shows every field, the reasons and the raw text; edit the dose → it re-scores; delete → it leaves Home *and* the full log; Settings → Deleted entries shows it with its date; restore → it comes back; the full log reads visibly muted against Home; kill and reopen → everything persists.
- [ ] Commit the result, pasting what actually happened.

---

## Definition of done

- `./tool/check.sh` prints PASS, output pasted.
- Detail, full log, Settings and Deleted entries all reachable from Home.
- Deleting is recoverable; only the Deleted page can destroy an entry.
- The full log is read-only, muted, and shows the raw text.
- Verified on the phone.

## What Phase 5 inherits

The daily reminder (`hasBrewOn` and the reschedule table are already
specified in the design), Indonesian localisation, and the CI workflow.
