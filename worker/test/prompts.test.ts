import { describe, expect, it } from 'vitest';
import {
  RUBRIC_VERSION, parseInstruction, scoreInstruction,
  buildScoreResponseSchema,
} from '../src/prompts';

const SCORED = [
  'espresso', 'coneDripper', 'flatBottomDripper', 'chemex',
  'batchBrewer', 'aeropress',
] as const;

describe('parseInstruction', () => {
  const en = parseInstruction('en');

  it('forbids guessing', () => {
    expect(en.toLowerCase()).toContain('null');
    expect(en.toLowerCase()).toContain('do not guess');
  });

  it('tells the model to classify the method first', () => {
    expect(en.toLowerCase()).toContain('brewmethod');
  });

  it('names every method so classification has a closed set', () => {
    for (const m of ['espresso', 'coneDripper', 'kopiTubruk', 'kopiKhop']) {
      expect(en).toContain(m);
    }
  });

  it('forbids scoring during a parse', () => {
    expect(en.toLowerCase()).toContain('do not score');
  });

  it('mentions Indonesian input when the locale is id', () => {
    expect(parseInstruction('id').toLowerCase()).toContain('indonesian');
  });
});

describe('scoreInstruction', () => {
  it('carries concrete espresso targets', () => {
    const s = scoreInstruction('espresso', 'en');
    expect(s).toContain('1.8');
    expect(s).toContain('2.2');
    expect(s).toContain('25');
    expect(s).toContain('32');
  });

  it('carries concrete cone dripper targets', () => {
    const s = scoreInstruction('coneDripper', 'en');
    expect(s).toContain('15');
    expect(s).toContain('17');
    expect(s.toLowerCase()).toContain('brewer');
  });

  it('gives chemex a coarser, longer target than a cone dripper', () => {
    expect(scoreInstruction('chemex', 'en').toLowerCase())
      .toContain('thicker');
  });

  it('moves the espresso ratio target with shot style', () => {
    const s = scoreInstruction('espresso', 'en');
    expect(s).toContain('ristretto');
    expect(s).toContain('lungo');
    expect(s).toContain('1.8');
  });

  it('scores the new espresso fields', () => {
    const s = scoreInstruction('espresso', 'en').toLowerCase();
    expect(s).toContain('pre-infusion');
    expect(s).toContain('basket');
  });

  it('refuses a method it has no rubric for', () => {
    expect(() => scoreInstruction('kopiJoss', 'en')).toThrow();
  });

  it('carries concrete aeropress targets', () => {
    const s = scoreInstruction('aeropress', 'en');
    expect(s).toContain('steep');
  });

  it('says an unknown field is not a fault', () => {
    const s = scoreInstruction('espresso', 'en').toLowerCase();
    expect(s).toContain('do not deduct');
  });

  it('asks for reasons in the requested language', () => {
    expect(scoreInstruction('espresso', 'id').toLowerCase())
      .toContain('indonesian');
  });

  it('is defined for every scored method', () => {
    for (const m of SCORED) {
      expect(scoreInstruction(m, 'en').length).toBeGreaterThan(200);
    }
  });
});

describe('buildScoreResponseSchema', () => {
  const s = buildScoreResponseSchema() as any;

  it('bounds the score to 0-100 integers', () => {
    expect(s.properties.score.type).toBe('integer');
    expect(s.properties.score.minimum).toBe(0);
    expect(s.properties.score.maximum).toBe(100);
  });

  it('requires both a score and its reasons', () => {
    expect(s.required).toEqual(['score', 'reasons']);
  });

  it('makes reasons an array of strings', () => {
    expect(s.properties.reasons.type).toBe('array');
    expect(s.properties.reasons.items.type).toBe('string');
  });
});

describe('rubric version', () => {
  // Pinned so a scoring change cannot land without moving the version. An
  // r2 score and an r3 score of the same shot are not comparable, and a
  // stored score records which produced it.
  it('is r3, because espresso puck prep now depends on the basket', () =>
    expect(RUBRIC_VERSION).toBe('r3'));
});

describe('espresso puck preparation by basket type', () => {
  const r = scoreInstruction('espresso', 'en');

  it('tells the model to read basketType before weighting puck prep', () => {
    // The whole rule hangs on this: a rubric that lists two weights without
    // saying which applies is worse than one weight.
    expect(r).toContain('basketType');
    expect(r.toLowerCase()).toContain('weighted by baskettype');
  });

  it('keeps puck prep at weight 20 for a non-pressurised basket', () => {
    expect(r).toMatch(/nonPressurised[^]*weight 20/);
  });

  it('drops it to 5 for a pressurised basket and says where the rest goes', () => {
    expect(r).toMatch(/pressurised — weight 5/);
    expect(r).toContain('ratio and brew time');
  });

  it('forbids deducting for WDT on a pressurised basket', () => {
    // The bug in r2: a beginner on the basket that ships with the machine was
    // marked down for skipping a step that does nothing on it.
    expect(r).toContain('Do NOT deduct for puckPrepWdt');
  });

  it('still asks for a level bed, by either tool', () => {
    expect(r).toContain('puckPrepTamp AND puckPrepDistribution are both');
  });

  it('never treats basket diameter as a fault', () => {
    // It is the portafilter you own, not a choice you made about this shot.
    expect(r).toContain('basketDiameterMm');
    expect(r).toContain('never a fault');
  });
});
