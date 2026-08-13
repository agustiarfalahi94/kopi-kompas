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
and is versioned by `RUBRIC_VERSION`. **Bump the version whenever the numbers
change.** Every score the app stores records the rubric that produced it, and
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

Set in `wrangler.toml` as the `GEMINI_MODEL` var, defaulting in code to
`gemini-3.6-flash`.

**Always pin a concrete version. Never use an alias like
`gemini-flash-latest`.** Every score the app stores records the model that
produced it, so an old score stays interpretable. An alias would keep writing
one name while the model underneath changed, which defeats the provenance that
column exists for.

Note that `ListModels` lies by omission: `gemini-2.5-flash` is still listed but
returns `404 — no longer available to new users` for keys created recently. If
you get a 404 from `/parse`, the error body now carries Gemini's own message;
read it before assuming the URL is wrong.

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
