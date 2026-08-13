import { brewSchema, METHODS, type BrewMethod } from './schema';

/// Bumped from r1 when the taxonomy landed. Basket size, pre-infusion,
/// pressure, agitation and drawdown all change the verdict, and the espresso
/// ratio band now moves with shot style — an r1 score and an r2 score are not
/// the same measurement. Every stored score records which produced it.
///
/// r3 splits espresso puck preparation by basket type. A pressurised basket
/// makes its pressure at an orifice in the second wall rather than through
/// the bed, so WDT and distribution have almost nothing to act on — r2
/// deducted for skipping them anyway, and marked down every shot pulled on
/// the basket most beginners own.
export const RUBRIC_VERSION = 'r3';

export type Locale = 'en' | 'id';

function languageLine(locale: Locale): string {
  return locale === 'id'
    ? 'The user writes in Indonesian. Understand Indonesian coffee ' +
      'vocabulary (gula, sangrai, kental, tubruk, saring, kocok) and write ' +
      'any prose you produce in Indonesian.'
    : 'The user writes in English.';
}

/// The clock block, present only when the app sent its local time.
///
/// Without it the model has no "now", so every relative expression in the
/// text — "yesterday at 11.30", "kemarin sore", "roasted last Tuesday" — is
/// uncomputable and has to be thrown away. That is exactly what used to
/// happen: the brew time a user stated was silently dropped and the row was
/// stamped with the moment they pressed Save.
function clockLines(nowLocal: string): string[] {
  return [
    '',
    `The brewer's local clock reads ${nowLocal}. Use it only to turn`,
    'relative wording into absolute dates.',
    '',
    '- brewedAt: when the coffee was brewed, as a local datetime',
    '  YYYY-MM-DDTHH:MM:SS, with no zone suffix and no offset. Resolve',
    '  "yesterday at 11.30 am", "tadi pagi jam 6", "kemarin sore" against',
    '  the clock above.',
    '- If the text gives a day but no time, use 12:00:00. Midday stands for',
    '  an unknown hour; do not invent a plausible one.',
    '- If the text says nothing at all about when it was brewed, return',
    '  null. Do not default it to the current time.',
    '- Never return a moment later than the clock above.',
  ];
}

export function parseInstruction(locale: Locale, nowLocal?: string): string {
  const methods = METHODS.map((m) => {
    const fields = Object.keys(brewSchema.methods[m].fields).join(', ');
    return `- ${m}: ${fields}`;
  }).join('\n');

  const categories = Object.entries(brewSchema.categories)
    .map(([id, c]) => `- ${c.label.en}: ${c.methods.join(', ')}`)
    .join('\n');

  return [
    'You extract structured data from a short, informal description of a',
    'coffee someone just brewed. You are a parser, not an assistant.',
    '',
    languageLine(locale),
    '',
    'First classify brewMethod. It must be exactly one of the values listed',
    'below, chosen from what the text describes. Variants are fields, not',
    'methods: a ristretto is an espresso with shotStyle ristretto, and a V60',
    'is a coneDripper with brewer v60.',
    '',
    'The categories, for orientation only — always return the method id:',
    categories,
    '',
    'Methods and their fields:',
    '',
    methods,
    '',
    'Then extract the core fields (beanOrigin, roaster, process, roastLevel,',
    'roastDate, doseGrams, grinder, grindSetting, grindSize, waterType,',
    'notes) and, in methodData, only the fields listed above for the method',
    'you chose. Leave every field belonging to another method absent.',
    '',
    'Rules:',
    '- Use null for anything not stated or not clear. Do not guess, do not',
    '  infer a typical value, and do not fill a field because it is usually',
    '  present. A missing value will be asked about; a wrong one will not.',
    '- Booleans: true if the text says it was done, false if the text says',
    '  it was skipped, null if the text does not mention it.',
    '- Numbers are plain numbers without units. "15.5g" is 15.5.',
    '- A ratio written as "1:16" is the number 16.',
    '- Times are seconds unless the field name says minutes or hours.',
    // Only computable once the model has a clock. Without one this rule read
    // "leave it null", which is the honest answer to a question you cannot
    // answer — and the wrong one the moment you can.
    '- roastDate is an ISO date, YYYY-MM-DD.',
    ...(nowLocal === undefined
      ? ['  "roasted last Tuesday" is not a date you can compute; leave it', '  null.']
      : ['  Resolve relative wording against the clock below.']),
    '- notes holds the drinker\'s impressions only (taste, body, what they',
    '  would change), never restated measurements.',
    '- Do not score the brew. Do not return any score, rating or quality',
    '  judgement. Something else does that.',
    ...(nowLocal === undefined ? [] : clockLines(nowLocal)),
  ].join('\n');
}

// The filter methods share a skeleton — ratio 30, total time 25, bloom 20,
// temperature 15, technique 10 — and differ where the hardware does.
const FILTER_SKELETON = (brewNotes: string[]): string[] => [
  'Ratio (waterGrams / doseGrams, or the ratio field), weight 30. Target',
  '  15 to 17. Outside 13 to 19 is a large fault.',
  ...brewNotes,
  'Bloom, weight 20. bloomWaterGrams should be roughly two to three times',
  '  doseGrams, and bloomTimeSeconds 30 to 45.',
  'Water temperature (waterTempC), weight 15. Target 92 to 96.',
  'Technique, weight 10. Pour count 3 to 5 after the bloom; agitation of',
  '  none or a swirl is normal and stirring is a choice, not a fault. A',
  '  drawdownTimeSeconds far longer than the pours suggests too fine a grind.',
];

