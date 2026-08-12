# Kopi Kompas — design

A personal coffee-brewing logbook for Android. You describe a brew in your own
words, an AI turns it into structured fields, the app asks about anything it
could not find, and the finished entry is scored out of 100 against a written
rubric — with the reasons shown next to the number.

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

Flutter won on where this app's difficulty actually sits. Kopi Kompas is two
network clients, a schema-driven form, a SQLite table and a nightly alarm.
Almost nothing here is UI-hard, and the components most likely to carry bugs —
the parse and score clients with their failure states, date arithmetic, and
queries — all run headless on a free CI runner in Flutter, the clients against
a real local HTTP server. `sqflite_common_ffi` executes real SQLite on the
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
  notes           TEXT
  rawInputText    TEXT NOT NULL      what you actually typed, always kept
  methodData      TEXT NOT NULL      JSON object, shape keyed by brewMethod
  overallScore    INTEGER            0-100, null unless scoreStatus = scored
  scoreReasons    TEXT               JSON array of strings, see section 5
  scoreStatus     TEXT NOT NULL      scored | notApplicable | pending | failed
  scoreRubric     TEXT               rubric version that produced the score
  scoreModel      TEXT               model id that produced the score
  scoredAt        TEXT               ISO-8601
  createdAt       TEXT NOT NULL      ISO-8601, never updated
  updatedAt       TEXT NOT NULL      ISO-8601
  deletedAt       TEXT               ISO-8601, null when live — see section 8
```

Indexes on `brewDate` (the list and the reminder's has-a-brew-today check) and
on `deletedAt` (every Home query filters it).

`scoreRubric` and `scoreModel` are not bookkeeping for its own sake — see
section 5. A score produced by an AI is only comparable to another score
produced by the same rubric and the same model, and if that pairing is not
recorded the history degrades without ever looking wrong.

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

POST /score
  { "entry": { ...all core and method fields... },
    "locale": "en" | "id", "installId": "<uuid>" }
  → 200 { "score": 82, "reasons": [...], "rubric": "r1",
          "model": "gemini-3.6-flash" }

both → 400 unparseable request
       429 rate limited
       502 Gemini unreachable or returned non-JSON
```

`/score` is called only for espresso, V60 and Aeropress; the app does not
spend a request on a method it will display as unscored.

The Worker calls Gemini 3.6 Flash with `responseMimeType: "application/json"`
and an explicit `responseSchema`, so JSON shape is enforced by the API rather
than requested politely in a prompt. It rate-limits per `installId` — a uuid
generated on first launch, stored locally, meaningless off-device — to bound
the damage if the URL leaks.

Anything Gemini returns that is not in the schema is dropped. In particular
**a score in a `/parse` response is discarded unconditionally** — parsing
extracts fields and nothing else, and a score arrives only from `/score`,
after the entry is complete. The two calls stay separate so a re-parse can
never quietly change a score.

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

**Gemini scores the brew.** There is no local rule-based scorer — not as a
primary path and not as an offline fallback. One scoring path means there is
never a question about which number is the real one.

Scored in v1: **espresso, V60, Aeropress**. `frenchPress` and the four
Indonesian methods log every field and display **"not scored"**
(`scoreStatus = notApplicable`) and never trigger a scoring call at all. The
reason is unchanged by the move to AI: kopi joss, talua and khop have no
agreed-upon correct parameters, so a number against them would be confidently
invented rather than assessed.

### The flow

Scoring runs **after** the follow-up form is complete, not as part of parsing.
It has to: it judges the finished entry, including the fields you filled in by
hand.

1. You complete the follow-up form and tap Submit.
2. A loading animation runs while the Worker calls Gemini with every field,
   your notes, and the original raw text.
3. The score appears with its reasons. **At 90 or above, confetti.**
4. The entry is written to SQLite with the score attached.

This is a second Gemini call per entry, separate from the parse. It cannot be
merged into the first one, because the first runs before the gaps are filled.

### Making an AI score as stable as it can be

An LLM is not deterministic. The same espresso submitted twice can score 78
and 86, and since a logbook exists largely to compare your own shots over
time, that noise is the real cost of this decision. Four things bound it:

- **Temperature 0** on the scoring call.
- **A fixed written rubric** in the Worker — explicit target ranges and
  weights per method, so the model applies a stated standard rather than its
  own taste. The rubric is versioned (`r1`, `r2`, …).
- **`responseSchema`** constraining output to an integer 0–100 plus a reasons
  array. The Dart side rejects anything outside that range rather than
  clamping it, and treats the response as failed.
- **`scoreRubric` and `scoreModel` stored on every row.** When the rubric is
  revised or the model changes, past scores stay readable as what they were.
  Comparing an `r1` score against an `r2` score is comparing two different
  measurements, and the database should be able to say so.

### Reasons are not optional

The model returns the score *and* the reasons for it, and the detail screen
shows them under the number:

```
82
  Ratio 2.4:1 — above the 1.8–2.2 target for a normal shot
  Time 22s — short for this ratio, suggesting a coarse grind
  Puck prep complete: WDT, distribution and tamp
  Water temperature not recorded
```

A score with no argument attached is one you cannot disagree with, and this
one will be wrong sometimes. Reasons are also the only way to notice the
rubric drifting.

### Failure never blocks saving

If the Worker is unreachable, rate-limited, or returns something invalid, the
entry **still saves**, with `scoreStatus = failed` and every field intact. The
detail screen offers "Score this brew" to retry. `pending` covers the window
between save and a returned score.

Scores are stored, never recomputed on read. Revising the rubric therefore
does not silently rewrite history. A deliberate "rescore" action on a single
entry is available from the detail screen; a bulk rescore is not in v1.

