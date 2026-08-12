import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

import 'brew_guide.dart' show BrewTargets;

import '../strings.dart' show AppStrings;

/// Both labels, kept so [Labelled.label] can resolve at read time.
Map<String, String> _labels(Map<String, dynamic> j) =>
    j.map((k, v) => MapEntry(k, v as String));

/// Resolves a label against whatever language is selected *now*.
///
/// Resolving at parse time froze the labels in whichever language was set
/// when the schema loaded — English, because main() loaded the schema before
/// reading the stored language — and switching language never updated them
/// because nothing re-parses. A getter has no such ordering to get wrong.
mixin Labelled {
  Map<String, String> get labels;
  String get label => labels[AppStrings.language] ?? labels['en']!;
}

enum FieldType { number, integer, string, boolean, enumerated, date }

FieldType _fieldType(String raw) => switch (raw) {
  'number' => FieldType.number,
  'integer' => FieldType.integer,
  'boolean' => FieldType.boolean,
  'enum' => FieldType.enumerated,
  'date' => FieldType.date,
  'string' => FieldType.string,
  _ => throw ArgumentError('unknown field type: $raw'),
};

/// Which section of the form a field belongs to.
///
/// The form renders one section per group, and the collapsed headers are what
/// tell a brewer a field exists at all.
enum FieldGroup { coffee, grind, brew, water }

FieldGroup _fieldGroup(String raw) => switch (raw) {
  'coffee' => FieldGroup.coffee,
  'grind' => FieldGroup.grind,
  'brew' => FieldGroup.brew,
  'water' => FieldGroup.water,
  _ => throw ArgumentError('unknown field group: $raw'),
};

class FieldSpec with Labelled {
  const FieldSpec({
    required this.name,
    required this.type,
    required this.group,
    required this.required,
    required this.labels,
    this.unit,
    this.values = const [],
  });

  final String name;
  final FieldType type;
  final FieldGroup group;
  final String? unit;
  final List<String> values;

  /// Shown expanded, above the fold — **not** compulsory. Nothing blocks
  /// saving an entry, however empty. A field nobody is ever shown is a field
  /// nobody knows exists, which is why the form renders all of them.
  final bool required;

  @override
  final Map<String, String> labels;

  factory FieldSpec.fromJson(String name, Map<String, dynamic> j) => FieldSpec(
    name: name,
    type: _fieldType(j['type'] as String),
    group: _fieldGroup(j['group'] as String),
    unit: j['unit'] as String?,
    values: ((j['values'] as List?) ?? const []).cast<String>(),
    required: j['required'] as bool,
    labels: _labels(j['label'] as Map<String, dynamic>),
  );
}

class CategorySpec with Labelled {
  const CategorySpec({
    required this.id,
    required this.labels,
    required this.methodIds,
  });

  final String id;
  @override
  final Map<String, String> labels;
  final List<String> methodIds;
}

class MethodSpec with Labelled {
  const MethodSpec({
    required this.id,
    required this.scored,
    required this.labels,
    required this.fields,
    this.targets,
  });

  final String id;
  final bool scored;
  @override
  final Map<String, String> labels;
  final List<FieldSpec> fields;

  /// The numbers this method is judged against, shared with the Worker's
  /// rubric so a guide and a score can never disagree.
  final BrewTargets? targets;
}

/// The sixteen brew methods, their categories and their fields, read from the
/// same `schema/brew_schema.json` the Worker uses.
///
/// Nothing else in the app may restate a field list. Adding a method is an
/// edit to that file plus a rubric in the Worker, and the follow-up form
/// picks it up for free.
class BrewSchema {
  BrewSchema._(this._categories, this._core, this._methods, this._valueLabels);

  final List<CategorySpec> _categories;
  final Map<String, Map<String, String>> _valueLabels;

  /// The human name for an enum value, in the current language.
  ///
  /// Dropdowns used to render the raw id, so a form offered "kalitaWave" and
  /// "wet-hulled" and neither changed with the language.
  String valueLabel(String value) =>
      _valueLabels[value]?[AppStrings.language] ??
      _valueLabels[value]?['en'] ??
      value;
  final List<FieldSpec> _core;
  final Map<String, MethodSpec> _methods;

  List<CategorySpec> get categories => List.unmodifiable(_categories);
  List<FieldSpec> get core => List.unmodifiable(_core);
  List<String> get methodIds => List.unmodifiable(_methods.keys);

  /// The category a method belongs to. Throws rather than returning a
  /// default: a method in no category is a schema bug, and quietly bucketing
  /// it would hide that from the picker.
  CategorySpec categoryOf(String methodId) => _categories.firstWhere(
    (c) => c.methodIds.contains(methodId),
    orElse: () => throw ArgumentError('$methodId is in no category'),
  );

  List<String> get scoredMethodIds =>
      _methods.values.where((m) => m.scored).map((m) => m.id).toList();

  MethodSpec method(String id) {
    final m = _methods[id];
    if (m == null) throw ArgumentError('unknown brew method: $id');
    return m;
  }

  bool isScored(String id) => method(id).scored;

  static Future<BrewSchema> load() async =>
      parse(await rootBundle.loadString('schema/brew_schema.json'));

  /// Field order follows the file, because the follow-up form and the detail
  /// view both render in it. Dart preserves insertion order for maps decoded
  /// from JSON, which is what makes that free.
  static BrewSchema parse(String source) {
    final root = jsonDecode(source) as Map<String, dynamic>;

    final categories = <CategorySpec>[];
    (root['categories'] as Map<String, dynamic>).forEach((id, raw) {
      final c = raw as Map<String, dynamic>;
      categories.add(
        CategorySpec(
          id: id,
          labels: _labels(c['label'] as Map<String, dynamic>),
          methodIds: (c['methods'] as List).cast<String>(),
        ),
      );
    });

    final core = <FieldSpec>[];
    (root['core'] as Map<String, dynamic>).forEach((name, spec) {
      core.add(FieldSpec.fromJson(name, spec as Map<String, dynamic>));
    });

    final methods = <String, MethodSpec>{};
    (root['methods'] as Map<String, dynamic>).forEach((id, raw) {
      final m = raw as Map<String, dynamic>;
      final fields = <FieldSpec>[];
      (m['fields'] as Map<String, dynamic>).forEach((name, spec) {
        fields.add(FieldSpec.fromJson(name, spec as Map<String, dynamic>));
      });
      methods[id] = MethodSpec(
        id: id,
        scored: m['scored'] as bool,
        labels: _labels(m['label'] as Map<String, dynamic>),
        fields: fields,
        targets: m['targets'] == null
            ? null
            : BrewTargets.fromJson(m['targets'] as Map<String, dynamic>),
      );
    });

    final valueLabels = <String, Map<String, String>>{};
    (root['valueLabels'] as Map<String, dynamic>? ?? {}).forEach((k, v) {
      valueLabels[k] = (v as Map<String, dynamic>).cast<String, String>();
    });

    return BrewSchema._(categories, core, methods, valueLabels);
  }
}
