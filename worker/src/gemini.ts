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
