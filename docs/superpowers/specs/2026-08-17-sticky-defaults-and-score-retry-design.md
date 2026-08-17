# Remembered fields, and a retry that exists — design

Two changes that arrived from the same session, kept together because they
touch the same three files.

The first: a brew form should arrive already knowing everything it can know.
You told the app once that you grind on a Russell Taylors EM2 at setting 3,
with filtered water and Ethiopian beans. The next entry should not make you
say it again, and today it makes you say all of it again except four fields.

The second: the score reveal has been telling people to tap a thing that
cannot be tapped.

## 1. What is broken

### 1.1 Four fields out of forty

`lib/services/sticky_defaults.dart` remembers exactly four strings —
`grinder`, `grindSetting`, `waterType`, `machine` — in SharedPreferences,
globally, with no notion of which method they came from. Everything else is
retyped every morning.

The file's own comment records a deliberate exclusion:

> Bean origin is deliberately absent — it changes with every bag, so
> remembering it would pre-fill a wrong answer far more often than a right
> one.

That judgement is now reversed, at the user's explicit request. It was not
wrong in principle; it was weighing a wrong pre-fill against an empty field
and choosing the empty one. Section 4 changes the terms of that trade by
making a remembered value visibly remembered, which is what makes carrying
the bean origin defensible: a wrong answer you can see is not the same
failure as a wrong answer you cannot.

### 1.2 A retry with nothing to tap

`AppStrings.scoreFailed` reads "Not scored yet — tap to retry". It is
rendered in three places — `score_reveal.dart:177`,
`entry_detail_screen.dart:166`, `full_log_screen.dart:115` — and **none of
them has a tap handler**. No `onTap`, no `InkWell`, no `GestureDetector` in
any of the three files.

The real retry is a differently-named button in a fourth place: "Score this
brew" (`entry_detail_screen.dart:131`), shown only when the status is
`failed`, reached by backing out of the reveal and tapping the brew in the
list. Nobody would find it from the sentence that is on screen.

The failure that produced this report was upstream and is reproducible. A
live probe of the deployed Worker with an espresso payload:

```
HTTP 502   total 45.17s
{"error":"gemini 503: ... \"This model is currently experiencing high demand.
 Spikes in demand are usually temporary. Please try again later.\" ..."}
```

`gemini.ts:62` maps that to 502, `kopi_client.dart:184` maps 502 to
`KopiError.upstream`, and `new_entry_screen.dart:238` then discards the kind
entirely — every failure becomes a bare `ScoreStatus.failed`. "The scorer is
overloaded", "you are offline" and "you have hit the daily limit" are three
different problems with three different answers, and the reveal shows the
same nothing for all of them. The parse step, twenty lines up, gets this
right; the score step never did.

## 2. Where the memory lives

`sticky_defaults.dart` stops writing to SharedPreferences and becomes a pure
function over the brews you already have:

```dart
Map<String, Object?> stickyFor(
  BrewSchema schema,
  String method,
  List<BrewEntry> history,
)
```

`NewEntryScreen` loads `db.liveEntries()` — which already exists, already
sorts newest-first by `brewDate`, and already excludes soft-deleted rows —
and calls this once the method is known. `rememberSticky()` is deleted along
with the `sticky.` prefs keys.

**The rejected option was widening the prefs store.** Keeping
SharedPreferences and storing a JSON blob per scope would have worked, and
would have avoided touching the screen's load order. It was rejected because
it is a second copy of facts the database already holds, and a second copy
can disagree with the first. Editing an entry would not update it. Restoring
from Firestore onto a fresh install would not populate it. Deleting the brew
where a value came from would leave the value behind. Deriving from SQLite
makes "the same as last time" mean the last time, definitionally, and
CLAUDE.md already says SQLite is the source of truth.

The cost is that whatever sits in the prefs store today is discarded with no
migration. With any brews logged, the database returns the same four values
immediately. With none, four strings are lost. That is not worth a migration
path.

A pure function is also the point of the signature: no `Future`, no
`SharedPreferences.getInstance()`, no database. Every rule in section 3 is a
unit test over a hand-built list.

### 2.1 The other consumer

