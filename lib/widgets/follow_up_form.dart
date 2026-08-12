import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/brew_schema.dart';

/// The required fields the parse did not fill.
///
/// `false` counts as answered. "No WDT today" is a statement about the brew
/// that the rubric deducts for, so re-asking it would be wrong — and would
/// quietly turn a deliberate omission into an unknown. Only null, absent and
/// blank text count as missing.
///
/// Optional fields are never asked about. They exist so a brewer *can*
/// record a basket or a water temperature, not so the app can interrogate
/// them after every shot.
List<FieldSpec> missingFields(
  BrewSchema schema,
  String method,
  Map<String, Object?> core,
  Map<String, Object?> methodData,
) {
  bool absent(Object? v) => v == null || (v is String && v.trim().isEmpty);

  return [
    ...schema.core.where((f) => f.required && absent(core[f.name])),
    ...schema
        .method(method)
        .fields
        .where((f) => f.required && absent(methodData[f.name])),
  ];
}

/// One row per missing field, with the input type the schema declares.
///
/// Nothing here knows what a brew method is: fields, labels, units, keyboards
/// and dropdown values all arrive from `schema/brew_schema.json`, so adding a
/// method never means editing this file.
class FollowUpForm extends StatefulWidget {
  const FollowUpForm({
    super.key,
    required this.fields,
    required this.onChanged,
  });

  final List<FieldSpec> fields;
  final ValueChanged<Map<String, Object?>> onChanged;

  @override
  State<FollowUpForm> createState() => _FollowUpFormState();
}

class _FollowUpFormState extends State<FollowUpForm> {
  final _values = <String, Object?>{};

  @override
  void initState() {
    super.initState();
    // A switch shown at "off" is already answering the question, so seed
    // booleans as false rather than leaving them unset and losing the answer
    // if the user never touches the row.
    //
    // Seeding alone is not enough: the parent only learns values through
    // onChanged, so an untouched switch used to report nothing and the field
    // arrived absent rather than false. The rubric then read "distribution
    // was not recorded" and deducted nothing, when the honest reading is that
    // the step was skipped. Report the seed after the first frame — during
    // initState the parent cannot safely setState.
    //
    // Only booleans are seeded. An untouched text or number field is
    // genuinely unknown, and reporting a value for it would overwrite what
    // the parse found.
    for (final f in widget.fields) {
      if (f.type == FieldType.boolean) _values[f.name] = false;
    }
    if (_values.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) widget.onChanged(Map.of(_values));
      });
    }
  }

  void _set(String name, Object? value) {
    setState(() => _values[name] = value);
    widget.onChanged(Map.of(_values));
  }

  @override
  Widget build(BuildContext context) => ListView.separated(
    shrinkWrap: true,
    padding: const EdgeInsets.symmetric(vertical: 8),
    itemCount: widget.fields.length,
    separatorBuilder: (_, _) => const SizedBox(height: 12),
    itemBuilder: (context, i) => _row(widget.fields[i]),
  );

  Widget _row(FieldSpec f) {
    final label = f.unit == null ? f.label : '${f.label} (${f.unit})';

    return switch (f.type) {
      FieldType.boolean => SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: Text(f.label),
        value: _values[f.name] as bool? ?? false,
        onChanged: (v) => _set(f.name, v),
      ),
      FieldType.enumerated => DropdownButtonFormField<String>(
        decoration: InputDecoration(labelText: label),
        initialValue: _values[f.name] as String?,
        items: [
          for (final v in f.values) DropdownMenuItem(value: v, child: Text(v)),
        ],
        onChanged: (v) => _set(f.name, v),
      ),
      FieldType.integer => TextField(
        decoration: InputDecoration(labelText: label),
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        onChanged: (t) => _set(f.name, int.tryParse(t)),
      ),
      FieldType.number => TextField(
        decoration: InputDecoration(labelText: label),
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        onChanged: (t) => _set(f.name, double.tryParse(t)),
      ),
      FieldType.string => TextField(
        decoration: InputDecoration(labelText: label),
        onChanged: (t) => _set(f.name, t.trim().isEmpty ? null : t.trim()),
      ),
    };
  }
}
