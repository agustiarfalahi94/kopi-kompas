import 'package:flutter/material.dart';

import 'data/brew_schema.dart';
import 'screens/home_screen.dart';
import 'services/brew_database.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'services/auth_service.dart';
import 'services/backup_service.dart';
import 'services/firestore_store.dart';
import 'services/install_id.dart';
import 'services/kopi_client.dart';
import 'services/reminder_service.dart';
import 'services/settings_store.dart';
import 'strings.dart';
import 'theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Firebase is optional at runtime: if it cannot start — no config, no Play
  // Services — the app carries on signed out rather than refusing to open.
  AuthService? auth;
  try {
    await Firebase.initializeApp();
    auth = AuthService();
  } catch (_) {
    auth = null;
  }

  final settings = SettingsStore();
  AppStrings.language = await settings.language();

  final db = await BrewDatabase.open();
  final schema = await BrewSchema.load();
  final client = KopiClient(installId: await loadInstallId());

  final plugin = PluginNotifications(FlutterLocalNotificationsPlugin());
  await plugin.init();
  final reminder = ReminderService(
    db: db,
    settings: settings,
    notifications: plugin,
  );
  await reminder.ensurePermission();
  await reminder.reschedule();

  final backup = auth == null
      ? null
      : BackupService(
          db: db,
          remote: FirestoreStore(),
          uid: () => switch (auth!.current) {
            SignedIn(:final uid) => uid,
            SignedOut() => null,
          },
        );

  runApp(
    KopiKompasApp(
      db: db,
      schema: schema,
      client: client,
      reminder: reminder,
      auth: auth,
      backup: backup,
    ),
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
    required this.auth,
    required this.backup,
  });

  final BrewDatabase db;
  final BrewSchema schema;
  final KopiClient client;
  final ReminderService reminder;

  /// Null when Firebase could not start. Everything still works; there is
  /// simply no backup on offer.
  final AuthService? auth;
  final BackupService? backup;

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
      auth: widget.auth,
      backup: widget.backup,
    ),
  );
}
