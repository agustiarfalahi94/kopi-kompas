import raw from '../../schema/brew_schema.json';

export type BrewMethod =
  | 'espresso'
  | 'coneDripper' | 'flatBottomDripper' | 'chemex' | 'batchBrewer'
  | 'frenchPress' | 'coldBrew' | 'turkishIbrik'
  | 'aeropress' | 'smartDripper' | 'siphon'
  | 'kopiTubruk' | 'kopiSaring' | 'kopiJoss' | 'kopiTalua' | 'kopiKhop';

export type FieldType =
  | 'number' | 'integer' | 'string' | 'boolean' | 'enum' | 'date';

/// Which section of the form a field belongs to.
export type FieldGroup = 'coffee' | 'grind' | 'brew' | 'water';

export interface FieldSpec {
  type: FieldType;
  group: FieldGroup;
  unit?: string;
  values?: string[];
  /// Shown expanded, above the fold. **Not** compulsory — nothing blocks
  /// saving an entry, however empty.
  required: boolean;
  label: { en: string; id: string };
}

export interface MethodSpec {
  scored: boolean;
  label: { en: string; id: string };
  fields: Record<string, FieldSpec>;
}

export interface CategorySpec {
  label: { en: string; id: string };
  methods: BrewMethod[];
}

export interface BrewSchema {
  schemaVersion: string;
  categories: Record<string, CategorySpec>;
  core: Record<string, FieldSpec>;
  methods: Record<BrewMethod, MethodSpec>;
}

export const brewSchema = raw as BrewSchema;

export const METHODS = Object.keys(brewSchema.methods) as BrewMethod[];

export const SCORED_METHODS = METHODS.filter(
  (m) => brewSchema.methods[m].scored,
);

export const CATEGORIES = Object.keys(brewSchema.categories);

/// The category a method belongs to. Throws rather than returning a default:
/// a method in no category is a schema bug, and silently bucketing it would
/// hide that from the picker.
export function categoryOf(method: BrewMethod): string {
  const hit = CATEGORIES.find((c) =>
    brewSchema.categories[c]!.methods.includes(method),
  );
  if (!hit) throw new Error(`${method} is in no category`);
  return hit;
}

export function isBrewMethod(value: unknown): value is BrewMethod {
  return typeof value === 'string' && (METHODS as string[]).includes(value);
}

function geminiType(spec: FieldSpec): Record<string, unknown> {
  switch (spec.type) {
    case 'integer': return { type: 'integer' };
    case 'number':  return { type: 'number' };
    case 'boolean': return { type: 'boolean' };
    case 'enum':    return { type: 'string', enum: spec.values ?? [] };
    case 'date':    return { type: 'string', format: 'date' };
    case 'string':  return { type: 'string' };
  }
}

// Two properties of this schema are load-bearing, and both were learned from
// the live API rather than the docs.
//
// `nullable: true` — without it a string field the model wants to leave empty
// cannot be null, and the constrained decoder must emit *some* string. Real
// responses came back with {"beanOrigin":"doseGrams"} and
// {"grindSize":"roastLevel"}: it was filling string fields with adjacent
// property names out of the schema.
//
// `required: <every key>` — with only brewMethod required, the decoder
// satisfied the minimum and stopped after three fields, dropping a dose and a
// pour count that were plainly stated in the text. Requiring everything and
// allowing null forces a complete object; nulls are stripped in
// stripForeignFields afterwards, so the app still only sees real values.
export function buildParseResponseSchema(): Record<string, unknown> {
  const core: Record<string, unknown> = {};
  for (const [name, spec] of Object.entries(brewSchema.core)) {
    core[name] = { ...geminiType(spec), nullable: true };
  }

  // A field name shared by several methods collapses to one entry here, and
  // for `waterGrams` or `ratio` that is fine — the types agree. It is *not*
  // fine for an enum: `brewer` means v60/origami/kono on a coneDripper,
  // kalitaWave/… on a flatBottomDripper and clever/switch on a smartDripper.
  // Plain assignment let the last method win, so `v60` was never offered to
  // the model and a V60 came back as brewer "switch". Union the values
  // instead; stripForeignFields narrows them back down per method.
  const methodData: Record<string, Record<string, unknown>> = {};
  for (const method of METHODS) {
    for (const [name, spec] of Object.entries(
      brewSchema.methods[method].fields,
    )) {
      const next: Record<string, unknown> = {
        ...geminiType(spec),
        nullable: true,
      };
      const seenEnum = methodData[name]?.enum;
      if (Array.isArray(seenEnum) && Array.isArray(next.enum)) {
        next.enum = [...new Set([...seenEnum, ...next.enum])];
      }
      methodData[name] = next;
    }
  }

  const properties = {
    brewMethod: { type: 'string', enum: METHODS },
    ...core,
    methodData: {
      type: 'object',
      properties: methodData,
      required: Object.keys(methodData),
      nullable: true,
    },
  };

  return {
    type: 'object',
    properties,
    required: Object.keys(properties),
  };
}

export function stripForeignFields(
  method: BrewMethod,
  data: Record<string, unknown>,
): Record<string, unknown> {
  const allowed = brewSchema.methods[method].fields;
  const out: Record<string, unknown> = {};
  for (const [key, value] of Object.entries(data)) {
    const spec = allowed[key];
    if (!spec || value === null || value === undefined) continue;
    // The parse schema offers the union of every method's enum values, so a
    // coneDripper can come back with brewer "clever". It is not a cone
    // dripper, and storing it would render a nonsense label — drop it and
    // let the follow-up form ask.
    if (spec.type === 'enum' && !(spec.values ?? []).includes(value as string)) {
      continue;
    }
    out[key] = value;
  }
  return out;
}
