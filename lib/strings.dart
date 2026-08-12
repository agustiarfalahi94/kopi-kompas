import 'data/brew_schema.dart' show FieldGroup;

/// Every user-facing string in the app.
///
/// Static getters rather than a map, so a string that does not exist fails to
/// compile instead of rendering as an empty box. Phase 3 turns this into an
/// EN/ID pair; keeping widgets off bare literals now is what makes that a new
/// file rather than an edit to every screen.
class AppStrings {
  const AppStrings._();

  static String get appName => 'Kopi Kompas';
  static String get newEntryTitle => 'What did you brew?';
  static String get describeHint =>
      'e.g. 18g in, 36g out in 28 seconds, wdt and tamp, honduras medium';
  static String get parseButton => 'Continue';
  static String get parsing => 'Reading your brew…';
  static String get scoring => 'Scoring…';
  static String get saveButton => 'Save';
  static String get doneButton => 'Done';
  static String get emptyLog => 'No brews yet. Tap + to log one.';
  static String get notScored => 'Not scored';
  static String get scoreFailed => 'Not scored yet — tap to retry';
  static String get fillGapsTitle => 'A few more things';
  static String get parseFailed =>
      'Could not read that. Your text is safe — retry, or fill it in by hand.';
  static String get offline =>
      'No connection. Your text is safe — retry, or fill it in by hand.';
  static String get rateLimited =>
      'Daily limit reached. Your text is safe — fill it in by hand for now.';
  static String get retry => 'Retry';
  static String get byHand => 'Fill in by hand';
  static String get pickMethod => 'What did you brew it with?';
  static String get scoreThisBrew => 'Score this brew';
  static String get whatYouTyped => 'What you typed';
  static String get deleteTitle => 'Delete this brew?';
  static String get deleteBody =>
      'It moves to Deleted entries in Settings, where you can bring it '
      'back or remove it for good.';
  static String get delete => 'Delete';
  static String get cancel => 'Cancel';
  static String get yes => 'Yes';
  static String get no => 'No';
  static String get fullLogTitle => 'Full log';
  static String get editTitle => 'Edit';
  static String get scoreLabel => 'Score';
  static String get settingsTitle => 'Settings';
  static String get reminderTitle => 'Daily reminder';
  static String get reminderSubtitle =>
      'Only on days you have not logged a coffee.';
  static String get reminderBlocked =>
      'Notifications are turned off for this app in Android settings.';
  static String get reminderTime => 'Remind me at';
  static String get deletedTitle => 'Deleted entries';
  static String get deletedSubtitle => 'Bring a brew back, or remove it';
  static String get deletedOn => 'Deleted';
  static String get emptyDeleted => 'Nothing deleted.';
  static String get restore => 'Restore';
  static String get purge => 'Delete for good';
  static String get purgeTitle => 'Delete for good?';
  static String get purgeBody => 'This cannot be undone.';
  static String get rememberedTitle => 'Remembered for next time';
  static String get rememberedSubtitle =>
      'Filled in automatically. Say something different and it updates.';
  static String get rememberedEmpty => 'Nothing yet — log a brew.';

  static String stickyLabel(String name) => switch (name) {
    'grinder' => 'Grinder',
    'grindSetting' => 'Grind setting',
    'waterType' => 'Water',
    'machine' => 'Machine',
    _ => name,
  };
  static String get rateThis => 'What did you think?';

  static String groupLabel(FieldGroup g) => switch (g) {
    FieldGroup.coffee => 'Coffee',
    FieldGroup.grind => 'Grind',
    FieldGroup.brew => 'Brew',
    FieldGroup.water => 'Water',
  };
}
