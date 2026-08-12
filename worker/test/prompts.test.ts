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
  it('is r2, because the targets moved', () =>
    expect(RUBRIC_VERSION).toBe('r2'));
});
