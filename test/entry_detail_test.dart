import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kopi_kompas/data/brew_schema.dart';
import 'package:kopi_kompas/models/brew_entry.dart';
import 'package:kopi_kompas/screens/entry_detail_screen.dart';

late BrewSchema schema;

BrewEntry entryWith({
  String method = 'espresso',
  Map<String, Object?> methodData = const {},
  String? beanOrigin,
  String? roastLevel,
  double? doseGrams,
  ScoreStatus status = ScoreStatus.scored,
  int? score = 93,
  int? myRating,
  String raw = '18g in, 36g out',
}) => BrewEntry(
  id: 'a',
  brewMethod: method,
  myRating: myRating,
  beanOrigin: beanOrigin,
  roastLevel: roastLevel,
  doseGrams: doseGrams,
  brewDate: DateTime(2026, 8, 12, 7),
  rawInputText: raw,
  methodData: methodData,
  scoreStatus: status,
  overallScore: status == ScoreStatus.scored ? score : null,
  scoreReasons: status == ScoreStatus.scored
      ? const ['Ratio 2.0 — on target']
      : const [],
  scoreRubric: status == ScoreStatus.scored ? 'r2' : null,
  scoreModel: status == ScoreStatus.scored ? 'gemini-3.5-flash' : null,
  createdAt: DateTime(2026, 8, 12, 7),
  updatedAt: DateTime(2026, 8, 12, 7),
);

void main() {
  setUpAll(() {
    schema = BrewSchema.parse(
      File('schema/brew_schema.json').readAsStringSync(),
    );
  });

  group('detailRows', () {
    test('shows only fields that have a value', () {
      final rows = detailRows(
        schema,
        entryWith(beanOrigin: 'Honduras', methodData: {'yieldGrams': 36.0}),
      );
      final names = rows.map((r) => r.spec.name);
      expect(names, contains('beanOrigin'));
      expect(names, contains('yieldGrams'));
      expect(names, isNot(contains('pressureBars')));
      expect(names, isNot(contains('roaster')));
    });

    test('keeps schema order, core before method', () {
      final rows = detailRows(
        schema,
        entryWith(
          beanOrigin: 'Honduras',
          roastLevel: 'medium',
          methodData: {'yieldGrams': 36.0},
        ),
      );
      expect(rows.first.spec.name, 'beanOrigin');
      expect(rows.last.spec.name, 'yieldGrams');
    });

    test('shows a false boolean, which is a real answer', () {
      // "I skipped WDT" is information. Hiding it because it is falsey would
      // make a deliberate omission look like an unanswered question.
      final rows = detailRows(
        schema,
        entryWith(methodData: {'puckPrepWdt': false}),
      );
      expect(rows.map((r) => r.spec.name), contains('puckPrepWdt'));
    });

    test('ignores a method field that is not in the schema', () {
      final rows = detailRows(
        schema,
        entryWith(methodData: {'nonsense': 1, 'yieldGrams': 36.0}),
      );
      expect(rows.map((r) => r.spec.name), ['yieldGrams']);
    });
  });

  group('EntryDetailScreen', () {
    Future<void> pump(
      WidgetTester tester,
      BrewEntry entry, {
      Future<String?> Function()? onRescore,
      ValueChanged<int>? onRate,
    }) => tester.pumpWidget(
      MaterialApp(
        home: EntryDetailScreen(
          schema: schema,
          entry: entry,
          onEdit: () {},
          onDelete: () {},
          onRescore: onRescore ?? () async => null,
          onRate: onRate ?? (_) {},
        ),
      ),
    );

    testWidgets('shows the score, its reasons and its provenance', (
      tester,
    ) async {
      await pump(tester, entryWith());
      expect(find.text('93'), findsOneWidget);
      expect(find.text('Ratio 2.0 — on target'), findsOneWidget);
      expect(find.textContaining('r2'), findsOneWidget);
    });

    testWidgets('shows the original text you typed', (tester) async {
      await pump(tester, entryWith(raw: 'a very specific sentence'));
      expect(find.text('a very specific sentence'), findsOneWidget);
    });

    testWidgets('offers a rescore only when scoring failed', (tester) async {
      await pump(tester, entryWith());
      expect(find.text('Score this brew'), findsNothing);

      await pump(tester, entryWith(status: ScoreStatus.failed));
      expect(find.text('Score this brew'), findsOneWidget);
    });

    testWidgets('never offers a rescore for an unscored method', (
      tester,
    ) async {
      // kopiJoss has no rubric. Offering to score it would promise something
      // the Worker will refuse with a 422.
      await pump(
        tester,
        entryWith(method: 'kopiJoss', status: ScoreStatus.notApplicable),
      );
      expect(find.text('Score this brew'), findsNothing);
      expect(find.text('Not scored'), findsOneWidget);
    });

    testWidgets('delete asks first and says it is recoverable', (tester) async {
      await pump(tester, entryWith());
      await tester.tap(find.byIcon(Icons.delete_outline));
      await tester.pumpAndSettle();
      expect(find.textContaining('Deleted entries'), findsOneWidget);
    });

    testWidgets('the retry shows it is working', (tester) async {
      final done = Completer<String?>();
      await pump(
        tester,
        entryWith(status: ScoreStatus.failed, score: null),
        onRescore: () => done.future,
      );
      await tester.tap(find.widgetWithText(OutlinedButton, 'Score this brew'));
      await tester.pump();
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      done.complete(null);
      await tester.pumpAndSettle();
    });

    testWidgets('a retry that fails says so', (tester) async {
      // It used to await up to 45 seconds and then do nothing at all: no
      // spinner, no message, the button simply sitting there.
      await pump(
        tester,
        entryWith(status: ScoreStatus.failed, score: null),
        onRescore: () async => 'The scorer is busy.',
      );
      await tester.tap(find.widgetWithText(OutlinedButton, 'Score this brew'));
      await tester.pumpAndSettle();
      expect(find.text('The scorer is busy.'), findsOneWidget);
    });

    testWidgets('a tapped star fills in straight away', (tester) async {
      // The stars used to read straight off widget.entry, which never
      // changes while the screen is open: the tap saved the rating and the
      // icons stayed empty until you backed out and the list reloaded,
      // which reads as the tap not registering.
      await pump(tester, entryWith(myRating: null));
      await tester.tap(find.byKey(const ValueKey('detail-rating-4')));
      await tester.pump();
      expect(find.byIcon(Icons.star), findsNWidgets(4));
      expect(find.byIcon(Icons.star_border), findsNWidgets(1));
    });

    testWidgets('a tapped star still reports the rating', (tester) async {
      // Showing it locally must not replace saving it.
      int? rated;
      await pump(
        tester,
        entryWith(myRating: null),
        onRate: (stars) => rated = stars,
      );
      await tester.tap(find.byKey(const ValueKey('detail-rating-2')));
      await tester.pump();
      expect(rated, 2);
    });

    testWidgets('changing an existing rating down redraws it', (tester) async {
      // Going 5 -> 2 has to clear three stars, not just fill some.
      await pump(tester, entryWith(myRating: 5));
      await tester.tap(find.byKey(const ValueKey('detail-rating-2')));
      await tester.pump();
      expect(find.byIcon(Icons.star), findsNWidgets(2));
      expect(find.byIcon(Icons.star_border), findsNWidgets(3));
    });
  });
}
