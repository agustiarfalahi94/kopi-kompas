import 'package:flutter/material.dart';

import 'data/brew_schema.dart';
import 'screens/home_screen.dart';
import 'services/brew_database.dart';
import 'services/install_id.dart';
import 'services/kopi_client.dart';
import 'strings.dart';
import 'theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final db = await BrewDatabase.open();
  final schema = await BrewSchema.load();
  final client = KopiClient(installId: await loadInstallId());
  runApp(KopiKompasApp(db: db, schema: schema, client: client));
}

/// Dependencies are passed by constructor rather than through a
/// state-management package: this slice is one list and one flow.
class KopiKompasApp extends StatelessWidget {
  const KopiKompasApp({
    super.key,
    required this.db,
    required this.schema,
    required this.client,
  });

  final BrewDatabase db;
  final BrewSchema schema;
  final KopiClient client;

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: AppStrings.appName,
    theme: kopiTheme(Brightness.light),
    darkTheme: kopiTheme(Brightness.dark),
    home: HomeScreen(db: db, schema: schema, client: client),
  );
}
