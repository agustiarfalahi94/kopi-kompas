# AGENTS.md — instructions for AI coding agents

## Start here

**Kopi Kompas** — a Flutter coffee-brewing logbook, `com.inkpebble.kopi_kompas`,
v0.4.0+5. Android-first. 16 brew methods in 5 categories; 6 of them scored.

Read: this file → **`docs/STATE.md`** (what is true right now: what is
unmerged, what has never run on a phone, and every bug already paid for once)
→ `CLAUDE.md` (same instructions, must stay in sync) →
`docs/superpowers/specs/2026-08-12-kopi-kompas-design.md` → the relevant plan
in `docs/superpowers/plans/`.

`docs/STATE.md` is the handover file. Update it whenever a bug is fixed, a
branch is merged, or something is verified on a device — a new session has no
memory of this one, and the ledger is how a mistake gets made only once.

## Working agreement

Each of these exists because it was broken, and most of them reached the
phone before anyone noticed.

1. **Run `./tool/check.sh` before every commit and paste its output.** It runs
   analyze, format, the Flutter tests and the Worker tests, then prints the
   app name, version, package id, method counts and endpoint *read from the
   files*. A summary can be invented; a pasted run cannot.
2. **Gate the commit on its exit code, not on a grep.** `if ./tool/check.sh;
   then git commit …; fi`. Piping it into `grep` and chaining with `&&` has
   twice let a failing analyze through.
3. **Never state a fact about this project from memory.** Not the version, not
   the method count, not the package id. `test/docs_test.dart` is the arbiter.
4. **A green test suite is not proof the app works.** The missing `INTERNET`
   permission, the AI returning `brewer: "switch"` for a V60, and a form that
   reported nothing for an untouched switch all passed every test. Install the
   APK and use it.
5. **Assert that a string replacement actually matched.** An edit written
   against an anchor that no longer exists silently does nothing, and the
   suite stays green while you believe a case is covered.
6. **Work on a branch off `develop`.** Never commit to `develop` or `main`
   directly, never tag, never cut a release.
7. **Say what you changed and what was already there.**
8. **If you could not run a command, write "unverified".**

## Git flow

- Work on **`develop`** (default branch); features on a branch off it.
- Release: merge `develop` → `main`, push, annotated tag `vX.Y.Z`, push the tag.
- CI runs on PRs to `develop`/`main` and on `v*` tags.

## Validation

```bash
./tool/check.sh                  # everything, plus the facts
flutter analyze                  # must say "No issues found!"
dart format --set-exit-if-changed lib/ test/
flutter test
(cd worker && npx vitest run && npx tsc --noEmit)
flutter build apk --release --split-per-abi
```

## Constraints

- **The Gemini API key is a Cloudflare Worker secret.** Never in the
  repository, never in a commit, never in the APK. The app ships a URL, which
  is not a secret. CI fails the build if a key pattern appears in tracked
  files.
- Do NOT commit `android/key.properties` or `android/app/release-keystore.jks`.
  The keystore is shared with `random_recall` and `tiny_tapsters`.
- Do NOT add ads, analytics or tracking. The app **declares** only `INTERNET`;
  the merged manifest also carries `POST_NOTIFICATIONS` (the reminder),
  `ACCESS_NETWORK_STATE` and `VIBRATE` (Firebase and notifications). Firebase
  also tries to add `USE_BIOMETRIC` and `USE_FINGERPRINT`, which are stripped
  with `tools:node="remove"` — a coffee logbook has no business holding them.
  `test/manifest_test.dart` pins all of this.
- **Signing in is optional and must stay optional.** The app has always worked
  signed out. SQLite is the source of truth; Firestore is a backup, and a
  backup failure is never a save failure.
- **`schema/brew_schema.json` is the only place brew fields are defined.** The
  Worker and the app both read it. Never restate a field list in Dart or TS.
- **Bump `RUBRIC_VERSION` whenever a scoring number moves.** Every stored score
  records the rubric and model that produced it; leaving the version alone
  makes old scores silently wrong rather than merely old.
- **Photographs are licensed, and the licence has conditions.** Guide photos
  come from Wikimedia Commons under CC0, CC BY or CC BY-SA. NonCommercial and
  NoDerivatives are excluded: ND forbids the resize, NC binds the app.
  ShareAlike is fine — shipping a work inside an app distributes a
  *collection*, which does not put the app under the work's licence; the
  resized files in `assets/guides/` carry the obligation, never the code.
  Every photo must appear in `ASSET_CREDITS.md` **and** in Settings → Photo
  credits, because naming the author is a licence condition rather than a
  courtesy. `test/asset_credits_test.dart` fails the build if the images, the
  credits data and the document disagree.
- Every user-facing string goes through `AppStrings`, in both languages.
- The master logo is build-time only and must never enter `pubspec.yaml`.

## Things that only fail on a real phone

- **`flutter create` puts `INTERNET` in the debug and profile manifests only.**
  A release build then has no network while every test passes.
- **`flutter_local_notifications` stopped shipping its own receivers in v16.**
  The host app must declare `ScheduledNotificationReceiver` and
  `ScheduledNotificationBootReceiver` plus `RECEIVE_BOOT_COMPLETED`. Without
  the first, the alarm fires into nothing and a scheduled notification never
  appears — the daily reminder was dead in every build ever shipped while
  `reminder_schedule_test` stayed green, because the schedule maths is a pure
  function and was right all along. `test/manifest_test.dart` pins them now.
- **A colliding enum in `methodData` silently narrows.** `brewer` exists in
  three methods with different values; the union must merge them or the model
  is never offered the right one.
- **`ExpansionTile` keyed by `PageStorageKey` inside a `ListView`** makes the
  list read the tile's bool as its scroll offset.
- **SQLite's JSON1 extension is not guaranteed on Android.** Migrations that
  rewrite `methodData` do it in Dart.
- **HyperOS refuses every first-time install** unless "Install via USB" is on,
  with no prompt and a misleading error.

## Key files

- `schema/brew_schema.json` — the single source of truth.
- `worker/src/prompts.ts` — both prompts and all six rubrics. The opinionated
  part of the app.
- `lib/services/reminder_schedule.dart` — a pure function, so the day, month
  and year boundaries are unit tests rather than a day of waiting.
- `lib/widgets/follow_up_form.dart` — every field, grouped, nothing
  compulsory. `required` means "shown expanded", not "must answer".
- `lib/models/brew_entry.dart` — `brewDate` is when the coffee was brewed and
  `createdAt` is when it was written down. They are not the same column and
  must never be filled from the same clock: both were `now` at first, which
  silently threw away every "I brewed this yesterday". `copyWith` preserves
  the score; clearing it
  takes `clearScore: true`, because the default once ate scores on every edit.
- `lib/services/backup_service.dart` — the Firestore mirror. Push is keyed by
  the entry's uuid so it is idempotent, deleted rows are mirrored *as*
  deleted so a restore cannot empty the recovery page, and a newer local
  entry always wins a restore.
- `firestore.rules` — the actual security boundary. Client code is not one.
- `tool/check.sh` — the gate.