Settings has a read-only "Remembered for next time" list, which is the second
caller of the deleted functions and the easy one to miss. It has no method to
resolve against, so it takes a second export — `rememberedCore(history)`, the
core layer alone — and labels its rows from `schema.core` instead of
`AppStrings.stickyLabel`, a hand-written list of four names that could never
have grown to cover the rest. `stickyLabel` goes.

`machine` disappears from that list, being a method field with no single
value to show once memory is per-method. What the section promises is what
gets filled in whatever you brew next, and that is exactly the core layer.

One small thing gets better by accident: the screen already refreshes that
list after a visit to the deleted-entries screen, and until now that refresh
could not change anything, because the values lived in a store the database
could not reach.

## 3. How a value is chosen

Three layers, built by scanning `history` newest-first and taking the first
non-null value found for each field name:

| Layer | Read from | Fields taken |
|---|---|---|
| core | every entry | the 11 core fields |
| category | entries whose method shares the target's category | `methodData` only |
| method | entries with the target method | `methodData` only |

Merged most-specific-wins: method over category over core. Core field names
and `methodData` field names are disjoint today, so the core layer never
competes with the other two — section 6 pins that as an invariant rather
than leaving it as an assumption.

Then two filters.

**Relevance.** Keep only what the target method actually asks: `schema.core`
minus that method's `hideCore`, plus `spec.fields`. Kopi tubruk hides
`grinder`, `grindSetting`, `grindSize`, `roaster`, `process` and `roastDate`,
and must keep hiding them however many espresso shots precede it. This is
what makes espresso → french press keep the beans and drop the machine: an
espresso `machine` is not in french press's field list, so it never survives
the filter.

**Validity.** Drop any value that does not match the target `FieldSpec` —
wrong Dart type, or an enum value not in `spec.values`.

That second filter is not defensive padding, it is load-bearing. `brewer`
exists on `coneDripper`, `flatBottomDripper` and `smartDripper` with enum
values that share nothing at all — `v60 · origami · kono`, `kalitaWave ·
staggX · orea · april`, `clever · switch` — and the first two are both in the
`filter` category,
so the category layer will genuinely offer a V60 `brewer` to a Kalita form.
`BrewForm` would render the dropdown blank — `initialValue` already guards
with `f.values.contains(current)` — but `initState` seeds `_values` from
`f.value` unconditionally, so the invalid id would be saved to the database
behind an empty-looking control. The guard belongs in `stickyFor`, before the
value reaches the form.

`machine` is the same shape of hazard across categories: espresso and
`batchBrewer` both have a field called `machine` and they are not the same
device. Layer scoping already prevents that one, since `batchBrewer` is in
`filter` and espresso is in `espresso`. The validity filter is what covers
the case the scoping does not.

**`notes` is never carried.** It is prose about one specific cup. Stapling
"tasted sharp, a bit thin" onto tomorrow's coffee is worse than an empty box.

### 3.1 A value never dies, and that is a choice

Scanning field-by-field through the whole history means clearing a field does
not clear it: blank `filterType` on today's brew and tomorrow's form finds it
again two entries back, because a null reads as "not recorded" and the scan
keeps walking.

The alternative is to read only the single most recent matching entry per
layer, which makes clearing stick and makes "last time" literal — at the cost
of losing a field entirely whenever one brew happens to omit it.

The scan wins because maximum carry-over is the actual request, and because
pre-filling everything means a field only goes null when someone deliberately
empties it. It is recorded here because it is the kind of behaviour that
reads as a bug when you meet it without having agreed to it.

## 4. What the form shows

`formFields` is unchanged. Its precedence is already parsed → sticky → empty,
and the comment explaining why the free text always wins over a remembered
default is already correct. It simply receives a much richer map.

`FieldSource` is already computed for every field and rendered nowhere, which
was survivable when four fields could be remembered and is not survivable at
forty. A remembered value is saved data that nobody has confirmed. It must
not look identical to a value you typed.

Each control gains a quiet helper line, nothing for `empty`:

| Source | English | Indonesian |
|---|---|---|
| `sticky` | remembered | diingat |
| `parsed` | from your text | dari teks kamu |

