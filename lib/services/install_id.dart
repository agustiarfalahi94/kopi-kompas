import 'package:shared_preferences/shared_preferences.dart';

import '../models/brew_entry.dart' show newUuid;

/// A random id for this installation, used only to rate-limit the Worker.
///
/// It means nothing off-device and identifies no person — it exists so a
/// leaked endpoint URL costs one install's daily allowance rather than the
/// whole Gemini quota.
Future<String> loadInstallId() async {
  final prefs = await SharedPreferences.getInstance();
  final existing = prefs.getString('installId');
  if (existing != null) return existing;
  final fresh = newUuid();
  await prefs.setString('installId', fresh);
  return fresh;
}
