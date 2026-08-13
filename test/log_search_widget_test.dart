import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kopi_kompas/data/brew_schema.dart';
import 'package:kopi_kompas/models/brew_entry.dart';
import 'package:kopi_kompas/screens/full_log_screen.dart';
import 'package:kopi_kompas/services/brew_database.dart';
import 'package:kopi_kompas/strings.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

late BrewSchema schema;

BrewEntry brew(String id, String method, {String? origin, int? rating}) =>
    BrewEntry(
      id: id,
      brewMethod: method,
      beanOrigin: origin,
      myRating: rating,
      brewDate: DateTime(2026, 8, 12, 7),
      rawInputText: 'raw $id',
      methodData: const {},
      scoreStatus: ScoreStatus.scored,
      overallScore: 80,
      createdAt: DateTime(2026, 8, 12, 7),
      updatedAt: DateTime(2026, 8, 12, 7),
    );

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    schema = BrewSchema.parse(
      File('schema/brew_schema.json').readAsStringSync(),
    );
  });

  late BrewDatabase db;
  setUp(() async {
    db = await BrewDatabase.open(path: inMemoryDatabasePath);
    await db.insert(brew('a', 'espresso', origin: 'Gayo', rating: 5));
    await db.insert(brew('b', 'kopiTubruk', origin: 'Toraja', rating: 2));
    await db.insert(brew('c', 'kopiTubruk', origin: 'Gayo'));
  });
  tearDown(() async => db.close());

  /// sqflite's ffi backend does real I/O, which the test binding's fake clock
  /// will not advance through — `pumpAndSettle` alone spins on the loading
  /// indicator forever. `runAsync` lets the query actually finish first.
  Future<void> pump(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: FullLogScreen(db: db, schema: schema),
      ),
    );
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('typing narrows the list', (tester) async {
    await pump(tester);
    expect(find.textContaining('Kopi tubruk'), findsNWidgets(2));

    await tester.enterText(find.byType(TextField), 'gayo');
    await tester.pumpAndSettle();

    expect(find.textContaining('Kopi tubruk'), findsOneWidget);
    expect(find.textContaining('Espresso'), findsOneWidget);
  });

  testWidgets('a search that matches nothing says so', (tester) async {
    await pump(tester);
    await tester.enterText(find.byType(TextField), 'zzzz');
    await tester.pumpAndSettle();
    expect(find.text(AppStrings.noMatches), findsOneWidget);
  });

  testWidgets('the count shows how much is hidden', (tester) async {
    // A filtered list that looks short must never read as a list that lost
    // entries, which is the whole reason this number is on screen.
    await pump(tester);
    expect(find.text(AppStrings.matchCount(1, 3)), findsNothing);

    await tester.enterText(find.byType(TextField), 'toraja');
    await tester.pumpAndSettle();
    expect(find.text(AppStrings.matchCount(1, 3)), findsOneWidget);
  });

  testWidgets('the filter survives opening something and coming back', (
    tester,
  ) async {
    await pump(tester);
    await tester.enterText(find.byType(TextField), 'toraja');
    await tester.pumpAndSettle();
    expect(find.textContaining('Kopi tubruk'), findsOneWidget);

    // Any pushed route will do: what is under test is that the filter lives in
    // the screen's State, which outlives a route on top of it, rather than in
    // the bar, which does not survive being rebuilt.
    final ctx = tester.element(find.byType(FullLogScreen));
    unawaited(
      Navigator.of(ctx).push(
        MaterialPageRoute<void>(
          builder: (_) => const Scaffold(body: Text('detail')),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('detail'), findsOneWidget);

    Navigator.of(tester.element(find.text('detail'))).pop();
    await tester.pumpAndSettle();

    expect(find.textContaining('Kopi tubruk'), findsOneWidget);
    expect(find.text(AppStrings.matchCount(1, 3)), findsOneWidget);
  });

  testWidgets('a chip never draws a cross it cannot honour', (tester) async {
    // A chip has one tap target, so a ✕ inside it opened the picker rather
    // than clearing anything. Clearing belongs to the button at the end of
    // the row; the chip only ever offers to open its own list.
    await pump(tester);
    await tester.tap(find.text(AppStrings.filterRating));
    await tester.pumpAndSettle();
    await tester.tap(find.text(AppStrings.atLeastStars(2)));
    await tester.pumpAndSettle();

    expect(find.text(AppStrings.atLeastStars(2)), findsOneWidget);
    expect(find.byIcon(Icons.close), findsNothing);
    expect(find.byIcon(Icons.arrow_drop_down), findsNWidgets(2));
  });

  testWidgets('clearing brings everything back', (tester) async {
    await pump(tester);
    await tester.enterText(find.byType(TextField), 'toraja');
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip(AppStrings.filterClear));
    await tester.pumpAndSettle();

    expect(find.textContaining('Kopi tubruk'), findsNWidgets(2));
    expect(find.text(AppStrings.matchCount(1, 3)), findsNothing);
  });
}

/// The push is deliberately not awaited — it completes only when the route
/// pops. `unawaited` says that on purpose rather than leaving a bare future.
void unawaited(Future<void> _) {}
