import 'package:flutter/material.dart';

import '../data/brew_schema.dart';
import '../models/brew_entry.dart';
import '../services/brew_database.dart';
import '../strings.dart';
import '../theme.dart';
import 'entry_detail_screen.dart' show detailRows;
import 'home_screen.dart' show displayLabel;

/// The record: every live brew, in full, since day one.
///
/// Where Home is a scannable summary, this shows each entry expanded — every
/// field with a value, the score with its reasons, and the original text
/// verbatim next to what the AI made of it.
///
/// **Read-only, and deliberately muted.** Editing happens in the detail
/// screen. The archive colouring is not decoration: it should be obvious at a
/// glance which of the two screens you are looking at, and that treatment
/// lives in the theme so it cannot drift away from the design.
///
/// Deleted entries are absent. They live in Settings, because this is a
/// record of brewing rather than of edits.
class FullLogScreen extends StatefulWidget {
  const FullLogScreen({super.key, required this.db, required this.schema});

  final BrewDatabase db;
  final BrewSchema schema;

  @override
  State<FullLogScreen> createState() => _FullLogScreenState();
}

class _FullLogScreenState extends State<FullLogScreen> {
  late final Future<List<BrewEntry>> _entries = widget.db.liveEntries();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ink = kopiArchiveColor(theme.brightness);

    return Scaffold(
      appBar: AppBar(title: Text(AppStrings.fullLogTitle)),
      body: FutureBuilder<List<BrewEntry>>(
        future: _entries,
        builder: (context, snap) {
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final entries = snap.data!;
          if (entries.isEmpty) {
            return Center(child: Text(AppStrings.emptyLog));
          }
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: entries.length,
            separatorBuilder: (_, _) => Divider(height: 40, color: ink),
            itemBuilder: (context, i) => _entry(theme, ink, entries[i]),
          );
        },
      ),
    );
  }

  Widget _entry(ThemeData theme, Color ink, BrewEntry e) {
    final dense = theme.textTheme.bodySmall?.copyWith(color: ink);
    final when = e.brewDate;
    final stamp =
        '${when.year}-${when.month.toString().padLeft(2, '0')}-'
        '${when.day.toString().padLeft(2, '0')} '
        '${when.hour.toString().padLeft(2, '0')}:'
        '${when.minute.toString().padLeft(2, '0')}';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              displayLabel(widget.schema, e),
              style: theme.textTheme.titleSmall?.copyWith(color: ink),
            ),
            Text(stamp, style: dense),
          ],
        ),
        const SizedBox(height: 8),
        // No colour on the number here: the archive does not rank, it records.
        Text(switch (e.scoreStatus) {
          ScoreStatus.scored =>
            '${AppStrings.scoreLabel}: ${e.overallScore}'
                '${e.scoreRubric == null ? '' : ' (${e.scoreRubric})'}',
          ScoreStatus.notApplicable => AppStrings.notScored,
          _ => AppStrings.scoreFailed,
        }, style: dense),
        if (e.myRating != null)
          Text('${AppStrings.rateThis} ${'★' * e.myRating!}', style: dense),
        const SizedBox(height: 8),
        for (final row in detailRows(widget.schema, e))
          Text(
            '${row.spec.label}: ${_value(row.spec, row.value)}'
            '${row.spec.unit == null ? '' : ' ${row.spec.unit}'}',
            style: dense,
          ),
        for (final reason in e.scoreReasons)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text('— $reason', style: dense),
          ),
        const SizedBox(height: 8),
        Text(AppStrings.whatYouTyped, style: theme.textTheme.labelSmall),
        Text(
          e.rawInputText,
          style: dense?.copyWith(fontStyle: FontStyle.italic),
        ),
      ],
    );
  }

  /// Enum values are ids. Rendering them raw put "filtered" and "kalitaWave"
  /// straight on screen, in both languages — the archive had its own copy of
  /// this logic and never got the label lookup the detail screen has.
  String _value(FieldSpec spec, Object? v) => switch (v) {
    final bool b => b ? AppStrings.yes : AppStrings.no,
    final String s when spec.type == FieldType.enumerated =>
      widget.schema.valueLabel(s),
    final Object o => o.toString(),
    null => '',
  };
}