## 6. Notifications

One daily reminder, default 08:00, configurable, skipped on days a brew is
already logged.

The brief suggested cancelling the day's notification when a brew is saved.
That does not work against a repeating schedule — you cannot cancel a single
occurrence of a recurring notification. Instead **a single notification id is
cancelled and rescheduled** on every app resume and after any change to
today's entries — save, delete or restore:

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

**New entry** — three stages on one screen.

*Describe.* A free-text box (dictation via the native keyboard mic; no custom
speech recognition) and a submit button, with a loading state while `/parse`
runs.

*Fill the gaps.* The follow-up form, one row per field the parse returned as
`null`, each with the input type the schema declares: number pad for grams and
seconds, dropdown for roast level and puck-prep booleans, plain text for
origin and machine. Espresso's `machine` is pre-filled from the Settings
default when one is set, rather than asked every time.

*Score.* Submitting the completed form runs a loading animation while
`/score` works, then reveals the number with its reasons — **confetti at 90 or
above** — and writes the entry. For the five unscored methods this stage is
skipped entirely: the entry saves immediately and reads "not scored".

Failure is a first-class path at both stages. A Worker that is unreachable,
rate-limited or returns nonsense must never lose what you typed. A failed
parse keeps the raw text and lets you retry or fill the form by hand; a failed
score still saves the entry, marked `failed`, retryable from the detail
screen.

**Entry detail** — every field for one brew, the score with its reasons, and
edit and delete. Editing re-runs scoring; "Score this brew" appears when the
status is `failed`.

**Full log** — the archive of live entries, described in section 8.

**Settings** — reminder time and toggle, default espresso machine, language,
and a route to **Deleted entries**. **No API-key field**: the key lives in the
Worker.

**Deleted entries** (inside Settings) — soft-deleted brews with the date each
was deleted, offering restore and permanent delete. It sits here rather than
in the main navigation because it is a recovery tool, not somewhere you
browse.

## 8. The full log

A dedicated page holding **every live entry since day one**, distinct from
Home in both content and appearance.

Where Home is a scannable summary, the full log is the record: every entry in
chronological order, each expanded to show all of its fields — core,
method-specific, the score with its reasons, and the original `rawInputText`
verbatim, so what you actually said stays recoverable next to what the AI made
of it. It is **read-only**; editing happens in the detail screen.

It is styled as an archive rather than a second Home: a muted, low-contrast
palette, dense type, no icons or score colouring competing for attention. The
visual difference is doing real work — it should be obvious at a glance which
of the two screens you are looking at.

**Deleted entries do not appear here.** They live on their own page inside
Settings (section 7). Deleting is a soft delete: the entry leaves Home, leaves
the full log, and stops counting for the daily reminder's has-a-brew-today
check, but the row survives with `deletedAt` set and can be restored or purged
from that page. The archive stays a record of your brewing, not of your
edits.

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
| `scoring_test.dart` | The score client and its state machine: a valid score stored with rubric and model; out-of-range, non-integer and missing-reasons responses rejected as `failed`; the five unscored methods never issuing a request; retry moving `failed` → `scored`; the confetti threshold firing at 90 and not at 89 |
| `schema_test.dart` | `brew_schema.json` parity across the Worker, the Dart model and the form; every field has EN and ID labels |
| `parser_test.dart` | The client against a real local HTTP server: valid parse, malformed JSON, unknown method, missing fields, 429, timeout, and that a score appearing in a parse response is discarded |
| `database_test.dart` | `sqflite_common_ffi`: insert, query, soft delete and restore, deleted rows absent from Home and the full log but present on the Deleted page, the has-a-brew-today check across a day boundary and ignoring deleted entries, schema migration |
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

## 12. Branding

The mark is coffee beans arranged as an eight-point compass rose — the name,
drawn. Master artwork lives at `assets/branding/kopi-kompas-logo.png`
(2000×2000, RGB, no alpha), with an alternate at `-alt.png`.

**The master is build-time only and must never be listed in `pubspec.yaml`.**
Nothing derived from it belongs in git either, beyond the generated icon
resources themselves. This mirrors Tiny Tapsters, where a 1 MB master shipped
inside the APK for several releases before anyone noticed.

Two constraints on anything derived from it:

- **Launcher icons use the compass mark alone.** The wordmark occupies the
  bottom third of the master and is illegible at 48 dp. The mark is cropped
  and padded to sit inside the adaptive-icon safe zone — the centre 66 of 108
  units — with the tan as the background layer and the compass as the
  foreground, so the system can mask it to any shape without clipping a point
  off the star.
- **The stray superscript "R" above "Kompas" is a generation artifact**, not a
  trademark claim. The master keeps it; everything derived crops it out. Worth
  regenerating the source eventually.

The palette is taken from the logo and drives both themes: tan `#DDBC8E`, mid
brown `#9A6B4A`, dark brown `#5A3825`, bean `#2E1A0F`. The full log's muted
archive treatment (section 8) is a desaturated variant of the same ramp rather
than a separate palette.

## 13. Documentation

`README.md`, `AGENTS.md` and `CLAUDE.md` (the last two kept in sync, enforced
by `docs_test.dart`), `CHANGELOG.md`, `worker/README.md` for one-time Worker
setup, and this specs directory.

## 14. Out of scope for v1

Charts, trends and statistics · cloud sync, accounts, multi-user · scoring for
`frenchPress` and the four Indonesian methods · bulk rescore after a rubric
revision · offline scoring of any kind · iOS polish · Play Store release ·
photos of the cup.

The first fast-follow is expected to be scoring the remaining five methods.
Nothing structural blocks it: it is a rubric written for those methods and a
change to which methods call `/score`.
