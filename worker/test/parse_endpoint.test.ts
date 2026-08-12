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
