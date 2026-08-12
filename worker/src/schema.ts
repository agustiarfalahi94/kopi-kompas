import raw from '../../schema/brew_schema.json';

export type BrewMethod =
  | 'espresso' | 'v60' | 'aeropress' | 'frenchPress'
  | 'kopiTubruk' | 'kopiJoss' | 'kopiTalua' | 'kopiKhop';

export type FieldType = 'number' | 'integer' | 'string' | 'boolean' | 'enum';

export interface FieldSpec {
  type: FieldType;
  unit?: string;
  values?: string[];
  required: boolean;
  label: { en: string; id: string };
}

export interface MethodSpec {
  scored: boolean;
  label: { en: string; id: string };
  fields: Record<string, FieldSpec>;
}

export interface BrewSchema {
  schemaVersion: string;
  core: Record<string, FieldSpec>;
  methods: Record<BrewMethod, MethodSpec>;
}

export const brewSchema = raw as BrewSchema;

export const METHODS = Object.keys(brewSchema.methods) as BrewMethod[];

export const SCORED_METHODS = METHODS.filter(
  (m) => brewSchema.methods[m].scored,
);

export function isBrewMethod(value: unknown): value is BrewMethod {
  return typeof value === 'string' && (METHODS as string[]).includes(value);
}

function geminiType(spec: FieldSpec): Record<string, unknown> {
  switch (spec.type) {
    case 'integer': return { type: 'integer' };
    case 'number':  return { type: 'number' };
    case 'boolean': return { type: 'boolean' };
    case 'enum':    return { type: 'string', enum: spec.values ?? [] };
    case 'string':  return { type: 'string' };
  }
}

export function buildParseResponseSchema(): Record<string, unknown> {
  const core: Record<string, unknown> = {};
  for (const [name, spec] of Object.entries(brewSchema.core)) {
    core[name] = geminiType(spec);
  }

  const methodData: Record<string, unknown> = {};
  for (const method of METHODS) {
    for (const [name, spec] of Object.entries(
      brewSchema.methods[method].fields,
    )) {
      methodData[name] = geminiType(spec);
    }
  }

  return {
    type: 'object',
    properties: {
      brewMethod: { type: 'string', enum: METHODS },
      ...core,
      methodData: { type: 'object', properties: methodData },
    },
    required: ['brewMethod'],
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
