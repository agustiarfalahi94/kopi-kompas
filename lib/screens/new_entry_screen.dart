import 'package:flutter/material.dart';

import '../data/brew_schema.dart';
import '../models/brew_entry.dart';
import '../services/brew_database.dart';
import '../services/kopi_client.dart';
import '../services/sticky_defaults.dart';
import '../strings.dart';
import '../widgets/brew_date_field.dart';
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
  DateTime? brewedAt,
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
    roaster: mergedCore['roaster'] as String?,
    process: mergedCore['process'] as String?,
    roastLevel: mergedCore['roastLevel'] as String?,
    // The form and the parse both hand this over as an ISO date string.
    roastDate: switch (mergedCore['roastDate']) {
      final String s => DateTime.tryParse(s),
      final DateTime d => d,
      _ => null,
    },
    doseGrams: (mergedCore['doseGrams'] as num?)?.toDouble(),
    grinder: mergedCore['grinder'] as String?,
    grindSetting: mergedCore['grindSetting'] as String?,
    grindSize: mergedCore['grindSize'] as String?,
    waterType: mergedCore['waterType'] as String?,
    notes: mergedCore['notes'] as String?,
    // When the coffee was brewed, which is not when it was written down.
    // `now` is the fallback for a text that said nothing about when, and
    // createdAt below keeps the second meaning on its own column.
    brewDate: brewedAt ?? now,
    rawInputText: rawInputText,
    methodData: mergedMethod,
    scoreStatus: schema.isScored(brewMethod)
        ? ScoreStatus.pending
        : ScoreStatus.notApplicable,
    createdAt: now,
    updatedAt: now,
  );
}

enum _Stage { describe, pickMethod, fillGaps, scoring, revealed }

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
  Map<String, Object?> _sticky = const {};
  BrewEntry? _saved;

  /// Null until the form opens. Set from the parse when the text said when,
  /// otherwise to the moment the form appeared — not the moment Save is
  /// pressed, so a long fill-in does not drift the timestamp.
  DateTime? _brewedAt;
  bool _brewedAtFromText = false;

  @override
  void initState() {
    super.initState();
    loadStickyDefaults().then((d) {
      if (mounted) setState(() => _sticky = d);
    });
  }

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
      case ParseOk(
        :final brewMethod,
        :final core,
        :final methodData,
        :final brewedAt,
      ):
        // Always show the form, however complete the parse was. A field
        // nobody is shown is a field nobody knows exists.
        setState(() {
          _brewMethod = brewMethod;
          _core = core;
          _methodData = methodData;
          _brewedAt = brewedAt ?? DateTime.now();
          _brewedAtFromText = brewedAt != null;
          _stage = _Stage.fillGaps;
        });
    }
  }

  /// Falls back to filling the form by hand when the parse could not run.
  ///
  /// Shows the category picker rather than guessing: defaulting to the first
  /// method across sixteen of them is a wrong answer dressed as a choice.
  void _byHand() => setState(() {
    _stage = _Stage.pickMethod;
    _error = null;
  });

  /// Persists the star rating immediately. The entry is already in the
  /// database by the time the reveal is on screen, so this is an update — and
  /// it means a rating survives even if the app is killed before Done.
  Future<void> _rate(int stars) async {
    final entry = _saved;
    if (entry == null) return;
    final rated = entry.copyWith(myRating: stars, updatedAt: DateTime.now());
    await widget.db.update(rated);
    if (mounted) setState(() => _saved = rated);
  }

  void _pickMethod(String methodId) => setState(() {
    _brewMethod = methodId;
    _core = const {};
    _methodData = const {};
    // Filling in by hand means no parse ran, so there is nothing to have
    // found — now, adjustable, is the only honest default.
    _brewedAt = DateTime.now();
    _brewedAtFromText = false;
    _stage = _Stage.fillGaps;
  });

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
      brewedAt: _brewedAt,
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
          entry = entry.copyWith(
            scoreStatus: ScoreStatus.failed,
            clearScore: true,
          );
      }
    }

    // Written before the reveal, so a crash during the celebration cannot
    // lose the brew.
    await widget.db.insert(entry);
    await rememberSticky(entry);
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
        _Stage.pickMethod => AppStrings.pickMethod,
        _ => AppStrings.newEntryTitle,
      }),
    ),
    body: Padding(
      padding: const EdgeInsets.all(16),
      child: switch (_stage) {
        _Stage.describe => _describe(),
        _Stage.pickMethod => _methodPicker(),
        _Stage.fillGaps => _fillGaps(),
        _Stage.scoring => _busy(),
        _Stage.revealed => ScoreReveal(
          entry: _saved!,
          schema: widget.schema,
          method: widget.schema.method(_saved!.brewMethod),
          onRated: _rate,
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

  Widget _methodPicker() => ListView(
    children: [
      for (final category in widget.schema.categories) ...[
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 16, 4, 4),
          child: Text(
            category.label,
            style: Theme.of(context).textTheme.titleSmall,
          ),
        ),
        for (final id in category.methodIds)
          ListTile(
            title: Text(widget.schema.method(id).label),
            onTap: () => _pickMethod(id),
          ),
      ],
    ],
  );

  Widget _fillGaps() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(
        '${widget.schema.categoryOf(_brewMethod).label} · '
        '${widget.schema.method(_brewMethod).label}',
        style: Theme.of(context).textTheme.titleMedium,
      ),
      // Above the groups rather than inside one: this is the entry's own
      // timestamp, not a property of the coffee, the grind or the water.
      BrewDateField(
        value: _brewedAt ?? DateTime.now(),
        fromText: _brewedAtFromText,
        onChanged: (t) => setState(() {
          _brewedAt = t;
          _brewedAtFromText = false;
        }),
      ),
      Expanded(
        child: BrewForm(
          schema: widget.schema,
          fields: formFields(
            widget.schema,
            _brewMethod,
            _core,
            _methodData,
            _sticky,
          ),
          onChanged: (v) => _answers = v,
        ),
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
