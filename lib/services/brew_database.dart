import 'dart:convert';

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../models/brew_entry.dart';

/// Every brew, live and deleted.
///
/// Core fields are columns because they are what the app filters and sorts
/// by; method-specific fields are a JSON blob because eight methods would
/// otherwise make a sixty-column sparse table.
class BrewDatabase {
  BrewDatabase._(this._db);

  final Database _db;

  static const _createSql = '''
    CREATE TABLE brews (
      id            TEXT PRIMARY KEY,
      brewMethod    TEXT NOT NULL,
      beanOrigin    TEXT,
      roaster       TEXT,
      process       TEXT,
      roastLevel    TEXT,
      roastDate     TEXT,
      doseGrams     REAL,
      grinder       TEXT,
      grindSetting  TEXT,
      grindSize     TEXT,
      waterType     TEXT,
      myRating      INTEGER,
      brewDate      TEXT NOT NULL,
      notes         TEXT,
      rawInputText  TEXT NOT NULL,
      methodData    TEXT NOT NULL,
      overallScore  INTEGER,
      scoreReasons  TEXT,
      scoreStatus   TEXT NOT NULL,
      scoreRubric   TEXT,
      scoreModel    TEXT,
      scoredAt      TEXT,
      createdAt     TEXT NOT NULL,
      updatedAt     TEXT NOT NULL,
      deletedAt     TEXT
    )
  ''';

  /// Columns added between v1 and v2. Listed rather than derived so the
  /// upgrade path is readable next to the create statement.
  static const _v2Columns = [
    'roaster TEXT',
    'process TEXT',
    'roastDate TEXT',
    'grinder TEXT',
    'grindSetting TEXT',
    'waterType TEXT',
    'myRating INTEGER',
  ];

  /// Methods renamed by the taxonomy, and the variant field that replaces the
  /// old name. `v60` stopped being a method and became a `coneDripper` whose
  /// `brewer` is `v60`.
  static const _renamed = {'v60': ('coneDripper', 'brewer', 'v60')};

  static Future<BrewDatabase> open({String? path}) async {
    final dbPath = path ?? p.join(await getDatabasesPath(), 'kopi_kompas.db');
    final db = await openDatabase(
      dbPath,
      version: 2,
      onCreate: (db, _) async {
        await db.execute(_createSql);
        await db.execute('CREATE INDEX idx_brewDate ON brews(brewDate)');
        await db.execute('CREATE INDEX idx_deletedAt ON brews(deletedAt)');
      },
      onUpgrade: (db, from, to) async {
        if (from < 2) await _upgradeToV2(db);
      },
    );
    return BrewDatabase._(db);
  }

  /// Adds the v2 columns and rewrites renamed methods.
  ///
  /// The rewrite runs in Dart rather than with SQLite's `json_set`, because
  /// the JSON1 extension is not guaranteed on every Android build — exactly
  /// the kind of thing that passes on a test runner and fails on a phone.
  static Future<void> _upgradeToV2(Database db) async {
    for (final column in _v2Columns) {
      await db.execute('ALTER TABLE brews ADD COLUMN $column');
    }

    for (final entry in _renamed.entries) {
      final (newMethod, field, value) = entry.value;
      final rows = await db.query(
        'brews',
        columns: ['id', 'methodData'],
        where: 'brewMethod = ?',
        whereArgs: [entry.key],
      );
      for (final row in rows) {
        final data =
            jsonDecode(row['methodData'] as String? ?? '{}')
                as Map<String, dynamic>;
        data[field] = value;
        await db.update(
          'brews',
          {'brewMethod': newMethod, 'methodData': jsonEncode(data)},
          where: 'id = ?',
          whereArgs: [row['id']],
        );
      }
    }
  }

  Future<void> insert(BrewEntry e) async => _db.insert('brews', e.toRow());

  Future<void> update(BrewEntry e) async =>
      _db.update('brews', e.toRow(), where: 'id = ?', whereArgs: [e.id]);

  Future<List<BrewEntry>> liveEntries() async {
    final rows = await _db.query(
      'brews',
      where: 'deletedAt IS NULL',
      orderBy: 'brewDate DESC',
    );
    return rows.map(BrewEntry.fromRow).toList();
  }

  Future<BrewEntry?> byId(String id) async {
    final rows = await _db.query('brews', where: 'id = ?', whereArgs: [id]);
    return rows.isEmpty ? null : BrewEntry.fromRow(rows.first);
  }

  /// Deleting is soft: the row survives with [deletedAt] set, leaves the live
  /// list, and stops counting for the reminder. Phase 3's Deleted entries
  /// page reads these back.
  Future<void> softDelete(String id, DateTime when) async => _db.update(
    'brews',
    {'deletedAt': when.toIso8601String()},
    where: 'id = ?',
    whereArgs: [id],
  );

  /// Whether a live brew exists on [day]'s local calendar date.
  ///
  /// Compared on the local date string rather than an instant range, because
  /// "did I log a coffee today" is a question about the wall clock in front of
  /// the brewer. Stored dates keep their offset, so the first ten characters
  /// are already the local date.
  Future<bool> hasBrewOn(DateTime day) async {
    final key = day.toIso8601String().substring(0, 10);
    final rows = await _db.query(
      'brews',
      columns: ['id'],
      where: 'deletedAt IS NULL AND substr(brewDate, 1, 10) = ?',
      whereArgs: [key],
      limit: 1,
    );
    return rows.isNotEmpty;
  }

  Future<void> close() => _db.close();
}
