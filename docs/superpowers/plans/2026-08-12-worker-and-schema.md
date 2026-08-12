# Kopi Kompas Phase 1 — Schema and Worker Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A deployed Cloudflare Worker exposing `POST /parse` and `POST /score`, both driven by one shared brew schema, with the Gemini key never leaving Cloudflare.

**Architecture:** `schema/brew_schema.json` at the repository root is the single source of truth for all eight brew methods; the Worker reads it to build Gemini's `responseSchema`, and the Flutter app will read the same file in Phase 2 to build its follow-up form. The Worker owns both prompts — the app sends only free text or a completed entry, never a prompt — because an app that could supply prompts would turn the endpoint into a free Gemini proxy for anyone who read the URL out of the APK. Handlers are pure functions over an injected `fetch` and clock, so every path is testable without network or a deployed Worker.

**Tech Stack:** TypeScript · Cloudflare Workers · wrangler 4 · Workers KV (rate limiting) · vitest · Gemini 2.5 Flash

## Global Constraints

- **The Gemini key is a Worker secret. It never appears in the repository, in any test, in any commit, or in the APK.** Tests stub the Gemini call; they never make a real one.
- Endpoint contract, exactly as specified: `POST /parse`, `POST /score`, with `400` for an unparseable request, `429` for rate limited, `502` for Gemini unreachable or non-JSON.
- Model: `gemini-2.5-flash`. Both calls set `responseMimeType: "application/json"` and an explicit `responseSchema`.
- Scoring temperature is `0`. Parsing temperature is `0`.
- Scored methods are **espresso, v60, aeropress** only. The other five are `notApplicable` and `/score` rejects them rather than inventing a number.
- The rubric is versioned. `r1` is defined in this plan; every score response carries `rubric` and `model` so the app can store them.
- Every brew method's field set lives in `schema/brew_schema.json` and nowhere else.
- Node 20+ for the Worker toolchain. All Worker commands run from `worker/`.
- Commit after every task. Work on branch `feature/worker-and-schema` off `develop`.

---

## File Structure

| File | Responsibility |
|---|---|
| `schema/brew_schema.json` | Single source of truth: core fields, eight method field sets, EN/ID labels, which methods are scored |
| `worker/package.json` | Dependencies and scripts |
| `worker/tsconfig.json` | TypeScript config |
| `worker/wrangler.toml` | Worker name, entry point, KV binding |
| `worker/vitest.config.ts` | Test config |
| `worker/src/schema.ts` | Loads the shared schema; builds Gemini `responseSchema` objects; strips fields foreign to a method |
| `worker/src/prompts.ts` | The parse system instruction and the `r1` scoring rubric |
| `worker/src/gemini.ts` | The single Gemini HTTP call, with JSON extraction and error mapping |
| `worker/src/ratelimit.ts` | Per-install-id daily counter over KV |
| `worker/src/index.ts` | Routing, request validation, response shaping |
| `worker/test/*.test.ts` | One test file per source module |
| `worker/README.md` | One-time setup: account, key, KV namespace, deploy |

A note on decomposition: `index.ts` does routing and nothing else. Every decision worth testing — schema shaping, prompt content, Gemini error mapping, rate limiting — lives in a module that can be tested without constructing a `Request`.

---

### Task 1: The shared brew schema

**Files:**
- Create: `schema/brew_schema.json`
- Create: `worker/package.json`, `worker/tsconfig.json`, `worker/vitest.config.ts`
- Create: `worker/src/schema.ts`
- Test: `worker/test/schema.test.ts`

**Interfaces:**
- Consumes: nothing.
- Produces: `schema/brew_schema.json` with the structure below. `worker/src/schema.ts` exports `brewSchema: BrewSchema`, `METHODS: BrewMethod[]`, `SCORED_METHODS: BrewMethod[]`, and the types `BrewMethod = 'espresso' | 'v60' | 'aeropress' | 'frenchPress' | 'kopiTubruk' | 'kopiJoss' | 'kopiTalua' | 'kopiKhop'` and `FieldSpec = { type: 'number' | 'integer' | 'string' | 'boolean' | 'enum'; unit?: string; values?: string[]; required: boolean; label: { en: string; id: string } }`.

**Design decision to carry forward:** the spec wrote espresso's puck prep as a nested object `{ wdt, distribution, tamp }`. This plan flattens it to three nullable booleans `puckPrepWdt`, `puckPrepDistribution`, `puckPrepTamp`. Nesting buys nothing and costs a special case in the form generator, the Gemini schema, and the field-stripping logic. Nullable is load-bearing: `false` means you said you skipped it, `null` means nobody knows, and the rubric treats those differently.

- [ ] **Step 1: Create the Worker project files**

`worker/package.json`:

```json
{
  "name": "kopi-kompas-worker",
  "private": true,
  "type": "module",
  "scripts": {
    "dev": "wrangler dev",
    "deploy": "wrangler deploy",
    "test": "vitest run",
    "typecheck": "tsc --noEmit"
  },
  "devDependencies": {
    "@cloudflare/workers-types": "^4.20250109.0",
    "typescript": "^5.7.0",
    "vitest": "^2.1.0",
    "wrangler": "^4.0.0"
  }
}
```

`worker/tsconfig.json`:

```json
{
  "compilerOptions": {
    "target": "ES2022",
    "module": "ES2022",
    "moduleResolution": "bundler",
    "lib": ["ES2022"],
    "types": ["@cloudflare/workers-types"],
    "strict": true,
    "noUncheckedIndexedAccess": true,
    "resolveJsonModule": true,
    "esModuleInterop": true,
    "skipLibCheck": true,
    "noEmit": true
  },
  "include": ["src/**/*.ts", "test/**/*.ts"]
}
```

`worker/vitest.config.ts`:

```ts
import { defineConfig } from 'vitest/config';

export default defineConfig({
  test: { environment: 'node', include: ['test/**/*.test.ts'] },
});
```

- [ ] **Step 2: Write `schema/brew_schema.json`**

Every field is nullable in practice — the parse prompt is told to use `null` for anything absent. `required: true` means "ask about it in the follow-up form if it is missing", not "reject without it".

