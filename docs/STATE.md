# Where this project actually is

**Read this before doing anything.** `CLAUDE.md` says how to work here and the
spec says why things are the way they are. This file says what is true *right
now* — what is unmerged, what has never been run on a phone, and which bugs
have already been paid for once.

Keep it current. A stale state file is worse than none, because it is believed.

Last updated: 2026-08-13, after cutting v0.4.0.

---

## Right now

| | |
|---|---|
| Version | `0.4.0+5` — see `pubspec.yaml`, which is the arbiter |
| Latest GitHub release | **v0.4.0**, cut 2026-08-13; `main` and `develop` are level |
| Working branch | `feature/localized-reminder-notification` (off `develop`) |
| Worker deployed | rubric `r3`, verified live |
| App tests | run `./tool/check.sh` for the real number; never quote one from here |

**Unmerged work:**
- `feature/localized-reminder-notification`: notification title/body now follow the active language setting (`AppStrings`) and reschedule on language switch.

v0.4.0 carries everything that had accumulated on `develop` since v0.3.0:

- the filter chip no longer draws a ✕ it cannot honour
- editing announces the new score instead of changing it silently
- guide photos keep their own shape instead of being cropped to a box
- better photos for espresso, siphon, cold brew and kopi saring
- every document brought back in line with what ships
- Settings shows which build it is
- **the daily reminder can fire at all** — see the ledger below

**v0.4.0 was cut on light testing, by the user's decision.** They had tried
some of it and what they tried worked; the list under "Never verified on a
phone" was *not* worked through first. So this tag ships the reminder fix
unobserved, and sign-in and backup still unproven on hardware.

Cutting a release: merge `develop` → `main`, push, annotated tag `vX.Y.Z`,
push the tag. CI builds and attaches the APKs. Only on the user's say-so.

---

## Never verified on a phone

The single most important section. This project has shipped four features that
passed every test and were dead on the device.

- **Signing in** — Google, email, phone. Built in v0.2.0, never once run on
  hardware.
- **Cloud backup and restore** — same. The uninstall-and-restore test is the
  one that matters and the one nobody has done.
- **The daily reminder** — could not physically fire until 2026-08-13. Now
  fixed, still never observed working.
- **The brew timestamp** — verified against the deployed Worker with curl,
  never on a phone. The phone sends its own clock, so a timezone mistake would
  only show there.

There is a checklist for all of this, in the order it should be run, at
`docs/DEVICE_TESTS.md`.

---

## Open threads

- **Kopi talua has no photograph.** Neither Wikimedia Commons nor Openverse
  has a freely licensed one; the only near-matches are `teh talua`, which is
  the tea. Needs a photograph the user takes.
- **The kopi khop photograph is filed on Commons as `Kupi Tubrôk.JPG`.** The
  image plainly shows the inverted-glass serve, which is kopi khop by
  definition, so it is used for that. The original title is in
  `ASSET_CREDITS.md` so anyone can check. Unresolved with the user.
- **Ten of the sixteen guides have never been reviewed by the user.** Tubruk,
  saring, joss, talua, khop, ibrik, siphon, French press, cold brew and smart
  dripper were written from general knowledge with no rubric anchoring them.
  The user has already found two problems in that text.
- **Old scores are `r2`, new ones `r3`.** Every row records which produced it,
  so nothing is silently wrong, but a pressurised-basket shot scored before
  2026-08-13 is not comparable to one scored after. There is no bulk rescore.
- **Commits up to and including the `v0.4.0` tag carry `your@email.com`.** The
  global git email was a placeholder until 2026-08-13; it is now the GitHub
  noreply address, so commits from here on attribute correctly. The earlier
  ones are not being rewritten — the history is pushed and `v0.4.0` is tagged
  on it, and rewriting a published tag costs more than a wrong author field.

---

## Bug ledger

Every one of these passed the test suite at the moment it was wrong. That is
the point of the list: it is a record of what a green suite does not prove.

### Found only on a real phone

