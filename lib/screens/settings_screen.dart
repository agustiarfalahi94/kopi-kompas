import 'package:flutter/material.dart';

import '../data/brew_schema.dart';
import '../services/brew_database.dart';
import '../services/reminder_service.dart';
import '../services/settings_store.dart';
import '../services/sticky_defaults.dart';
import '../strings.dart';
import 'deleted_entries_screen.dart';

/// Settings.
///
/// Holds the Deleted entries page and shows what the app has remembered.
/// Phase 5 hangs the daily reminder and the language switch here.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({
    super.key,
    required this.db,
    required this.schema,
    required this.reminder,
  });

  final BrewDatabase db;
  final BrewSchema schema;
  final ReminderService reminder;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _settings = SettingsStore();
  late Future<Map<String, Object?>> _sticky = loadStickyDefaults();
  bool _enabled = true;
  TimeOfDay _time = const TimeOfDay(hour: 8, minute: 0);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final enabled = await _settings.reminderEnabled();
    final time = await _settings.reminderTime();
    if (!mounted) return;
    setState(() {
      _enabled = enabled;
      _time = time;
    });
  }

  Future<void> _setEnabled(bool value) async {
    // Asking only when switching on: a permission prompt when someone is
    // turning the thing off would be absurd.
    if (value && !widget.reminder.permitted) {
      await widget.reminder.ensurePermission();
    }
    await _settings.setReminderEnabled(value);
    await widget.reminder.reschedule();
    if (mounted) setState(() => _enabled = value);
  }

  Future<void> _setLanguage(String code) async {
    await _settings.setLanguage(code);
    AppStrings.language = code;
    // Rebuild the whole tree: labels come from the schema and the strings
    // file, and both read the language at build time.
    if (mounted) setState(() {});
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(context: context, initialTime: _time);
    if (picked == null) return;
    await _settings.setReminderTime(picked);
    await widget.reminder.reschedule();
    if (mounted) setState(() => _time = picked);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(AppStrings.settingsTitle)),
    body: ListView(
      children: [
        SwitchListTile(
          secondary: const Icon(Icons.notifications_outlined),
          title: Text(AppStrings.reminderTitle),
          subtitle: Text(
            widget.reminder.permitted
                ? AppStrings.reminderSubtitle
                : AppStrings.reminderBlocked,
          ),
          value: _enabled && widget.reminder.permitted,
          onChanged: widget.reminder.permitted ? _setEnabled : null,
        ),
        if (_enabled && widget.reminder.permitted)
          ListTile(
            leading: const SizedBox(width: 24),
            title: Text(AppStrings.reminderTime),
            trailing: Text(
              '${_time.hour.toString().padLeft(2, '0')}:'
              '${_time.minute.toString().padLeft(2, '0')}',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            onTap: _pickTime,
          ),
        const Divider(),
        ListTile(
          leading: const Icon(Icons.language),
          title: Text(AppStrings.languageTitle),
          trailing: SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'en', label: Text('EN')),
              ButtonSegment(value: 'id', label: Text('ID')),
            ],
            selected: {AppStrings.language},
            onSelectionChanged: (v) => _setLanguage(v.first),
          ),
        ),
        const Divider(),
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