```json
{
  "schemaVersion": "s1",
  "core": {
    "beanOrigin":  { "type": "string", "required": true,  "label": { "en": "Bean origin", "id": "Asal biji" } },
    "roastLevel":  { "type": "enum", "values": ["light", "medium", "medium-dark", "dark"], "required": true, "label": { "en": "Roast level", "id": "Tingkat sangrai" } },
    "doseGrams":   { "type": "number", "unit": "g", "required": true, "label": { "en": "Dose", "id": "Dosis" } },
    "grindSize":   { "type": "string", "required": false, "label": { "en": "Grind size", "id": "Kehalusan giling" } },
    "notes":       { "type": "string", "required": false, "label": { "en": "Notes", "id": "Catatan" } }
  },
  "methods": {
    "espresso": {
      "scored": true,
      "label": { "en": "Espresso", "id": "Espresso" },
      "fields": {
        "yieldGrams":            { "type": "number", "unit": "g", "required": true,  "label": { "en": "Yield", "id": "Hasil" } },
        "brewTimeSeconds":       { "type": "number", "unit": "s", "required": true,  "label": { "en": "Brew time", "id": "Waktu ekstraksi" } },
        "puckPrepWdt":           { "type": "boolean", "required": true,  "label": { "en": "WDT", "id": "WDT" } },
        "puckPrepDistribution":  { "type": "boolean", "required": true,  "label": { "en": "Distribution", "id": "Distribusi" } },
        "puckPrepTamp":          { "type": "boolean", "required": true,  "label": { "en": "Tamp", "id": "Tamping" } },
        "machine":               { "type": "string", "required": true,  "label": { "en": "Machine", "id": "Mesin" } },
        "basketType":            { "type": "string", "required": false, "label": { "en": "Basket", "id": "Basket" } },
        "waterTempC":            { "type": "number", "unit": "°C", "required": false, "label": { "en": "Water temperature", "id": "Suhu air" } }
      }
    },
    "v60": {
      "scored": true,
      "label": { "en": "V60", "id": "V60" },
      "fields": {
        "waterGrams":            { "type": "number", "unit": "g", "required": true,  "label": { "en": "Water", "id": "Air" } },
        "ratio":                 { "type": "number", "required": false, "label": { "en": "Ratio (1:x)", "id": "Rasio (1:x)" } },
        "bloomTimeSeconds":      { "type": "number", "unit": "s", "required": true,  "label": { "en": "Bloom time", "id": "Waktu bloom" } },
        "bloomWaterGrams":       { "type": "number", "unit": "g", "required": true,  "label": { "en": "Bloom water", "id": "Air bloom" } },
        "pourCount":             { "type": "integer", "required": true,  "label": { "en": "Number of pours", "id": "Jumlah tuangan" } },
        "totalBrewTimeSeconds":  { "type": "number", "unit": "s", "required": true,  "label": { "en": "Total brew time", "id": "Total waktu seduh" } },
        "waterTempC":            { "type": "number", "unit": "°C", "required": true,  "label": { "en": "Water temperature", "id": "Suhu air" } },
        "filterType":            { "type": "string", "required": false, "label": { "en": "Filter", "id": "Filter" } }
      }
    },
    "aeropress": {
      "scored": true,
      "label": { "en": "Aeropress", "id": "Aeropress" },
      "fields": {
        "waterGrams":         { "type": "number", "unit": "g", "required": true,  "label": { "en": "Water", "id": "Air" } },
        "ratio":              { "type": "number", "required": false, "label": { "en": "Ratio (1:x)", "id": "Rasio (1:x)" } },
        "steepTimeSeconds":   { "type": "number", "unit": "s", "required": true,  "label": { "en": "Steep time", "id": "Waktu rendam" } },
        "inverted":           { "type": "boolean", "required": true,  "label": { "en": "Inverted", "id": "Terbalik" } },
        "plungeTimeSeconds":  { "type": "number", "unit": "s", "required": true,  "label": { "en": "Plunge time", "id": "Waktu tekan" } },
        "waterTempC":         { "type": "number", "unit": "°C", "required": true,  "label": { "en": "Water temperature", "id": "Suhu air" } }
      }
    },
    "frenchPress": {
      "scored": false,
      "label": { "en": "French press", "id": "French press" },
      "fields": {
        "waterGrams":         { "type": "number", "unit": "g", "required": true,  "label": { "en": "Water", "id": "Air" } },
        "ratio":              { "type": "number", "required": false, "label": { "en": "Ratio (1:x)", "id": "Rasio (1:x)" } },
        "steepTimeMinutes":   { "type": "number", "unit": "min", "required": true, "label": { "en": "Steep time", "id": "Waktu rendam" } },
        "waterTempC":         { "type": "number", "unit": "°C", "required": true, "label": { "en": "Water temperature", "id": "Suhu air" } },
        "plungeStyle":        { "type": "string", "required": false, "label": { "en": "Plunge style", "id": "Cara menekan" } }
      }
    },
    "kopiTubruk": {
      "scored": false,
      "label": { "en": "Kopi tubruk", "id": "Kopi tubruk" },
      "fields": {
        "waterGrams":       { "type": "number", "unit": "g", "required": true,  "label": { "en": "Water", "id": "Air" } },
        "waterTempC":       { "type": "number", "unit": "°C", "required": false, "label": { "en": "Water temperature", "id": "Suhu air" } },
        "steepTimeMinutes": { "type": "number", "unit": "min", "required": true, "label": { "en": "Steep time", "id": "Waktu rendam" } },
        "sugarAdded":       { "type": "boolean", "required": true,  "label": { "en": "Sugar added", "id": "Pakai gula" } },
        "settled":          { "type": "boolean", "required": false, "label": { "en": "Grounds settled", "id": "Ampas mengendap" } }
      }
    },
    "kopiJoss": {
      "scored": false,
      "label": { "en": "Kopi joss", "id": "Kopi joss" },
      "fields": {
        "waterGrams":    { "type": "number", "unit": "g", "required": true,  "label": { "en": "Water", "id": "Air" } },
        "waterTempC":    { "type": "number", "unit": "°C", "required": false, "label": { "en": "Water temperature", "id": "Suhu air" } },
        "charcoalUsed":  { "type": "boolean", "required": true,  "label": { "en": "Charcoal used", "id": "Pakai arang" } },
        "sugarAdded":    { "type": "boolean", "required": true,  "label": { "en": "Sugar added", "id": "Pakai gula" } }
      }
    },
    "kopiTalua": {
      "scored": false,
      "label": { "en": "Kopi talua", "id": "Kopi talua" },
      "fields": {
        "waterGrams":               { "type": "number", "unit": "g", "required": true,  "label": { "en": "Water", "id": "Air" } },
        "eggYolkUsed":              { "type": "boolean", "required": true,  "label": { "en": "Egg yolk used", "id": "Pakai kuning telur" } },
        "sugarGrams":               { "type": "number", "unit": "g", "required": false, "label": { "en": "Sugar", "id": "Gula" } },
        "whippedDurationSeconds":   { "type": "number", "unit": "s", "required": true,  "label": { "en": "Whipping time", "id": "Waktu kocok" } },
        "spicesAdded":              { "type": "string", "required": false, "label": { "en": "Spices", "id": "Rempah" } }
      }
    },
    "kopiKhop": {
      "scored": false,
      "label": { "en": "Kopi khop", "id": "Kopi khop" },
      "fields": {
        "waterGrams":          { "type": "number", "unit": "g", "required": true,  "label": { "en": "Water", "id": "Air" } },
        "waterTempC":          { "type": "number", "unit": "°C", "required": false, "label": { "en": "Water temperature", "id": "Suhu air" } },
        "sugarAdded":          { "type": "boolean", "required": true,  "label": { "en": "Sugar added", "id": "Pakai gula" } },
        "flipDurationMinutes": { "type": "number", "unit": "min", "required": true, "label": { "en": "Time inverted", "id": "Lama dibalik" } }
      }
    }
  }
}
```

- [ ] **Step 3: Write the failing test**

`worker/test/schema.test.ts`:

```ts
import { describe, expect, it } from 'vitest';
import { brewSchema, METHODS, SCORED_METHODS } from '../src/schema';

describe('brew schema', () => {
  it('defines exactly the eight brew methods', () => {
    expect(METHODS).toEqual([
      'espresso', 'v60', 'aeropress', 'frenchPress',
      'kopiTubruk', 'kopiJoss', 'kopiTalua', 'kopiKhop',
    ]);
  });

  it('scores only espresso, v60 and aeropress', () => {
    expect(SCORED_METHODS).toEqual(['espresso', 'v60', 'aeropress']);
  });

  it('gives every core and method field an en and id label', () => {
    const specs = [
      ...Object.values(brewSchema.core),
      ...METHODS.flatMap((m) => Object.values(brewSchema.methods[m].fields)),
    ];
    expect(specs.length).toBeGreaterThan(0);
    for (const spec of specs) {
      expect(spec.label.en, JSON.stringify(spec)).toBeTruthy();
      expect(spec.label.id, JSON.stringify(spec)).toBeTruthy();
    }
  });

  it('uses only field types the form generator understands', () => {
    const allowed = ['number', 'integer', 'string', 'boolean', 'enum'];
    for (const m of METHODS) {
      for (const [name, spec] of Object.entries(brewSchema.methods[m].fields)) {
        expect(allowed, `${m}.${name}`).toContain(spec.type);
      }
    }
  });

  it('gives every enum field its allowed values', () => {
    for (const [name, spec] of Object.entries(brewSchema.core)) {
      if (spec.type === 'enum') expect(spec.values, name).toBeDefined();
    }
  });
});
```

- [ ] **Step 4: Run the test to verify it fails**

```bash
cd worker && npm install && npx vitest run test/schema.test.ts
```

Expected: FAIL — `Cannot find module '../src/schema'`.

- [ ] **Step 5: Write `worker/src/schema.ts`**

```ts
import raw from '../../schema/brew_schema.json';

export type BrewMethod =
  | 'espresso' | 'v60' | 'aeropress' | 'frenchPress'
  | 'kopiTubruk' | 'kopiJoss' | 'kopiTalua' | 'kopiKhop';

export type FieldType = 'number' | 'integer' | 'string' | 'boolean' | 'enum';

export interface FieldSpec {
  type: FieldType;
  unit?: string;
  values?: string[];
  required: boolean;
  label: { en: string; id: string };
}

export interface MethodSpec {
  scored: boolean;
  label: { en: string; id: string };
  fields: Record<string, FieldSpec>;
}

export interface BrewSchema {
  schemaVersion: string;
  core: Record<string, FieldSpec>;
  methods: Record<BrewMethod, MethodSpec>;
}

export const brewSchema = raw as BrewSchema;

export const METHODS = Object.keys(brewSchema.methods) as BrewMethod[];

export const SCORED_METHODS = METHODS.filter(
  (m) => brewSchema.methods[m].scored,
);

export function isBrewMethod(value: unknown): value is BrewMethod {
  return typeof value === 'string' && (METHODS as string[]).includes(value);
}
```

The `resolveJsonModule` and `noUncheckedIndexedAccess` flags together mean the
import is typed as its literal shape; the single `as BrewSchema` cast is the
one place the JSON is trusted, and the tests above are what justify it.

- [ ] **Step 6: Run the test to verify it passes**

```bash
cd worker && npx vitest run test/schema.test.ts && npx tsc --noEmit
```

Expected: 5 passing, no type errors.

- [ ] **Step 7: Commit**

```bash
git add schema/brew_schema.json worker/package.json worker/package-lock.json \
        worker/tsconfig.json worker/vitest.config.ts \
        worker/src/schema.ts worker/test/schema.test.ts
git commit -m "feat(worker): the shared brew schema, read by one loader

Eight methods, their fields, EN/ID labels and which three are scored,
in one file the Flutter app will read too. Espresso's puck prep is three
nullable booleans rather than the nested object the spec sketched:
nesting cost a special case in three places, and null-versus-false is
the distinction that actually matters — false means you skipped the
step, null means nobody knows, and the rubric treats them differently."
```

