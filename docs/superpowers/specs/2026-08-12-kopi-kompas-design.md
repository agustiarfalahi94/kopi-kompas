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
Method-specific fields are a JSON blob, because there are sixteen different
shapes and a column per field would be a sparse table nobody could query.

```
brews
  id              TEXT PRIMARY KEY   uuid v4
  brewMethod      TEXT NOT NULL      enum, see below
  beanOrigin      TEXT
  roastLevel      TEXT               light | medium | medium-dark | dark
  doseGrams       REAL
  grindSize       TEXT
  brewDate        TEXT NOT NULL      local wall clock, no zone — see below
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

`brewDate` stores the **local wall-clock time with no zone suffix**, rather
than a UTC instant. "Did I log a brew today?" is a question about the wall
clock in front of you, and a shot pulled at 00:30 belongs to the day you were
awake for — stored as an instant it would file under the previous day for
anyone east of Greenwich.

This originally read "local time with its offset", which Dart cannot do: a
`DateTime` is either UTC or device-local and carries no offset, so
`DateTime.parse('...+07:00').toIso8601String()` returns the UTC form. The
model converts any UTC value to local before writing, and `hasBrewOn` buckets
on the first ten characters of the stored string.

Methods and their field shapes live in `schema/brew_schema.json` (sections
2a and 4), not here — a schema written in two places is a schema that
disagrees with itself.

## 2a. Brew taxonomy

Sixteen methods in five categories. Categories exist for navigation and to
group rubrics; a method belongs to exactly one.

```
Espresso        espresso            shotStyle: ristretto | normale | lungo

Filter coffee   coneDripper         brewer: v60 | origami | kono
                flatBottomDripper   brewer: kalitaWave | staggX | orea | april
                chemex
                batchBrewer

Immersion       frenchPress · coldBrew · turkishIbrik

Hybrid          aeropress · smartDripper (clever | switch) · siphon