| Bug | Why tests missed it | Fix |
|---|---|---|
| Release builds had no `INTERNET` permission | Flutter's template declares it in the debug and profile manifests only; every test runs debug | Declared in the main manifest; `manifest_test.dart` pins it |
| **The daily reminder could never fire** | `flutter_local_notifications` stopped contributing its broadcast receivers in v16. The schedule maths is a pure function and was correct all along, so its tests passed while the alarm fired into an app with nothing registered to receive it | Declared `ScheduledNotificationReceiver`, `ScheduledNotificationBootReceiver` and `RECEIVE_BOOT_COMPLETED`; `manifest_test.dart` pins them |
| An untouched switch reported nothing rather than `false` | The test that claimed to cover it tapped the switch twice, returning it to its original state | Booleans seeded `false`, and the form reports on first build |
| `ExpansionTile` keyed by `PageStorageKey` inside a `ListView` | Nothing in a widget test reads a scroll offset | `ValueKey` instead |
| Release build failed only at `assembleRelease` | Desugaring is not needed for debug | `coreLibraryDesugaring` enabled |
| HyperOS refuses every first-time install | Not a code problem at all | Turn on "Install via USB" |

### Found by reading output instead of assuming

| Bug | Why tests missed it | Fix |
|---|---|---|
| `responseSchema` corrupted every parse — `beanOrigin: "doseGrams"` | Worker tests use a fake Gemini, so the real constrained decoder was never exercised | Every property both `required` and `nullable` |
| A colliding enum let the last method win, so a V60 came back as `brewer: "switch"` | Each method's schema was correct in isolation | Union the enum values, then strip foreign ones per method |
| `copyWith` erased scores on every edit | No test rated a scored brew | Score fields preserved; dropping them needs `clearScore: true` |
| `brewDate` and `createdAt` were both `now`, so a stated brew time was thrown away | Both columns were populated and non-null | The Worker extracts `brewedAt`; the app falls back to now |
| Field labels froze in English | `main()` parsed the schema before reading the stored language | `Labelled` mixin resolves at read time |
| Dropdowns rendered raw ids (`kalitaWave`) for weeks | The "fix" was an edit whose anchor no longer existed, so it silently did nothing | Fixed, and a test asserts every screen formatting a value calls `valueLabel` |
| A pressurised basket was marked down for skipping WDT | The rubric was internally consistent; it was just wrong about espresso | Puck prep weighted by `basketType`; rubric `r3` |
| The gate printed "PASS" over a tree that could not compile | `check.sh` ran vitest, which transpiles without typechecking | `tsc --noEmit` added to the gate, and proven to fail |
| The espresso guide advised better distribution for channelling | Guide text and rubric text were never compared | Guide aligned with `r3`; targets already come from `brew_schema.json` |
| Reminder notification fired in English regardless of language | Title and body were hardcoded constants in ReminderService and reschedule() wasn't called on language change | Read title and body from `AppStrings` and reschedule on language switch |

### Process failures worth not repeating

- **A string replacement that matches nothing fails silently.** This has
  happened four times, twice hiding a bug the user had already reported.
  Assert the anchor exists, then check the result.
- **Committing off a `grep` instead of the gate's exit code** let a failing
  analyze through three times. Use `if ./tool/check.sh; then …; fi`.
- **Five APKs went out in one day all reporting `0.3.0+4`**, release-signed
  with the same keystore, with different code inside. Settings now shows the
  commit; build with `tool/build_apk.sh`, which stamps it.
- **A tagged release was cut on a commit that could not compile** (`v0.2.0`).
  The tag remains in the history as a build that failed; `v0.2.1` is the real
  one.

---

## What the user cares about

- **Short answers, plain words.** They have asked twice. Long explanations get
  called out.
- **Natural Indonesian, not stiff translations.** Method and category names
  stay in English on purpose.
- **They test on the device and report back by number.** They will not read a
  wall of text about what to test.
- **They decide releases.** Do not tag, merge to `main`, or deploy the Worker
  without being asked.
