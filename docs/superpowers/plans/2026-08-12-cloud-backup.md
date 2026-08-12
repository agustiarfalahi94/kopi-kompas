# Kopi Kompas Phase 6 — Login and Cloud Backup

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Your log survives a lost or factory-reset phone. Sign in with Google, email or phone; every brew is backed up; a new phone restores everything.

**Architecture:** Firebase Auth for the three sign-in methods and Firestore for the data, following `random_recall`, which already ships all three working. **The phone stays the source of truth**: SQLite remains the app's database and Firestore is a mirror. Nothing about logging a coffee changes when you are signed out, and nothing waits on the network.

**Tech Stack:** `firebase_core` · `firebase_auth` · `cloud_firestore` · `google_sign_in` · `firebase_app_check`

## Global Constraints

- **Signing in is optional and always has been optional.** The app works fully signed out — that is what it does today, and Phase 6 must not quietly make an account the price of entry.
- **SQLite stays the source of truth.** Firestore is a backup, not the live store. A dropped connection must never block a save or lose an edit.
- **Firestore rules deny by default.** Copy `random_recall/firestore.rules`: a user may read and write only `/users/{their own uid}/**`, writes capped at 100 KB, everything else denied. Rules are the security boundary — client code is not.
- **`google-services.json` is git-ignored** and written by CI from a secret.
- **Every user-facing string in both languages**, as ever.
- Branch `feature/cloud-backup` off `develop`.

## The cost, stated up front

Firebase pulls in Google Play Services and its permissions. Today this app requests exactly one permission, `INTERNET`, and `test/manifest_test.dart` enforces that. **That test will have to be relaxed**, and the change should be deliberate rather than discovered. If the permission list grows beyond what sign-in genuinely needs, that is a bug, not a cost of doing business.

---

### Task 1: Firebase project and sign-in

**Files:** `lib/services/auth_service.dart`, `lib/screens/auth/`, `pubspec.yaml`, `android/app/build.gradle.kts` · Test: `test/auth_service_test.dart`

**Needs the owner:** a Firebase project, `google-services.json`, the release SHA-1 registered, and phone auth enabled in the console.

**Interfaces:** `sealed class AuthState` → `SignedOut` · `SignedIn(uid, displayName, email)`; `AuthService` with `signInWithGoogle()`, `signInWithEmail()`, `signInWithPhone()`, `signOut()`, `Stream<AuthState> changes`.

- [ ] **Step 1: Write the failing tests** — against a fake Firebase interface: each method reaching `SignedIn`, a cancelled Google sign-in returning to `SignedOut` **without** an error banner, a wrong password surfacing a readable message, and `account-exists-with-different-credential` routing to the linking flow rather than failing.
- [ ] **Step 2: Implement**, copying `random_recall/lib/screens/auth/` for the flows. `google_sign_in` 7.x **always needs `serverClientId`** and must never swallow a non-cancel exception — both cost that project a release.
- [ ] **Step 3:** `./tool/check.sh`, commit.

---

### Task 2: Rules first, then the mirror

**Files:** `firestore.rules`, `lib/services/backup_service.dart` · Test: `test/backup_service_test.dart`

Rules are written and deployed **before** any code writes a document, so there is never a window where the database is open.

**Interfaces:** `BackupService` with `Future<void> push(BrewEntry)`, `Future<void> pushAll()`, `Future<List<BrewEntry>> pull()`, `Stream<BackupState> state`.

- [ ] **Step 1: Write `firestore.rules`** — `/users/{uid}/brews/{id}`, readable and writable only by that uid, 100 KB cap, everything else denied. Deploy and verify with the emulator or the console's rules playground.
- [ ] **Step 2: Write the failing tests**

```dart
test('a signed-out user never touches the network', () { … });
test('a failed push leaves the local entry untouched', () {
  // The phone is the source of truth. A backup failure is not a data loss.
});
test('push is idempotent — the same entry twice is one document', () { … });
test('a soft-deleted entry is mirrored as deleted, not removed', () {
  // Otherwise restoring on a new phone loses the recovery page.
});
test('pull never overwrites a local entry that is newer', () { … });
```

- [ ] **Step 3: Implement.** Documents keyed by the entry's existing uuid, which makes push idempotent for free. Then `./tool/check.sh`, commit.

---

### Task 3: Restore on a new phone

**Files:** `lib/screens/auth/restore_screen.dart`, `lib/services/backup_service.dart` · Test: `test/restore_test.dart`

- [ ] **Step 1: Write the failing tests** — signing in on an empty install offers a restore; restoring writes every brew including deleted ones and their scores, rubrics and ratings; restoring twice does not duplicate; a restore that fails halfway leaves a usable app rather than a half-empty log.
- [ ] **Step 2: Implement.** Restore is explicit, not automatic: silently merging a stranger's log into an existing one would be worse than asking.
- [ ] **Step 3:** `./tool/check.sh`, commit.

---

### Task 4: Settings, and telling the truth about state

**Files:** `lib/screens/settings_screen.dart`, `lib/strings.dart` · Test: `test/settings_backup_test.dart`

- [ ] **Step 1: Write the failing tests** — signed out shows a sign-in row and says the log is on this phone only; signed in shows the account and when the last backup succeeded; a failed backup says so rather than showing a stale success.
- [ ] **Step 2: Implement.** *"Backed up 3 minutes ago"* and *"Couldn't back up — will retry"* are the whole feature from the user's side. A sync indicator that lies is worse than none.
- [ ] **Step 3:** `./tool/check.sh`, commit.

---

### Task 5: CI and the permission list

**Files:** `.github/workflows/release-apk.yml`, `test/manifest_test.dart`, `AGENTS.md`

- [ ] **Step 1:** Decode `google-services.json` from a secret in CI, and fail loudly if the secret is missing.
- [ ] **Step 2: Update `manifest_test.dart` deliberately** — list the permissions Firebase genuinely adds and assert *exactly* that set. The test keeps its teeth; it just knows more.
- [ ] **Step 3:** Record in `AGENTS.md` what each new permission is for.

---

### Task 6: Device verification

- [ ] Sign in with each of Google, email and phone.
- [ ] Log a brew, confirm it appears in Firestore under your uid and nowhere else.
- [ ] **Uninstall the app**, reinstall, sign in, restore — every brew back with its score, rubric, rating and deleted entries.
- [ ] Turn on airplane mode, log a brew, confirm it saves locally and backs up when the network returns.
- [ ] Sign out, confirm the local log still works.

## Definition of done

- All three sign-in methods work on the device.
- An uninstall–reinstall–restore round trip loses nothing.
- Signed out, the app behaves exactly as it does today.
- Firestore rules deny everything except a user's own tree.
- The permission list is asserted, not merely observed.
