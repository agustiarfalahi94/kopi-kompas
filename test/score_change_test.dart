import 'package:flutter_test/flutter_test.dart';
import 'package:kopi_kompas/strings.dart';
import 'package:kopi_kompas/widgets/score_change_dialog.dart';

ScoreChange change({
  int? before = 88,
  int? after = 75,
  String? beforeRubric = 'r3',
  String? afterRubric = 'r3',
  bool failed = false,
}) => ScoreChange(
  before: before,
  after: after,
  beforeRubric: beforeRubric,
  afterRubric: afterRubric,
  reasons: const ['Ratio 2.0 — on target'],
  failed: failed,
);

void main() {
  tearDown(() => AppStrings.language = 'en');

  test('a different number is announced as a change', () {
    final c = change();
    expect(c.moved, isTrue);
    expect(c.title, AppStrings.scoreChangedTitle);
    expect(c.body, AppStrings.scoreChangedWhy);
  });

  test('the same number says so rather than staying quiet', () {
    // Silence after an edit reads as "nothing happened", and something did:
    // the brew was sent to the model and judged again.
    final c = change(after: 88);
    expect(c.moved, isFalse);
    expect(c.title, AppStrings.scoreSameTitle);
    expect(c.body, AppStrings.scoreSameWhy);
  });

  test('a failed re-score is admitted, not hidden behind the old number', () {
    final c = change(failed: true);
    expect(c.moved, isFalse);
    expect(c.title, AppStrings.scoreRetryFailed);
  });

  test('a rubric change is disclosed, because it is not the edit', () {
    // The trap this exists for: r2 marked a pressurised basket down for
    // skipping WDT and r3 does not, so an otherwise untouched shot can move
    // fourteen points. Blaming that on the edit would be a confident lie.
    expect(change(beforeRubric: 'r2', afterRubric: 'r3').rubricMoved, isTrue);
    expect(change().rubricMoved, isFalse);
  });

  test('a failed call never claims the rubric moved', () {
    // Nothing was scored, so nothing can be attributed to anything.
    final c = change(beforeRubric: 'r2', afterRubric: 'r3', failed: true);
    expect(c.rubricMoved, isFalse);
  });

  test('an unscored brew gaining its first score still announces', () {
    final c = change(before: null, beforeRubric: null);
    expect(c.moved, isTrue);
    expect(c.rubricMoved, isFalse);
  });

  test('every message exists in both languages', () {
    for (final read in [
      () => AppStrings.scoreChangedTitle,
      () => AppStrings.scoreSameTitle,
      () => AppStrings.scoreChangedWhy,
      () => AppStrings.scoreSameWhy,
      () => AppStrings.scoreRubricMoved,
      () => AppStrings.scoreRetryFailed,
    ]) {
      AppStrings.language = 'en';
      final en = read();
      AppStrings.language = 'id';
      final id = read();
      expect(en, isNotEmpty);
      expect(id, isNotEmpty);
      expect(en, isNot(id), reason: 'untranslated: $en');
    }
  });
}
