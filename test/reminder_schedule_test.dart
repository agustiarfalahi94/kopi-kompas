import 'package:flutter/material.dart' show TimeOfDay;
import 'package:flutter_test/flutter_test.dart';
import 'package:kopi_kompas/services/reminder_schedule.dart';

const eight = TimeOfDay(hour: 8, minute: 0);

void main() {
  test('a brew already logged today pushes it to tomorrow', () {
    // The whole point: never nag about a coffee you already made.
    final next = nextReminder(
      now: DateTime(2026, 8, 12, 7, 0),
      at: eight,
      hasBrewToday: true,
      enabled: true,
    );
    expect(next, DateTime(2026, 8, 13, 8, 0));
  });

  test('no brew and the time is still ahead fires today', () {
    final next = nextReminder(
      now: DateTime(2026, 8, 12, 6, 30),
      at: eight,
      hasBrewToday: false,
      enabled: true,
    );
    expect(next, DateTime(2026, 8, 12, 8, 0));
  });

  test('no brew but the time has passed fires tomorrow', () {
    final next = nextReminder(
      now: DateTime(2026, 8, 12, 9, 15),
      at: eight,
      hasBrewToday: false,
      enabled: true,
    );
    expect(next, DateTime(2026, 8, 13, 8, 0));
  });

  test('disabled schedules nothing', () {
    expect(
      nextReminder(
        now: DateTime(2026, 8, 12, 6, 0),
        at: eight,
        hasBrewToday: false,
        enabled: false,
      ),
      isNull,
    );
  });

  test('exactly at the reminder minute still counts as due today', () {
    // Otherwise opening the app at 08:00 sharp silently skips a whole day.
    final next = nextReminder(
      now: DateTime(2026, 8, 12, 8, 0),
      at: eight,
      hasBrewToday: false,
      enabled: true,
    );
    expect(next, DateTime(2026, 8, 12, 8, 0));
  });

  test('crossing a month boundary lands on the first', () {
    final next = nextReminder(
      now: DateTime(2026, 8, 31, 9, 0),
      at: eight,
      hasBrewToday: false,
      enabled: true,
    );
    expect(next, DateTime(2026, 9, 1, 8, 0));
  });

  test('crossing a year boundary lands in January', () {
    final next = nextReminder(
      now: DateTime(2026, 12, 31, 9, 0),
      at: eight,
      hasBrewToday: false,
      enabled: true,
    );
    expect(next, DateTime(2027, 1, 1, 8, 0));
  });

  test('the result carries the reminder minute, not the current one', () {
    final next = nextReminder(
      now: DateTime(2026, 8, 12, 6, 43),
      at: const TimeOfDay(hour: 7, minute: 15),
      hasBrewToday: false,
      enabled: true,
    );
    expect(next, DateTime(2026, 8, 12, 7, 15));
  });

  test('a late-night brew still counts for that calendar day', () {
    // Logged at 00:30 on the 12th, checked at 01:00 on the 12th: the app
    // must know today is covered.
    final next = nextReminder(
      now: DateTime(2026, 8, 12, 1, 0),
      at: eight,
      hasBrewToday: true,
      enabled: true,
    );
    expect(next, DateTime(2026, 8, 13, 8, 0));
  });
}