---

### Task 2: Gemini response schemas built from the brew schema

**Files:**
- Modify: `worker/src/schema.ts`
- Test: `worker/test/gemini_schema.test.ts`

**Interfaces:**
- Consumes: `brewSchema`, `METHODS`, `BrewMethod`, `FieldSpec` from Task 1.
- Produces: `buildParseResponseSchema(): object` and `stripForeignFields(method: BrewMethod, data: Record<string, unknown>): Record<string, unknown>`.

**Why a flat union rather than a discriminated one:** Gemini's `responseSchema` is a restricted JSON Schema subset, and per-method branching through `anyOf` is unreliable. Instead the schema declares `methodData` as the *union of every method's fields*, all optional, and the prompt instructs the model to fill only those belonging to the method it classified. `stripForeignFields` then deletes anything that does not belong, server-side. The model is asked to be tidy; the Worker guarantees it.

- [ ] **Step 1: Write the failing test**

`worker/test/gemini_schema.test.ts`:

```ts
import { describe, expect, it } from 'vitest';
import { buildParseResponseSchema, stripForeignFields } from '../src/schema';

describe('buildParseResponseSchema', () => {
  const schema = buildParseResponseSchema() as any;

  it('constrains brewMethod to the eight known methods', () => {
    expect(schema.properties.brewMethod.enum).toContain('espresso');
    expect(schema.properties.brewMethod.enum).toContain('kopiKhop');
    expect(schema.properties.brewMethod.enum).toHaveLength(8);
  });

  it('requires brewMethod and nothing else', () => {
    expect(schema.required).toEqual(['brewMethod']);
  });

  it('exposes core fields at the top level', () => {
    expect(schema.properties.doseGrams.type).toBe('number');
    expect(schema.properties.roastLevel.enum).toEqual([
      'light', 'medium', 'medium-dark', 'dark',
    ]);
  });

  it('unions every method field into methodData', () => {
    const md = schema.properties.methodData.properties;
    expect(md.yieldGrams.type).toBe('number');      // espresso
    expect(md.bloomTimeSeconds.type).toBe('number'); // v60
    expect(md.eggYolkUsed.type).toBe('boolean');     // kopiTalua
    expect(md.puckPrepWdt.type).toBe('boolean');
  });

  it('maps integer fields to integer, not number', () => {
    expect(schema.properties.methodData.properties.pourCount.type)
      .toBe('integer');
  });

  it('never marks a methodData field required', () => {
    expect(schema.properties.methodData.required).toBeUndefined();
  });
});

describe('stripForeignFields', () => {
  it('keeps fields belonging to the method', () => {
    const out = stripForeignFields('espresso', {
      yieldGrams: 30, brewTimeSeconds: 25,
    });
    expect(out).toEqual({ yieldGrams: 30, brewTimeSeconds: 25 });
  });

  it('drops fields belonging to another method', () => {
    const out = stripForeignFields('espresso', {
      yieldGrams: 30, eggYolkUsed: true, bloomTimeSeconds: 40,
    });
    expect(out).toEqual({ yieldGrams: 30 });
  });

  it('drops keys in no method at all', () => {
    expect(stripForeignFields('espresso', { overallScore: 95 })).toEqual({});
  });

  it('drops nulls, so a missing field stays missing', () => {
    const out = stripForeignFields('espresso', {
      yieldGrams: 30, machine: null,
    });
    expect(out).toEqual({ yieldGrams: 30 });
  });

  it('keeps false, which is a real answer', () => {
    const out = stripForeignFields('espresso', { puckPrepWdt: false });
    expect(out).toEqual({ puckPrepWdt: false });
  });
});
```

The last two cases are the ones that matter. `null` means "not mentioned" and must vanish so the app asks about it; `false` means "I skipped that step" and must survive, because the rubric deducts for it.

- [ ] **Step 2: Run the test to verify it fails**

```bash
cd worker && npx vitest run test/gemini_schema.test.ts
```

Expected: FAIL — `buildParseResponseSchema is not a function`.

- [ ] **Step 3: Append to `worker/src/schema.ts`**

```ts
function geminiType(spec: FieldSpec): Record<string, unknown> {
  switch (spec.type) {
    case 'integer': return { type: 'integer' };
    case 'number':  return { type: 'number' };
    case 'boolean': return { type: 'boolean' };
    case 'enum':    return { type: 'string', enum: spec.values ?? [] };
    case 'string':  return { type: 'string' };
  }
}

export function buildParseResponseSchema(): Record<string, unknown> {
  const core: Record<string, unknown> = {};
  for (const [name, spec] of Object.entries(brewSchema.core)) {
    core[name] = geminiType(spec);
  }

  const methodData: Record<string, unknown> = {};
  for (const method of METHODS) {
    for (const [name, spec] of Object.entries(
      brewSchema.methods[method].fields,
    )) {
      methodData[name] = geminiType(spec);
    }
  }

  return {
    type: 'object',
    properties: {
      brewMethod: { type: 'string', enum: METHODS },
      ...core,
      methodData: { type: 'object', properties: methodData },
    },
    required: ['brewMethod'],
  };
}

export function stripForeignFields(
  method: BrewMethod,
  data: Record<string, unknown>,
): Record<string, unknown> {
  const allowed = brewSchema.methods[method].fields;
  const out: Record<string, unknown> = {};
  for (const [key, value] of Object.entries(data)) {
    if (key in allowed && value !== null && value !== undefined) {
      out[key] = value;
    }
  }
  return out;
}
```

A field appearing in two methods (`waterGrams`, `waterTempC`, `ratio`) collapses to one entry in the union, which is correct — the types agree, and `stripForeignFields` does the per-method narrowing.

- [ ] **Step 4: Run the test to verify it passes**

```bash
cd worker && npx vitest run && npx tsc --noEmit
```

Expected: all passing.

- [ ] **Step 5: Commit**

```bash
git add worker/src/schema.ts worker/test/gemini_schema.test.ts
git commit -m "feat(worker): build Gemini's response schema from the brew schema

methodData is the union of all eight methods' fields rather than a
per-method branch, because Gemini's responseSchema subset handles anyOf
badly. stripForeignFields does the narrowing server-side afterwards, so
the model is asked to be tidy and the Worker guarantees it.

Nulls are dropped and false is kept: null means the field was never
mentioned and the app should ask, false means the step was skipped and
the rubric should deduct."
```

---

### Task 3: The Gemini client

**Files:**
- Create: `worker/src/gemini.ts`
- Test: `worker/test/gemini.test.ts`

**Interfaces:**
- Consumes: nothing from earlier tasks.
- Produces:
  - `type GeminiResult<T> = { ok: true; value: T } | { ok: false; status: 429 | 502; detail: string }`
  - `async function callGemini<T>(opts: { apiKey: string; model: string; systemInstruction: string; userText: string; responseSchema: Record<string, unknown>; fetchImpl: typeof fetch }): Promise<GeminiResult<T>>`

- [ ] **Step 1: Write the failing test**

`worker/test/gemini.test.ts`:

```ts
import { describe, expect, it, vi } from 'vitest';
import { callGemini } from '../src/gemini';

const base = {
  apiKey: 'test-key',
  model: 'gemini-2.5-flash',
  systemInstruction: 'be exact',
  userText: 'an americano',
  responseSchema: { type: 'object' },
};

function reply(body: unknown, status = 200) {
  return vi.fn(async () => new Response(JSON.stringify(body), { status }));
}

function candidate(text: string) {
  return { candidates: [{ content: { parts: [{ text }] } }] };
}

describe('callGemini', () => {
  it('returns the parsed JSON from the first candidate', async () => {
    const fetchImpl = reply(candidate('{"brewMethod":"espresso"}'));
    const res = await callGemini({ ...base, fetchImpl: fetchImpl as any });
    expect(res).toEqual({ ok: true, value: { brewMethod: 'espresso' } });
  });

  it('sends the key in a header, never in the URL', async () => {
    const fetchImpl = reply(candidate('{}'));
    await callGemini({ ...base, fetchImpl: fetchImpl as any });
    const [url, init] = (fetchImpl as any).mock.calls[0];
    expect(String(url)).not.toContain('test-key');
    expect((init.headers as Record<string, string>)['x-goog-api-key'])
      .toBe('test-key');
  });

  it('asks for JSON output at temperature 0', async () => {
    const fetchImpl = reply(candidate('{}'));
    await callGemini({ ...base, fetchImpl: fetchImpl as any });
    const body = JSON.parse((fetchImpl as any).mock.calls[0][1].body);
    expect(body.generationConfig.responseMimeType).toBe('application/json');
    expect(body.generationConfig.temperature).toBe(0);
    expect(body.generationConfig.responseSchema).toEqual({ type: 'object' });
  });

  it('maps a 429 from Gemini to a 429', async () => {
    const fetchImpl = reply({ error: 'quota' }, 429);
    const res = await callGemini({ ...base, fetchImpl: fetchImpl as any });
    expect(res).toEqual({ ok: false, status: 429, detail: 'gemini quota' });
  });

  it('maps any other non-200 to a 502', async () => {
    const fetchImpl = reply({ error: 'boom' }, 500);
    const res = await callGemini({ ...base, fetchImpl: fetchImpl as any });
    expect(res.ok).toBe(false);
    if (!res.ok) expect(res.status).toBe(502);
  });

  it('maps a network failure to a 502', async () => {
    const fetchImpl = vi.fn(async () => { throw new Error('ECONNRESET'); });
    const res = await callGemini({ ...base, fetchImpl: fetchImpl as any });
    if (!res.ok) expect(res.status).toBe(502);
  });

  it('maps non-JSON candidate text to a 502', async () => {
    const fetchImpl = reply(candidate('I am afraid I cannot do that'));
    const res = await callGemini({ ...base, fetchImpl: fetchImpl as any });
    if (!res.ok) expect(res.status).toBe(502);
  });

  it('maps an empty candidate list to a 502', async () => {
    const fetchImpl = reply({ candidates: [] });
    const res = await callGemini({ ...base, fetchImpl: fetchImpl as any });
    if (!res.ok) expect(res.status).toBe(502);
  });
});
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
cd worker && npx vitest run test/gemini.test.ts
```

