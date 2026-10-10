const API = 'https://generativelanguage.googleapis.com/v1beta/models';
const CACHE_MS = 60 * 60 * 1000;
interface ListedModel { name?: string; supportedGenerationMethods?: string[] }
const catalogs = new WeakMap<typeof fetch, Map<string, {
  expires: number; models: ListedModel[];
}>>();

async function timedFetch(
  fetchImpl: typeof fetch, url: string, init: RequestInit, timeout: number,
): Promise<Response> {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), timeout);
  try {
    const response = await fetchImpl(url, { ...init, signal: controller.signal });
    const body = response.body ? await response.text() : null;
    return new Response(body, { status: response.status, headers: response.headers });
  } finally {
    clearTimeout(timer);
  }
}

async function compatibleModels(
  apiKey: string, preferred: string, fetchImpl: typeof fetch, deadline: number,
): Promise<string[]> {
  let cache = catalogs.get(fetchImpl);
  if (!cache) { cache = new Map(); catalogs.set(fetchImpl, cache); }
  let entry = cache.get(apiKey);
  if (!entry || entry.expires <= Date.now()) {
    const models: ListedModel[] = [];
    let token: string | undefined;
    try {
      for (let page = 0; page < 3; page++) {
        const url = `${API}?pageSize=1000${token ? `&pageToken=${encodeURIComponent(token)}` : ''}`;
        if (Date.now() >= deadline) return [];
        const response = await timedFetch(fetchImpl, url, {
          headers: { 'x-goog-api-key': apiKey },
        }, Math.min(5000, deadline - Date.now()));
        if (!response.ok) return [];
        const body = await response.json() as { models?: ListedModel[]; nextPageToken?: string };
        if (!Array.isArray(body.models)) return [];
        models.push(...body.models);
        token = body.nextPageToken;
        if (!token) break;
      }
    } catch { return []; }
    entry = { expires: Date.now() + CACHE_MS, models };
    cache.set(apiKey, entry);
  }
  const lite = preferred.includes('flash-lite');
  const eligible = entry.models.flatMap(model => {
    const name = model.name?.replace(/^models\//, '') ?? '';
    const match = /^gemini-(\d+(?:\.\d+){0,2})-flash(-lite)?$/.exec(name);
    if (!match || Boolean(match[2]) !== lite ||
      !model.supportedGenerationMethods?.includes('generateContent')) return [];
    return [{ name, version: match[1]!.split('.').map(Number) }];
  });
  eligible.sort((a, b) => {
    for (let i = 0; i < Math.max(a.version.length, b.version.length); i++) {
      const delta = (b.version[i] ?? 0) - (a.version[i] ?? 0);
      if (delta) return delta;
    }
    return 0;
  });
  return [...new Set(eligible.map(model => model.name))].filter(name => name !== preferred);
}

export async function generateWithFallback(options: {
  apiKey: string; model: string; body: unknown; fetchImpl: typeof fetch;
}): Promise<{ response: Response; model: string }> {
  const init = {
    method: 'POST', headers: {
      'content-type': 'application/json', 'x-goog-api-key': options.apiKey,
    },
  };
  const deadline = Date.now() + 40_000;
  const send = async (model: string) => {
    if (Date.now() >= deadline) throw new Error('Gemini request timed out');
    const body = typeof options.body === 'function' ? options.body(model) : options.body;
    try {
      return await timedFetch(options.fetchImpl,
        `${API}/${encodeURIComponent(model)}:generateContent`, {
          ...init, body: JSON.stringify(body),
        }, Math.min(15_000, deadline - Date.now()));
    } catch (error) {
      if (error instanceof Error && error.name === 'AbortError') {
        return new Response(JSON.stringify({ error: 'Gemini generation timed out' }), { status: 503 });
      }
      throw error;
    }
  };
  const preferred = options.model.replace(/^models\//, '').trim();
  let model = preferred;
  let response = await send(model);
  if (response.status !== 404 && response.status !== 503) return { response, model };

  const alternatives = await compatibleModels(options.apiKey, preferred, options.fetchImpl, deadline);
  for (const candidate of alternatives.slice(0, 2)) {
    // Release the failed body before making another upstream request.
    await response.body?.cancel().catch(() => undefined);
    model = candidate;
    response = await send(model);
    if (response.status !== 404 && response.status !== 503) break;
  }
  return { response, model };
}
