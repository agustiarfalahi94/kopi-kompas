export interface CounterStore {
  get(key: string): Promise<string | null>;
  put(
    key: string,
    value: string,
    opts?: { expirationTtl: number },
  ): Promise<void>;
}

export const DEFAULT_DAILY_LIMIT = 200;

const TWO_DAYS_SECONDS = 60 * 60 * 48;

function dayKey(installId: string, now: number): string {
  const d = new Date(now);
  const day = `${d.getUTCFullYear()}-${d.getUTCMonth() + 1}-${d.getUTCDate()}`;
  return `rl:${installId}:${day}`;
}

export async function checkRateLimit(
  store: CounterStore,
  installId: string,
  now: number,
  limit: number = DEFAULT_DAILY_LIMIT,
): Promise<{ allowed: boolean; used: number }> {
  const key = dayKey(installId, now);
  try {
    const raw = await store.get(key);
    const used = raw ? Number.parseInt(raw, 10) || 0 : 0;
    if (used >= limit) return { allowed: false, used };
    const next = used + 1;
    await store.put(key, String(next), { expirationTtl: TWO_DAYS_SECONDS });
    return { allowed: true, used: next };
  } catch {
    return { allowed: true, used: 0 };
  }
}
