import 'package:flutter/material.dart';

import '../data/brew_schema.dart';
import '../models/brew_entry.dart';
import '../services/brew_database.dart';
import '../services/kopi_client.dart';
import '../strings.dart';
import 'edit_entry_screen.dart';
import 'entry_detail_screen.dart';
import 'full_log_screen.dart';
import 'new_entry_screen.dart';
import 'settings_screen.dart';

/// Human names for the variant values, which are stored as ids.
///
/// Kept here rather than in the schema because these are display strings for
/// one screen; the schema's job is the shape of the data.
const _variantLabels = {
  'v60': 'V60',
  'origami': 'Origami',
  'kono': 'Kono',
  'kalitaWave': 'Kalita Wave',
  'staggX': 'Stagg [X]',
  'orea': 'Orea',
  'april': 'April',
  'clever': 'Clever Dripper',
  'switch': 'Hario Switch',
  'ristretto': 'Ristretto',
  'lungo': 'Lungo',
};

/// What to call a brew in a list.
///
/// Prefers the variant over the method: you brewed a V60, not a "cone
/// dripper", and a ristretto, not an "espresso". `normale` is the exception —
/// nobody says it out loud, so it reads as Espresso. Anything unrecognised
/// falls back to the method label rather than showing a raw id.
String displayLabel(BrewSchema schema, BrewEntry entry) {
  for (final key in ['brewer', 'shotStyle']) {
    final value = entry.methodData[key];
    if (value == 'normale') continue;
    final label = _variantLabels[value];
    if (label != null) return label;
  }
  return schema.method(entry.brewMethod).label;
}

/// The everyday surface: live brews, newest first. Deliberately sparse — the
/// full log in Phase 3 is where everything is shown at once.
class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    required this.db,
    required this.schema,
    required this.client,
  });

  final BrewDatabase db;
  final BrewSchema schema;
  final KopiClient client;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late Future<List<BrewEntry>> _entries = widget.db.liveEntries();

  void _reload() => setState(() => _entries = widget.db.liveEntries());

  Future<void> _newEntry() async {
    await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => NewEntryScreen(
          db: widget.db,
          schema: widget.schema,
          client: widget.client,
        ),
      ),
    );
    _reload();
  }

  Future<void> _open(Widget screen) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));
    _reload();
  }

  Future<void> _openDetail(BrewEntry e) async {
    // Captured before the await so the pop below never reaches for a context
    // that may have gone away.
    final navigator = Navigator.of(context);
    await navigator.push(
      MaterialPageRoute(
        builder: (_) => EntryDetailScreen(
          schema: widget.schema,
          entry: e,
          onEdit: () async {
            final changed = await navigator.push<bool>(
              MaterialPageRoute(
                builder: (_) => EditEntryScreen(
                  db: widget.db,
                  schema: widget.schema,
                  client: widget.client,
                  entry: e,
                ),
              ),
            );
            if (changed == true) navigator.pop();
          },
          onRescore: () async {
            final result = await widget.client.score(e);
            if (result case ScoreOk(
              :final score,
              :final reasons,
              :final rubric,
              :final model,
            )) {
              await widget.db.update(
                e.copyWith(
                  overallScore: score,
                  scoreReasons: reasons,
                  scoreStatus: ScoreStatus.scored,
                  scoreRubric: rubric,
                  scoreModel: model,
                  scoredAt: DateTime.now(),
                  updatedAt: DateTime.now(),
                ),
              );
              navigator.pop();
            }
          },
          onRate: (stars) async {
            await widget.db.update(
              e.copyWith(myRating: stars, updatedAt: DateTime.now()),
            );
          },
          onDelete: () async {
            await widget.db.softDelete(e.id, DateTime.now());
            navigator.pop();
          },
        ),
      ),
    );
    _reload();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(AppStrings.appName),
      actions: [
        IconButton(
          tooltip: AppStrings.fullLogTitle,
          icon: const Icon(Icons.article_outlined),
          onPressed: () =>
              _open(FullLogScreen(db: widget.db, schema: widget.schema)),
        ),
        IconButton(
          tooltip: AppStrings.settingsTitle,
          icon: const Icon(Icons.settings_outlined),
          onPressed: () =>
              _open(SettingsScreen(db: widget.db, schema: widget.schema)),
        ),
      ],
    ),
    floatingActionButton: FloatingActionButton(
      onPressed: _newEntry,
      child: const Icon(Icons.add),
    ),
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
          itemCount: entries.length,
          separatorBuilder: (_, _) => const Divider(height: 1),
          itemBuilder: (context, i) => _tile(entries[i]),
        );
      },
    ),
  );

  Widget _tile(BrewEntry e) {
    final theme = Theme.of(context);
    final when = e.brewDate;
    final stamp =
        '${when.day}/${when.month} '
        '${when.hour.toString().padLeft(2, '0')}:'
        '${when.minute.toString().padLeft(2, '0')}';

    return ListTile(
      onTap: () => _openDetail(e),
      title: Text(displayLabel(widget.schema, e)),
      subtitle: Text(
        [
          if (e.beanOrigin != null) e.beanOrigin!,
          if (e.myRating != null) '★' * e.myRating!,
          stamp,
        ].join(' · '),
      ),
      trailing: switch (e.scoreStatus) {
        ScoreStatus.scored => Text(
          '${e.overallScore}',
          style: theme.textTheme.titleLarge?.copyWith(
            color: theme.colorScheme.primary,
            fontWeight: FontWeight.bold,
          ),
        ),
        _ => Text(AppStrings.notScored, style: theme.textTheme.bodySmall),
      },
    );
  }
}
