import 'package:flutter/material.dart';

import 'screens/home_screen.dart';
import 'strings.dart';
import 'theme.dart';

void main() => runApp(const KopiKompasApp());

class KopiKompasApp extends StatelessWidget {
  const KopiKompasApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: AppStrings.appName,
    theme: kopiTheme(Brightness.light),
    darkTheme: kopiTheme(Brightness.dark),
    home: const HomeScreen(),
  );
}
