import { describe, expect, it } from 'vitest';
import { brewSchema, METHODS, SCORED_METHODS } from '../src/schema';

describe('brew schema', () => {
  it('defines exactly the eight brew methods', () => {
    expect(METHODS).toEqual([
      'espresso', 'v60', 'aeropress', 'frenchPress',
      'kopiTubruk', 'kopiJoss', 'kopiTalua', 'kopiKhop',
    ]);
  });

  it('scores only espresso, v60 and aeropress', () => {
    expect(SCORED_METHODS).toEqual(['espresso', 'v60', 'aeropress']);
  });

  it('gives every core and method field an en and id label', () => {
    const specs = [
      ...Object.values(brewSchema.core),
      ...METHODS.flatMap((m) => Object.values(brewSchema.methods[m].fields)),
    ];
    expect(specs.length).toBeGreaterThan(0);
    for (const spec of specs) {
      expect(spec.label.en, JSON.stringify(spec)).toBeTruthy();
      expect(spec.label.id, JSON.stringify(spec)).toBeTruthy();
    }
  });

  it('uses only field types the form generator understands', () => {
    const allowed = ['number', 'integer', 'string', 'boolean', 'enum'];
    for (const m of METHODS) {
      for (const [name, spec] of Object.entries(brewSchema.methods[m].fields)) {
        expect(allowed, `${m}.${name}`).toContain(spec.type);
      }
    }
  });

  it('gives every enum field its allowed values', () => {
    for (const [name, spec] of Object.entries(brewSchema.core)) {
      if (spec.type === 'enum') expect(spec.values, name).toBeDefined();
    }
  });
});