Expected: FAIL — cannot find `../src/gemini`.

- [ ] **Step 3: Write `worker/src/gemini.ts`**

```ts
export type GeminiResult<T> =
  | { ok: true; value: T }
  | { ok: false; status: 429 | 502; detail: string };

export interface GeminiOptions {
  apiKey: string;
  model: string;
  systemInstruction: string;
  userText: string;
  responseSchema: Record<string, unknown>;
  fetchImpl: typeof fetch;
}

export async function callGemini<T>(
  opts: GeminiOptions,
): Promise<GeminiResult<T>> {
  const url =
    `https://generativelanguage.googleapis.com/v1beta/models/` +
    `${opts.model}:generateContent`;

  const body = {
    systemInstruction: { parts: [{ text: opts.systemInstruction }] },
    contents: [{ role: 'user', parts: [{ text: opts.userText }] }],
    generationConfig: {
      temperature: 0,
      responseMimeType: 'application/json',
      responseSchema: opts.responseSchema,
    },
  };

  let response: Response;
  try {
    response = await opts.fetchImpl(url, {
      method: 'POST',
      headers: {
        'content-type': 'application/json',
        'x-goog-api-key': opts.apiKey,
      },
      body: JSON.stringify(body),
    });
  } catch (e) {
    return { ok: false, status: 502, detail: `gemini unreachable: ${e}` };
  }

  if (response.status === 429) {
    return { ok: false, status: 429, detail: 'gemini quota' };
  }
  if (!response.ok) {
    return { ok: false, status: 502, detail: `gemini ${response.status}` };
  }

  let envelope: any;
  try {
    envelope = await response.json();
  } catch {
    return { ok: false, status: 502, detail: 'gemini sent non-json' };
  }

  const text = envelope?.candidates?.[0]?.content?.parts?.[0]?.text;
  if (typeof text !== 'string') {
    return { ok: false, status: 502, detail: 'gemini sent no candidate' };
  }

  try {
    return { ok: true, value: JSON.parse(text) as T };
  } catch {
    return { ok: false, status: 502, detail: 'candidate was not json' };
  }
}
```

The key travels in the `x-goog-api-key` header rather than a query string. A key in a URL ends up in logs, and Cloudflare logs request URLs.

- [ ] **Step 4: Run the test to verify it passes**

```bash
cd worker && npx vitest run && npx tsc --noEmit
```

Expected: all passing.

- [ ] **Step 5: Commit**

```bash
git add worker/src/gemini.ts worker/test/gemini.test.ts
git commit -m "feat(worker): one Gemini call, with every failure mapped

Takes fetch as a parameter so the whole thing tests without network.
The key goes in x-goog-api-key rather than a query parameter, because
Cloudflare logs request URLs. Quota becomes 429; unreachable, non-200,
missing candidate and unparseable candidate all become 502, so the app
can tell 'try later' from 'something is broken'."
```

---

### Task 4: The parse prompt and the `r1` scoring rubric

**Files:**
- Create: `worker/src/prompts.ts`
- Test: `worker/test/prompts.test.ts`

**Interfaces:**
- Consumes: `brewSchema`, `BrewMethod`, `SCORED_METHODS` from Task 1.
- Produces: `RUBRIC_VERSION = 'r1'`, `parseInstruction(locale: 'en' | 'id'): string`, `scoreInstruction(method: BrewMethod, locale: 'en' | 'id'): string`, `buildScoreResponseSchema(): Record<string, unknown>`.

**The rubric is the product.** These numbers are the app's opinion about coffee. They are deliberately conservative, and they are versioned so they can be argued with later without corrupting old scores.

- [ ] **Step 1: Write the failing test**

`worker/test/prompts.test.ts`:

```ts
import { describe, expect, it } from 'vitest';
import {
  RUBRIC_VERSION, parseInstruction, scoreInstruction,
  buildScoreResponseSchema,
} from '../src/prompts';

describe('parseInstruction', () => {
  const en = parseInstruction('en');

  it('forbids guessing', () => {
    expect(en.toLowerCase()).toContain('null');
    expect(en.toLowerCase()).toContain('do not guess');
  });

  it('tells the model to classify the method first', () => {
    expect(en.toLowerCase()).toContain('brewmethod');
  });

  it('names every method so classification has a closed set', () => {
    for (const m of ['espresso', 'v60', 'kopiTubruk', 'kopiKhop']) {
      expect(en).toContain(m);
    }
  });

  it('forbids scoring during a parse', () => {
    expect(en.toLowerCase()).toContain('do not score');
  });

  it('mentions Indonesian input when the locale is id', () => {
    expect(parseInstruction('id').toLowerCase()).toContain('indonesian');
  });
});

const SCORED = ['espresso', 'v60', 'aeropress'] as const;

describe('scoreInstruction', () => {
  it('carries concrete espresso targets', () => {
    const s = scoreInstruction('espresso', 'en');
    expect(s).toContain('1.8');
    expect(s).toContain('2.2');
    expect(s).toContain('25');
    expect(s).toContain('32');
  });

  it('carries concrete v60 targets', () => {
    const s = scoreInstruction('v60', 'en');
    expect(s).toContain('15');
    expect(s).toContain('17');
  });

  it('carries concrete aeropress targets', () => {
    const s = scoreInstruction('aeropress', 'en');
    expect(s).toContain('steep');
  });

  it('says an unknown field is not a fault', () => {
    const s = scoreInstruction('espresso', 'en').toLowerCase();
    expect(s).toContain('do not deduct');
  });

  it('asks for reasons in the requested language', () => {
    expect(scoreInstruction('espresso', 'id').toLowerCase())
      .toContain('indonesian');
  });

  it('is defined for every scored method', () => {
    for (const m of SCORED) {
      expect(scoreInstruction(m, 'en').length).toBeGreaterThan(200);
    }
  });
});

describe('buildScoreResponseSchema', () => {
  const s = buildScoreResponseSchema() as any;

  it('bounds the score to 0-100 integers', () => {
    expect(s.properties.score.type).toBe('integer');
    expect(s.properties.score.minimum).toBe(0);
    expect(s.properties.score.maximum).toBe(100);
  });

  it('requires both a score and its reasons', () => {
    expect(s.required).toEqual(['score', 'reasons']);
  });

  it('makes reasons an array of strings', () => {
    expect(s.properties.reasons.type).toBe('array');
    expect(s.properties.reasons.items.type).toBe('string');
  });
});

describe('rubric version', () => {
  it('is r1', () => expect(RUBRIC_VERSION).toBe('r1'));
});
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
cd worker && npx vitest run test/prompts.test.ts
```

Expected: FAIL — cannot find `../src/prompts`.

- [ ] **Step 3: Write `worker/src/prompts.ts`**

```ts
import { brewSchema, METHODS, type BrewMethod } from './schema';

export const RUBRIC_VERSION = 'r1';

export type Locale = 'en' | 'id';

function languageLine(locale: Locale): string {
  return locale === 'id'
    ? 'The user writes in Indonesian. Understand Indonesian coffee ' +
      'vocabulary (gula, sangrai, kental, tubruk, saring, kocok) and write ' +
      'any prose you produce in Indonesian.'
    : 'The user writes in English.';
}

