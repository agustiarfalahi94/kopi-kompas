import 'package:flutter/material.dart';

import 'data/brew_schema.dart';
import 'screens/home_screen.dart';
import 'services/brew_database.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'services/install_id.dart';
import 'services/kopi_client.dart';
import 'services/reminder_service.dart';
import 'services/settings_store.dart';
import 'strings.dart';
import 'theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final db = await BrewDatabase.open();
  final schema = await BrewSchema.load();
  final client = KopiClient(installId: await loadInstallId());

  final plugin = PluginNotifications(FlutterLocalNotificationsPlugin());
  await plugin.init();
  final reminder = ReminderService(
    db: db,
    settings: SettingsStore(),
    notifications: plugin,
  );
  await reminder.ensurePermission();
  await reminder.reschedule();

  runApp(
    KopiKompasApp(db: db, schema: schema, client: client, reminder: reminder),
  );
}

/// Dependencies are passed by constructor rather than through a
/// state-management package: this slice is one list and one flow.
class KopiKompasApp extends StatefulWidget {
  const KopiKompasApp({
    super.key,
    required this.db,
    required this.schema,
    required this.client,
    required this.reminder,
  });

  final BrewDatabase db;
  final BrewSchema schema;
  final KopiClient client;
  final ReminderService reminder;

  @override
  State<KopiKompasApp> createState() => _KopiKompasAppState();
}

class _KopiKompasAppState extends State<KopiKompasApp>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Rescheduling on resume is what keeps the reminder honest across a day
    // boundary: the pending notification was correct when it was set, and
    // stops being correct the moment the date changes.
    if (state == AppLifecycleState.resumed) widget.reminder.reschedule();
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: AppStrings.appName,
    theme: kopiTheme(Brightness.light),
    darkTheme: kopiTheme(Brightness.dark),
    home: HomeScreen(
      db: widget.db,
      schema: widget.schema,
      client: widget.client,
      reminder: widget.reminder,
    ),
  );
}
