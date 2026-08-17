import 'package:flutter/material.dart';

import '../data/brew_guide.dart';
import '../data/brew_schema.dart';
import '../data/guide_photo.dart';
import '../models/brew_entry.dart';
import '../services/brew_database.dart';
import '../services/kopi_client.dart';
import '../services/auth_service.dart';
import '../services/backup_service.dart';
import '../services/log_filter.dart';
import '../services/reminder_service.dart';
import '../strings.dart';
import '../widgets/log_filter_bar.dart';
import 'edit_entry_screen.dart';
import 'entry_detail_screen.dart';
import 'full_log_screen.dart';
import 'guide_screen.dart';
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
    required this.reminder,
    required this.guides,
    required this.photos,
    required this.auth,
    required this.backup,
  });

  final BrewDatabase db;
  final BrewSchema schema;
  final KopiClient client;
  final ReminderService reminder;
  final BrewGuides guides;
  final GuidePhotos photos;
  final AuthService? auth;
  final BackupService? backup;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late Future<List<BrewEntry>> _entries = widget.db.liveEntries();

  /// Held here rather than in the bar, so opening a brew and coming back
  /// leaves the list exactly as you left it. `_reload` deliberately does not
  /// touch it: a save must refresh the entries without dropping the filter.
  LogFilter _filter = const LogFilter();

  void _reload() {
    setState(() => _entries = widget.db.liveEntries());
    // Anything that changes today's entries changes when the next nudge is
    // due, so this runs after every save, delete, restore and edit.
    widget.reminder.reschedule();
    // Fire-and-forget: the entry is already saved locally, and a failed
    // backup must never surface as a failed save.
    widget.backup?.pushAll();
  }

  Future<void> _newEntry() async {
    await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => NewEntryScreen(
          db: widget.db,
          schema: widget.schema,
          client: widget.client,
          photos: widget.photos,
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
            switch (result) {
              case ScoreOk(
                :final score,
                :final reasons,
                :final rubric,
                :final model,
              ):
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
                return null;
              case ScoreFailed(:final kind):
                return scoreMessageFor(kind);
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
          tooltip: AppStrings.guidesTitle,
          icon: const Icon(Icons.menu_book_outlined),
          onPressed: () => _open(
            GuideListScreen(
              schema: widget.schema,
              guides: widget.guides,
              photos: widget.photos,
            ),
          ),
        ),
        IconButton(
          tooltip: AppStrings.settingsTitle,
          icon: const Icon(Icons.settings_outlined),
          onPressed: () => _open(
            SettingsScreen(
              db: widget.db,
              schema: widget.schema,
              photos: widget.photos,
              reminder: widget.reminder,
              auth: widget.auth,
              backup: widget.backup,
            ),
          ),
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
        final shown = _filter.apply(entries, widget.schema);
        return Column(
          children: [
            LogFilterBar(
              schema: widget.schema,
              filter: _filter,
              shown: shown.length,
              total: entries.length,
              onChanged: (f) => setState(() => _filter = f),
            ),
            Expanded(
              child: shown.isEmpty
                  ? Center(child: Text(AppStrings.noMatches))
                  : ListView.separated(
                      itemCount: shown.length,
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (context, i) => _tile(shown[i]),
                    ),
            ),
          ],
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
