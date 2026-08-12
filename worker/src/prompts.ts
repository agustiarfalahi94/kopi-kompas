import { brewSchema, METHODS, type BrewMethod } from './schema';

export const RUBRIC_VERSION = 'r1';

export type Locale = 'en' | 'id';

function languageLine(locale: Locale): string {
  return locale === 'id'
    ? 'The user writes in Indonesian. Understand Indonesian coffee ' +
      'vocabulary (gula, sangrai, kental, tubruk, saring, kocok) and write ' +
      'any prose you produce in Indonesian.'
    : 'The user writes in English.';
}

export function parseInstruction(locale: Locale): string {
  const methods = METHODS.map((m) => {
    const fields = Object.keys(brewSchema.methods[m].fields).join(', ');
    return `- ${m}: ${fields}`;
  }).join('\n');

  return [
    'You extract structured data from a short, informal description of a',
    'coffee someone just brewed. You are a parser, not an assistant.',
    '',
    languageLine(locale),
    '',
    'First classify brewMethod. It must be exactly one of the eight values',
    'below, chosen from what the text describes:',
    '',
    methods,
    '',
    'Then extract the core fields (beanOrigin, roastLevel, doseGrams,',
    'grindSize, notes) and, in methodData, only the fields listed above for',
    'the method you chose. Leave every field belonging to another method',
    'absent.',
    '',
    'Rules:',
    '- Use null for anything not stated or not clear. Do not guess, do not',
    '  infer a typical value, and do not fill a field because it is usually',
    '  present. A missing value will be asked about; a wrong one will not.',
    '- Booleans: true if the text says it was done, false if the text says',
    '  it was skipped, null if the text does not mention it.',
    '- Numbers are plain numbers without units. "15.5g" is 15.5.',
    '- A ratio written as "1:16" is the number 16.',
    '- Times are seconds unless the field name says minutes.',
    '- notes holds the drinker\'s impressions only (taste, body, what they',
    '  would change), never restated measurements.',
    '- Do not score the brew. Do not return any score, rating or quality',
    '  judgement. Something else does that.',
  ].join('\n');
}

const TARGETS: Record<string, string[]> = {
  espresso: [
    'Ratio (yieldGrams / doseGrams), weight 30. Target 1.8 to 2.2 for a',
    '  normal shot. Deduct in proportion to the distance outside that band;',
    '  0.3 outside is a small fault, 1.0 outside is a large one.',
    'Brew time (brewTimeSeconds), weight 25. Target 25 to 32 seconds.',
    '  Judge it together with the ratio: 20 seconds at 1:2 means the grind',
    '  ran fast, which is a real fault; 36 seconds at 1:1.5 is choked.',
    'Puck preparation, weight 20. puckPrepWdt, puckPrepDistribution and',
    '  puckPrepTamp are worth up to 7 each. Deduct only where the value is',
    '  false, meaning the step was deliberately skipped.',
    'Water temperature (waterTempC), weight 15. Target 90 to 96 for medium',
    '  roast; light roast tolerates the upper end, dark roast the lower.',
    'Coherence, weight 10. Do the dose, basket and machine make sense',
    '  together, and does anything in notes contradict the numbers?',
  ],
  v60: [
    'Ratio (waterGrams / doseGrams, or the ratio field), weight 30. Target',
    '  15 to 17. Outside 13 to 19 is a large fault.',
    'Total brew time (totalBrewTimeSeconds), weight 25. Target 150 to 210',
    '  seconds for a 15 g dose, scaling up with dose.',
    'Bloom, weight 20. bloomWaterGrams should be roughly two to three times',
    '  doseGrams, and bloomTimeSeconds 30 to 45.',
    'Water temperature (waterTempC), weight 15. Target 92 to 96.',
    'Pour structure (pourCount), weight 10. Target 3 to 5 pours after the',
    '  bloom. One pour is a fault; more than six is fussing.',
  ],
  aeropress: [
    'Ratio (waterGrams / doseGrams, or the ratio field), weight 30. Target',
    '  12 to 16 for a concentrate meant to be diluted, 14 to 17 drunk',
    '  straight. Judge from notes which was intended if it is stated.',
    'Steep time (steepTimeSeconds), weight 30. Target 60 to 120 seconds.',
    '  Under 45 is thin, over 180 is heavy and bitter.',
    'Water temperature (waterTempC), weight 25. Target 80 to 92. The',
    '  Aeropress is forgiving here, so deduct gently.',
    'Plunge (plungeTimeSeconds), weight 15. Target 20 to 30 seconds. A',
    '  plunge under 10 seconds means the grind was too coarse or the',
    '  pressure too high.',
  ],
};

export function scoreInstruction(
  method: BrewMethod,
  locale: Locale,
): string {
  const targets = TARGETS[method];
  if (!targets) throw new Error(`no rubric for ${method}`);

  return [
    `You are grading one ${method} against a fixed rubric. Rubric version`,
    `${RUBRIC_VERSION}. Apply the rubric as written, not your own taste.`,
    '',
    languageLine(locale),
    '',
    'Start from 100 and deduct. The weights below are the most a factor can',
    'cost. A factor inside its target range costs nothing.',
    '',
    ...targets.map((t) => `- ${t}`),
    '',
    'Rules:',
    '- If a field is null, the brewer did not record it. Do not deduct for',
    '  it. Ignore that factor and say in the reasons that it was not',
    '  recorded.',
    '- A boolean that is false is a deliberate omission and does count.',
    '- The final score is an integer from 0 to 100.',
    '- Give one short reason per factor you considered, in the order above.',
    '  Each reason states the value, how it compares to the target, and the',
    '  effect. Do not pad, do not encourage, do not add advice that is not',
    '  a consequence of a number in the rubric.',
    locale === 'id'
      ? '- Write every reason in Indonesian.'
      : '- Write every reason in English.',
  ].join('\n');
}

export function buildScoreResponseSchema(): Record<string, unknown> {
  return {
    type: 'object',
    properties: {
      score: { type: 'integer', minimum: 0, maximum: 100 },
      reasons: { type: 'array', items: { type: 'string' } },
    },
    required: ['score', 'reasons'],
  };
}
