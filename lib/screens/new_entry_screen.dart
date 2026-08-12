import 'package:flutter/material.dart';

import '../data/brew_schema.dart';
import '../models/brew_entry.dart';
import '../services/brew_database.dart';
import '../services/kopi_client.dart';
import '../strings.dart';
import '../widgets/follow_up_form.dart';
import '../widgets/score_reveal.dart';

/// Confetti at 90 or above.
bool shouldCelebrate(int? score) => score != null && score >= 90;

/// Assembles the entry from what the model extracted plus what the user
/// filled in.
///
/// Which bucket an answer belongs to is decided by the schema rather than by
/// a hand-written list that would drift from it.
BrewEntry buildEntry({
  required String brewMethod,
  required Map<String, Object?> core,
  required Map<String, Object?> methodData,
  required Map<String, Object?> answers,
  required String rawInputText,
  required BrewSchema schema,
  required DateTime now,
}) {
  final coreNames = schema.core.map((f) => f.name).toSet();
  final mergedCore = Map<String, Object?>.of(core);
  final mergedMethod = Map<String, Object?>.of(methodData);

  answers.forEach((name, value) {
    // A null answer means the user left the row alone; it must never erase
    // something the parse already found.
    if (value == null) return;
    if (coreNames.contains(name)) {
      mergedCore[name] = value;
    } else {
      mergedMethod[name] = value;
    }
  });

  return BrewEntry(
    id: newUuid(),
    brewMethod: brewMethod,
    beanOrigin: mergedCore['beanOrigin'] as String?,
    roastLevel: mergedCore['roastLevel'] as String?,
    doseGrams: (mergedCore['doseGrams'] as num?)?.toDouble(),
    grindSize: mergedCore['grindSize'] as String?,
    notes: mergedCore['notes'] as String?,
    brewDate: now,
    rawInputText: rawInputText,
    methodData: mergedMethod,
    scoreStatus: schema.isScored(brewMethod)
        ? ScoreStatus.pending
        : ScoreStatus.notApplicable,
    createdAt: now,
    updatedAt: now,
  );
}

enum _Stage { describe, fillGaps, scoring, revealed }

class NewEntryScreen extends StatefulWidget {
  const NewEntryScreen({
    super.key,
    required this.db,
    required this.schema,
    required this.client,
  });

  final BrewDatabase db;
  final BrewSchema schema;
  final KopiClient client;

  @override
  State<NewEntryScreen> createState() => _NewEntryScreenState();
}

class _NewEntryScreenState extends State<NewEntryScreen> {
  final _text = TextEditingController();

  _Stage _stage = _Stage.describe;
  String? _error;

  String _brewMethod = '';
  Map<String, Object?> _core = const {};
  Map<String, Object?> _methodData = const {};
  Map<String, Object?> _answers = const {};
  List<FieldSpec> _missing = const [];
  BrewEntry? _saved;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  String _messageFor(KopiError kind) => switch (kind) {
    KopiError.network => AppStrings.offline,
    KopiError.rateLimited => AppStrings.rateLimited,
    _ => AppStrings.parseFailed,
  };

  Future<void> _parse() async {
    final raw = _text.text.trim();
    if (raw.isEmpty) return;

    setState(() {
      _stage = _Stage.scoring; // reused as the busy state for the parse call
      _error = null;
    });

    final result = await widget.client.parse(raw);
    if (!mounted) return;

    switch (result) {
      case ParseFailed(:final kind):
        // The typed text stays in the controller. Losing what someone wrote
        // is the one failure this flow must never have.
        setState(() {
          _stage = _Stage.describe;
          _error = _messageFor(kind);
        });
      case ParseOk(:final brewMethod, :final core, :final methodData):
        _brewMethod = brewMethod;
        _core = core;
        _methodData = methodData;
        _missing = missingFields(widget.schema, brewMethod, core, methodData);
        if (_missing.isEmpty) {
          await _save();
        } else {
          setState(() => _stage = _Stage.fillGaps);
        }
    }
  }

