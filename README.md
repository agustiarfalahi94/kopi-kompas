# Kopi Kompas — a coffee-brewing logbook

Describe a coffee you just made in your own words. An AI turns it into
structured fields, the app shows you everything it holds so you can fill in
what it missed, and the finished entry is scored out of 100 against a written
rubric — with the reasons shown next to the number.

Android-first, Flutter, `com.inkpebble.kopi_kompas`, v0.4.1+6.
English and Bahasa Indonesia.

## What it does

**Type or dictate.** *"18g in, 36g out in 28 seconds on the gaggia, honduras
medium roast, no wdt today, tamped"* becomes an espresso with its dose, yield,
time, machine, origin and roast filled in — and `wdt: false`, because saying
you skipped a step is different from not mentioning it.

**Fill in the rest, or don't.** The form shows every field the method has,
grouped into coffee, grind, brew and water, pre-filled from the parse and from
what it remembered last time. Nothing is compulsory: leave all of it blank and
the entry still saves.

**Get a score you can argue with.** Six methods are scored — espresso and the
four filter methods, plus AeroPress — each against explicit target ranges. The
reasons are always shown, because a number with no argument attached is a
number you cannot disagree with, and this one will sometimes be wrong. Rate it
yourself 1–5 afterwards; over months, that is the only way to find out whether
the rubric matches your palate.

**16 brew methods in 5 categories.** Espresso · Filter coffee (cone dripper,
flat-bottom dripper, Chemex, batch brewer) · Immersion (French press, cold
brew, Turkish) · Hybrid (AeroPress, smart dripper, siphon) · Indonesian (kopi
tubruk, saring, joss, talua, khop).

Variants are fields, not methods: a ristretto is an espresso with a shot
style, a V60 is a cone dripper with a brewer. That is what lets the rubric
judge the ratio instead of assuming it from the name.

**Say when you brewed it.** *"kopi tubruk kemarin sore"* is filed under
yesterday evening, not the moment you typed it. `brewDate` is when the coffee
was made; `createdAt` is when it was written down, and they are different
columns for a reason.

**Find it again.** Search and filter on both the log screens. Typing matches
what the fields hold, the method's own name, and the words you originally
wrote — so "gula aren" finds the brew you mentioned it in even though no field
stores it. The filter stays applied while you open a brew and come back.

**A how-to guide for every method.** Bilingual, with gear at three price
tiers, a troubleshooting table and a photograph for fifteen of the sixteen.
The target numbers come from the same file the rubric reads, so following a
guide cannot cost you points.

**A daily reminder that knows when to stay quiet.** It only fires on days you
have not logged anything.

**Optional sign-in, and a backup you can survive a factory reset with.**
Google, email or phone. The app has always worked signed out and must keep
doing so: SQLite is the source of truth, Firestore is a mirror, and a backup
that fails is never a save that fails.

## Where the API key lives

**In Cloudflare, never in this repository and never in the APK.** The app
ships a Worker URL, which is not a secret; the Gemini key it stands in front
of is, and it is a Worker secret. See `worker/README.md`.

## Architecture & Security

Kopi Kompas is local-first: SQLite is the source of truth and Firestore is an
optional authenticated mirror. The AI path is deliberately server-side:

```text
Flutter app → Cloudflare Worker → Gemini API
                  ↘ KV rate limit
```

The Worker owns the prompts, response schemas and rubric. `GEMINI_API_KEY` is
stored as a Cloudflare secret and never enters the repository, APK or client
request. The app sends an opaque install ID only for abuse control. Worker
inputs are bounded, malformed responses are rejected, and rate-limit or
upstream failures are returned as typed errors instead of being treated as a
successful brew save.

Firestore rules deny access by default and allow a signed-in user to read or
write only their own `/users/{uid}` tree, with a per-document size cap. The
same rules are the access boundary; client-side checks are not authorization.

Local development uses a git-ignored `worker/.dev.vars` file. Production
deployment uses `wrangler secret put GEMINI_API_KEY`. `KOPI_ENDPOINT` is a
public Worker URL and may be supplied through `--dart-define` or a GitHub
Actions variable; it is not a secret.

Pull requests run Flutter analysis, formatting, Flutter tests, Worker type
checks and Worker tests. Tagged releases restore Firebase configuration and
signing material from GitHub Actions secrets, verify that no Gemini key is
tracked, then build signed APKs.

## Run it

```sh
flutter run
./tool/check.sh                       # analyze, format, tests, typecheck, facts
flutter build apk --release --split-per-abi
adb install -r build/app/outputs/flutter-apk/app-arm64-v8a-release.apk
```

A fat APK is about 55 MB, most of it three CPU architectures of the Flutter
engine. `--split-per-abi` gives the ~21 MB arm64 build a modern phone needs,
of which about 1 MB is the guide photographs.

Release builds are signed with the keystore shared with `random_recall` and
`tiny_tapsters`. `android/key.properties` and `android/app/release-keystore.jks`
are git-ignored and must never be committed.

## How it is put together

| | |
|---|---|
| `schema/brew_schema.json` | Every method and field, read by **both** the app and the Worker |
| `worker/` | Cloudflare Worker holding the Gemini key; owns both prompts and the rubric |
| `lib/data/brew_schema.dart` | Loads the schema; drives the form, the detail view and the log |
| `lib/services/brew_database.dart` | sqflite; core fields as columns, method fields as a JSON blob |
| `lib/services/kopi_client.dart` | The two Worker calls, with every failure typed |
| `lib/services/reminder_schedule.dart` | When the reminder fires — a pure function, so it is testable |
| `lib/widgets/follow_up_form.dart` | The grouped, entirely optional form |
| `lib/services/log_filter.dart` | What the log is showing — a value object, so matching is testable without a widget |
| `lib/services/backup_service.dart` | The Firestore mirror: idempotent by uuid, deletions mirrored, newest wins |
| `lib/data/guide_photo.dart` | Each guide photo with the attribution its licence requires |
| `firestore.rules` | The actual security boundary. Client code is not one |
| `tool/check.sh` | The gate: analyze, format, Flutter tests, Worker tests, Worker typecheck, then the facts read from the files |
| `ASSET_CREDITS.md` | Every photograph, its photographer and its licence |
| `docs/superpowers/specs/` | Why things are the way they are |

## Deciding anything about this project

Read `docs/superpowers/specs/2026-08-12-kopi-kompas-design.md`. It records the
decisions **and the rejected alternatives**, including why Flutter over React
Native, why the Worker owns the prompt, why variants are fields, and why the
score is stored rather than recomputed. Section 15 covers everything decided
after v1 shipped — accounts, guides, photographs, the brew timestamp and the
basket split that forced rubric `r3`.
