import { describe, expect, it } from 'vitest';
import { checkRateLimit, type CounterStore } from '../src/ratelimit';

function fakeStore(): CounterStore & { data: Map<string, string> } {
  const data = new Map<string, string>();
  return {
    data,
    async get(k) { return data.get(k) ?? null; },
    async put(k, v) { data.set(k, v); },
  };
}

const DAY1 = Date.UTC(2026, 7, 12, 9, 0, 0);
const DAY2 = Date.UTC(2026, 7, 13, 9, 0, 0);

describe('checkRateLimit', () => {
  it('allows the first request', async () => {
    const res = await checkRateLimit(fakeStore(), 'install-a', DAY1);
    expect(res).toEqual({ allowed: true, used: 1 });
  });

  it('counts requests from the same install', async () => {
    const store = fakeStore();
    await checkRateLimit(store, 'install-a', DAY1);
    const res = await checkRateLimit(store, 'install-a', DAY1);
    expect(res).toEqual({ allowed: true, used: 2 });
  });

  it('refuses past the limit', async () => {
    const store = fakeStore();
    for (let i = 0; i < 5; i++) {
      await checkRateLimit(store, 'install-a', DAY1, 5);
    }
    const res = await checkRateLimit(store, 'install-a', DAY1, 5);
    expect(res.allowed).toBe(false);
  });

  it('keeps installs separate', async () => {
    const store = fakeStore();
    await checkRateLimit(store, 'install-a', DAY1, 1);
    const res = await checkRateLimit(store, 'install-b', DAY1, 1);
    expect(res.allowed).toBe(true);
  });

  it('resets the next day', async () => {
    const store = fakeStore();
    await checkRateLimit(store, 'install-a', DAY1, 1);
    const res = await checkRateLimit(store, 'install-a', DAY2, 1);
    expect(res).toEqual({ allowed: true, used: 1 });
  });

  it('fails open when the store throws', async () => {
    const broken: CounterStore = {
      async get() { throw new Error('kv down'); },
      async put() { throw new Error('kv down'); },
    };
    const res = await checkRateLimit(broken, 'install-a', DAY1);
    expect(res.allowed).toBe(true);
  });
});