export function parseInstruction(locale: Locale): string {
  const methods = METHODS.map((m) => {
    const fields = Object.keys(brewSchema.methods[m].fields).join(', ');
    return `- ${m}: ${fields}`;
  }).join('\n');

  return [
    'You extract structured data from a short, informal description of a',
    'coffee someone just brewed. You are a parser, not an assistant.',
    '',
    languageLine(locale),
    '',
    'First classify brewMethod. It must be exactly one of the eight values',
    'below, chosen from what the text describes:',
    '',
    methods,
    '',
    'Then extract the core fields (beanOrigin, roastLevel, doseGrams,',
    'grindSize, notes) and, in methodData, only the fields listed above for',
    'the method you chose. Leave every field belonging to another method',
    'absent.',
    '',
    'Rules:',
    '- Use null for anything not stated or not clear. Do not guess, do not',
    '  infer a typical value, and do not fill a field because it is usually',
    '  present. A missing value will be asked about; a wrong one will not.',
    '- Booleans: true if the text says it was done, false if the text says',
    '  it was skipped, null if the text does not mention it.',
    '- Numbers are plain numbers without units. "15.5g" is 15.5.',
    '- A ratio written as "1:16" is the number 16.',
    '- Times are seconds unless the field name says minutes.',
    '- notes holds the drinker\'s impressions only (taste, body, what they',
    '  would change), never restated measurements.',
    '- Do not score the brew. Do not return any score, rating or quality',
    '  judgement. Something else does that.',
  ].join('\n');
}

const TARGETS: Record<string, string[]> = {
  espresso: [
    'Ratio (yieldGrams / doseGrams), weight 30. Target 1.8 to 2.2 for a',
    '  normal shot. Deduct in proportion to the distance outside that band;',
    '  0.3 outside is a small fault, 1.0 outside is a large one.',
    'Brew time (brewTimeSeconds), weight 25. Target 25 to 32 seconds.',
    '  Judge it together with the ratio: 20 seconds at 1:2 means the grind',
    '  ran fast, which is a real fault; 36 seconds at 1:1.5 is choked.',
    'Puck preparation, weight 20. puckPrepWdt, puckPrepDistribution and',
    '  puckPrepTamp are worth up to 7 each. Deduct only where the value is',
    '  false, meaning the step was deliberately skipped.',
    'Water temperature (waterTempC), weight 15. Target 90 to 96 for medium',
    '  roast; light roast tolerates the upper end, dark roast the lower.',
    'Coherence, weight 10. Do the dose, basket and machine make sense',
    '  together, and does anything in notes contradict the numbers?',
  ],
  v60: [
    'Ratio (waterGrams / doseGrams, or the ratio field), weight 30. Target',
    '  15 to 17. Outside 13 to 19 is a large fault.',
    'Total brew time (totalBrewTimeSeconds), weight 25. Target 150 to 210',
    '  seconds for a 15 g dose, scaling up with dose.',
    'Bloom, weight 20. bloomWaterGrams should be roughly two to three times',
    '  doseGrams, and bloomTimeSeconds 30 to 45.',
    'Water temperature (waterTempC), weight 15. Target 92 to 96.',
    'Pour structure (pourCount), weight 10. Target 3 to 5 pours after the',
    '  bloom. One pour is a fault; more than six is fussing.',
  ],
  aeropress: [
    'Ratio (waterGrams / doseGrams, or the ratio field), weight 30. Target',
    '  12 to 16 for a concentrate meant to be diluted, 14 to 17 drunk',
    '  straight. Judge from notes which was intended if it is stated.',
    'Steep time (steepTimeSeconds), weight 30. Target 60 to 120 seconds.',
    '  Under 45 is thin, over 180 is heavy and bitter.',
    'Water temperature (waterTempC), weight 25. Target 80 to 92. The',
    '  Aeropress is forgiving here, so deduct gently.',
    'Plunge (plungeTimeSeconds), weight 15. Target 20 to 30 seconds. A',
    '  plunge under 10 seconds means the grind was too coarse or the',
    '  pressure too high.',
  ],
};

export function scoreInstruction(
  method: BrewMethod,
  locale: Locale,
): string {
  const targets = TARGETS[method];
  if (!targets) throw new Error(`no rubric for ${method}`);

  return [
    `You are grading one ${method} against a fixed rubric. Rubric version`,
    `${RUBRIC_VERSION}. Apply the rubric as written, not your own taste.`,
    '',
    languageLine(locale),
    '',
    'Start from 100 and deduct. The weights below are the most a factor can',
    'cost. A factor inside its target range costs nothing.',
    '',
    ...targets.map((t) => `- ${t}`),
    '',
    'Rules:',
    '- If a field is null, the brewer did not record it. Do not deduct for',
    '  it. Ignore that factor and say in the reasons that it was not',
    '  recorded.',
    '- A boolean that is false is a deliberate omission and does count.',
    '- The final score is an integer from 0 to 100.',
    '- Give one short reason per factor you considered, in the order above.',
    '  Each reason states the value, how it compares to the target, and the',
    '  effect. Do not pad, do not encourage, do not add advice that is not',
    '  a consequence of a number in the rubric.',
    locale === 'id'
      ? '- Write every reason in Indonesian.'
      : '- Write every reason in English.',
  ].join('\n');
}

export function buildScoreResponseSchema(): Record<string, unknown> {
  return {
    type: 'object',
    properties: {
      score: { type: 'integer', minimum: 0, maximum: 100 },
      reasons: { type: 'array', items: { type: 'string' } },
    },
    required: ['score', 'reasons'],
  };
}
```

- [ ] **Step 4: Run the test to verify it passes**

```bash
cd worker && npx vitest run && npx tsc --noEmit
```

Expected: all passing.

- [ ] **Step 5: Commit**

```bash
git add worker/src/prompts.ts worker/test/prompts.test.ts
git commit -m "feat(worker): the parse instruction and rubric r1

The rubric is the opinionated part of this app, so it is written down
with explicit target ranges and weights per method rather than left to
the model's taste, and versioned so it can be revised without making
old scores unreadable.

The parse instruction forbids guessing in three different ways, because
a hallucinated dose is worse than a missing one: a missing value gets
asked about, a wrong one gets stored."
```

---

### Task 5: Rate limiting

**Files:**
- Create: `worker/src/ratelimit.ts`
- Test: `worker/test/ratelimit.test.ts`

**Interfaces:**
- Consumes: nothing.
- Produces: `interface CounterStore { get(key: string): Promise<string | null>; put(key: string, value: string, opts: { expirationTtl: number }): Promise<void> }` and `async function checkRateLimit(store: CounterStore, installId: string, now: number, limit?: number): Promise<{ allowed: boolean; used: number }>`.

`CounterStore` is the slice of `KVNamespace` this needs. Depending on two methods rather than the whole binding is what lets the tests use a ten-line fake.

- [ ] **Step 1: Write the failing test**

`worker/test/ratelimit.test.ts`:

```ts
import { describe, expect, it } from 'vitest';
import { checkRateLimit, type CounterStore } from '../src/ratelimit';

function fakeStore(): CounterStore & { data: Map<string, string> } {
  const data = new Map<string, string>();
  return {
    data,
    async get(k) { return data.get(k) ?? null; },
    async put(k, v) { data.set(k, v); },
  };
}

const DAY1 = Date.UTC(2026, 7, 12, 9, 0, 0);
const DAY2 = Date.UTC(2026, 7, 13, 9, 0, 0);

describe('checkRateLimit', () => {
  it('allows the first request', async () => {
    const res = await checkRateLimit(fakeStore(), 'install-a', DAY1);
    expect(res).toEqual({ allowed: true, used: 1 });
  });

  it('counts requests from the same install', async () => {
    const store = fakeStore();
    await checkRateLimit(store, 'install-a', DAY1);
    const res = await checkRateLimit(store, 'install-a', DAY1);
    expect(res).toEqual({ allowed: true, used: 2 });
  });

  it('refuses past the limit', async () => {
    const store = fakeStore();
    for (let i = 0; i < 5; i++) {
      await checkRateLimit(store, 'install-a', DAY1, 5);
    }
    const res = await checkRateLimit(store, 'install-a', DAY1, 5);
    expect(res.allowed).toBe(false);
  });

  it('keeps installs separate', async () => {
    const store = fakeStore();
    await checkRateLimit(store, 'install-a', DAY1, 1);
    const res = await checkRateLimit(store, 'install-b', DAY1, 1);
    expect(res.allowed).toBe(true);
  });

  it('resets the next day', async () => {
    const store = fakeStore();
    await checkRateLimit(store, 'install-a', DAY1, 1);
    const res = await checkRateLimit(store, 'install-a', DAY2, 1);
    expect(res).toEqual({ allowed: true, used: 1 });
  });

  it('fails open when the store throws', async () => {
    const broken: CounterStore = {
      async get() { throw new Error('kv down'); },
      async put() { throw new Error('kv down'); },
    };
    const res = await checkRateLimit(broken, 'install-a', DAY1);
    expect(res.allowed).toBe(true);
  });
});
```

Failing open is deliberate: this limiter exists to bound a leaked URL, not to protect revenue. A KV outage should not stop you logging your morning coffee.

- [ ] **Step 2: Run the test to verify it fails**

```bash
cd worker && npx vitest run test/ratelimit.test.ts
```

Expected: FAIL — cannot find `../src/ratelimit`.

- [ ] **Step 3: Write `worker/src/ratelimit.ts`**

```ts
export interface CounterStore {
  get(key: string): Promise<string | null>;
  put(
    key: string,
    value: string,
    opts?: { expirationTtl: number },
  ): Promise<void>;
}

