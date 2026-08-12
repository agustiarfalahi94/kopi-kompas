import { describe, expect, it } from 'vitest';
import { buildParseResponseSchema, stripForeignFields } from '../src/schema';

describe('buildParseResponseSchema', () => {
  const schema = buildParseResponseSchema() as any;

  it('constrains brewMethod to the sixteen known methods', () => {
    expect(schema.properties.brewMethod.enum).toContain('espresso');
    expect(schema.properties.brewMethod.enum).toContain('coneDripper');
    expect(schema.properties.brewMethod.enum).toContain('kopiKhop');
    expect(schema.properties.brewMethod.enum).toHaveLength(16);
  });

  it('maps a date field to a date-formatted string', () => {
    expect(schema.properties.roastDate.type).toBe('string');
    expect(schema.properties.roastDate.format).toBe('date');
  });

  // Both of the next two exist because of a real failure against the live
  // API. With only brewMethod required, the constrained decoder satisfied the
  // minimum and stopped after three fields. Without `nullable`, a string
  // field the model wanted to leave empty could not be null, so it emitted an
  // adjacent property name instead — real responses contained
  // {"beanOrigin":"doseGrams"} and {"grindSize":"roastLevel"}.
  it('requires every property, so the decoder cannot stop early', () => {
    expect(schema.required).toContain('brewMethod');
    expect(schema.required).toContain('doseGrams');
    expect(schema.required).toContain('methodData');
    expect(schema.required.sort())
      .toEqual(Object.keys(schema.properties).sort());
  });

  it('marks every field except brewMethod nullable', () => {
    expect(schema.properties.brewMethod.nullable).toBeUndefined();
    expect(schema.properties.beanOrigin.nullable).toBe(true);
    expect(schema.properties.doseGrams.nullable).toBe(true);
    expect(schema.properties.roastLevel.nullable).toBe(true);
    expect(schema.properties.methodData.nullable).toBe(true);
  });

  it('makes methodData fields required and nullable too', () => {
    const md = schema.properties.methodData;
    expect(md.required.sort()).toEqual(Object.keys(md.properties).sort());
    expect(md.properties.yieldGrams.nullable).toBe(true);
    expect(md.properties.puckPrepWdt.nullable).toBe(true);
  });

  it('exposes core fields at the top level', () => {
    expect(schema.properties.doseGrams.type).toBe('number');
    expect(schema.properties.roastLevel.enum).toEqual([
      'light', 'medium-light', 'medium', 'medium-dark', 'dark',
    ]);
  });

  it('unions every method field into methodData', () => {
    const md = schema.properties.methodData.properties;
    expect(md.yieldGrams.type).toBe('number');       // espresso
    expect(md.bloomTimeSeconds.type).toBe('number'); // coneDripper
    expect(md.eggYolkUsed.type).toBe('boolean');     // kopiTalua
    expect(md.puckPrepWdt.type).toBe('boolean');
  });

  it('unions enum values when a field name collides across methods', () => {
    // brewer is a coneDripper field (v60/origami/kono), a flatBottomDripper
    // field (kalitaWave/...) and a smartDripper field (clever/switch).
    // Overwriting on collision meant only the last method's values reached
    // the model, so a V60 came back as brewer "switch" — the right value was
    // never offered to it.
    const brewer = (schema.properties.methodData.properties as any).brewer;
    for (const v of [
      'v60', 'origami', 'kono', 'kalitaWave', 'staggX', 'clever', 'switch',
    ]) {
      expect(brewer.enum, v).toContain(v);
    }
  });

  it('maps integer fields to integer, not number', () => {
    expect(schema.properties.methodData.properties.pourCount.type)
      .toBe('integer');
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

  it('drops an enum value that is foreign to this method', () => {
    // The union lets the model see every brewer value, so the narrowing has
    // to happen here: a coneDripper with brewer "clever" is not a cone
    // dripper, and storing it would render a nonsense label.
    expect(stripForeignFields('coneDripper', { brewer: 'clever' }))
      .toEqual({});
    expect(stripForeignFields('coneDripper', { brewer: 'v60' }))
      .toEqual({ brewer: 'v60' });
    expect(stripForeignFields('smartDripper', { brewer: 'clever' }))
      .toEqual({ brewer: 'clever' });
  });

  it('keeps false, which is a real answer', () => {
    const out = stripForeignFields('espresso', { puckPrepWdt: false });
    expect(out).toEqual({ puckPrepWdt: false });
  });
});
