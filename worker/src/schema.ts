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
