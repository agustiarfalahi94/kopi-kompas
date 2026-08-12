import 'package:flutter/material.dart';

import '../strings.dart';

/// Placeholder until Task 8 gives it the log list.
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(AppStrings.appName)),
    body: Center(child: Text(AppStrings.emptyLog)),
  );
}
