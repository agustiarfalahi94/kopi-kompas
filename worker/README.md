# Kopi Kompas Worker

Holds the Gemini API key and exposes two endpoints to the app. The key is a
Cloudflare secret: it is never in this repository, never in a commit, and
never in the APK. The app ships only the Worker's URL, which is not a secret.

## Endpoints

```
POST /parse   { text, locale, installId }  → the extracted entry
POST /score   { entry, locale, installId } → { score, reasons, rubric, model }
```

`400` malformed request · `422` method is not scored · `429` daily limit
reached · `502` Gemini unreachable or unusable.

## One-time setup

1. Get a Gemini API key from https://aistudio.google.com/apikey (free tier).
2. Install and authenticate wrangler:

   ```sh
   cd worker && npm install && npx wrangler login
   ```

3. Create the rate-limit KV namespace and copy the printed id into the
   `id = ` field in `wrangler.toml`:

   ```sh
   npx wrangler kv namespace create RATE_LIMIT
   ```

4. Store the key as a secret (this prompts; the value is never written to
   disk):

   ```sh
   npx wrangler secret put GEMINI_API_KEY
   ```

5. Deploy:

   ```sh
   npx wrangler deploy
   ```

Wrangler prints the URL — something like
`https://kopi-kompas.<your-subdomain>.workers.dev`. That is the value the app
needs as `KOPI_ENDPOINT`.

## Local development

```sh
npx wrangler dev            # needs the secret; use .dev.vars locally
npm test                    # no key needed, Gemini is stubbed
npm run typecheck
```

For `wrangler dev`, put the key in `worker/.dev.vars` (git-ignored):

```
GEMINI_API_KEY=your-key-here
```

## Checking it works

```sh
curl -sS https://kopi-kompas.<subdomain>.workers.dev/parse \
  -H 'content-type: application/json' \
  -d '{"text":"18g in, 36g out, 28 seconds, wdt and tamp, honduras medium",
       "locale":"en","installId":"curl-test"}'
```

## Changing the rubric

The scoring rubric lives in `src/prompts.ts` as `TARGETS`, keyed by method,
and is versioned by `RUBRIC_VERSION`. **Bump the version whenever numerical
targets or explanation policy change.** Every stored score records the rubric that produced it, and
comparing an `r1` score to an `r3` score is comparing two different
measurements. Leaving the version alone makes past scores silently wrong
rather than merely old.

## Adding a brew method

Edit `schema/brew_schema.json` — the field set, the EN and ID labels, and
whether it is scored. Both the Worker and the Flutter app read that file. If
the method is scored, add its entry to `TARGETS` in `src/prompts.ts` and bump
`RUBRIC_VERSION`. Then run `npm test`; the schema tests will tell you what you
missed.

## Choosing the model

`GEMINI_PARSE_MODEL` defaults to `gemini-flash-lite-latest` and
`GEMINI_SCORE_MODEL` to `gemini-flash-latest`. Both are server variables in
`wrangler.toml`; existing APKs do not need a rebuild when Google changes the
model behind an alias. An explicit model can still be set for rollback.

Google's [latest aliases](https://ai.google.dev/gemini-api/docs/models#latest)
can move to stable, preview, or experimental releases. If a request returns
`404` or `503`, or the generation times out, the Worker reads Google's Models API and tries at most two
different stable text-generation models in the same Flash/Lite family, newest
numeric version first. Preview, image, audio, live, and unrelated model families
are excluded from fallback. The catalog is cached for an hour per key and Worker
instance, with concurrent lookups shared and one forced refresh on a fallback
`404`. An alias and a concrete ID can refer to the same model; without response
metadata a fallback may retry that underlying model, still within the cap.
Catalog membership does not guarantee access; a rejected fallback
uses the same bounded retry budget. No rotation occurs on quota, authentication,
bad requests, blocked output, or malformed answers. Each generation has a
15-second deadline and the complete retry/catalog budget is 40 seconds, below
the app's 45-second request timeout. A timed-out attempt may still use provider
quota, so the three-attempt cap applies to these failures too.

