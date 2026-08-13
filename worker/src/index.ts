import {
  brewSchema, buildParseResponseSchema, isBrewMethod, stripForeignFields,
  SCORED_METHODS, type BrewMethod,
} from './schema';
import { callGemini } from './gemini';
import {
  RUBRIC_VERSION, buildScoreResponseSchema, parseInstruction,
  scoreInstruction, type Locale,
} from './prompts';
import { checkRateLimit, type CounterStore } from './ratelimit';

export interface Env {
  GEMINI_API_KEY: string;
  GEMINI_PARSE_MODEL?: string;
  GEMINI_SCORE_MODEL?: string;
  RATE_LIMIT: CounterStore;
}

export interface Deps {
  fetchImpl: typeof fetch;
  now: () => number;
}

const MAX_TEXT = 2000;

// Two models on purpose. Parsing is mechanical extraction and a lite model
// does it well; scoring applies a rubric and wants the fuller model. The free
// tier meters each model separately, so splitting the two endpoints also
// doubles the daily allowance instead of spending one pool on both.
//
// Both pinned, never an alias like `gemini-flash-latest`. Every score records
// the model that produced it, so an old score stays interpretable; an alias
// would keep writing one name while the model underneath changed, defeating
// exactly the provenance that column exists for.
const DEFAULT_PARSE_MODEL = 'gemini-3.5-flash-lite';
const DEFAULT_SCORE_MODEL = 'gemini-3.5-flash';

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
  return handleScore(payload, env, deps);
}

async function handleParse(
  payload: any,
  env: Env,
  deps: Deps,
): Promise<Response> {
  const text = typeof payload?.text === 'string' ? payload.text.trim() : '';
  if (text.length === 0) return error(400, 'text is required');
  if (text.length > MAX_TEXT) return error(400, 'text is too long');

  // The app sends its own wall clock, because the Worker's is UTC and a
  // brewer's "this morning" is not a UTC morning.
  const nowLocal = localClock(payload?.now);

  const result = await callGemini<any>({
    apiKey: env.GEMINI_API_KEY,
    model: env.GEMINI_PARSE_MODEL ?? DEFAULT_PARSE_MODEL,
    systemInstruction: parseInstruction(toLocale(payload.locale), nowLocal),
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
  const brewedAt = sanitiseBrewedAt(raw.brewedAt, nowLocal);
  if (brewedAt) out.brewedAt = brewedAt;
  for (const name of Object.keys(brewSchema.core)) {
    const value = raw[name];
    if (value !== null && value !== undefined) out[name] = value;
  }
  out.methodData = stripForeignFields(method, raw.methodData ?? {});

  return json(out);
}

/** A local wall clock, `YYYY-MM-DDTHH:MM:SS`, with no zone and no offset. */
const LOCAL_DATETIME = /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}(:\d{2})?$/;

/// The app's own clock, accepted only in the exact shape the prompt quotes.
///
/// Undefined when absent or malformed, which drops the whole clock block from
/// the instruction rather than quoting a time that is not the brewer's — a
/// wrong "now" would silently misdate every relative expression in the text.
function localClock(value: unknown): string | undefined {
  if (typeof value !== 'string' || !LOCAL_DATETIME.test(value)) return undefined;
  return value;
}

/// What the model returned, or nothing.
///
/// Rejects anything that is not a bare local datetime, and anything in the
/// future: a model that resolves "this morning" against its own idea of today
/// can hand back tomorrow, and a brew logged for tomorrow would sit at the top
/// of the log forever and count as an already-logged day for the reminder.
export function sanitiseBrewedAt(
  value: unknown,
  nowLocal: string | undefined,
): string | undefined {
  if (typeof value !== 'string' || !LOCAL_DATETIME.test(value)) return undefined;
  const at = Date.parse(`${value.length === 16 ? `${value}:00` : value}Z`);
  if (Number.isNaN(at)) return undefined;
  if (nowLocal !== undefined) {
    // A minute of slack, so a brew logged the instant it finished is not
    // rejected for being a few seconds ahead of the clock we were sent.
    const now = Date.parse(`${nowLocal.length === 16 ? `${nowLocal}:00` : nowLocal}Z`);
    if (!Number.isNaN(now) && at > now + 60_000) return undefined;
  }
  return value.length === 16 ? `${value}:00` : value;
}

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

  const model = env.GEMINI_SCORE_MODEL ?? DEFAULT_SCORE_MODEL;
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

export default {
  fetch(req: Request, env: Env): Promise<Response> {
    return handleRequest(req, env, {
      fetchImpl: globalThis.fetch.bind(globalThis),
      now: () => Date.now(),
    });
  },
};
