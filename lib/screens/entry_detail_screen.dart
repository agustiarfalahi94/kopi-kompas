import 'package:flutter/material.dart';

import '../data/brew_schema.dart';
import '../models/brew_entry.dart';
import '../strings.dart';
import '../theme.dart';
import 'home_screen.dart' show displayLabel;

typedef DetailRow = ({FieldSpec spec, Object? value});

/// Every field of an entry that actually has a value, in schema order.
///
/// A `false` boolean counts as a value: "I skipped WDT" is information, and
/// hiding it because it is falsey would make a deliberate omission look like
/// an unanswered question. A key that is not in the schema is ignored, so an
/// old row cannot render a raw id as a label.
List<DetailRow> detailRows(BrewSchema schema, BrewEntry entry) {
  final core = <String, Object?>{
    'beanOrigin': entry.beanOrigin,
    'roaster': entry.roaster,
    'process': entry.process,
    'roastLevel': entry.roastLevel,
    'roastDate': entry.roastDate?.toIso8601String().substring(0, 10),
    'doseGrams': entry.doseGrams,
    'grinder': entry.grinder,
    'grindSetting': entry.grindSetting,
    'grindSize': entry.grindSize,
    'waterType': entry.waterType,
    'notes': entry.notes,
  };

  return [
    for (final f in schema.core)
      if (core[f.name] != null) (spec: f, value: core[f.name]),
    for (final f in schema.method(entry.brewMethod).fields)
      if (entry.methodData[f.name] != null)
        (spec: f, value: entry.methodData[f.name]),
  ];
}

/// One brew, in full.
///
/// Takes callbacks rather than a database so it can be pumped in a test
/// without one; the wiring lives in the screen that pushes it.
class EntryDetailScreen extends StatefulWidget {
  const EntryDetailScreen({
    super.key,
    required this.schema,
    required this.entry,
    required this.onEdit,
    required this.onDelete,
    required this.onRescore,
    required this.onRate,
  });

  final BrewSchema schema;
  final BrewEntry entry;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  /// Returns null when the score succeeded, or a message saying why it did
  /// not. A VoidCallback could not report failure, which is why this screen
  /// used to wait up to 45 seconds and then show nothing.
  final Future<String?> Function() onRescore;
  final ValueChanged<int> onRate;

  @override
  State<EntryDetailScreen> createState() => _EntryDetailScreenState();
}

class _EntryDetailScreenState extends State<EntryDetailScreen> {
  bool _scoring = false;
  String? _scoreError;

  /// The rating as shown, which the tap updates before the save returns.
  ///
  /// Read straight off `widget.entry` this used to never change while the
  /// screen was open: tapping a star saved the rating and left the icons
  /// exactly as they were until you backed out and the list reloaded, so the
  /// tap read as having missed. The reveal has always held it locally for the
  /// same reason.
  late int? _stars = widget.entry.myRating;

  Future<void> _rescore() async {
    setState(() {
      _scoring = true;
      _scoreError = null;
    });
    final failure = await widget.onRescore();
    if (!mounted) return;
    setState(() {
      _scoring = false;
      _scoreError = failure;
    });
  }

  Future<void> _confirmDelete(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(AppStrings.deleteTitle),
        // Naming where it goes is the only thing telling the user this is
        // recoverable.
        content: Text(AppStrings.deleteBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(AppStrings.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(AppStrings.delete),
          ),
        ],
      ),
    );
    if (ok == true) widget.onDelete();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final rows = detailRows(widget.schema, widget.entry);

    return Scaffold(
      appBar: AppBar(
        title: Text(displayLabel(widget.schema, widget.entry)),
        actions: [
          IconButton(
            onPressed: widget.onEdit,
            icon: const Icon(Icons.edit_outlined),
          ),
          IconButton(
            onPressed: () => _confirmDelete(context),
            icon: const Icon(Icons.delete_outline),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Center(child: _score(theme)),
          for (final reason in widget.entry.scoreReasons)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('•  '),
                  Expanded(child: Text(reason)),
                ],
              ),
            ),
          if (widget.entry.scoreRubric != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                'rubric ${widget.entry.scoreRubric} · ${widget.entry.scoreModel}',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall,
              ),
            ),
          // Only a failed score can be retried. An unscored method has no
          // rubric, so offering it would promise something the Worker refuses.
          if (widget.entry.scoreStatus == ScoreStatus.failed)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: _scoring
                  ? const Center(child: CircularProgressIndicator())
                  : OutlinedButton(
                      onPressed: _rescore,
                      child: Text(AppStrings.scoreThisBrew),
                    ),
            ),
          if (_scoreError case final why?)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(
                why,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium,
              ),
            ),
          const SizedBox(height: 8),
          _rating(theme),
          const Divider(height: 32),
          for (final row in rows) _field(theme, row),
          const Divider(height: 32),
          Text(AppStrings.whatYouTyped, style: theme.textTheme.labelMedium),
          const SizedBox(height: 4),
          Text(
            widget.entry.rawInputText,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: kopiArchiveColor(theme.brightness),
            ),
          ),
        ],
      ),
    );
  }

  Widget _score(ThemeData theme) => switch (widget.entry.scoreStatus) {
    ScoreStatus.scored => Text(
      '${widget.entry.overallScore}',
      style: theme.textTheme.displayMedium?.copyWith(
        color: theme.colorScheme.primary,
        fontWeight: FontWeight.bold,
      ),
    ),
    ScoreStatus.notApplicable => Text(
      AppStrings.notScored,
      style: theme.textTheme.titleMedium,
    ),
    _ => Text(AppStrings.scoreFailed, style: theme.textTheme.titleMedium),
  };

  Widget _rating(ThemeData theme) => Column(
    children: [
      Text(AppStrings.rateThis, style: theme.textTheme.bodySmall),
      Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (var i = 1; i <= 5; i++)
            IconButton(
              key: ValueKey('detail-rating-$i'),
              icon: Icon((_stars ?? 0) >= i ? Icons.star : Icons.star_border),
              color: theme.colorScheme.primary,
              onPressed: () {
                setState(() => _stars = i);
                widget.onRate(i);
              },
            ),
        ],
      ),
    ],
  );

  Widget _field(ThemeData theme, DetailRow row) {
    final label = row.spec.unit == null
        ? row.spec.label
        : '${row.spec.label} (${row.spec.unit})';
    final value = switch (row.value) {
      final bool b => b ? AppStrings.yes : AppStrings.no,
      final String v when row.spec.type == FieldType.enumerated =>
        widget.schema.valueLabel(v),
      final Object v => v.toString(),
      null => '',
    };
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 2,
            child: Text(label, style: theme.textTheme.bodyMedium),
          ),
          Expanded(
            flex: 3,
            child: Text(
              value,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
