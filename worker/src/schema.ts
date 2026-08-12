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

  const methodData: Record<string, unknown> = {};
  for (const method of METHODS) {
    for (const [name, spec] of Object.entries(
      brewSchema.methods[method].fields,
    )) {
      methodData[name] = { ...geminiType(spec), nullable: true };
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
    if (key in allowed && value !== null && value !== undefined) {
      out[key] = value;
    }
  }
  return out;
}
