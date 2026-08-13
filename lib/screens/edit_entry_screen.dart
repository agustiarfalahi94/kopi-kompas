import 'package:flutter/material.dart';

import '../data/brew_schema.dart';
import '../models/brew_entry.dart';
import '../services/brew_database.dart';
import '../services/kopi_client.dart';
import '../strings.dart';
import '../widgets/brew_date_field.dart';
import '../widgets/follow_up_form.dart';
import 'home_screen.dart' show displayLabel;

/// Rebuilds an entry from the form's answers.
///
/// The form reports every field it holds a value for, so its answers are the
/// complete new state of the entry — a row the user cleared comes back absent
/// and must actually be dropped, not left stale underneath.
///
/// Three things never change: the id, `createdAt`, and `rawInputText`. The
/// original words are the record of what was said; editing the numbers must
/// not rewrite them.
///
/// The existing score is kept until a new one replaces it. A network blip
/// while re-scoring must not destroy a number you already had — the opposite
/// of the first save, where there was nothing to lose.
///
/// [rescore] is false when only the timestamp moved. No rubric looks at when
/// a coffee was brewed, so re-running the model would spend a request to
/// arrive at the same number with a newer `scoredAt`.
BrewEntry applyEdits(
  BrewEntry entry,
  Map<String, Object?> answers,
  BrewSchema schema,
  DateTime now, {
  DateTime? brewDate,
  bool rescore = true,
}) {
  final coreNames = schema.core.map((f) => f.name).toSet();
  final core = <String, Object?>{};
  final methodData = <String, Object?>{};

  answers.forEach((name, value) {
    if (value == null) return;
    if (coreNames.contains(name)) {
      core[name] = value;
    } else {
      methodData[name] = value;
    }
  });

  return BrewEntry(
    id: entry.id,
    brewMethod: entry.brewMethod,
    beanOrigin: core['beanOrigin'] as String?,
    roaster: core['roaster'] as String?,
    process: core['process'] as String?,
    roastLevel: core['roastLevel'] as String?,
    roastDate: switch (core['roastDate']) {
      final String s => DateTime.tryParse(s),
      final DateTime d => d,
      _ => null,
    },
    doseGrams: (core['doseGrams'] as num?)?.toDouble(),
    grinder: core['grinder'] as String?,
    grindSetting: core['grindSetting'] as String?,
    grindSize: core['grindSize'] as String?,
    waterType: core['waterType'] as String?,
    notes: core['notes'] as String?,
    brewDate: brewDate ?? entry.brewDate,
    rawInputText: entry.rawInputText,
    methodData: methodData,
    overallScore: entry.overallScore,
    scoreReasons: entry.scoreReasons,
    scoreStatus: !schema.isScored(entry.brewMethod)
        ? ScoreStatus.notApplicable
        : rescore
        ? ScoreStatus.pending
        : entry.scoreStatus,
    scoreRubric: entry.scoreRubric,
    scoreModel: entry.scoreModel,
    scoredAt: entry.scoredAt,
    myRating: entry.myRating,
    createdAt: entry.createdAt,
    updatedAt: now,
    deletedAt: entry.deletedAt,
  );
}

/// The same form as a new entry, pre-filled with what the brew already says.
class EditEntryScreen extends StatefulWidget {
  const EditEntryScreen({
    super.key,
    required this.db,
    required this.schema,
    required this.client,
    required this.entry,
  });

  final BrewDatabase db;
  final BrewSchema schema;
  final KopiClient client;
  final BrewEntry entry;

  @override
  State<EditEntryScreen> createState() => _EditEntryScreenState();
}

class _EditEntryScreenState extends State<EditEntryScreen> {
  Map<String, Object?> _answers = const {};
  bool _busy = false;
  late DateTime _brewedAt = widget.entry.brewDate;

  /// What the form reported when it first rendered, before anything was
  /// touched. Comparing against this is what tells us an edit is real.
  Map<String, Object?>? _initial;

  /// True when no field differs from what it said on arrival.
  ///
  /// Saving an unchanged entry would re-score it for nothing — a Gemini
  /// request, a new number that may differ by a point or two, and a fresh
  /// scoredAt on a brew nobody actually edited.
  bool get _fieldsUnchanged {
    final start = _initial;
    if (start == null) return true;
    if (start.length != _answers.length) return false;
    for (final e in _answers.entries) {
      if (start[e.key] != e.value) return false;
    }
    return true;
  }

  /// The timestamp counts as an edit — it is stored data — but it is the one
  /// change that must not trigger a re-score.
  bool get _unchanged => _fieldsUnchanged && _brewedAt == widget.entry.brewDate;

  Map<String, Object?> get _core => {
    'beanOrigin': widget.entry.beanOrigin,
    'roaster': widget.entry.roaster,
    'process': widget.entry.process,
    'roastLevel': widget.entry.roastLevel,
    'roastDate': widget.entry.roastDate?.toIso8601String().substring(0, 10),
    'doseGrams': widget.entry.doseGrams,
    'grinder': widget.entry.grinder,
    'grindSetting': widget.entry.grindSetting,
    'grindSize': widget.entry.grindSize,
    'waterType': widget.entry.waterType,
    'notes': widget.entry.notes,
  };

  Future<void> _save() async {
    setState(() => _busy = true);

    var edited = applyEdits(
      widget.entry,
      _answers,
      widget.schema,
      DateTime.now(),
      brewDate: _brewedAt,
      rescore: !_fieldsUnchanged,
    );

    if (edited.scoreStatus == ScoreStatus.pending) {
      final result = await widget.client.score(edited);
      if (result case ScoreOk(
        :final score,
        :final reasons,
        :final rubric,
        :final model,
      )) {
        edited = edited.copyWith(
          overallScore: score,
          scoreReasons: reasons,
          scoreStatus: ScoreStatus.scored,
          scoreRubric: rubric,
          scoreModel: model,
          scoredAt: DateTime.now(),
        );
      } else {
        // Keep the old number rather than clearing it — it is still the last
        // real assessment this brew had.
        edited = edited.copyWith(
          scoreStatus: widget.entry.scoreStatus == ScoreStatus.scored
              ? ScoreStatus.scored
              : ScoreStatus.failed,
        );
      }
    }

    await widget.db.update(edited);
    if (mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(
        '${AppStrings.editTitle} ${displayLabel(widget.schema, widget.entry)}',
      ),
    ),
    body: _busy
        ? Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const CircularProgressIndicator(),
                const SizedBox(height: 16),
                Text(AppStrings.scoring),
              ],
            ),
          )
        : Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                BrewDateField(
                  value: _brewedAt,
                  onChanged: (t) => setState(() => _brewedAt = t),
                ),
                Expanded(
                  child: BrewForm(
                    schema: widget.schema,
                    fields: formFields(
                      widget.schema,
                      widget.entry.brewMethod,
                      _core,
                      widget.entry.methodData,
                      const {},
                    ),
                    onChanged: (v) => setState(() {
                      _answers = v;
                      _initial ??= Map.of(v);
                    }),
                  ),
                ),
                const SizedBox(height: 8),
                FilledButton(
                  // Disabled until something actually differs, so an edit
                  // opened out of curiosity costs nothing.
                  onPressed: _unchanged ? null : _save,
                  child: Text(
                    _unchanged ? AppStrings.noChanges : AppStrings.saveButton,
                  ),
                ),
              ],
            ),
          ),
  );
}
