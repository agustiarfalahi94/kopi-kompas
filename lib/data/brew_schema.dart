import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

enum FieldType { number, integer, string, boolean, enumerated }

FieldType _fieldType(String raw) => switch (raw) {
  'number' => FieldType.number,
  'integer' => FieldType.integer,
  'boolean' => FieldType.boolean,
  'enum' => FieldType.enumerated,
  'string' => FieldType.string,
  _ => throw ArgumentError('unknown field type: $raw'),
};

class FieldSpec {
  const FieldSpec({
    required this.name,
    required this.type,
    required this.required,
    required this.label,
    this.unit,
    this.values = const [],
  });

  final String name;
  final FieldType type;
  final String? unit;
  final List<String> values;
  final bool required;
  final String label;

  factory FieldSpec.fromJson(String name, Map<String, dynamic> j) => FieldSpec(
    name: name,
    type: _fieldType(j['type'] as String),
    unit: j['unit'] as String?,
    values: ((j['values'] as List?) ?? const []).cast<String>(),
    required: j['required'] as bool,
    // Phase 3 switches this to the active locale's label.
    label: (j['label'] as Map<String, dynamic>)['en'] as String,
  );
}

class MethodSpec {
  const MethodSpec({
    required this.id,
    required this.scored,
    required this.label,
    required this.fields,
  });

  final String id;
  final bool scored;
  final String label;
  final List<FieldSpec> fields;
}

/// The eight brew methods and their fields, read from the same
/// `schema/brew_schema.json` the Worker uses.
///
/// Nothing else in the app may restate a field list. Adding a method is an
/// edit to that file plus a rubric in the Worker, and the follow-up form
/// picks it up for free.
class BrewSchema {
  BrewSchema._(this._core, this._methods);

  final List<FieldSpec> _core;
  final Map<String, MethodSpec> _methods;

  List<FieldSpec> get core => List.unmodifiable(_core);
  List<String> get methodIds => List.unmodifiable(_methods.keys);

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
        label: (m['label'] as Map<String, dynamic>)['en'] as String,
        fields: fields,
      );
    });

    return BrewSchema._(core, methods);
  }
}