`TextFormField` and `DropdownButtonFormField` take it as `helperText`;
`SwitchListTile` has no `InputDecoration` and takes it as `subtitle`.

The marker is tracked against a `_touched` set in `_BrewFormState` and clears
the moment you edit that field, so it always means exactly "nobody has looked
at this."

Both strings go in `AppStrings` in English and Indonesian, like every other
user-facing string.

## 5. The retry

**The sentence stops lying.** `AppStrings.scoreFailed` becomes plain "Not
scored yet" in both languages. The instruction to tap moves out of the status
text and into an actual button. This is what fixes the third site: the full
log is an archive with no tap target and no honest way to grow one, so the
only correct fix there is for the text to stop promising.

**`ScoreReveal` gains a retry.** When `entry.scoreStatus` is `failed`, the
reveal renders a "Score this brew" button — the same string the detail screen
already uses — plus the reason the score failed. A new `onRescore` callback
on the widget; `NewEntryScreen` supplies it, calls `client.score`, and
updates both the database and `_saved` on success.

**The reason survives.** `_save` keeps the `KopiError` from a `ScoreFailed`
in screen state and passes its message to the reveal, reusing `_messageFor`.
`KopiError.upstream` needs a message of its own — the existing `_ => parseFailed`
fallback says "could not read that", which is the parse step's sentence and
false here. `AppStrings.scoreUnavailable`: "The scorer is busy. Your brew is
saved — try again in a minute." / "Penilai sedang sibuk. Seduhan kamu aman —
coba lagi sebentar."

`scoreFailed` itself becomes "Not scored yet" / "Belum dinilai".

The score status is still not stored with a reason. It does not need to be: a
reason is only actionable in the moment, and the detail screen's retry is the
answer for anything later.

**The detail-screen retry stops failing silently.** `home_screen.dart:143`
awaits `client.score` and acts only on `ScoreOk`. On any failure it does
nothing at all — no spinner while it waits up to 45 seconds, no message when
it gives up, the button simply sitting there. It gains both.

## 6. Tests

The suite is green today *because* nothing ever tapped that text. Every case
below is one that currently passes by not being asked.

`sticky_defaults_test.dart` is rewritten against `stickyFor` as a pure
function over hand-built entry lists:

- espresso then french press: beans, roaster, grinder, grind setting and
  water type carry; `machine` and `shotStyle` do not
- V60 then Kalita: `waterTempC` and `ratio` carry, `brewer` does not
- the method layer beats the category layer for the same field name
- `notes` is never carried
- a `hideCore` field is never offered, however many entries hold it
- a value whose type does not match the target spec is dropped
- an empty history yields an empty map

`brew_schema_test.dart` gains the invariant section 3 depends on: no core
field name also appears as a method field name.

`follow_up_form_test.dart`: a sticky field renders "remembered", a parsed
field renders "from your text", an empty field renders neither, and the
marker clears when the field is edited.

`score_reveal_test.dart`: a `failed` entry renders a retry button and tapping
it fires `onRescore`; a `scored` entry does not; a `notApplicable` entry does
not, because an unscored method has no rubric and the Worker would refuse.

`new_entry_flow_test.dart`: a save whose score call fails still writes the
brew, reaches the reveal, and shows a retry that works; and a new entry form
opens pre-filled from history.

## 7. Files

| File | Change |
|---|---|
| `lib/services/sticky_defaults.dart` | rewritten as `stickyFor` and `rememberedCore`; prefs and `rememberSticky` deleted |
| `lib/screens/settings_screen.dart` | its remembered list reads the core layer from history |
| `lib/screens/new_entry_screen.dart` | load history, per-method sticky, keep the error kind, wire the reveal's retry |
| `lib/widgets/follow_up_form.dart` | render `FieldSource`, track touched fields |
| `lib/widgets/score_reveal.dart` | retry button and failure reason |
| `lib/screens/home_screen.dart` | detail rescore gets progress and a failure message |
| `lib/strings.dart` | `remembered`, `fromYourText`, an upstream-failure message; `scoreFailed` reworded |
| six test files | section 6 |
| `docs/STATE.md` | the handover ledger |

Out of scope: the edit screen, which must keep showing what an entry actually
holds and must never pre-fill from anywhere else.
