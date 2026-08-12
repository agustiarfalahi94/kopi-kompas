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
