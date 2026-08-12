import 'package:flutter/material.dart';

import '../data/brew_schema.dart';
import '../models/brew_entry.dart';
import '../services/brew_database.dart';
import '../services/kopi_client.dart';
import '../strings.dart';
import 'new_entry_screen.dart';

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

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(AppStrings.appName)),
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
      title: Text(widget.schema.method(e.brewMethod).label),
      subtitle: Text(
        [if (e.beanOrigin != null) e.beanOrigin!, stamp].join(' · '),
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
