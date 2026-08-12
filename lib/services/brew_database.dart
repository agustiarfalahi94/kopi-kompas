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
      roastLevel    TEXT,
      doseGrams     REAL,
      grindSize     TEXT,
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

  static Future<BrewDatabase> open({String? path}) async {
    final dbPath = path ?? p.join(await getDatabasesPath(), 'kopi_kompas.db');
    final db = await openDatabase(
      dbPath,
      version: 1,
      onCreate: (db, _) async {
        await db.execute(_createSql);
        await db.execute('CREATE INDEX idx_brewDate ON brews(brewDate)');
        await db.execute('CREATE INDEX idx_deletedAt ON brews(deletedAt)');
      },
    );
    return BrewDatabase._(db);
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
