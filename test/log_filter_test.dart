import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kopi_kompas/data/brew_schema.dart';
import 'package:kopi_kompas/models/brew_entry.dart';
import 'package:kopi_kompas/services/log_filter.dart';
import 'package:kopi_kompas/strings.dart';

late BrewSchema schema;

BrewEntry brew({
  String id = 'a',
  String method = 'espresso',
  String? origin,
  String? roaster,
  String? notes,
  String? water,
  int? rating,
  String raw = '',
  Map<String, Object?> methodData = const {},
}) => BrewEntry(
  id: id,
  brewMethod: method,
  beanOrigin: origin,
  roaster: roaster,
  notes: notes,
  waterType: water,
  myRating: rating,
  brewDate: DateTime(2026, 8, 12, 7),
  rawInputText: raw,
  methodData: methodData,
  scoreStatus: ScoreStatus.scored,
  createdAt: DateTime(2026, 8, 12),
  updatedAt: DateTime(2026, 8, 12),
);

void main() {
  setUpAll(() {
    schema = BrewSchema.parse(
      File('schema/brew_schema.json').readAsStringSync(),
    );
  });

  tearDown(() => AppStrings.language = 'en');

  test('an empty filter shows everything', () {
    const f = LogFilter();
    expect(f.isActive, isFalse);
    expect(f.apply([brew(), brew(id: 'b')], schema), hasLength(2));
  });

  test('filtering by method keeps only that method', () {
    final entries = [
      brew(id: 'a', method: 'espresso'),
      brew(id: 'b', method: 'kopiTubruk'),
      brew(id: 'c', method: 'kopiTubruk'),
    ];
    const f = LogFilter(methodId: 'kopiTubruk');
    expect(f.apply(entries, schema).map((e) => e.id), ['b', 'c']);
  });

  test('search finds a method by name without an exact id', () {
    // The point of the feature: you type what the coffee is called, not the
    // camelCase key it happens to be stored under.
    final entries = [
      brew(id: 'a', method: 'espresso'),
      brew(id: 'b', method: 'kopiTubruk'),
    ];
    const f = LogFilter(query: 'tubruk');
    expect(f.apply(entries, schema).map((e) => e.id), ['b']);
  });

  test('search expands stored ids to their labels', () {
    // The database says `kalitaWave`; nobody searches for that.
    final entries = [
      brew(
        id: 'a',
        method: 'flatBottomDripper',
        methodData: {'brewer': 'kalitaWave'},
      ),
      brew(id: 'b', method: 'coneDripper', methodData: {'brewer': 'v60'}),
    ];
    expect(
      const LogFilter(query: 'kalita wave').apply(entries, schema).single.id,
      'a',
    );
  });

  test('search reaches the words you originally typed', () {
    // Often the only place a detail survives — no field holds "gula aren".
    final entries = [
      brew(id: 'a', raw: 'kopi tubruk pakai gula aren'),
      brew(id: 'b', raw: 'espresso pagi'),
    ];
    expect(
      const LogFilter(query: 'gula aren').apply(entries, schema).single.id,
      'a',
    );
  });

  test('two words narrow rather than widen', () {
    final entries = [
      brew(id: 'a', origin: 'Gayo', method: 'kopiTubruk'),
      brew(id: 'b', origin: 'Gayo', method: 'espresso'),
      brew(id: 'c', origin: 'Toraja', method: 'kopiTubruk'),
    ];
    expect(
      const LogFilter(query: 'gayo tubruk').apply(entries, schema).single.id,
      'a',
    );
  });

  test('search ignores case', () {
    final entries = [brew(id: 'a', roaster: 'Tanamera')];
    expect(
      const LogFilter(query: 'TANAMERA').apply(entries, schema),
      hasLength(1),
    );
  });

  test('search follows the selected language', () {
    // A brewer reading Indonesian searches in Indonesian. The stored id never
    // changes, so only the label lookup can make this work.
    final entries = [brew(id: 'a', water: 'tap')];
    AppStrings.language = 'id';
    expect(
      const LogFilter(query: 'keran').apply(entries, schema),
      hasLength(1),
    );
    AppStrings.language = 'en';
    expect(const LogFilter(query: 'keran').apply(entries, schema), isEmpty);
  });

  test('a rating filter excludes unrated brews', () {
    // Unrated is not zero. Letting a null slide through as "0 stars" would be
    // the same bug that made myRating nullable in the first place.
    final entries = [
      brew(id: 'a', rating: 5),
      brew(id: 'b', rating: 3),
      brew(id: 'c'),
    ];
    expect(
      const LogFilter(minRating: 4).apply(entries, schema).map((e) => e.id),
      ['a'],
    );
  });

  test('filters combine', () {
    final entries = [
      brew(id: 'a', method: 'espresso', origin: 'Gayo', rating: 5),
      brew(id: 'b', method: 'espresso', origin: 'Gayo', rating: 2),
      brew(id: 'c', method: 'kopiTubruk', origin: 'Gayo', rating: 5),
    ];
    const f = LogFilter(query: 'gayo', methodId: 'espresso', minRating: 4);
    expect(f.apply(entries, schema).single.id, 'a');
  });

  test('clearing one part leaves the others alone', () {
    const f = LogFilter(query: 'gayo', methodId: 'espresso', minRating: 4);
    final cleared = f.copyWith(clearMethod: true);
    expect(cleared.methodId, isNull);
    expect(cleared.query, 'gayo');
    expect(cleared.minRating, 4);
  });

  test('an entry whose method the schema dropped is still searchable', () {
    // Old rows outlive schema edits. Searching must not throw on one.
    final entries = [
      brew(id: 'a', method: 'someRetiredMethod', origin: 'Gayo'),
    ];
    expect(const LogFilter(query: 'gayo').apply(entries, schema), hasLength(1));
  });
}
