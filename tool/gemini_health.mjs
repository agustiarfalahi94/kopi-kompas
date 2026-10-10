const endpoint = process.env.KOPI_ENDPOINT || 'https://kopi-kompas.inkpebble.workers.dev';
const installId = 'gemini-health-check';
async function post(path, payload) {
  const response = await fetch(`${endpoint}/${path}`, {
    method: 'POST', headers: { 'content-type': 'application/json' },
    body: JSON.stringify({ installId, locale: 'en', ...payload }),
    signal: AbortSignal.timeout(45_000),
  });
  if (!response.ok) throw new Error(`${path} returned HTTP ${response.status}: ${(await response.text()).slice(0, 1000)}`);
  return response.json();
}
const parsed = await post('parse', { text: 'An espresso, 18g in, 36g out in 28 seconds.' });
if (parsed.brewMethod !== 'espresso') throw new Error('Parse did not recognise the synthetic espresso');
const score = await post('score', { entry: {
  brewMethod: 'espresso', doseGrams: 18, roastLevel: 'medium',
  methodData: { yieldGrams: 36, brewTimeSeconds: 28 },
} });
if (!Number.isInteger(score.score) || score.score < 0 || score.score > 100 ||
  !Array.isArray(score.reasons) || !score.reasons.every(reason => typeof reason === 'string') ||
  typeof score.model !== 'string' || !score.model.trim() ||
  typeof score.rubric !== 'string' || !score.rubric.trim()) {
  throw new Error('Score response failed schema/provenance checks');
}
console.log(`Parsing and scoring passed; model=${score.model}, rubric=${score.rubric}`);