export const DEFAULT_DAILY_LIMIT = 200;

const TWO_DAYS_SECONDS = 60 * 60 * 48;

function dayKey(installId: string, now: number): string {
  const d = new Date(now);
  const day = `${d.getUTCFullYear()}-${d.getUTCMonth() + 1}-${d.getUTCDate()}`;
  return `rl:${installId}:${day}`;
}

export async function checkRateLimit(
  store: CounterStore,
  installId: string,
  now: number,
  limit: number = DEFAULT_DAILY_LIMIT,
): Promise<{ allowed: boolean; used: number }> {
  const key = dayKey(installId, now);
  try {
    const raw = await store.get(key);
    const used = raw ? Number.parseInt(raw, 10) || 0 : 0;
    if (used >= limit) return { allowed: false, used };
    const next = used + 1;
    await store.put(key, String(next), { expirationTtl: TWO_DAYS_SECONDS });
    return { allowed: true, used: next };
  } catch {
    return { allowed: true, used: 0 };
  }
}
```

This counter races under concurrent requests — two simultaneous calls can both read the same value. That is acceptable: the limit is a ceiling on abuse, not an accounting record, and a single-user app does not issue concurrent requests. Durable Objects would fix it and are not worth the complexity here.

- [ ] **Step 4: Run the test to verify it passes**

```bash
cd worker && npx vitest run && npx tsc --noEmit
```

Expected: all passing.

- [ ] **Step 5: Commit**

```bash
git add worker/src/ratelimit.ts worker/test/ratelimit.test.ts
git commit -m "feat(worker): per-install daily rate limit over KV

Bounds the damage if the endpoint URL is read out of the APK. It fails
open on a KV error and races under concurrency, both on purpose: this
is a ceiling on abuse, not an accounting record, and a KV outage should
not stop the owner logging their morning coffee."
```

---

### Task 6: `POST /parse`

**Files:**
- Create: `worker/src/index.ts`
- Create: `worker/wrangler.toml`
- Test: `worker/test/parse_endpoint.test.ts`

**Interfaces:**
- Consumes: `buildParseResponseSchema`, `stripForeignFields`, `isBrewMethod`, `brewSchema` (Task 1–2); `callGemini` (Task 3); `parseInstruction` (Task 4); `checkRateLimit`, `CounterStore` (Task 5).
- Produces:
  - `interface Env { GEMINI_API_KEY: string; GEMINI_MODEL?: string; RATE_LIMIT: CounterStore }`
  - `interface Deps { fetchImpl: typeof fetch; now: () => number }`
  - `async function handleRequest(req: Request, env: Env, deps: Deps): Promise<Response>`
  - default export `{ fetch }` for wrangler.

- [ ] **Step 1: Write `worker/wrangler.toml`**

```toml
name = "kopi-kompas"
main = "src/index.ts"
compatibility_date = "2026-01-01"

[[kv_namespaces]]
binding = "RATE_LIMIT"
id = "REPLACE_WITH_NAMESPACE_ID"
```

The namespace id is filled in during deployment (Task 9) with the value
`wrangler kv namespace create RATE_LIMIT` prints. It is an identifier, not a
secret.

- [ ] **Step 2: Write the failing test**

`worker/test/parse_endpoint.test.ts`:

```ts
import { describe, expect, it, vi } from 'vitest';
import { handleRequest, type Env } from '../src/index';

function env(): Env {
  const data = new Map<string, string>();
  return {
    GEMINI_API_KEY: 'test-key',
    RATE_LIMIT: {
      async get(k) { return data.get(k) ?? null; },
      async put(k, v) { data.set(k, v); },
    },
  };
}

function geminiReturning(payload: unknown) {
  return vi.fn(async () => new Response(JSON.stringify({
    candidates: [{ content: { parts: [{ text: JSON.stringify(payload) }] } }],
  })));
}

function post(body: unknown, path = '/parse') {
  return new Request(`https://w.dev${path}`, {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify(body),
  });
}

const deps = (fetchImpl: any) => ({ fetchImpl, now: () => Date.now() });

const GOOD = {
  text: 'americano, 15.5g in 30g out in 25s, wdt and tamp, honduras medium',
  locale: 'en',
  installId: 'install-a',
};

describe('POST /parse', () => {
  it('returns the parsed entry', async () => {
    const f = geminiReturning({
      brewMethod: 'espresso',
      beanOrigin: 'honduras',
      roastLevel: 'medium',
      doseGrams: 15.5,
      methodData: { yieldGrams: 30, brewTimeSeconds: 25, puckPrepWdt: true },
    });
    const res = await handleRequest(post(GOOD), env(), deps(f));
    expect(res.status).toBe(200);
    const body = await res.json() as any;
    expect(body.brewMethod).toBe('espresso');
    expect(body.doseGrams).toBe(15.5);
    expect(body.methodData.yieldGrams).toBe(30);
  });

  it('strips fields foreign to the classified method', async () => {
    const f = geminiReturning({
      brewMethod: 'espresso',
      methodData: { yieldGrams: 30, eggYolkUsed: true },
    });
    const res = await handleRequest(post(GOOD), env(), deps(f));
    const body = await res.json() as any;
    expect(body.methodData.eggYolkUsed).toBeUndefined();
  });

  it('discards a score the model volunteers', async () => {
    const f = geminiReturning({
      brewMethod: 'espresso', overallScore: 95, score: 95, methodData: {},
    });
    const res = await handleRequest(post(GOOD), env(), deps(f));
    const body = await res.json() as any;
    expect(body.overallScore).toBeUndefined();
    expect(body.score).toBeUndefined();
  });

  it('502s when the model returns an unknown method', async () => {
    const f = geminiReturning({ brewMethod: 'pourover', methodData: {} });
    const res = await handleRequest(post(GOOD), env(), deps(f));
    expect(res.status).toBe(502);
  });

  it('400s on empty text', async () => {
    const f = geminiReturning({});
    const res = await handleRequest(
      post({ ...GOOD, text: '   ' }), env(), deps(f),
    );
    expect(res.status).toBe(400);
    expect(f).not.toHaveBeenCalled();
  });

  it('400s on a missing installId', async () => {
    const f = geminiReturning({});
    const res = await handleRequest(
      post({ text: 'x', locale: 'en' }), env(), deps(f),
    );
    expect(res.status).toBe(400);
  });

  it('400s on text longer than 2000 characters', async () => {
    const f = geminiReturning({});
    const res = await handleRequest(
      post({ ...GOOD, text: 'a'.repeat(2001) }), env(), deps(f),
    );
    expect(res.status).toBe(400);
    expect(f).not.toHaveBeenCalled();
  });

  it('defaults an unknown locale to en rather than failing', async () => {
    const f = geminiReturning({ brewMethod: 'espresso', methodData: {} });
    const res = await handleRequest(
      post({ ...GOOD, locale: 'fr' }), env(), deps(f),
    );
    expect(res.status).toBe(200);
  });

  it('429s once the install is over its limit', async () => {
    const e = env();
    const f = geminiReturning({ brewMethod: 'espresso', methodData: {} });
    for (let i = 0; i < 200; i++) {
      await handleRequest(post(GOOD), e, deps(f));
    }
    const res = await handleRequest(post(GOOD), e, deps(f));
    expect(res.status).toBe(429);
  });

  it('405s on GET', async () => {
    const res = await handleRequest(
      new Request('https://w.dev/parse'), env(), deps(geminiReturning({})),
    );
    expect(res.status).toBe(405);
  });

  it('404s on an unknown path', async () => {
    const res = await handleRequest(
      post(GOOD, '/nope'), env(), deps(geminiReturning({})),
    );
    expect(res.status).toBe(404);
  });

  it('never echoes the api key in an error body', async () => {
    const f = vi.fn(async () => new Response('nope', { status: 500 }));
    const res = await handleRequest(post(GOOD), env(), deps(f));
    expect(await res.text()).not.toContain('test-key');
  });
});
```

- [ ] **Step 3: Run the test to verify it fails**

```bash
cd worker && npx vitest run test/parse_endpoint.test.ts
```

Expected: FAIL — cannot find `../src/index`.

- [ ] **Step 4: Write `worker/src/index.ts`**

```ts
import {
  brewSchema, buildParseResponseSchema, isBrewMethod, stripForeignFields,
  type BrewMethod,
} from './schema';
import { callGemini } from './gemini';
import { parseInstruction, type Locale } from './prompts';
import { checkRateLimit, type CounterStore } from './ratelimit';

export interface Env {
  GEMINI_API_KEY: string;
  GEMINI_MODEL?: string;
  RATE_LIMIT: CounterStore;
}

