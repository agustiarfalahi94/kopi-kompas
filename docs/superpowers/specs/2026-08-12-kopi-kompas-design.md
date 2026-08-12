# Kopi Kompas — design

A personal coffee-brewing logbook for Android. You describe a brew in your own
words, an AI turns it into structured fields, the app asks about anything it
could not find, and every shot is scored by rules that live in the app and can
be read out loud.

This document is the design agreed before any code existed. It records the
decisions and, more importantly, why the rejected options were rejected.

## 1. Stack

Flutter 3.41.6 · Dart 3.11.4 · `com.inkpebble.kopi_kompas` · v0.1.0+1 ·
Android-first, iOS kept buildable but not tuned.

**Packages**: `sqflite` (brew storage), `shared_preferences` (settings and the
install id), `flutter_local_notifications` (daily reminder), `intl` +
`flutter_localizations` (EN/ID), `timezone` (scheduling). Dev:
`flutter_lints`, `sqflite_common_ffi` (headless database tests).

No secure-storage package: there is no secret on the device to protect. The
install id is a random uuid that means nothing off-device, and the Gemini key
never leaves the Worker.

No HTTP package — the Gemini proxy is reached with `HttpClient` from
`dart:io`, the same way Tiny Tapsters talks to its Worker.

### Why Flutter and not React Native

The original brief called for React Native + Expo. It was reconsidered on the
merits, setting aside the fact that two other Android apps here are already
Flutter.

The case *for* React Native was real and specific: the Cloudflare Worker is
TypeScript no matter which framework wins, so RN would let one `zod` schema
serve as the app's static types, the runtime validator for Gemini's response,
and the JSON Schema sent to Gemini as `responseSchema`. Section 4's
`brew_schema.json` and its parity test exist only to reproduce that by hand
across a language boundary.

Flutter won on where this app's difficulty actually sits. Kopi Kompas is a
deterministic scoring engine, a schema-driven form, a SQLite table and a
nightly alarm. Almost nothing here is UI-hard, and the three components most
likely to carry bugs — scoring, date arithmetic, queries — all run headless on
a free CI runner in Flutter. `sqflite_common_ffi` executes real SQLite on the
runner; `expo-sqlite` does not run in Node, so the equivalent RN tests need
either an emulator in CI or an abstraction layer with a `better-sqlite3`
double. You would write scaffolding to test the thing instead of testing it.

Two smaller factors: `flutter build apk --release` produces a signed APK from
an ordinary runner, whereas the free RN path is `expo prebuild` plus gradle,
which means owning native-project regeneration in CI — and the managed
workflow's convenience is gone regardless, since SQLite, notifications and
secure storage all require native modules, so Expo Go could never run this
app. And `flutter_local_notifications` is one mature option, against an
`expo-notifications` that has churned repeatedly on Android permissions and
alarm behaviour.

A Flutter-logic / React-Native-UI hybrid was also considered and rejected.
They are not a logic layer and a view layer; both are complete frameworks that
own the rendering surface and the app lifecycle. Combining them ships two
runtimes in one APK and routes every score and every query through JS → RN
native module → Android → platform channel → Dart, with no shared type
checking across the seam.

**The accepted cost** is two languages. It is contained by keeping the Worker
deliberately stupid (section 3) — roughly a hundred lines that change twice a
year.

## 2. Data model

Core fields are columns, because they are what you filter and sort by.
Method-specific fields are a JSON blob, because there are eight different
shapes and a column per field would be a sparse table with sixty columns.

```
brews
  id              TEXT PRIMARY KEY   uuid v4
  brewMethod      TEXT NOT NULL      enum, see below
  beanOrigin      TEXT
  roastLevel      TEXT               light | medium | medium-dark | dark
  doseGrams       REAL
  grindSize       TEXT
  brewDate        TEXT NOT NULL      ISO-8601, local time with offset
  overallScore    INTEGER            0-100, null when the method is unscored
  notes           TEXT
  rawInputText    TEXT NOT NULL      what you actually typed, always kept
  methodData      TEXT NOT NULL      JSON object, shape keyed by brewMethod
  scoreReasons    TEXT               JSON array of strings, see section 5
  createdAt       TEXT NOT NULL      ISO-8601, never updated
  updatedAt       TEXT NOT NULL      ISO-8601
  deletedAt       TEXT               ISO-8601, null when live — see section 7
```

