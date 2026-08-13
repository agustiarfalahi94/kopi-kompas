import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kopi_kompas/data/brew_schema.dart';
import 'package:kopi_kompas/services/brew_database.dart';
import 'package:kopi_kompas/services/kopi_client.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:kopi_kompas/models/brew_entry.dart';
import 'package:flutter/material.dart';
import 'package:kopi_kompas/screens/edit_entry_screen.dart';
import 'package:kopi_kompas/strings.dart';

late BrewSchema schema;
late BrewDatabase db;
late KopiClient client;

BrewEntry original({
  String method = 'espresso',
  ScoreStatus status = ScoreStatus.scored,
}) => BrewEntry(
  id: 'keep-me',
  brewMethod: method,
  beanOrigin: 'Honduras',
  doseGrams: 18,
  brewDate: DateTime(2026, 8, 12, 7),
  rawInputText: 'the sentence I first typed',
  methodData: const {'yieldGrams': 36.0, 'puckPrepWdt': true},
  scoreStatus: status,
  overallScore: status == ScoreStatus.scored ? 93 : null,
  scoreReasons: const ['Ratio on target'],
  scoreRubric: status == ScoreStatus.scored ? 'r2' : null,
  scoreModel: status == ScoreStatus.scored ? 'gemini-3.5-flash' : null,
  myRating: 4,
  createdAt: DateTime(2026, 8, 12, 7),
  updatedAt: DateTime(2026, 8, 12, 7),
);

void main() {
  setUpAll(() {
    schema = BrewSchema.parse(
      File('schema/brew_schema.json').readAsStringSync(),
    );
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    db = await BrewDatabase.open(path: inMemoryDatabasePath);
    // Points nowhere on purpose: these tests never save, and a widget test
    // must not reach the network.
    client = KopiClient(endpoint: 'http://127.0.0.1:1', installId: 't');
  });
  tearDown(() => db.close());

  test('keeps the identity of the entry', () {
    final e = applyEdits(
      original(),
      {'doseGrams': 19.0},
      schema,
      DateTime(2026, 8, 13, 9),
    );
    expect(e.id, 'keep-me');
    expect(e.createdAt, DateTime(2026, 8, 12, 7));
    expect(e.brewDate, DateTime(2026, 8, 12, 7));
    // The original words are the record of what was said. Editing the
    // numbers must never rewrite them.
    expect(e.rawInputText, 'the sentence I first typed');
  });

  test('applies the change and bumps updatedAt', () {
    final e = applyEdits(
      original(),
      {'doseGrams': 19.0},
      schema,
      DateTime(2026, 8, 13, 9),
    );
    expect(e.doseGrams, 19);
    expect(e.updatedAt, DateTime(2026, 8, 13, 9));
  });

  test('keeps your rating', () {
    final e = applyEdits(original(), {'doseGrams': 19.0}, schema, DateTime(0));
    expect(e.myRating, 4);
  });

  test('routes an answer to core or methodData by schema', () {
    final e = applyEdits(
      original(),
      {'roaster': 'Common Grounds', 'yieldGrams': 40.0},
      schema,
      DateTime(0),
    );
    expect(e.roaster, 'Common Grounds');
    expect(e.methodData['yieldGrams'], 40.0);
    expect(e.methodData.containsKey('roaster'), isFalse);
  });

  test('a field cleared in the form is removed, not left stale', () {
    // The form reports a cleared row as absent. An edit that drops the
    // machine has to actually drop it, or the entry keeps a value the user
    // deliberately erased.
    final e = applyEdits(original(), {'doseGrams': 18.0}, schema, DateTime(0));
    expect(e.methodData.containsKey('yieldGrams'), isFalse);
  });

  test('a scored method goes back to pending, ready to re-score', () {
    final e = applyEdits(original(), {'doseGrams': 19.0}, schema, DateTime(0));
    expect(e.scoreStatus, ScoreStatus.pending);
  });

  test('an unscored method stays notApplicable', () {
    final e = applyEdits(
      original(method: 'kopiJoss', status: ScoreStatus.notApplicable),
      {'doseGrams': 19.0},
      schema,
      DateTime(0),
    );
    expect(e.scoreStatus, ScoreStatus.notApplicable);
  });

  test('the old score survives until a new one replaces it', () {
    // A network blip while re-scoring must not destroy a number you already
    // had. This is the opposite of the first save, where there was nothing to
    // lose.
    final e = applyEdits(original(), {'doseGrams': 19.0}, schema, DateTime(0));
    expect(e.overallScore, 93);
    expect(e.scoreRubric, 'r2');
  });

  testWidgets('Save is disabled until something actually changes', (
    tester,
  ) async {
    // Opening an entry out of curiosity and backing out must not re-score it.
    // A pointless re-score costs a Gemini request and can move the number by
    // a point or two on a brew nobody edited.
    await tester.pumpWidget(
      MaterialApp(
        home: EditEntryScreen(
          db: db,
          schema: schema,
          client: client,
          entry: original(),
        ),
      ),
    );
    await tester.pump();

    final button = tester.widget<FilledButton>(find.byType(FilledButton));
    expect(button.onPressed, isNull, reason: 'Save should start disabled');
    expect(find.text(AppStrings.noChanges), findsOneWidget);
  });

  testWidgets('Save enables once a field is edited', (tester) async {
    // Tall surface so the dose row is on screen; the form is long by design.
    tester.view.physicalSize = const Size(1200, 6000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: EditEntryScreen(
          db: db,
          schema: schema,
          client: client,
          entry: original(),
        ),
      ),
    );
    await tester.pump();

    await tester.enterText(
      find
          .ancestor(of: find.text('Dose (g)'), matching: find.byType(TextField))
          .first,
      '19',
    );
    await tester.pump();

    final button = tester.widget<FilledButton>(find.byType(FilledButton));
    expect(button.onPressed, isNotNull);
    expect(find.text(AppStrings.saveButton), findsOneWidget);
  });
}