Scores keep the response's `modelVersion`, with the requested model as a
fallback when that metadata is missing. Current rubric `r4` distinguishes
recipe-target comparisons from measured extraction: dose, yield, ratio and
time alone cannot establish under- or over-extraction. Numerical weights and
bands are unchanged from `r3`. Historical
scores retain their original model and rubric. Do not rewrite old scores when
models change. Requests omit deprecated sampling parameters and combine only
non-thinking text parts into the JSON answer.

Scoring inputs include every core and method-specific schema field, using
`null` for unrecorded values and retaining explicit `false`/`0`. This makes the
existing rubric's missing-value rule explicit instead of leaving an omitted
boolean open to interpretation. The rubric weights and target bands are unchanged.

The 15g-dose, 25g-yield, 30-second normale case is a 1:1.67 ratio (below
the 1.8–2.2 recipe target), with time inside 25–32 seconds. The prompt must
not invent a time deduction or an extraction/taste diagnosis for that case.
EN/ID endpoint regressions inspect the actual outgoing prompt and the `r4`
response provenance. They do not prove Gemini always follows the policy.
All-six-method outgoing-prompt guards also reject inherited categorical
bitterness/channeling instructions that would contradict the r4 policy.
Review live explanations after deployment and model changes. Old stored
reasons are not rewritten; editing/rescoring uses the deployed rubric.

On 2026-10-10 full Flash passed local scoring checks but repeatedly exhausted
the request budget in GitHub's live checks. A Lite scoring experiment passed
availability checks but gave an incorrect rubric explanation for an in-range
Chemex brew. Full Flash therefore remains the scoring default; reducing
timeouts alone was insufficient to justify the switch. Neither model choice
nor fallback guarantees provider availability or perfectly calibrated scores.

After the October 11 `r4` deployment, parsing succeeded in
[the live health run](https://github.com/agustiarfalahi94/kopi-kompas/actions/runs/38112815948),
but scoring timed out. Separate EN/ID espresso and EN AeroPress requests also
returned generation timeouts or Google's explicit high-demand `503`. Live
explanation compliance could not be verified during that service issue. No
model switch or additional unbounded retries were made; the tested policy and
the provider's availability are separate checks.

The weekly **Gemini health** workflow runs synthetic `/parse` and `/score`
requests. Run it manually after deployment, or use `node tool/gemini_health.mjs`.
A successful generation and valid schema are required; a reachable Worker alone
is insufficient. GitHub Actions reports failures according to your account's
notification settings. This check uses two generation requests per run.

Aliases and fallback reduce manual model maintenance, but cannot repair expired
keys, quota exhaustion, changed safety rules, or incompatible API changes.
Review [Google's migration guide](https://ai.google.dev/gemini-api/docs/generate-content/latest-model)
and [deprecations](https://ai.google.dev/gemini-api/docs/deprecations) for those.

Deploy verified code with `npm run deploy`. To roll back a model change, set
the two model variables to a known working version and redeploy, or use
`npx wrangler rollback` to restore the preceding Worker deployment. An APK
release and a Worker deployment are separate steps.

## Design notes

- **The Worker owns both prompts.** The app sends free text or a completed
  entry, never a prompt. This is a security boundary: an app that could supply
  its own prompt would make this a free Gemini proxy for anyone who read the
  URL out of the APK.
- **Handlers take `fetch` and a clock as parameters.** Every path is tested
  without network and without a deployed Worker, and no test has ever needed a
  real key.
- **The rate limiter fails open and races under concurrency, deliberately.**
  It is a ceiling on abuse if the URL leaks, not an accounting record, and a
  KV outage should not stop the owner logging their morning coffee.
- **`/parse` omits absent fields rather than sending `null`.** The app's rule
  is that a missing field is one to ask about in the follow-up form.
- **The parse schema marks every property `required` *and* `nullable`, and
  changing either breaks parsing in a way the unit tests cannot see.** Without
  `nullable`, a string field the model wants to leave empty cannot be null, so
  the constrained decoder emits an adjacent property name instead — real
  responses contained `{"beanOrigin":"doseGrams"}`. With only `brewMethod`
  required, the decoder satisfies the minimum and stops after three fields,
  silently dropping values that were stated in the text. If you touch
  `buildParseResponseSchema`, re-run the live curl checks above; a green
  `npm test` does not cover this.
