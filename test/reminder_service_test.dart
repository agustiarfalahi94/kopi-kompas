import 'package:flutter/material.dart' show TimeOfDay;
import 'package:flutter_test/flutter_test.dart';
import 'package:kopi_kompas/models/brew_entry.dart';
import 'package:kopi_kompas/services/brew_database.dart';
import 'package:kopi_kompas/services/reminder_service.dart';
import 'package:kopi_kompas/services/settings_store.dart';
import 'package:kopi_kompas/strings.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class FakeNotifications implements Notifications {
  final calls = <String>[];
  DateTime? scheduled;
  String? scheduledTitle;
  String? scheduledBody;
  bool grant = true;

  @override
  Future<bool> requestPermission() async {
    calls.add('permission');
    return grant;
  }

  @override
  Future<void> cancelAll() async {
    calls.add('cancel');
    scheduled = null;
  }

  @override
  Future<void> scheduleAt(DateTime when, String title, String body) async {
    calls.add('schedule');
    scheduled = when;
    scheduledTitle = title;
    scheduledBody = body;
  }
}

BrewEntry brew(DateTime when) => BrewEntry(
  id: 'a',
  brewMethod: 'espresso',
  brewDate: when,
  rawInputText: 'x',
  methodData: const {},
  scoreStatus: ScoreStatus.scored,
  createdAt: when,
  updatedAt: when,
);

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late BrewDatabase db;
  late FakeNotifications notes;
  late SettingsStore settings;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    db = await BrewDatabase.open(path: inMemoryDatabasePath);
    notes = FakeNotifications();
    settings = SettingsStore();
  });

  tearDown(() => db.close());

  ReminderService service(DateTime now) => ReminderService(
    db: db,
    settings: settings,
    notifications: notes,
    now: () => now,
  );

  test('cancels before scheduling, always', () async {
    // A repeating notification cannot have one occurrence removed. Cancelling
    // and re-setting a single id is what makes "skip today" work at all.
    final s = service(DateTime(2026, 8, 12, 6));
    await s.ensurePermission();
    await s.reschedule();
    expect(notes.calls, ['permission', 'cancel', 'schedule']);
  });

  test('schedules today when nothing is logged yet', () async {
    final s = service(DateTime(2026, 8, 12, 6));
    await s.ensurePermission();
    await s.reschedule();
    expect(notes.scheduled, DateTime(2026, 8, 12, 8));
  });

  test('skips to tomorrow once a brew exists for today', () async {
    await db.insert(brew(DateTime(2026, 8, 12, 7)));
    final s = service(DateTime(2026, 8, 12, 7, 30));
    await s.ensurePermission();
    await s.reschedule();
    expect(notes.scheduled, DateTime(2026, 8, 13, 8));
  });

  test('a deleted brew makes today count as unlogged again', () async {
    final when = DateTime(2026, 8, 12, 7);
    await db.insert(brew(when));
    await db.softDelete('a', when);
    final s = service(DateTime(2026, 8, 12, 7, 30));
    await s.ensurePermission();
    await s.reschedule();
    expect(notes.scheduled, DateTime(2026, 8, 12, 8));
  });

  test('disabled cancels and schedules nothing', () async {
    await settings.setReminderEnabled(false);
    final s = service(DateTime(2026, 8, 12, 6));
    await s.ensurePermission();
    await s.reschedule();
    expect(notes.calls, ['permission', 'cancel']);
    expect(notes.scheduled, isNull);
  });

  test('uses the configured time', () async {
    await settings.setReminderTime(const TimeOfDay(hour: 6, minute: 45));
    final s = service(DateTime(2026, 8, 12, 5));
    await s.ensurePermission();
    await s.reschedule();
    expect(notes.scheduled, DateTime(2026, 8, 12, 6, 45));
  });

  test('a denied permission leaves it disabled, not crashed', () async {
    notes.grant = false;
    final s = service(DateTime(2026, 8, 12, 6));
    await s.ensurePermission();
    await s.reschedule();
    expect(s.permitted, isFalse);
    expect(notes.scheduled, isNull);
    // Still cancels, so an old notification from before the denial goes away.
    expect(notes.calls, contains('cancel'));
  });

  test('notification text follows the language setting', () async {
    // The bug: even with Indonesian selected, the notification fired in
    // English because the title and body were hardcoded constants.
    AppStrings.language = 'id';
    final s = service(DateTime(2026, 8, 12, 6));
    await s.ensurePermission();
    await s.reschedule();
    expect(notes.scheduledTitle, 'Kopi Kompas');
    expect(notes.scheduledBody, 'Belum ada kopi dicatat hari ini.');

    AppStrings.language = 'en';
    await s.reschedule();
    expect(notes.scheduledBody, 'No coffee logged yet today.');
  });

  tearDown(() => AppStrings.language = 'en');
}
