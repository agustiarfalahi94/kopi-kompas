import { describe, expect, it } from 'vitest';
import { buildParseResponseSchema, stripForeignFields } from '../src/schema';

describe('buildParseResponseSchema', () => {
  const schema = buildParseResponseSchema() as any;

  it('constrains brewMethod to the eight known methods', () => {
    expect(schema.properties.brewMethod.enum).toContain('espresso');
    expect(schema.properties.brewMethod.enum).toContain('kopiKhop');
    expect(schema.properties.brewMethod.enum).toHaveLength(8);
  });

  it('requires brewMethod and nothing else', () => {
    expect(schema.required).toEqual(['brewMethod']);
  });

  it('exposes core fields at the top level', () => {
    expect(schema.properties.doseGrams.type).toBe('number');
    expect(schema.properties.roastLevel.enum).toEqual([
      'light', 'medium', 'medium-dark', 'dark',
    ]);
  });

  it('unions every method field into methodData', () => {
    const md = schema.properties.methodData.properties;
    expect(md.yieldGrams.type).toBe('number');       // espresso
    expect(md.bloomTimeSeconds.type).toBe('number'); // v60
    expect(md.eggYolkUsed.type).toBe('boolean');     // kopiTalua
    expect(md.puckPrepWdt.type).toBe('boolean');
  });

  it('maps integer fields to integer, not number', () => {
    expect(schema.properties.methodData.properties.pourCount.type)
      .toBe('integer');
  });

  it('never marks a methodData field required', () => {
    expect(schema.properties.methodData.required).toBeUndefined();
  });
});

describe('stripForeignFields', () => {
  it('keeps fields belonging to the method', () => {
    const out = stripForeignFields('espresso', {
      yieldGrams: 30, brewTimeSeconds: 25,
    });
    expect(out).toEqual({ yieldGrams: 30, brewTimeSeconds: 25 });
  });

  it('drops fields belonging to another method', () => {
    const out = stripForeignFields('espresso', {
      yieldGrams: 30, eggYolkUsed: true, bloomTimeSeconds: 40,
    });
    expect(out).toEqual({ yieldGrams: 30 });
  });

  it('drops keys in no method at all', () => {
    expect(stripForeignFields('espresso', { overallScore: 95 })).toEqual({});
  });

  it('drops nulls, so a missing field stays missing', () => {
    const out = stripForeignFields('espresso', {
      yieldGrams: 30, machine: null,
    });
    expect(out).toEqual({ yieldGrams: 30 });
  });

  it('keeps false, which is a real answer', () => {
    const out = stripForeignFields('espresso', { puckPrepWdt: false });
    expect(out).toEqual({ puckPrepWdt: false });
  });
});
