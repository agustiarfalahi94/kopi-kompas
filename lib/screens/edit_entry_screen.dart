import 'package:flutter/material.dart';

import '../data/brew_schema.dart';
import '../models/brew_entry.dart';
import '../services/brew_database.dart';
import '../services/kopi_client.dart';
import '../strings.dart';
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
BrewEntry applyEdits(
  BrewEntry entry,
  Map<String, Object?> answers,
  BrewSchema schema,
  DateTime now,
) {
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
    brewDate: entry.brewDate,
    rawInputText: entry.rawInputText,
    methodData: methodData,
    overallScore: entry.overallScore,
    scoreReasons: entry.scoreReasons,
    scoreStatus: schema.isScored(entry.brewMethod)
        ? ScoreStatus.pending
        : ScoreStatus.notApplicable,
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
                Expanded(
                  child: BrewForm(
                    fields: formFields(
                      widget.schema,
                      widget.entry.brewMethod,
                      _core,
                      widget.entry.methodData,
                      const {},
                    ),
                    onChanged: (v) => _answers = v,
                  ),
                ),
                const SizedBox(height: 8),
                FilledButton(
                  onPressed: _save,
                  child: Text(AppStrings.saveButton),
                ),
              ],
            ),
          ),
  );
}