export interface Deps {
  fetchImpl: typeof fetch;
  now: () => number;
}

const MAX_TEXT = 2000;
const DEFAULT_MODEL = 'gemini-2.5-flash';

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { 'content-type': 'application/json' },
  });
}

function error(status: number, message: string): Response {
  return json({ error: message }, status);
}

function toLocale(value: unknown): Locale {
  return value === 'id' ? 'id' : 'en';
}

export async function handleRequest(
  req: Request,
  env: Env,
  deps: Deps,
): Promise<Response> {
  const path = new URL(req.url).pathname;
  if (path !== '/parse' && path !== '/score') return error(404, 'not found');
  if (req.method !== 'POST') return error(405, 'method not allowed');

  let payload: any;
  try {
    payload = await req.json();
  } catch {
    return error(400, 'body must be json');
  }

  const installId = payload?.installId;
  if (typeof installId !== 'string' || installId.length === 0) {
    return error(400, 'installId is required');
  }

  const limit = await checkRateLimit(env.RATE_LIMIT, installId, deps.now());
  if (!limit.allowed) return error(429, 'daily limit reached');

  if (path === '/parse') return handleParse(payload, env, deps);
  return error(404, 'not found');
}

async function handleParse(
  payload: any,
  env: Env,
  deps: Deps,
): Promise<Response> {
  const text = typeof payload?.text === 'string' ? payload.text.trim() : '';
  if (text.length === 0) return error(400, 'text is required');
  if (text.length > MAX_TEXT) return error(400, 'text is too long');

  const result = await callGemini<any>({
    apiKey: env.GEMINI_API_KEY,
    model: env.GEMINI_MODEL ?? DEFAULT_MODEL,
    systemInstruction: parseInstruction(toLocale(payload.locale)),
    userText: text,
    responseSchema: buildParseResponseSchema(),
    fetchImpl: deps.fetchImpl,
  });

  if (!result.ok) return error(result.status, result.detail);

  const raw = result.value ?? {};
  if (!isBrewMethod(raw.brewMethod)) {
    return error(502, 'model returned an unknown brew method');
  }
  const method: BrewMethod = raw.brewMethod;

  const out: Record<string, unknown> = { brewMethod: method };
  for (const name of Object.keys(brewSchema.core)) {
    const value = raw[name];
    if (value !== null && value !== undefined) out[name] = value;
  }
  out.methodData = stripForeignFields(method, raw.methodData ?? {});

  return json(out);
}

export default {
  fetch(req: Request, env: Env): Promise<Response> {
    return handleRequest(req, env, {
      fetchImpl: globalThis.fetch.bind(globalThis),
      now: () => Date.now(),
    });
  },
};
```

Note the shape of the response: only `brewMethod` is guaranteed. Core fields that came back null are omitted rather than sent as `null`, so the Flutter side has one rule — a field that is absent is a field to ask about.

- [ ] **Step 5: Run the test to verify it passes**

```bash
cd worker && npx vitest run && npx tsc --noEmit
```

Expected: all passing.

- [ ] **Step 6: Commit**

```bash
git add worker/src/index.ts worker/wrangler.toml worker/test/parse_endpoint.test.ts
git commit -m "feat(worker): POST /parse

Validates, rate-limits, calls Gemini, then narrows the result to the
classified method's fields. A score volunteered by the model is dropped
here rather than trusted, and an unrecognised brewMethod is a 502 rather
than a row the app cannot render.

Absent beats null in the response: the app's rule is that a missing
field is one to ask about, so nulls never reach it."
```

---

### Task 7: `POST /score`

**Files:**
- Modify: `worker/src/index.ts`
- Test: `worker/test/score_endpoint.test.ts`

**Interfaces:**
- Consumes: everything from Task 6, plus `scoreInstruction`, `buildScoreResponseSchema`, `RUBRIC_VERSION` (Task 4) and `SCORED_METHODS` (Task 1).
- Produces: `POST /score` returning `{ score: number; reasons: string[]; rubric: string; model: string }`.

- [ ] **Step 1: Write the failing test**

`worker/test/score_endpoint.test.ts`:

```ts
import { describe, expect, it, vi } from 'vitest';
import { handleRequest, type Env } from '../src/index';

function env(): Env {
  const data = new Map<string, string>();
  return {
    GEMINI_API_KEY: 'test-key',
    RATE_LIMIT: {
      async get(k) { return data.get(k) ?? null; },
      async put(k, v) { data.set(k, v); },
    },
  };
}

function geminiReturning(payload: unknown) {
  return vi.fn(async () => new Response(JSON.stringify({
    candidates: [{ content: { parts: [{ text: JSON.stringify(payload) }] } }],
  })));
}

const deps = (fetchImpl: any) => ({ fetchImpl, now: () => Date.now() });

function scoreReq(entry: unknown) {
  return new Request('https://w.dev/score', {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify({ entry, locale: 'en', installId: 'install-a' }),
  });
}

const ESPRESSO = {
  brewMethod: 'espresso',
  doseGrams: 18,
  beanOrigin: 'honduras',
  roastLevel: 'medium',
  methodData: {
    yieldGrams: 36, brewTimeSeconds: 28,
    puckPrepWdt: true, puckPrepDistribution: true, puckPrepTamp: true,
  },
};

describe('POST /score', () => {
  it('returns the score with its rubric and model', async () => {
    const f = geminiReturning({ score: 88, reasons: ['Ratio 2.0:1 — on target'] });
    const res = await handleRequest(scoreReq(ESPRESSO), env(), deps(f));
    expect(res.status).toBe(200);
    const body = await res.json() as any;
    expect(body.score).toBe(88);
    expect(body.reasons).toEqual(['Ratio 2.0:1 — on target']);
    expect(body.rubric).toBe('r1');
    expect(body.model).toBe('gemini-2.5-flash');
  });

  it('sends the rubric for the entry\'s own method', async () => {
    const f = geminiReturning({ score: 70, reasons: ['x'] });
    await handleRequest(
      scoreReq({ ...ESPRESSO, brewMethod: 'v60', methodData: {} }),
      env(), deps(f),
    );
    const sent = JSON.parse((f as any).mock.calls[0][1].body);
    const instruction = sent.systemInstruction.parts[0].text;
    expect(instruction).toContain('v60');
    expect(instruction).not.toContain('Puck preparation');
  });

  it('422s for an unscored method without calling Gemini', async () => {
    const f = geminiReturning({ score: 50, reasons: [] });
    const res = await handleRequest(
      scoreReq({ ...ESPRESSO, brewMethod: 'kopiJoss' }), env(), deps(f),
    );
    expect(res.status).toBe(422);
    expect(f).not.toHaveBeenCalled();
  });

  it('400s on a missing entry', async () => {
    const res = await handleRequest(
      scoreReq(undefined), env(), deps(geminiReturning({})),
    );
    expect(res.status).toBe(400);
  });

  it('400s on an unknown brewMethod', async () => {
    const res = await handleRequest(
      scoreReq({ ...ESPRESSO, brewMethod: 'pourover' }),
      env(), deps(geminiReturning({})),
    );
    expect(res.status).toBe(400);
  });

  it('502s on a score above 100', async () => {
    const f = geminiReturning({ score: 140, reasons: ['x'] });
    const res = await handleRequest(scoreReq(ESPRESSO), env(), deps(f));
    expect(res.status).toBe(502);
  });

  it('502s on a negative score', async () => {
    const f = geminiReturning({ score: -3, reasons: ['x'] });
    const res = await handleRequest(scoreReq(ESPRESSO), env(), deps(f));
    expect(res.status).toBe(502);
  });

  it('502s on a non-integer score', async () => {
    const f = geminiReturning({ score: 82.5, reasons: ['x'] });
    const res = await handleRequest(scoreReq(ESPRESSO), env(), deps(f));
    expect(res.status).toBe(502);
  });

  it('502s when reasons are missing', async () => {
    const f = geminiReturning({ score: 82 });
    const res = await handleRequest(scoreReq(ESPRESSO), env(), deps(f));
    expect(res.status).toBe(502);
  });

  it('drops non-string entries from reasons', async () => {
    const f = geminiReturning({ score: 82, reasons: ['ok', 7, null] });
    const res = await handleRequest(scoreReq(ESPRESSO), env(), deps(f));
    const body = await res.json() as any;
    expect(body.reasons).toEqual(['ok']);
  });

  it('gives the model the entry as json', async () => {
    const f = geminiReturning({ score: 88, reasons: ['x'] });
    await handleRequest(scoreReq(ESPRESSO), env(), deps(f));
    const sent = JSON.parse((f as any).mock.calls[0][1].body);
    const userText = sent.contents[0].parts[0].text;
    expect(userText).toContain('yieldGrams');
    expect(userText).toContain('36');
  });
});
```

Rejecting an out-of-range score as a `502` rather than clamping it is
deliberate. A model returning 140 has misunderstood the rubric, and a clamped
100 would hide that behind a perfect score.

- [ ] **Step 2: Run the test to verify it fails**

```bash
cd worker && npx vitest run test/score_endpoint.test.ts
```

Expected: FAIL — all `/score` requests currently 404.

- [ ] **Step 3: Extend `worker/src/index.ts`**

Add to the imports:

```ts
import { SCORED_METHODS } from './schema';
import {
  RUBRIC_VERSION, buildScoreResponseSchema, scoreInstruction,
} from './prompts';
```

Replace the final line of `handleRequest`:

```ts
  if (path === '/parse') return handleParse(payload, env, deps);
  return handleScore(payload, env, deps);
