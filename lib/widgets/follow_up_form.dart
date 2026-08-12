import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/brew_schema.dart';
import '../strings.dart';

/// Where a field's current value came from.
///
/// The form shows parsed values differently from empty ones, so a glance
/// confirms what the AI actually got right.
enum FieldSource { parsed, sticky, empty }

class BrewFormField {
  const BrewFormField(this.spec, this.value, this.source);

  final FieldSpec spec;
  final Object? value;
  final FieldSource source;
}

/// Every field the method has, with whatever value is already known.
///
/// This deliberately returns *all* fields rather than only the missing ones.
/// Asking only for what the parse could not find kept the form short, but it
/// also meant a field nobody was ever shown was a field nobody knew existed —
/// `grinder` would have sat empty forever, and it is the field that most
/// determines whether a good brew can be repeated.
///
/// Precedence is parsed → sticky → empty, in that order: the free text is the
/// most recent statement of fact and always wins over a remembered default.
List<BrewFormField> formFields(
  BrewSchema schema,
  String method,
  Map<String, Object?> core,
  Map<String, Object?> methodData,
  Map<String, Object?> sticky,
) {
  // Throws for an unknown method rather than rendering an empty form.
  final spec = schema.method(method);

  BrewFormField resolve(FieldSpec f, Map<String, Object?> parsed) {
    final fromParse = parsed[f.name];
    if (fromParse != null) {
      return BrewFormField(f, fromParse, FieldSource.parsed);
    }
    final fromSticky = sticky[f.name];
    if (fromSticky != null) {
      return BrewFormField(f, fromSticky, FieldSource.sticky);
    }
    return BrewFormField(f, null, FieldSource.empty);
  }

  return [
    for (final f in schema.core) resolve(f, core),
    for (final f in spec.fields) resolve(f, methodData),
  ];
}

/// The same fields, sectioned, in a fixed order. Empty groups are dropped so
/// a bare header never renders.
Map<FieldGroup, List<BrewFormField>> groupedFields(List<BrewFormField> fields) {
  final out = <FieldGroup, List<BrewFormField>>{};
  for (final group in FieldGroup.values) {
    final rows = fields.where((f) => f.spec.group == group).toList();
    if (rows.isNotEmpty) out[group] = rows;
  }
  return out;
}

/// The whole form: every field, grouped, and **nothing compulsory**. Leave all
/// of it untouched and the entry still saves.
class BrewForm extends StatefulWidget {
  const BrewForm({
    super.key,
    required this.fields,
    required this.onChanged,
    required this.schema,
  });

  final List<BrewFormField> fields;
  final BrewSchema schema;
  final ValueChanged<Map<String, Object?>> onChanged;

  @override
  State<BrewForm> createState() => _BrewFormState();
}

class _BrewFormState extends State<BrewForm> {
  final _values = <String, Object?>{};

  @override
  void initState() {
    super.initState();
    for (final f in widget.fields) {
      // A switch drawn off is already answering, so seed booleans false. And
      // anything already known — parsed or remembered — is an answer too.
      if (f.value != null) {
        _values[f.spec.name] = f.value;
      } else if (f.spec.type == FieldType.boolean) {
        _values[f.spec.name] = false;
      }
    }
    // Seeding is not enough on its own: the parent only learns values through
    // onChanged, so an untouched form used to report nothing at all.
    if (_values.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) widget.onChanged(Map.of(_values));
      });
    }
  }

  void _set(String name, Object? value) {
    setState(() {
      if (value == null) {
        _values.remove(name);
      } else {
        _values[name] = value;
      }
    });
    widget.onChanged(Map.of(_values));
  }

  @override
  Widget build(BuildContext context) {
    final groups = groupedFields(widget.fields);
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 8),
      children: [
        for (final entry in groups.entries)
          _section(context, entry.key, entry.value),
      ],
    );
  }

  Widget _section(
    BuildContext context,
    FieldGroup group,
    List<BrewFormField> rows,
  ) {
    // Coffee and brew carry what most brews actually record; grind and water
    // collapse to a header with a count, which is the thing that tells a
    // brewer those fields exist without making them scroll past twelve rows.
    final open = group == FieldGroup.coffee || group == FieldGroup.brew;
    return ExpansionTile(
      // A ValueKey, not a PageStorageKey: the enclosing ListView stores its
      // scroll offset under the nearest PageStorageKey, and an ExpansionTile
      // storing a bool there makes the list read it as a double.
      key: ValueKey(group),
      initiallyExpanded: open,
      shape: const Border(),
      collapsedShape: const Border(),
      title: Text(
        AppStrings.groupLabel(group),
        style: Theme.of(context).textTheme.titleMedium,
      ),
      subtitle: open ? null : Text('${rows.length}'),
      childrenPadding: const EdgeInsets.only(left: 8, right: 8, bottom: 8),
      children: [for (final row in rows) _row(row)],
    );
  }

  Widget _row(BrewFormField field) {
    final f = field.spec;
    final label = f.unit == null ? f.label : '${f.label} (${f.unit})';
    final current = _values[f.name];

    return switch (f.type) {
      FieldType.boolean => SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: Text(f.label),
        value: current as bool? ?? false,
        onChanged: (v) => _set(f.name, v),
      ),
      FieldType.enumerated => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: DropdownButtonFormField<String>(
          decoration: InputDecoration(labelText: label),
          initialValue: f.values.contains(current) ? current as String? : null,
          items: [
            for (final v in f.values)
              DropdownMenuItem(value: v, child: Text(v)),
          ],
          onChanged: (v) => _set(f.name, v),
        ),
      ),
      FieldType.date => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: TextFormField(
          initialValue: current?.toString(),
          decoration: InputDecoration(labelText: label, hintText: 'YYYY-MM-DD'),
          keyboardType: TextInputType.datetime,
          onChanged: (t) => _set(f.name, _asDate(t)),
        ),
      ),
      FieldType.integer => _text(f, label, current, TextInputType.number, [
        FilteringTextInputFormatter.digitsOnly,
      ], (t) => int.tryParse(t)),
      FieldType.number => _text(
        f,
        label,
        current,
        const TextInputType.numberWithOptions(decimal: true),
        const [],
        (t) => double.tryParse(t),
      ),
      FieldType.string => _text(
        f,
        label,
        current,
        TextInputType.text,
        const [],
        (t) => t.trim().isEmpty ? null : t.trim(),
      ),
    };
  }

  Widget _text(
    FieldSpec f,
    String label,
    Object? current,
    TextInputType keyboard,
    List<TextInputFormatter> formatters,
    Object? Function(String) parse,
  ) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: TextFormField(
      initialValue: current?.toString(),
      decoration: InputDecoration(labelText: label),
      keyboardType: keyboard,
      inputFormatters: formatters,
      onChanged: (t) => _set(f.name, parse(t)),
    ),
  );

  /// Only a complete ISO date counts. A half-typed "2026-08" is not a date,
  /// and storing it would put a nonsense value in the column.
  static String? _asDate(String raw) {
    final t = raw.trim();
    if (t.length != 10) return null;
    return DateTime.tryParse(t) == null ? null : t;
  }
}