Indexes on `brewDate` (the list and the reminder's has-a-brew-today check) and
on `deletedAt` (every Home query filters it).

`brewDate` stores local time with its offset rather than UTC. "Did I log a
brew today?" is a question about the wall clock in front of you, and a shot
pulled at 00:30 belongs to the day you were awake for.

**Methods**: `espresso`, `v60`, `aeropress`, `frenchPress`, `kopiTubruk`,
`kopiJoss`, `kopiTalua`, `kopiKhop`. Their field shapes are in
`schema/brew_schema.json` (section 4), not duplicated here — a schema written
in two places is a schema that disagrees with itself.

## 3. The Cloudflare Worker

Every Gemini call goes through a Worker. **No API key ever enters the
repository or the APK.** The app ships a URL, which is not a secret, supplied
at build time by `--dart-define=KOPI_ENDPOINT=...` and defaulting to the
deployed proxy.

This mirrors Tiny Tapsters, which moved its key out of the APK for exactly
this reason. The alternative the brief proposed — you paste your own key into
Settings, held in secure storage — is defensible for a single user, but it
puts a key-handling surface in the app that has to stay correct forever, and
it cannot survive the APK being handed to a second person.

**The Worker owns the prompt and the schema; the app sends only text.** This
is a security boundary, not a layering preference. If the app could supply its
own prompt, anyone who read the URL out of the APK would have a free,
unmetered Gemini proxy.

```
POST /parse
  { "text": "...", "locale": "en" | "id", "installId": "<uuid>" }
  → 200 { "brewMethod": "espresso", "beanOrigin": "honduras", ... }
  → 400 unparseable request
  → 429 rate limited
  → 502 Gemini unreachable or returned non-JSON
```

The Worker calls Gemini 2.5 Flash with `responseMimeType: "application/json"`
and an explicit `responseSchema`, so JSON shape is enforced by the API rather
than requested politely in a prompt. It rate-limits per `installId` — a uuid
generated on first launch, stored locally, meaningless off-device — to bound
the damage if the URL leaks.

Anything Gemini returns that is not in the schema is dropped. In particular
**`overallScore` from the model is discarded unconditionally** on the Dart
side before a `BrewEntry` is constructed, even if a future prompt edit lets it
slip into the response. Scoring is section 5's job and nobody else's.

The system instruction tells the model to classify `brewMethod` first, extract
only fields belonging to that method, use `null` for anything absent or
unclear, and never infer a plausible value. A guessed dose is worse than a
missing one, because a missing one gets asked about.

## 4. One schema, three consumers

`schema/brew_schema.json` at the repository root is the single source of truth
for all eight method shapes. It is read by:

1. **The Worker**, to build Gemini's `responseSchema`.
2. **The app** (`lib/data/brew_schemas.dart`), to drive the follow-up form —
   which fields exist, which are required, and which keyboard each one gets.
3. **The entry detail and full log screens**, to render fields in a stable
   order with proper labels and units.

A test asserts all three cover exactly the same field set. Adding a brew
method is then one file edit rather than four places to forget, and the
failure mode of forgetting is a red test rather than a field that silently
never gets asked about.

Each field carries its type (`number`, `integer`, `string`, `boolean`,
`enum`), its unit, whether it is required for a complete entry, and its
label keys for EN and ID.

## 5. Scoring

Scored in v1: **espresso, V60, Aeropress**. These three have established
target ranges that can be defended. `frenchPress` and the four Indonesian
methods log every field and display **"not scored"** — kopi joss, talua and
khop have no agreed-upon correct parameters, and inventing deductions would
make the number meaningless while looking authoritative.

Scoring lives in `lib/services/scoring.dart` as pure functions. No I/O, no
clock, no network, no AI. It must be deterministic and explainable, which
rules out asking the model.

**A score is never returned alone.** Each scorer returns a value *and* the
reasons that produced it:

```
BrewScore(
  value: 82,
  factorsUsed: 3, factorsPossible: 5,
  reasons: [
    "Ratio 2.4:1 — 0.2 above the 1.8–2.2 target, −8",
    "Time 22s — 3s below the 25–32s window, −6",
    "Puck prep complete",
    "Water temperature not recorded",
  ],
)
```

The detail screen shows the reasons under the number. A score with no
argument attached is a score you cannot disagree with, and this one will be
wrong sometimes.

The shape, for all three methods: base 100, proportional deductions for
deviation outside a target range, a fixed deduction per puck-prep step **only
where it was explicitly stated as skipped**, then clamp to 0–100. A `null`
field deducts nothing and instead lowers `factorsUsed`, surfaced as "82, from
3 of 5 factors" — an unknown is not a fault, but it should be visible that the
number rests on less.

The v1 numbers are deliberately crude and expected to be tuned. What must not
change is that they are constants in Dart, covered by table-driven tests, and
never in a prompt.

**Scores are stored, not recomputed on read.** `overallScore` and
`scoreReasons` are written at save time and rewritten when an entry is edited.
Tuning the constants later therefore does not silently rewrite history: old
brews keep the score they were actually given, which is the only way a trend
means anything. A deliberate "rescore everything" action can be added when the
constants first change; it is not in v1.

## 6. Notifications

One daily reminder, default 08:00, configurable, skipped on days a brew is
already logged.

The brief suggested cancelling the day's notification when a brew is saved.
That does not work against a repeating schedule — you cannot cancel a single
occurrence of a recurring notification. Instead **a single notification id is
cancelled and rescheduled** on every app resume and after every save and
delete:

| State | Next fire |
|---|---|
| A brew exists for today | Tomorrow at T |
| No brew today, T still ahead | Today at T |
| No brew today, T already passed | Tomorrow at T |
| Reminder disabled | Nothing scheduled |

The decision is a pure function of `(now, reminderTime, hasBrewToday)`,
returning the next fire time. It takes an injected clock, so every branch —
including the day-boundary and daylight-shift cases — is a unit test rather
than a thing you wait a day to observe.

Scheduling is **inexact**, so the app needs no `SCHEDULE_EXACT_ALARM`
permission. A logbook nudge does not need to land on the second.
`POST_NOTIFICATIONS` is requested on Android 13+ behind a short screen that
says what the notification is for, on first launch. Declining is a supported
state: the app works, Settings shows the reminder as unavailable with a route
to system settings.

## 7. Screens

**Home** — reverse-chronological list of live entries. Each row: method icon,
bean origin, score, date and time. Tap opens the detail. This is the everyday
surface, and it stays sparse.

**New entry** — a free-text box (dictation via the native keyboard mic; no
custom speech recognition), a submit button, a loading state while the Worker
call runs, then the follow-up form for every field the parse returned as
`null`, then Save. The form renders one field per row with the input type the
schema declares: number pad for grams and seconds, dropdown for roast level
and puck-prep booleans, plain text for origin and machine. Espresso's
`machine` is pre-filled from the Settings default when one is set, rather than
asked every time.

Failure is a first-class path. A Worker that is unreachable, rate-limited or
returns nonsense must not lose what you typed: the raw text is preserved, the
error is stated plainly, and you can retry the parse or fill the form by hand.

**Entry detail** — every field for one brew, the score with its reasons, and
edit and delete. Editing recomputes the score.

**Full log** — the complete archive, described in section 8.

**Settings** — reminder time and toggle, default espresso machine, language.
**No API-key field**: the key lives in the Worker.

## 8. The full log

A dedicated page holding **everything entered since day one**, distinct from
Home in both content and appearance.

Where Home is a scannable summary of live entries, the full log is the record:
every entry, in chronological order, each one expanded to show all of its
fields — core, method-specific, the score with its reasons, and the original
`rawInputText` verbatim, so what you actually said is always recoverable next
to what the AI made of it. It is **read-only**; editing happens in the detail
screen.

It is styled as an archive rather than a second Home: a muted, low-contrast
palette, dense type, no icons or score colouring competing for attention. The
visual difference is doing real work — it should be obvious at a glance which
of the two screens you are looking at.

**Deleted entries remain here**, marked as deleted with their date, which is
what `deletedAt` is for. Deleting from the detail screen is a soft delete: the
entry leaves Home, leaves the score statistics and stops blocking the daily
reminder, but the record of having written it survives. "Since day one" is
taken literally. A hard delete is available from the full log for entries that
genuinely should not exist.

> **Flagged for review.** Two readings of the request were possible: a
> full-detail browsable archive, or an audit trail of raw text submissions.
> This design is the first, with `rawInputText` included so it also answers
> the second. Soft delete is an inference from "since day one" and is cheap to
> drop — one column and one filter — if the record surviving deletion is not
> wanted.

## 9. Internationalisation

English and Bahasa Indonesia from the start, via ARB files and
`flutter gen-l10n`, as in Random Recall. Half of the brew methods are
Indonesian; shipping this English-only and retrofitting would mean touching
every screen twice.

A test asserts key parity between `app_en.arb` and `app_id.arb`. Brew-method
and field labels come from `brew_schema.json`, so a new method's translations
are added in the same edit as the method itself.

The Worker receives the locale and instructs the model accordingly, so
Indonesian free text parses as well as English — `"kopi tubruk, 20g, gula satu
sendok"` should not need to be written in English to be understood.

## 10. Testing

`tool/check.sh` is the gate, mirroring Tiny Tapsters: it runs analyze, format
and the tests, then prints the app name, version, package id, scored-method
count and git remote **read from the files**. A summary can be invented; a
pasted run of this cannot.

| Test | Covers |
|---|---|
| `scoring_test.dart` | Table-driven cases per scored method: in-range, both edges, far out, all-null, explicit skips, clamping |
| `schema_test.dart` | `brew_schema.json` parity across the Worker, the Dart model and the form; every field has EN and ID labels |
| `parser_test.dart` | The client against a real local HTTP server: valid parse, malformed JSON, unknown method, missing fields, 429, timeout, and that a model-supplied `overallScore` is discarded |
| `database_test.dart` | `sqflite_common_ffi`: insert, query, soft delete, the has-a-brew-today check across a day boundary, schema migration |
| `reminder_test.dart` | The next-fire function against a fake clock, all four rows of section 6's table |
| `l10n_test.dart` | EN/ID key parity |
| `docs_test.dart` | The load-bearing facts in README/AGENTS.md/CLAUDE.md: app name, package id, version, scored-method count, and that no document ever claims the Gemini key ships in the APK |
| `widget_test.dart` | Every screen builds; the follow-up form renders the input type each schema field declares; the full log is visually distinct and read-only |

## 11. Repository and CI

`agustiarfalahi94/kopi-kompas`, private, matching the other two.

- `develop` is the default branch and where work lands.
- Features and fixes go on a dedicated branch off `develop`, never directly on
  it.
- Release: merge `develop` → `main` locally, push `main`, annotated tag
  `vX.Y.Z`, push the tag.

CI runs on pull requests to `develop` and `main`, and on `v*` tags — not on
plain pushes, exactly as Tiny Tapsters does. A tag build runs analyze, format
and tests, signs with the shared release keystore, and attaches the APK to the
GitHub Release.

Secrets, copied from Tiny Tapsters: `KEYSTORE_BASE64`, `STORE_PASSWORD`,
`KEY_PASSWORD`, `KEY_ALIAS`. Plus a repository *variable* `KOPI_ENDPOINT`
holding the Worker URL.

Signing reuses the keystore shared with `random_recall` and `tiny_tapsters`;
the package id keeps the apps distinct. `android/key.properties` and
`android/app/release-keystore.jks` are git-ignored and must never be
committed.

## 12. Documentation

`README.md`, `AGENTS.md` and `CLAUDE.md` (the last two kept in sync, enforced
by `docs_test.dart`), `CHANGELOG.md`, `worker/README.md` for one-time Worker
setup, and this specs directory.

## 13. Out of scope for v1

Charts, trends and statistics · cloud sync, accounts, multi-user · scoring for
`frenchPress` and the four Indonesian methods · iOS polish · Play Store
release · photos of the cup.

The first fast-follow is expected to be scoring for the remaining methods,
which section 4's schema and section 5's pure functions are shaped to accept
without restructuring.
