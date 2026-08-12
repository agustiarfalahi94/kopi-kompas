import { describe, expect, it, vi } from 'vitest';
import { callGemini } from '../src/gemini';

const base = {
  apiKey: 'test-key',
  model: 'gemini-3.6-flash',
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
    expect(res).toEqual({ ok: false, status: 429, detail: expect.stringContaining('gemini quota') });
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