Indonesian      kopiTubruk · kopiSaring · kopiJoss · kopiTalua · kopiKhop
```

**Variants are fields, not methods.** `shotStyle` and `brewer` shift the
rubric's target ranges rather than duplicating a field set. Ristretto,
espresso and lungo differ only in the ratio being aimed at (~1:1, ~1:2, ~1:3);
made separate methods, three near-identical schemas would need maintaining and
— worse — the ratio would stop being something the rubric could judge, because
it would be implied by the method name instead of measured against a target.
The same reasoning collapses V60, Origami and Kono into `coneDripper`, and
Kalita Wave, Stagg [X], Orea and April into `flatBottomDripper`.

**Kopi luwak is a bean, not a method.** It is a value in `process`, alongside
wet-hulled (*giling basah*), because you brew a V60 *with* luwak beans — as a
method it would make that unrecordable.

Two deliberate imperfections, recorded so they are not re-litigated. **Turkish
coffee is decoction, not immersion** — boiled with the grounds left in the cup
— which makes it a closer cousin to kopi tubruk than to a French press; it
sits in Immersion because a category of one for it would be worse. And
**every category except Indonesian is defined by technique, while Indonesian
is defined by culture**, so kopi saring — a cloth pour-over — sits apart from
Filter. That is the right call for a personal logbook, at the cost of "show me
all my filter brews" not including it.

Chemex is separated from `coneDripper` despite being conical: the split is on
filter thickness, which genuinely changes the grind and time targets, not on
geometry.

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

`/score` is called only for the six scored methods; the app does not spend a
request on a method it will display as unscored.

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
for the categories, the sixteen methods and their field shapes. It is read
by:

1. **The Worker**, to build Gemini's `responseSchema`.
2. **The app** (`lib/data/brew_schemas.dart`), to drive the follow-up form —
   which fields exist, which are required, and which keyboard each one gets.
3. **The entry detail and full log screens**, to render fields in a stable
   order with proper labels and units.

A test asserts all three cover exactly the same field set. Adding a brew
method is then one file edit rather than four places to forget, and the
failure mode of forgetting is a red test rather than a field that silently
never gets asked about. Adding a *dripper* is smaller still — one value in a
`brewer` enum.

Each field carries its type (`number`, `integer`, `string`, `boolean`,
`enum`), its unit, whether it is required for a complete entry, and its
label keys for EN and ID.

### Every field is shown; nothing is compulsory

The follow-up form shows **all** of a method's fields, pre-filled with whatever
the parse found, and **Save works no matter how many are blank**. The only
thing that must be known is the brew method, and only because it decides which
fields exist.

This reverses an earlier decision, and the reason is worth keeping. The
original design asked only for missing *required* fields and never mentioned
the rest, on the grounds that a form which interrogates you after every shot
is a form you abandon. That was half right. The other half: **a field you are
never shown is a field you do not know exists.** Optional-and-invisible is
indistinguishable from absent, which is precisely what would have happened to
`grinder` — the single most useful field for ever reproducing a good brew, and
one nobody mentions when they type "espresso this morning".

So `required` is redefined. It no longer means "you must answer this"; it
means **"show this expanded, above the fold"**. Everything else is one tap
away in a collapsed group, which is what makes it discoverable.

Scoring needs no change to accommodate this: the rubric already treats `null`
as *not recorded, do not deduct*, and says so in its reasons. A half-filled
entry scores on what it has.

### Grouping

Eighteen fields in a flat list is a wall people scroll past. Fields carry a
`group` — **coffee · grind · brew · water** — and the form renders one section
each. Coffee and brew open by default; grind and water collapse to a header
with a count. The collapsed header is doing the real work here: it is the
thing that tells you the fields exist.

### Sticky defaults

Grinder, machine, basket and water type change perhaps twice a year, so they
are remembered from the last entry and pre-filled, editable every time. Free
text always wins — mention a different grinder and the parse overwrites the
default.

Without this, the long form's cost lands on exactly the fields it was meant to
rescue: you would retype your grinder every morning and stop bothering by
Thursday.

### Shared fields

On top of origin, roast level, dose and notes: **roaster**, **process**
(washed | natural | honey | anaerobic | wet-hulled | luwak), **roast date**,
**grinder**, **grind setting**, **water type**, and **your own rating, 1–5**.

`grinder` plus `grindSetting` — "Niche, 18" — is the single biggest
contributor to actually reproducing a good brew later, which free-text
`grindSize` ("medium-fine") never was. `roastDate` lets the app show days off
roast without being told.

**The 1–5 rating is asked on the score reveal, not in the follow-up form.**
It is the one field you cannot answer before tasting, and putting it under the
number — "here is what the app thinks, what do you think?" — is one tap in
context. It is also the check on the rubric itself: if your ratings and the
scores disagree consistently over months, the rubric is wrong, and nothing
else in the app would ever reveal that.

## 5. Scoring

**Gemini scores the brew.** There is no local rule-based scorer — not as a
primary path and not as an offline fallback. One scoring path means there is
never a question about which number is the real one.

Scored: **espresso** and every Filter coffee method (`coneDripper`,
`flatBottomDripper`, `chemex`, `batchBrewer`), plus **aeropress** — six
rubrics. The four filter ones share a formula with brewer-specific target
shifts, so they cost far less than six independent rubrics.

Everything else logs every field and displays **"not scored"**
(`scoreStatus = notApplicable`), never triggering a scoring call. For the
Indonesian methods and Turkish coffee the reason is unchanged by the move to
AI: there are no agreed-upon correct parameters, so a number would be
confidently invented rather than assessed. French press, cold brew, smart
drippers and siphon *do* have defensible targets and are the obvious next
rubrics; they are simply not in this round.

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
  own taste. The rubric is versioned (`r1`, `r2`, …), and **the version must
  be bumped whenever a number moves**. The taxonomy change alone forces `r2`:
  basket size, pre-infusion, pressure, agitation and drawdown all change how a
  brew is judged, and pour-over targets now vary by brewer. An `r1` score and
  an `r2` score are not the same measurement.
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

*Fill the gaps.* The form shows every field the method has, grouped into
coffee / grind / brew / water, with the parse's findings already filled in and
sticky defaults pre-filled. Each row uses the input type the schema declares:
number pad for grams and seconds, dropdown for roast level and enums, switches
for puck prep, plain text for origin and machine. **Nothing blocks Save** —
leave the whole form untouched and the entry still saves.

*Score.* Submitting the completed form runs a loading animation while
`/score` works, then reveals the number with its reasons — **confetti at 90 or
above** — and writes the entry. For the ten unscored methods this stage is
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
| `scoring_test.dart` | The score client and its state machine: a valid score stored with rubric and model; out-of-range, non-integer and missing-reasons responses rejected as `failed`; the ten unscored methods never issuing a request; retry moving `failed` → `scored`; the confetti threshold firing at 90 and not at 89 |
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

**Written before v1 shipped, and half of it has since been built.** Left here
rather than quietly rewritten, because a scope list that only ever agrees with
the present teaches nothing about what was hard to predict.

Still out of scope: charts, trends and statistics · scoring for the ten
unscored methods · bulk rescore after a rubric revision · offline scoring of
any kind · iOS polish · Play Store release.

Shipped after this was written — see section 15 for each:

- **Cloud sync and accounts**, in v0.2.0. Optional, and the app still works
  entirely signed out, which was the condition of building it at all.
- **Photos of the cup**, in v0.3.0. Not photos you take — one licensed
  photograph per method, alongside the how-to guides.

The remaining fast-follow is still scoring the other ten methods. Nothing
structural blocks it: a rubric written for those methods, and a change to
which ones call `/score`.

## 15. What shipped after the spec

The design above describes v0.1. These are the decisions taken since, recorded
here because this file is where the README sends anyone asking *why*.

**How-to guides, v0.2.0.** One per method, bilingual, with gear tiers and a
troubleshooting table. Their target numbers come from `brew_schema.json` —
the same file the rubric reads — so a guide and a score cannot disagree about
what a good espresso is.

**Sign-in and Firestore backup, v0.2.0.** Google, email and phone.
Deliberately optional: SQLite stays the source of truth, Firestore is a
mirror, and a backup failure is never a save failure. Deleted rows are
mirrored *as deleted*, so a restore cannot resurrect what you threw away, and
a newer local entry always wins a restore.

**Search and filter, v0.3.0.** On both Home and the full log. Stored ids are
expanded to their labels before matching, so "Kalita Wave" finds a row the
database stores as `kalitaWave`, and the search follows the selected language.
The filter lives in each screen's state rather than in the bar, which is what
keeps it applied while you open a brew and come back.

**`brewDate` means when the coffee was brewed, v0.3.0.** It previously held
the moment Save was pressed — the same value as `createdAt`, from the same
clock — so a stated brew time was thrown away. The app now sends its own wall
clock with each `/parse` call (the Worker runs in UTC, which is the wrong day
for anyone far from Greenwich) and the model resolves "yesterday at 11.30" or
"kemarin sore" against it. Both screens carry a picker. `createdAt` keeps the
second meaning, untouched by edits.

**Espresso baskets split, and rubric `r3`, v0.3.0.** Capacity in grams is what
interacts with dose and what the rubric judges; diameter is fixed by the
portafilter and is never a fault. Basket type became a two-value enum, and
puck preparation is now weighted by it: a pressurised basket makes its
pressure at an orifice in the second wall rather than through the bed, so WDT
and distribution have almost nothing to act on. `r2` deducted for skipping
them anyway, marking down every shot pulled on the basket most machines ship
with. An `r2` score and an `r3` score are not the same measurement.

**A re-score is announced, v0.3.0.** Editing a brew changed the number in
silence, which reads as the app having second thoughts rather than as a
consequence of the edit. A dialog now shows the old number beside the new one.
It also discloses two things the obvious version gets wrong: a re-score that
failed kept the old number and looked identical to one that agreed with it,
and an entry last scored under an older rubric may have moved because the
rules changed rather than because of the edit.

**The reminder had never once worked, found v0.3.1.** Not a scheduling bug —
`reminder_schedule.dart` was correct from the start, which is why every unit
test passed. `flutter_local_notifications` stopped contributing its broadcast
receivers to the merged manifest in v16, and this app never declared them, so
the AlarmManager alarm fired into an app with nothing registered to receive
it. A scheduled notification could not appear at all. Found by reading the
plugin's current documentation and then the merged manifest, rather than by
testing, because there is nothing in Dart to test.

**Guide photographs, v0.3.0.** Fifteen of sixteen methods, from Wikimedia
Commons and Openverse under CC0, CC BY or CC BY-SA. `kopiTalua` has none —
no archive holds a freely licensed one. See `ASSET_CREDITS.md`; attribution is
a licence condition, so the credit is welded into the widget that draws the
photo and there is no code path that shows one without it.
