import 'package:flutter/material.dart' show TimeOfDay;
import 'package:shared_preferences/shared_preferences.dart';

/// App preferences: the daily reminder and the language.
///
/// Separate from [stickyDefaults] because these are things you choose, not
/// things the app noticed.
class SettingsStore {
  static const _enabled = 'reminder.enabled';
  static const _hour = 'reminder.hour';
  static const _minute = 'reminder.minute';
  static const _language = 'language';

  Future<bool> reminderEnabled() async =>
      (await SharedPreferences.getInstance()).getBool(_enabled) ?? true;

  Future<void> setReminderEnabled(bool value) async =>
      (await SharedPreferences.getInstance()).setBool(_enabled, value);

  Future<TimeOfDay> reminderTime() async {
    final prefs = await SharedPreferences.getInstance();
    return TimeOfDay(
      hour: prefs.getInt(_hour) ?? 8,
      minute: prefs.getInt(_minute) ?? 0,
    );
  }

  Future<void> setReminderTime(TimeOfDay value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_hour, value.hour);
    await prefs.setInt(_minute, value.minute);
  }

  Future<String> language() async =>
      (await SharedPreferences.getInstance()).getString(_language) ?? 'en';

  Future<void> setLanguage(String code) async =>
      (await SharedPreferences.getInstance()).setString(_language, code);
}
