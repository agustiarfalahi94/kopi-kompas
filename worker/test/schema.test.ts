import { describe, expect, it } from 'vitest';
import {
  brewSchema, CATEGORIES, METHODS, SCORED_METHODS, categoryOf,
} from '../src/schema';

describe('brew schema', () => {
  it('groups sixteen methods into five categories', () => {
    expect(METHODS).toHaveLength(16);
    expect(CATEGORIES).toEqual([
      'espresso', 'filter', 'immersion', 'hybrid', 'indonesian',
    ]);
  });

  it('puts every method in exactly one category', () => {
    const listed = CATEGORIES.flatMap(
      (c) => brewSchema.categories[c]!.methods,
    );
    expect([...listed].sort()).toEqual([...METHODS].sort());
    expect(new Set(listed).size).toBe(listed.length);
    for (const m of METHODS) expect(() => categoryOf(m)).not.toThrow();
  });

  it('scores espresso, the four filter methods and aeropress', () => {
    expect(SCORED_METHODS).toEqual([
      'espresso', 'coneDripper', 'flatBottomDripper', 'chemex',
      'batchBrewer', 'aeropress',
    ]);
  });

  it('keeps variants as fields rather than methods', () => {
    // Made separate methods, the ratio would stop being something the rubric
    // could judge, because it would be implied by the name.
    for (const notAMethod of ['v60', 'ristretto', 'lungo', 'kopiLuwak']) {
      expect(METHODS).not.toContain(notAMethod);
    }
    expect(brewSchema.methods.espresso.fields.shotStyle!.values)
      .toEqual(['ristretto', 'normale', 'lungo']);
    expect(brewSchema.methods.coneDripper.fields.brewer!.values)
      .toContain('v60');
  });

  it('treats luwak and wet-hulled as bean processes', () => {
    expect(brewSchema.core.process!.values).toContain('luwak');
    expect(brewSchema.core.process!.values).toContain('wet-hulled');
  });

  it('gives every field a group, so the form can section it', () => {
    const groups = ['coffee', 'grind', 'brew', 'water'];
    const all = [
      ...Object.entries(brewSchema.core),
      ...METHODS.flatMap((m) => Object.entries(brewSchema.methods[m].fields)),
    ];
    for (const [name, spec] of all) expect(groups, name).toContain(spec.group);
  });

  it('keeps the expanded-by-default set small', () => {
    // required now means "shown above the fold", not "must answer". Past
    // about seven rows the form stops being skimmable.
    for (const m of METHODS) {
      const open = Object.values(brewSchema.methods[m].fields)
        .filter((f) => f.required).length;
      expect(open, `${m} opens with ${open} rows`).toBeLessThanOrEqual(7);
    }
  });

  it('offers medium-light, between light and medium', () => {
    expect(brewSchema.core.roastLevel!.values).toEqual([
      'light', 'medium-light', 'medium', 'medium-dark', 'dark',
    ]);
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
