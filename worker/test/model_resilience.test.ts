import { describe, expect, it, vi } from 'vitest';
import { callGemini } from '../src/gemini';

const opts = {
  apiKey: 'test-key', model: 'gemini-flash-latest',
  systemInstruction: 'Apply the espresso rubric', userText: '{}',
  responseSchema: { type: 'object' },
};
const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status });
const answer = (modelVersion = 'gemini-3.8-flash') => json({
  modelVersion, candidates: [{ content: { parts: [
    { text: 'private reasoning', thought: true },
    { text: '{"score":' }, { text: '82}' },
  ] } }],
});
const catalog = () => json({ models: [
  ...['gemini-3.7-flash', 'gemini-3.8-flash', 'gemini-3.10-flash',
    'gemini-9.0-flash-preview', 'gemini-9.0-flash-tts', 'gemini-9.0-flash-lite']
    .map(name => ({ name: `models/${name}`, supportedGenerationMethods: ['generateContent'] })),
  { name: 'models/gemini-10.0-flash', supportedGenerationMethods: ['embedContent'] },
] });

describe('Gemini model resilience', () => {
  it('falls back when the preferred model times out before headers', async () => {
    const fetchImpl = vi.fn()
      .mockRejectedValueOnce(new DOMException('timed out', 'AbortError'))
      .mockResolvedValueOnce(catalog())
      .mockResolvedValueOnce(answer('gemini-3.10-flash'));
    const result = await callGemini({ ...opts, fetchImpl: fetchImpl as any });
    expect(result).toMatchObject({ ok: true, model: 'gemini-3.10-flash' });
    expect(fetchImpl.mock.calls).toHaveLength(3);
  });
  it('uses low thinking only on compatible full Flash requests', async () => {
    const fetchImpl = vi.fn(async () => answer());
    await callGemini({ ...opts, fetchImpl: fetchImpl as any });
    const init = (fetchImpl.mock.calls as any[][])[0]![1];
    expect(JSON.parse(init.body).generationConfig.thinkingConfig).toEqual({ thinkingLevel: 'low' });
  });

  it('does not carry newer thinking controls to an older fallback', async () => {
    const fetchImpl = vi.fn().mockResolvedValueOnce(json({}, 404))
      .mockResolvedValueOnce(json({ models: [
        { name: 'models/gemini-2.5-flash', supportedGenerationMethods: ['generateContent'] },
      ] }))
      .mockResolvedValueOnce(answer('gemini-2.5-flash'));
    await callGemini({ ...opts, fetchImpl: fetchImpl as any });
    const init = fetchImpl.mock.calls[2]![1];
    expect(JSON.parse(init.body).generationConfig).not.toHaveProperty('thinkingConfig');
  });
  it('records the resolved model and joins answer parts without thoughts', async () => {
    const fetchImpl = vi.fn(async () => answer());
    const result = await callGemini({ ...opts, fetchImpl: fetchImpl as any });
    expect(result).toEqual({ ok: true, value: { score: 82 }, model: 'gemini-3.8-flash' });
  });

  it.each([404, 503])('discovers the newest compatible stable Flash after %i', async status => {
    const fetchImpl = vi.fn()
      .mockResolvedValueOnce(json({ error: { message: 'unavailable' } }, status))
      .mockResolvedValueOnce(catalog())
      .mockResolvedValueOnce(answer('gemini-3.10-flash'));
    const result = await callGemini({ ...opts, fetchImpl: fetchImpl as any });
    expect(result.ok).toBe(true);
    expect(String(fetchImpl.mock.calls[2]![0])).toContain('/gemini-3.10-flash:');
    expect(fetchImpl.mock.calls[1]![1].headers['x-goog-api-key']).toBe('test-key');
  });

  it.each([400, 401, 403, 429])('does not spend extra requests on %i', async status => {
    const fetchImpl = vi.fn(async () => json({ error: 'quota or configuration' }, status));
    const result = await callGemini({ ...opts, fetchImpl: fetchImpl as any });
    expect(result.ok).toBe(false);
    expect(fetchImpl).toHaveBeenCalledTimes(1);
  });

  it('limits a completely unavailable catalog to three generation attempts', async () => {
    const fetchImpl = vi.fn(async (url: string) => url.includes('?pageSize=')
      ? catalog() : json({ error: 'busy' }, 503));
    await callGemini({ ...opts, fetchImpl: fetchImpl as any });
    expect(fetchImpl.mock.calls.filter(([url]) => url.includes(':generateContent'))).toHaveLength(3);
  });

  it('reuses the catalog for the same key and fetch implementation', async () => {
    const fetchImpl = vi.fn(async (url: string) => url.includes('?pageSize=')
      ? catalog() : url.includes('latest:') ? json({}, 404) : answer());
    await callGemini({ ...opts, fetchImpl: fetchImpl as any });
    await callGemini({ ...opts, fetchImpl: fetchImpl as any });
    expect(fetchImpl.mock.calls.filter(([url]) => url.includes('?pageSize='))).toHaveLength(1);
  });

  it('keeps parsing in the lite family and preserves the response schema', async () => {
    const fetchImpl = vi.fn(async (url: string) => url.includes('?pageSize=')
      ? catalog() : url.includes('latest:') ? json({}, 404) : answer('gemini-9.0-flash-lite'));
    await callGemini({ ...opts, model: 'gemini-flash-lite-latest', fetchImpl: fetchImpl as any });
    const calls = fetchImpl.mock.calls as any[][];
    const [url, init] = calls[calls.length - 1]!;
    expect(url).toContain('gemini-9.0-flash-lite:generateContent');
    const body = JSON.parse(init.body);
    expect(body.generationConfig.responseSchema).toEqual(opts.responseSchema);
    expect(body.generationConfig).not.toHaveProperty('temperature');
  });

  it('preserves the original error if model discovery fails', async () => {
    const fetchImpl = vi.fn().mockResolvedValueOnce(json({ error: 'busy' }, 503))
      .mockRejectedValueOnce(new Error('offline'));
    const result = await callGemini({ ...opts, fetchImpl: fetchImpl as any });
    expect(result).toMatchObject({ ok: false, status: 502, detail: expect.stringContaining('503') });
    expect(fetchImpl).toHaveBeenCalledTimes(2);
  });
});
