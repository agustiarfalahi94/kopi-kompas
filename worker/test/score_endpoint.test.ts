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
    expect(body.model).toBe('gemini-3.5-flash');
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
