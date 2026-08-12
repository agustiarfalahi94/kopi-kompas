import 'package:shared_preferences/shared_preferences.dart';

import '../models/brew_entry.dart';

/// Fields remembered from the last entry and pre-filled into the next form.
///
/// Only things that change once or twice a year. Bean origin is deliberately
/// absent — it changes with every bag, so remembering it would pre-fill a
/// wrong answer far more often than a right one.
///
/// Without this, the full form's cost lands on exactly the fields it exists to
/// rescue: you would retype your grinder every morning and stop bothering by
/// Thursday.
const stickyFieldNames = ['grinder', 'grindSetting', 'waterType', 'machine'];

const _prefix = 'sticky.';

Future<Map<String, Object?>> loadStickyDefaults() async {
  final prefs = await SharedPreferences.getInstance();
  final out = <String, Object?>{};
  for (final name in stickyFieldNames) {
    final v = prefs.getString('$_prefix$name');
    if (v != null && v.isNotEmpty) out[name] = v;
  }
  return out;
}

/// Remembers the sticky fields from a saved entry.
///
/// Reads core fields off the entry and method fields out of `methodData`,
/// because `machine` lives in the method while `grinder` is shared.
Future<void> rememberSticky(BrewEntry entry) async {
  final prefs = await SharedPreferences.getInstance();
  final source = <String, Object?>{
    'grinder': entry.grinder,
    'grindSetting': entry.grindSetting,
    'waterType': entry.waterType,
    ...entry.methodData,
  };
  for (final name in stickyFieldNames) {
    final v = source[name];
    if (v is String && v.trim().isNotEmpty) {
      await prefs.setString('$_prefix$name', v.trim());
    }
  }
}
