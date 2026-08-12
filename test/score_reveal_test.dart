import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kopi_kompas/data/brew_schema.dart';
import 'package:kopi_kompas/models/brew_entry.dart';
import 'package:kopi_kompas/widgets/score_reveal.dart';

late BrewSchema schema;

BrewEntry entryWith({
  String method = 'espresso',
  int? score,
  ScoreStatus status = ScoreStatus.scored,
  int? myRating,
}) => BrewEntry(
  id: 'a',
  brewMethod: method,
  brewDate: DateTime(2026, 8, 12, 7),
  rawInputText: 'x',
  methodData: const {},
  scoreStatus: status,
  overallScore: score,
  scoreReasons: const ['Ratio on target'],
  myRating: myRating,
  createdAt: DateTime(2026, 8, 12, 7),
  updatedAt: DateTime(2026, 8, 12, 7),
);

void main() {
  setUpAll(() {
    schema = BrewSchema.parse(
      File('schema/brew_schema.json').readAsStringSync(),
    );
  });

  Future<int?> pump(WidgetTester tester, BrewEntry entry) async {
    int? rated;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ScoreReveal(
            entry: entry,
            method: schema.method(entry.brewMethod),
            onRated: (v) => rated = v,
            onDone: () {},
          ),
        ),
      ),
    );
    await tester.pump();
    return rated;
  }

  testWidgets('shows five rating stars under the score', (tester) async {
    await pump(tester, entryWith(score: 93));
    expect(find.byIcon(Icons.star_border), findsNWidgets(5));
  });

  testWidgets('tapping the third star reports 3', (tester) async {
    int? rated;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ScoreReveal(
            entry: entryWith(score: 93),
            method: schema.method('espresso'),
            onRated: (v) => rated = v,
            onDone: () {},
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('rating-3')));
    await tester.pump();
    expect(rated, 3);
  });

  testWidgets('leaving it unrated never reports a value', (tester) async {
    // Not rating is a real state. Reporting 0 would make "unrated" read as
    // "hated it" in every average the app ever computes.
    expect(await pump(tester, entryWith(score: 93)), isNull);
  });

  testWidgets('an existing rating renders as filled stars', (tester) async {
    await pump(tester, entryWith(score: 93, myRating: 4));
    expect(find.byIcon(Icons.star), findsNWidgets(4));
    expect(find.byIcon(Icons.star_border), findsNWidgets(1));
  });

  testWidgets('the rating appears for an unscored method too', (tester) async {
    // Kopi joss gets no number, but what the brewer thought still matters —
    // arguably more, since nothing else judges it.
    await pump(
      tester,
      entryWith(method: 'kopiJoss', status: ScoreStatus.notApplicable),
    );
    expect(find.byIcon(Icons.star_border), findsNWidgets(5));
    expect(find.text('Not scored'), findsOneWidget);
  });

  testWidgets('the rating appears when scoring failed', (tester) async {
    await pump(tester, entryWith(status: ScoreStatus.failed));
    expect(find.byIcon(Icons.star_border), findsNWidgets(5));
  });
}
