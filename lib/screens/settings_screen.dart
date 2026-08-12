import 'package:flutter/material.dart';

import '../data/brew_schema.dart';
import '../services/brew_database.dart';
import '../services/sticky_defaults.dart';
import '../strings.dart';
import 'deleted_entries_screen.dart';

/// Settings.
///
/// Holds the Deleted entries page and shows what the app has remembered.
/// Phase 5 hangs the daily reminder and the language switch here.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key, required this.db, required this.schema});

  final BrewDatabase db;
  final BrewSchema schema;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late Future<Map<String, Object?>> _sticky = loadStickyDefaults();

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(AppStrings.settingsTitle)),
    body: ListView(
      children: [
        ListTile(
          leading: const Icon(Icons.delete_outline),
          title: Text(AppStrings.deletedTitle),
          subtitle: Text(AppStrings.deletedSubtitle),
          onTap: () async {
            await Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) =>
                    DeletedEntriesScreen(db: widget.db, schema: widget.schema),
              ),
            );
            if (mounted) setState(() => _sticky = loadStickyDefaults());
          },
        ),
        const Divider(),
        // Shown rather than editable: these are set by logging a brew, and a
        // second place to change them would be a second thing to keep in
        // step with what you actually used.
        FutureBuilder<Map<String, Object?>>(
          future: _sticky,
          builder: (context, snap) {
            final d = snap.data ?? const {};
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                  child: Text(
                    AppStrings.rememberedTitle,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: Text(
                    AppStrings.rememberedSubtitle,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
                if (d.isEmpty)
                  ListTile(subtitle: Text(AppStrings.rememberedEmpty))
                else
                  for (final name in stickyFieldNames)
                    if (d[name] != null)
                      ListTile(
                        dense: true,
                        title: Text(AppStrings.stickyLabel(name)),
                        trailing: Text('${d[name]}'),
                      ),
              ],
            );
          },
        ),
      ],
    ),
  );
}
