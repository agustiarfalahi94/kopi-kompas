import 'package:flutter/material.dart';

import '../data/brew_schema.dart';
import '../models/brew_entry.dart';
import '../services/brew_database.dart';
import '../strings.dart';
import 'home_screen.dart' show displayLabel;

/// Brews you deleted, with the date you deleted them.
///
/// This is a recovery tool, not somewhere you browse, which is why it sits
/// inside Settings rather than in the main navigation.
class DeletedEntriesScreen extends StatefulWidget {
  const DeletedEntriesScreen({
    super.key,
    required this.db,
    required this.schema,
  });

  final BrewDatabase db;
  final BrewSchema schema;

  @override
  State<DeletedEntriesScreen> createState() => _DeletedEntriesScreenState();
}

class _DeletedEntriesScreenState extends State<DeletedEntriesScreen> {
  late Future<List<BrewEntry>> _entries = widget.db.deletedEntries();

  void _reload() => setState(() => _entries = widget.db.deletedEntries());

  Future<void> _restore(BrewEntry e) async {
    await widget.db.restore(e.id, DateTime.now());
    _reload();
  }

  /// Asks twice, because this is the only thing in the app that cannot be
  /// undone.
  Future<void> _purge(BrewEntry e) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(AppStrings.purgeTitle),
        content: Text(AppStrings.purgeBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(AppStrings.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(AppStrings.purge),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await widget.db.purge(e.id);
    _reload();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(AppStrings.deletedTitle)),
    body: FutureBuilder<List<BrewEntry>>(
      future: _entries,
      builder: (context, snap) {
        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final entries = snap.data!;
        if (entries.isEmpty) {
          return Center(child: Text(AppStrings.emptyDeleted));
        }
        return ListView.separated(
          itemCount: entries.length,
          separatorBuilder: (_, _) => const Divider(height: 1),
          itemBuilder: (context, i) {
            final e = entries[i];
            final d = e.deletedAt;
            return ListTile(
              title: Text(displayLabel(widget.schema, e)),
              subtitle: Text(
                d == null
                    ? ''
                    : '${AppStrings.deletedOn} '
                          '${d.year}-${d.month.toString().padLeft(2, '0')}-'
                          '${d.day.toString().padLeft(2, '0')}',
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    tooltip: AppStrings.restore,
                    icon: const Icon(Icons.restore),
                    onPressed: () => _restore(e),
                  ),
                  IconButton(
                    tooltip: AppStrings.purge,
                    icon: const Icon(Icons.delete_forever),
                    onPressed: () => _purge(e),
                  ),
                ],
              ),
            );
          },
        );
      },
    ),
  );
}
