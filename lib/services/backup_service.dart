import 'dart:convert';

import '../models/brew_entry.dart';
import 'brew_database.dart';

/// The slice of Firestore this needs.
///
/// Depending on four methods rather than the SDK is what lets every rule
/// below be tested without a network or an emulator.
abstract class RemoteStore {
  Future<void> put(String uid, String id, Map<String, Object?> data);
  Future<List<Map<String, Object?>>> all(String uid);
  Future<void> delete(String uid, String id);
}

enum BackupOutcome { ok, offline, notSignedIn, failed }

class BackupResult {
  const BackupResult(this.outcome, {this.count = 0, this.detail});
  final BackupOutcome outcome;
  final int count;
  final String? detail;

  bool get ok => outcome == BackupOutcome.ok;
}

/// Mirrors the log to Firestore so a lost or reset phone is not lost data.
///
/// **SQLite stays the source of truth.** This is a backup, never the live
/// store: a failure here is a backup that did not happen, never an entry that
/// did not save. Nothing in the logging flow waits on it.
class BackupService {
  BackupService({
    required this.db,
    required this.remote,
    required this.uid,
    this.now = DateTime.now,
  });

  final BrewDatabase db;
  final RemoteStore remote;

  /// Null when signed out, which is a supported state and not an error.
  final String? Function() uid;

  final DateTime Function() now;

  DateTime? lastSuccess;

  /// Mirrors one entry. Keyed by the entry's own uuid, which makes pushing
  /// the same brew twice a no-op rather than a duplicate.
  Future<BackupResult> push(BrewEntry entry) async {
    final user = uid();
    if (user == null) return const BackupResult(BackupOutcome.notSignedIn);
    try {
      await remote.put(user, entry.id, _toRemote(entry));
      lastSuccess = now();
      return const BackupResult(BackupOutcome.ok, count: 1);
    } catch (e) {
      // The local entry is untouched. A backup failure is not data loss.
      return BackupResult(BackupOutcome.failed, detail: '$e');
    }
  }

  /// Mirrors everything, including soft-deleted entries.
  ///
  /// Deleted rows are pushed *as deleted* rather than skipped: dropping them
  /// would mean a restore silently emptied the Deleted entries page, turning
  /// a recoverable delete into a permanent one.
  Future<BackupResult> pushAll() async {
    final user = uid();
    if (user == null) return const BackupResult(BackupOutcome.notSignedIn);

    final entries = [...await db.liveEntries(), ...await db.deletedEntries()];
    var done = 0;
    for (final e in entries) {
      try {
        await remote.put(user, e.id, _toRemote(e));
        done++;
      } catch (err) {
        return BackupResult(BackupOutcome.failed, count: done, detail: '$err');
      }
    }
    lastSuccess = now();
    return BackupResult(BackupOutcome.ok, count: done);
  }

  /// Writes the remote log into the local database.
  ///
  /// A local entry that is newer wins. Restoring should never undo an edit
  /// you made on this phone while it was offline.
  Future<BackupResult> restore() async {
    final user = uid();
    if (user == null) return const BackupResult(BackupOutcome.notSignedIn);

    List<Map<String, Object?>> rows;
    try {
      rows = await remote.all(user);
    } catch (e) {
      return BackupResult(BackupOutcome.failed, detail: '$e');
    }

    var written = 0;
    for (final row in rows) {
      final incoming = BrewEntry.fromRow(_fromRemote(row));
      final existing = await db.byId(incoming.id);
      if (existing == null) {
        await db.insert(incoming);
        written++;
      } else if (incoming.updatedAt.isAfter(existing.updatedAt)) {
        await db.update(incoming);
        written++;
      }
    }
    return BackupResult(BackupOutcome.ok, count: written);
  }

  /// Firestore holds the same shape as the SQLite row, so the mapping stays
  /// in one place and a schema change cannot drift between them.
  static Map<String, Object?> _toRemote(BrewEntry e) => e.toRow();

  static Map<String, Object?> _fromRemote(Map<String, Object?> row) {
    // Firestore returns numbers as int or double regardless of what went in,
    // and nested maps as maps rather than the JSON strings a row expects.
    final out = Map<String, Object?>.of(row);
    for (final key in ['methodData', 'scoreReasons']) {
      final v = out[key];
      if (v != null && v is! String) out[key] = jsonEncode(v);
    }
    return out;
  }
}