  /// Falls back to filling the form by hand when the parse could not run.
  void _byHand() {
    _brewMethod = widget.schema.methodIds.first;
    _core = const {};
    _methodData = const {};
    _missing = missingFields(widget.schema, _brewMethod, const {}, const {});
    setState(() {
      _stage = _Stage.fillGaps;
      _error = null;
    });
  }

  Future<void> _save() async {
    setState(() {
      _stage = _Stage.scoring;
      _error = null;
    });

    var entry = buildEntry(
      brewMethod: _brewMethod,
      core: _core,
      methodData: _methodData,
      answers: _answers,
      rawInputText: _text.text.trim(),
      schema: widget.schema,
      now: DateTime.now(),
    );

    if (entry.scoreStatus == ScoreStatus.pending) {
      final result = await widget.client.score(entry);
      switch (result) {
        case ScoreOk(:final score, :final reasons, :final rubric, :final model):
          entry = entry.copyWith(
            overallScore: score,
            scoreReasons: reasons,
            scoreStatus: ScoreStatus.scored,
            scoreRubric: rubric,
            scoreModel: model,
            scoredAt: DateTime.now(),
          );
        case ScoreFailed():
          // Saving still happens. A brew that could not be scored is worth
          // far more than no brew at all, and the detail screen can retry.
          entry = entry.copyWith(scoreStatus: ScoreStatus.failed);
      }
    }

    // Written before the reveal, so a crash during the celebration cannot
    // lose the brew.
    await widget.db.insert(entry);
    if (!mounted) return;
    setState(() {
      _saved = entry;
      _stage = _Stage.revealed;
    });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(switch (_stage) {
        _Stage.fillGaps => AppStrings.fillGapsTitle,
        _ => AppStrings.newEntryTitle,
      }),
    ),
    body: Padding(
      padding: const EdgeInsets.all(16),
      child: switch (_stage) {
        _Stage.describe => _describe(),
        _Stage.fillGaps => _fillGaps(),
        _Stage.scoring => _busy(),
        _Stage.revealed => ScoreReveal(
          entry: _saved!,
          method: widget.schema.method(_saved!.brewMethod),
          onDone: () => Navigator.of(context).pop(true),
        ),
      },
    ),
  );

  Widget _describe() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      TextField(
        controller: _text,
        autofocus: true,
        minLines: 3,
        maxLines: 6,
        maxLength: 2000,
        textCapitalization: TextCapitalization.sentences,
        decoration: InputDecoration(
          hintText: AppStrings.describeHint,
          border: const OutlineInputBorder(),
        ),
      ),
      if (_error != null) ...[
        const SizedBox(height: 8),
        Text(
          _error!,
          style: TextStyle(color: Theme.of(context).colorScheme.error),
        ),
        const SizedBox(height: 8),
        OutlinedButton(onPressed: _byHand, child: Text(AppStrings.byHand)),
      ],
      const SizedBox(height: 16),
      FilledButton(
        onPressed: _parse,
        child: Text(_error == null ? AppStrings.parseButton : AppStrings.retry),
      ),
    ],
  );

  Widget _fillGaps() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(
        widget.schema.method(_brewMethod).label,
        style: Theme.of(context).textTheme.titleMedium,
      ),
      const SizedBox(height: 8),
      Expanded(
        child: FollowUpForm(fields: _missing, onChanged: (v) => _answers = v),
      ),
      const SizedBox(height: 8),
      FilledButton(onPressed: _save, child: Text(AppStrings.saveButton)),
    ],
  );

  Widget _busy() => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const CircularProgressIndicator(),
        const SizedBox(height: 16),
        Text(
          _stage == _Stage.scoring && _brewMethod.isEmpty
              ? AppStrings.parsing
              : AppStrings.scoring,
        ),
      ],
    ),
  );
}