```

And append:

```ts
async function handleScore(
  payload: any,
  env: Env,
  deps: Deps,
): Promise<Response> {
  const entry = payload?.entry;
  if (typeof entry !== 'object' || entry === null) {
    return error(400, 'entry is required');
  }
  if (!isBrewMethod(entry.brewMethod)) {
    return error(400, 'entry.brewMethod is not a known method');
  }
  const method: BrewMethod = entry.brewMethod;
  if (!SCORED_METHODS.includes(method)) {
    return error(422, `${method} is not scored`);
  }

  const model = env.GEMINI_MODEL ?? DEFAULT_MODEL;
  const result = await callGemini<any>({
    apiKey: env.GEMINI_API_KEY,
    model,
    systemInstruction: scoreInstruction(method, toLocale(payload.locale)),
    userText: JSON.stringify(entry),
    responseSchema: buildScoreResponseSchema(),
    fetchImpl: deps.fetchImpl,
  });

  if (!result.ok) return error(result.status, result.detail);

  const score = result.value?.score;
  if (
    typeof score !== 'number' || !Number.isInteger(score) ||
    score < 0 || score > 100
  ) {
    return error(502, 'model returned a score outside 0-100');
  }

  const rawReasons = result.value?.reasons;
  if (!Array.isArray(rawReasons)) {
    return error(502, 'model returned no reasons');
  }
  const reasons = rawReasons.filter(
    (r: unknown): r is string => typeof r === 'string' && r.length > 0,
  );

  return json({ score, reasons, rubric: RUBRIC_VERSION, model });
}
```

- [ ] **Step 4: Run the test to verify it passes**

```bash
cd worker && npx vitest run && npx tsc --noEmit
```

Expected: all passing across every test file.

- [ ] **Step 5: Commit**

```bash
git add worker/src/index.ts worker/test/score_endpoint.test.ts
git commit -m "feat(worker): POST /score

Sends the entry plus the rubric for its own method, and returns the
score with the rubric version and model that produced it so the app can
store all three. Unscored methods are a 422 without spending a request.

An out-of-range score is a 502 rather than a clamp: a model answering
140 has misread the rubric, and clamping would hide that behind a
perfect hundred."
```

---

### Task 8: Deployment documentation

**Files:**
- Create: `worker/README.md`
- Modify: `.gitignore` (add `worker/dist/`)

**Interfaces:**
- Consumes: the deployed shape of Tasks 1–7.
- Produces: documentation only.

- [ ] **Step 1: Write `worker/README.md`**

````markdown
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
comparing an `r1` score to an `r2` score is comparing two different
measurements. Leaving the version alone makes past scores silently wrong
rather than merely old.

## Adding a brew method

Edit `schema/brew_schema.json` — the field set, the EN and ID labels, and
whether it is scored. Both the Worker and the Flutter app read that file. If
the method is scored, add its entry to `TARGETS` in `src/prompts.ts` and bump
`RUBRIC_VERSION`. Then run `npm test`; the schema tests will tell you what you
missed.
````

- [ ] **Step 2: Add the build output to `.gitignore`**

Append to the Cloudflare Worker block:

```
worker/dist/
```

- [ ] **Step 3: Verify the whole suite and types are clean**

```bash
cd worker && npx vitest run && npx tsc --noEmit
```

Expected: every test passing, no type errors. Paste the output.

- [ ] **Step 4: Commit**

```bash
git add worker/README.md .gitignore
git commit -m "docs(worker): one-time setup, and the two rules for changing it

Bump RUBRIC_VERSION whenever the numbers move — every stored score
records the rubric that produced it, and leaving the version alone makes
old scores silently wrong rather than merely old. Adding a method starts
in schema/brew_schema.json, which the app reads too."
```

---

### Task 9: Deploy and verify against the real API

**Files:**
- Modify: `worker/wrangler.toml` (real KV namespace id)

**Interfaces:**
- Consumes: Tasks 1–8.
- Produces: a live URL for Phase 2's `KOPI_ENDPOINT`.

**This task needs the repository owner's Cloudflare account and Gemini key. An agent cannot complete it alone.**

- [ ] **Step 1: Follow `worker/README.md` setup steps 1–5**

- [ ] **Step 2: Verify `/parse` against the real API**

```bash
curl -sS "$KOPI_ENDPOINT/parse" -H 'content-type: application/json' \
  -d '{"text":"v60, 15g coffee, 250g water at 94, 45s bloom with 45g, 3 pours, done at 3:10","locale":"en","installId":"curl-test"}'
```

Expected: `brewMethod` is `v60`, `doseGrams` is 15, `methodData` holds
`waterGrams: 250`, `waterTempC: 94`, `bloomTimeSeconds: 45`,
`bloomWaterGrams: 45`, `pourCount: 3`, `totalBrewTimeSeconds: 190`, and **no
espresso fields at all**.

- [ ] **Step 3: Verify Indonesian input parses**

```bash
curl -sS "$KOPI_ENDPOINT/parse" -H 'content-type: application/json' \
  -d '{"text":"kopi tubruk, 20 gram, air 200ml, gula satu sendok, diamkan 4 menit","locale":"id","installId":"curl-test"}'
```

Expected: `brewMethod` is `kopiTubruk`, `sugarAdded` is `true`,
`steepTimeMinutes` is 4.

- [ ] **Step 4: Verify `/score` and check the rubric behaves**

```bash
curl -sS "$KOPI_ENDPOINT/score" -H 'content-type: application/json' \
  -d '{"entry":{"brewMethod":"espresso","doseGrams":18,"roastLevel":"medium","methodData":{"yieldGrams":36,"brewTimeSeconds":28,"puckPrepWdt":true,"puckPrepDistribution":true,"puckPrepTamp":true,"waterTempC":93}},"locale":"en","installId":"curl-test"}'
```

Expected: a high score — every factor is inside its target band — with one
reason per factor, `rubric: "r1"`.

Then a deliberately bad shot:

```bash
curl -sS "$KOPI_ENDPOINT/score" -H 'content-type: application/json' \
  -d '{"entry":{"brewMethod":"espresso","doseGrams":18,"roastLevel":"medium","methodData":{"yieldGrams":72,"brewTimeSeconds":12,"puckPrepWdt":false,"puckPrepDistribution":false,"puckPrepTamp":false}},"locale":"en","installId":"curl-test"}'
```

Expected: a low score, with reasons naming the 4:1 ratio, the 12-second
gusher, and the three skipped puck-prep steps.

- [ ] **Step 5: Verify an unscored method is refused**

```bash
curl -sS -o /dev/null -w '%{http_code}\n' "$KOPI_ENDPOINT/score" \
  -H 'content-type: application/json' \
  -d '{"entry":{"brewMethod":"kopiJoss","doseGrams":20,"methodData":{}},"locale":"en","installId":"curl-test"}'
```

Expected: `422`.

- [ ] **Step 6: Run the same scored espresso three times and record the spread**

The spec accepts that an AI score is not reproducible; this measures how much.
Run step 4's good-shot command three times and note the three values in the
commit message. If the spread exceeds about 10 points, the rubric is too vague
— tighten the wording of the weights before Phase 2 relies on it.

- [ ] **Step 7: Commit the namespace id**

```bash
git add worker/wrangler.toml
git commit -m "chore(worker): point at the real rate-limit namespace

Deployed and verified against the live API: English and Indonesian both
parse to the right method, a good espresso and a bad one land where the
rubric says they should, and kopiJoss is refused with a 422.

Repeat-score spread on an identical entry: <fill in the three values>."
```

---

## Definition of done

- `cd worker && npx vitest run` passes with every test green, and
  `npx tsc --noEmit` is clean.
- No Gemini API key appears anywhere in the repository history.
- `/parse` classifies all eight methods and returns only the classified
  method's fields.
- `/score` returns a 0–100 integer with reasons, the rubric version and the
  model, and refuses the five unscored methods with a 422.
- `worker/README.md` is enough for someone with no context to deploy it.
- The deployed URL is recorded for Phase 2's `KOPI_ENDPOINT`.

## What Phase 2 inherits

- `schema/brew_schema.json`, read by the Flutter form generator.
- The two endpoints and their exact error codes.
- The fact that a parse response **omits** unknown fields rather than sending
  `null` — the app's rule becomes "absent means ask".
- `rubric` and `model` on every score, to be stored in the `scoreRubric` and
  `scoreModel` columns.
