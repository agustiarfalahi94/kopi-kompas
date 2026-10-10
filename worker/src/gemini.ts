import { generateWithFallback } from './model_router';

export type GeminiResult<T> =
  | { ok: true; value: T; model: string }
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
  const body = {
    systemInstruction: { parts: [{ text: opts.systemInstruction }] },
    contents: [{ role: 'user', parts: [{ text: opts.userText }] }],
    generationConfig: {
      responseMimeType: 'application/json',
      responseSchema: opts.responseSchema,
    },
  };

  let response: Response;
  let requestedModel = opts.model;
  try {
    const result = await generateWithFallback({
      apiKey: opts.apiKey, model: opts.model, fetchImpl: opts.fetchImpl,
      body: (model: string) => ({
        ...body,
        generationConfig: {
          ...body.generationConfig,
          ...(!model.includes('flash-lite') &&
            (model === 'gemini-flash-latest' || Number(/^gemini-(\d+)/.exec(model)?.[1]) >= 3)
            ? { thinkingConfig: { thinkingLevel: 'low' } } : {}),
        },
      }),
    });
    response = result.response;
    requestedModel = result.model;
  } catch (e) {
    return { ok: false, status: 502, detail: `gemini unreachable: ${e}` };
  }

  if (response.status === 429) {
    // Keep the upstream text: a per-minute limit clears on its own and a
    // per-day one does not, and the app should be able to say which.
    const body = await response.text().catch(() => '');
    return {
      ok: false,
      status: 429,
      detail: `gemini quota: ${body.slice(0, 900)}`,
    };
  }
  if (!response.ok) {
    // The upstream message is worth keeping: "model not found" and "billing
    // required" are the same status here and very different problems. Gemini
    // never echoes the key back, so this leaks nothing.
    const body = await response.text().catch(() => '');
    return {
      ok: false,
      status: 502,
      detail: `gemini ${response.status}: ${body.slice(0, 900)}`,
    };
  }

  let envelope: any;
  try {
    envelope = await response.json();
  } catch {
    return { ok: false, status: 502, detail: 'gemini sent non-json' };
  }

  const parts = envelope?.candidates?.[0]?.content?.parts;
  const text = Array.isArray(parts) ? parts
    .filter(part => part?.thought !== true && typeof part?.text === 'string')
    .map(part => part.text).join('') : '';
  if (!text) {
    return { ok: false, status: 502, detail: 'gemini sent no candidate' };
  }

  try {
    const model = typeof envelope.modelVersion === 'string' && envelope.modelVersion.trim()
      ? envelope.modelVersion : requestedModel;
    return { ok: true, value: JSON.parse(text) as T, model };
  } catch {
    return { ok: false, status: 502, detail: 'candidate was not json' };
  }
}
