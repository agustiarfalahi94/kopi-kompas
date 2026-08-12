# Kopi Kompas Phase 5 — Reminder, Indonesian, CI

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The daily reminder that skips days you already logged, the whole app in Bahasa Indonesia, and CI that builds a signed APK on a tag.

**Architecture:** The reminder is a pure scheduling function over an injected clock plus a thin `flutter_local_notifications` wrapper — the decision is testable, the plugin call is not. Indonesian follows Tiny Tapsters' pattern: `AppStrings` getters switched by a stored language, so a missing translation fails to compile rather than rendering an empty box. Field labels already carry `id` in the schema. CI mirrors Tiny Tapsters' `release-apk.yml`.

## Global Constraints

- **The reminder never nags about a coffee already logged.** It reschedules on app resume and after every save, delete and restore.
- **Inexact scheduling only** — no `SCHEDULE_EXACT_ALARM`. A logbook nudge does not need to land on the second, and that permission is a Play Store review problem for no gain.
- `POST_NOTIFICATIONS` is requested on Android 13+ behind a short explanation. **Declining is a supported state**: the app works, Settings shows the reminder as unavailable.
- Indonesian must cover **every** user-facing string, including the schema's field labels and the Worker's `locale`.
- **The keystore is the shared one.** `android/key.properties` and `*.jks` stay git-ignored.
- Branch `feature/reminder-i18n-ci` off `develop`.

---

### Task 1: When should it fire

**Files:** `lib/services/reminder_schedule.dart` · Test: `test/reminder_schedule_test.dart`

**Interfaces:** `DateTime? nextReminder({required DateTime now, required TimeOfDay at, required bool hasBrewToday, required bool enabled})`

The whole decision, as a pure function. A repeating notification cannot have one occurrence cancelled, so the app instead cancels and reschedules a single id.

- [ ] **Step 1: Write the failing tests** — the four rows of the design's table, plus the awkward ones:

```dart
test('a brew already logged today pushes it to tomorrow', () { … });
test('no brew and the time is still ahead fires today', () { … });
test('no brew but the time has passed fires tomorrow', () { … });
test('disabled schedules nothing', () { … });
test('exactly at the reminder minute counts as still ahead', () {
  // now == 08:00 and nothing logged: fire now rather than skipping a day.
});
test('crossing a month boundary lands on the first', () { … });
test('the returned time carries the reminder minute, not now', () { … });
```

- [ ] **Step 2: Implement**, then `./tool/check.sh` and commit.

---

### Task 2: Scheduling it for real

**Files:** `lib/services/reminder_service.dart`, `pubspec.yaml`, `android/app/src/main/AndroidManifest.xml` · Test: `test/reminder_service_test.dart`

Adds `flutter_local_notifications` and `timezone`. `ReminderService` takes a `Notifications` interface so the tests use a fake and never touch the plugin.

- [ ] **Step 1: Write the failing tests**

```dart
test('reschedule cancels the old notification before setting a new one', () { … });
test('reschedule with nothing due cancels and schedules nothing', () { … });
test('it always uses the same notification id', () {
  // A repeating schedule cannot have one day cancelled. One id, cancelled
  // and re-set, is what makes "skip today" possible at all.
});
test('permission denied leaves the service disabled, not crashed', () { … });
test('it schedules inexactly, so no exact-alarm permission is needed', () { … });
```

- [ ] **Step 2: Implement.** Wire `reschedule()` into app resume (`WidgetsBindingObserver`) and after save, delete and restore. Then `./tool/check.sh` and commit.

---

### Task 3: Reminder settings

**Files:** `lib/screens/settings_screen.dart`, `lib/services/settings_store.dart`, `lib/strings.dart` · Test: `test/settings_store_test.dart`

- [ ] **Step 1: Write the failing tests** — the time and the on/off flag round-trip; the default is 08:00 and on; changing either reschedules.
- [ ] **Step 2: Implement** a toggle and a time picker in Settings, plus the permission explanation on first enable. Then `./tool/check.sh` and commit.

---

### Task 4: Bahasa Indonesia

**Files:** `lib/services/app_language.dart`, `lib/strings.dart`, every screen, `lib/data/brew_schema.dart` · Test: `test/language_test.dart`

Getters switched by a stored language, as in Tiny Tapsters — a missing
translation fails to compile, which an ARB map cannot promise.

- [ ] **Step 1: Write the failing tests**

```dart
test('every string differs between en and id', () {
  // Catches a translation that was copied and never translated.
});
test('field labels follow the language', () { … });
test('the language survives a restart', () { … });
test('the parse and score calls send the chosen locale', () {
  // The Worker's Indonesian prompt is already written; the app has to ask
  // for it.
});
```

- [ ] **Step 2: Implement.** `FieldSpec.label` becomes locale-aware, `KopiClient` sends the chosen locale, Settings gains the switch. Then `./tool/check.sh` and commit.

---

### Task 5: CI

**Files:** `.github/workflows/release-apk.yml`, `README.md`, `AGENTS.md`, `CLAUDE.md`, `CHANGELOG.md` · Test: `test/docs_test.dart`

- [ ] **Step 1: Write `docs_test.dart`** — asserts the app name, package id, version, method count and scored count in the docs match the files, and that **no document ever claims the Gemini key ships in the APK**.
- [ ] **Step 2: Write the workflow.** Runs on PRs to `develop`/`main` and on `v*` tags: analyze, format, `flutter test`, worker `vitest`, then on a tag sign with the shared keystore and attach the APK to the release. Secrets: `KEYSTORE_BASE64`, `STORE_PASSWORD`, `KEY_PASSWORD`, `KEY_ALIAS`; variable `KOPI_ENDPOINT`.
- [ ] **Step 3: Write the docs.** README (what it is, how to run), AGENTS.md + CLAUDE.md kept in sync, CHANGELOG.
- [ ] **Step 4:** `./tool/check.sh` and commit.

---

### Task 6: Device verification

- [ ] Enable the reminder for two minutes' time; confirm it fires.
- [ ] Log a brew, re-enable, confirm it does **not** fire the next day.
- [ ] Switch to Indonesian; confirm every screen, including field labels, and that a brew described in Indonesian parses and scores with Indonesian reasons.
- [ ] Deny the notification permission; confirm the app still works and Settings says so.
- [ ] Commit the result, pasting what happened.

## Definition of done

- `./tool/check.sh` prints PASS.
- The reminder fires on a day with no brew and stays silent on a day with one.
- Every screen reads correctly in both languages.
- A `v*` tag produces a signed APK on the GitHub release.
