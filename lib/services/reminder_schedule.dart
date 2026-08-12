import 'package:flutter/material.dart' show TimeOfDay;

/// When the daily reminder should next fire, or null if it should not.
///
/// A pure function over an injected clock, so every branch — including the
/// day, month and year boundaries — is a unit test rather than something you
/// wait a day to observe.
///
/// This exists because a *repeating* notification cannot have one occurrence
/// cancelled. The app instead keeps a single notification id and cancels and
/// re-schedules it whenever today's entries change, which is what makes
/// "skip today, I already logged one" possible at all.
DateTime? nextReminder({
  required DateTime now,
  required TimeOfDay at,
  required bool hasBrewToday,
  required bool enabled,
}) {
  if (!enabled) return null;

  final todayAt = DateTime(now.year, now.month, now.day, at.hour, at.minute);

  // Tomorrow is built by constructing the date, not by adding 24 hours:
  // across a daylight-saving change those differ, and the reminder should
  // keep its wall-clock time rather than drift an hour.
  final tomorrowAt = DateTime(
    now.year,
    now.month,
    now.day + 1,
    at.hour,
    at.minute,
  );

  // Already logged today, so the next useful nudge is tomorrow's.
  if (hasBrewToday) return tomorrowAt;

  // `!isBefore` rather than `isAfter`: at exactly 08:00 with nothing logged,
  // firing now is right. Treating it as passed would silently skip a day.
  if (!todayAt.isBefore(now)) return todayAt;

  return tomorrowAt;
}