const TARGETS: Record<string, string[]> = {
  espresso: [
    'Ratio (yieldGrams / doseGrams), weight 30. **The target band depends on',
    '  shotStyle**: ristretto 1.0 to 1.5, normale 1.8 to 2.2, lungo 2.8 to',
    '  3.5. Judge against the band for the style recorded — a 1.2 ratio is',
    '  correct for a ristretto and badly under-extracted for a normale. If',
    '  shotStyle is null, assume normale and say so.',
    'Brew time (brewTimeSeconds), weight 20. Target 25 to 32 seconds.',
    '  Judge it together with the ratio: 20 seconds at 1:2 means the grind',
    '  ran fast, which is a real fault; 36 seconds at 1:1.5 is choked.',
    '**Puck preparation is weighted by basketType. Read it first.**',
    '',
    'If basketType is nonPressurised, or is null — weight 20. puckPrepWdt,',
    '  puckPrepDistribution and puckPrepTamp are worth up to 7 each. Deduct',
    '  only where the value is false, meaning the step was deliberately',
    '  skipped. Flow is governed by the bed, so preparing it is most of the',
    '  technique.',
    '',
    'If basketType is pressurised — weight 5, and the other 15 goes to',
    '  ratio and brew time. A pressurised basket makes its pressure at a',
    '  small orifice in the second wall, not through the coffee, so the bed',
    '  barely governs flow. Do NOT deduct for puckPrepWdt or',
    '  puckPrepDistribution being false; on this basket they have almost',
    '  nothing to act on, and saying otherwise sends someone to buy a tool',
    '  that will not change their coffee. Levelling still matters a little,',
    '  so deduct only if puckPrepTamp AND puckPrepDistribution are both',
    '  false — either one levels the bed. Do not praise a tamp for building',
    '  resistance here; it does not.',
    '',
    'Water temperature (waterTempC), weight 10. Target 90 to 96 for medium',
    '  roast; light roast tolerates the upper end, dark roast the lower.',
    'Machine setup (pre-infusion, pressure, basket), weight 10.',
    '  preInfusionSeconds 3 to 10 where recorded;',
    '  pressureBars 6 to 9. A basketSizeGrams far above doseGrams means an',
    '  under-dosed basket, which channels — 18 g in a 22 g basket is a real',
    '  fault, 18 g in an 18 g basket is correct. On a pressurised basket',
    '  this matters less: judge it, but do not call it a large fault.',
    '  basketDiameterMm is the portafilter it fits and is never a fault.',
    'Coherence, weight 10. Do the dose, basket and machine make sense',
    '  together, and does anything in notes contradict the numbers?',
  ],

  coneDripper: FILTER_SKELETON([
    'Total brew time (totalBrewTimeSeconds), weight 25. Target 150 to 210',
    '  seconds for a 15 g dose, scaling up with dose. **Adjust for the',
    '  brewer**: a V60 or Origami on a cone filter drains fastest and should',
    '  sit near the lower end; a Kono restricts flow and runs longer.',
  ]),

  flatBottomDripper: FILTER_SKELETON([
    'Total brew time (totalBrewTimeSeconds), weight 25. Target 180 to 240',
    '  seconds for a 15 g dose. **Adjust for the brewer**: a Kalita Wave has',
    '  three small holes that restrict flow, so it runs long by design;',
    '  Orea and April drain faster and should sit nearer 180. The flat bed',
    '  extracts evenly, so an uneven-tasting brew points at pour technique',
    '  rather than at the dripper.',
  ]),

  chemex: FILTER_SKELETON([
    'Total brew time (totalBrewTimeSeconds), weight 25. Target 210 to 270',
    '  seconds. **The much thicker filter is the whole point of a Chemex**:',
    '  it demands a coarser grind and a longer contact time, so judge a',
    '  three-minute Chemex as fast rather than as normal, and do not treat a',
    '  four-minute one as slow.',
  ]),

  batchBrewer: [
    'Ratio (waterGrams / doseGrams, or the ratio field), weight 40. Target',
    '  15 to 17. Outside 13 to 19 is a large fault.',
    'Water temperature (waterTempC), weight 30. Target 92 to 96. Many',
    '  machines cannot hold this; if it is not recorded, ignore the factor.',
    'Total brew time (totalBrewTimeSeconds), weight 30. Target 240 to 360',
    '  seconds for a full batch.',
    'There are no bloom or pour fields for this method, because the machine',
    '  controls them. Score what is recorded and say which factors were not,',
    '  rather than inventing a deduction for something the brewer cannot set.',
  ],

  aeropress: [
    'Ratio (waterGrams / doseGrams, or the ratio field), weight 30. Target',
    '  12 to 16 for a concentrate meant to be diluted, 14 to 17 drunk',
    '  straight. Judge from notes which was intended if it is stated.',
    'Steep time (steepTimeSeconds), weight 30. Target 60 to 120 seconds.',
    '  Under 45 is thin, over 180 is heavy and bitter.',
    'Water temperature (waterTempC), weight 20. Target 80 to 92. The',
    '  Aeropress is forgiving here, so deduct gently.',
    'Plunge (plungeTimeSeconds), weight 15. Target 20 to 30 seconds. A',
    '  plunge under 10 seconds means the grind was too coarse or the',
    '  pressure too high.',
    'Technique, weight 5. Inverted or upright are both legitimate; agitation',
    '  of none or a swirl is normal. Neither is a fault on its own.',
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
