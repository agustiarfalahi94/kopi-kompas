import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../strings.dart';
import 'brew_database.dart';
import 'reminder_schedule.dart';
import 'settings_store.dart';

/// The slice of the notification plugin this needs.
///
/// Depending on three methods rather than the whole plugin is what lets the
/// tests use a fake — the plugin itself cannot run in a unit test.
abstract class Notifications {
  Future<bool> requestPermission();
  Future<void> cancelAll();
  Future<void> scheduleAt(DateTime when, String title, String body);
}

/// Keeps exactly one pending reminder, correct as of the last time anything
/// changed.
///
/// Call [reschedule] on app resume and after every save, delete and restore.
/// It is cheap and idempotent, and calling it too often is far safer than
/// calling it too rarely — a stale schedule is how you get nagged about a
/// coffee you already logged.
class ReminderService {
  ReminderService({
    required this.db,
    required this.settings,
    required this.notifications,
    this.now = DateTime.now,
  });

  final BrewDatabase db;
  final SettingsStore settings;
  final Notifications notifications;
  final DateTime Function() now;

  bool _permitted = true;

  bool get permitted => _permitted;

  Future<void> ensurePermission() async {
    _permitted = await notifications.requestPermission();
  }

  /// Cancels whatever was pending and schedules the next one, if any.
  ///
  /// Always cancel first. A repeating notification cannot have one occurrence
  /// removed, so "skip today" only works because there is a single pending
  /// notification that gets replaced wholesale.
  Future<void> reschedule() async {
    await notifications.cancelAll();
    if (!_permitted) return;

    final enabled = await settings.reminderEnabled();
    final at = await settings.reminderTime();
    final current = now();

    final next = nextReminder(
      now: current,
      at: at,
      hasBrewToday: await db.hasBrewOn(current),
      enabled: enabled,
    );
    if (next == null) return;

    await notifications.scheduleAt(
      next,
      AppStrings.appName,
      AppStrings.notificationBody,
    );
  }
}

/// The real plugin, behind the same three methods.
class PluginNotifications implements Notifications {
  PluginNotifications(this._plugin);

  final FlutterLocalNotificationsPlugin _plugin;

  static const _id = 1;

  /// One id, always. See [ReminderService.reschedule].
  static const _details = NotificationDetails(
    android: AndroidNotificationDetails(
      'daily_reminder',
      'Daily reminder',
      channelDescription: 'A nudge to log a coffee, on days you have not.',
      importance: Importance.defaultImportance,
    ),
  );

  Future<void> init() async {
    tzdata.initializeTimeZones();
    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      ),
    );
  }

  @override
  Future<bool> requestPermission() async {
    final android = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    return await android?.requestNotificationsPermission() ?? true;
  }

  @override
  Future<void> cancelAll() => _plugin.cancel(id: _id);

  @override
  Future<void> scheduleAt(DateTime when, String title, String body) =>
      _plugin.zonedSchedule(
        id: _id,
        title: title,
        body: body,
        scheduledDate: tz.TZDateTime.from(when, tz.local),
        notificationDetails: _details,
        // Inexact on purpose: a logbook nudge does not need to land on the
        // second, and asking for SCHEDULE_EXACT_ALARM is a Play Store review
        // problem for no gain.
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      );
}
