import { describe, expect, it, vi } from 'vitest';
import { handleRequest, type Env } from '../src/index';
import { parseInstruction } from '../src/prompts';
import { buildParseResponseSchema } from '../src/schema';

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

function post(body: unknown) {
  return new Request('https://w.dev/parse', {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify(body),
  });
}

const deps = (fetchImpl: any) => ({ fetchImpl, now: () => Date.now() });

const NOW = '2026-08-13T14:00:00';

/// `now` defaults to the fixed clock; pass undefined for an older app build
/// that sends none.
async function parseWith(brewedAt: unknown, now: string | undefined = NOW) {
  const f = geminiReturning({
    brewMethod: 'espresso',
    brewedAt,
    methodData: {},
  });
  const request = post({
    text: 'espresso yesterday at 11.30 am',
    locale: 'en',
    installId: 'install-a',
    ...(now === undefined ? {} : { now }),
  });
  const res = await handleRequest(request, env(), deps(f));
  return { body: (await res.json()) as any, sent: f };
}

describe('the response schema', () => {
  it('offers brewedAt, nullable and required like everything else', () => {
    const s = buildParseResponseSchema() as any;
    expect(s.properties.brewedAt).toEqual({ type: 'string', nullable: true });
    // Both, always. A property that is required but not nullable makes the
    // constrained decoder fill the slot with whatever is nearby.
    expect(s.required).toContain('brewedAt');
  });
});

describe('the parse prompt', () => {
  it('says nothing about a clock when the app sent none', () => {
    const p = parseInstruction('en');
    expect(p).not.toContain('brewedAt');
    // And keeps the old honest answer for relative roast dates.
    expect(p).toContain('is not a date you can compute');
  });

  it('quotes the clock the app sent', () => {
    const p = parseInstruction('en', NOW);
    expect(p).toContain(NOW);
    expect(p).toContain('brewedAt');
    expect(p).toContain('12:00:00');
  });

  it('stops refusing relative roast dates once it has a clock', () => {
    expect(parseInstruction('en', NOW)).not.toContain(
      'is not a date you can compute',
    );
  });
});

describe('POST /parse brewedAt', () => {
  it('passes a stated brew time through', async () => {
    const { body } = await parseWith('2026-08-12T11:30:00');
    expect(body.brewedAt).toBe('2026-08-12T11:30:00');
  });

  it('accepts a minute-precision time and pads the seconds', async () => {
    const { body } = await parseWith('2026-08-12T11:30');
    expect(body.brewedAt).toBe('2026-08-12T11:30:00');
  });

  it('omits brewedAt when the text said nothing about when', async () => {
    // Absent, not now. The app falls back to its own clock, and the two cases
    // must stay distinguishable.
    const { body } = await parseWith(null);
    expect(body.brewedAt).toBeUndefined();
  });

  it('drops a time in the future', async () => {
    // A model resolving "this morning" against its own idea of today can hand
    // back tomorrow, which would pin the entry to the top of the log forever.
    const { body } = await parseWith('2026-08-14T09:00:00');
    expect(body.brewedAt).toBeUndefined();
  });

  it('allows a minute of slack for a brew logged as it finishes', async () => {
    const { body } = await parseWith('2026-08-13T14:00:30');
    expect(body.brewedAt).toBe('2026-08-13T14:00:30');
  });

  it('drops anything carrying a zone', async () => {
    // Local wall clock only. An offset would be parsed as UTC on the way in
    // and file an 00:30 brew under the previous day.
    const { body } = await parseWith('2026-08-12T11:30:00+07:00');
    expect(body.brewedAt).toBeUndefined();
  });

  it('drops a date with no time', async () => {
    const { body } = await parseWith('2026-08-12');
    expect(body.brewedAt).toBeUndefined();
  });

  it('drops a non-string', async () => {
    const { body } = await parseWith(42);
    expect(body.brewedAt).toBeUndefined();
  });

  it('still parses when the app sent no clock at all', async () => {
    // An older app build. It gets no brewedAt rather than a broken parse.
    const { body } = await parseWith('2026-08-12T11:30:00', undefined);
    expect(body.brewMethod).toBe('espresso');
  });

  it('ignores a malformed clock rather than quoting it at the model', async () => {
    const f = geminiReturning({ brewMethod: 'espresso', methodData: {} });
    await handleRequest(
      post({ text: 'espresso', locale: 'en', installId: 'a', now: 'tuesday' }),
      env(),
      deps(f),
    );
    const sent = JSON.parse((f as any).mock.calls[0][1].body);
    expect(sent.systemInstruction.parts[0].text).not.toContain('tuesday');
  });
});
