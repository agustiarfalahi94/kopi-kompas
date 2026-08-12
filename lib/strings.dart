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
  static String get rateThis => 'What did you think?';

  static String groupLabel(FieldGroup g) => switch (g) {
    FieldGroup.coffee => 'Coffee',
    FieldGroup.grind => 'Grind',
    FieldGroup.brew => 'Brew',
    FieldGroup.water => 'Water',
  };
}
