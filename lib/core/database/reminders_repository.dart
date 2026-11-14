/// Reminder persistence (spec §10). Scheduling/cancelling of the actual
/// Android notifications is done by `NotificationService` using the stable
/// [Reminder.notificationId].
library;

import 'package:sqflite/sqflite.dart' as sqf;

import '../models/reminder.dart';
import 'app_database.dart';

class RemindersRepository {
  const RemindersRepository(this._db);

  final AppDatabase _db;

  /// Inserts a new reminder row. Never inserts an explicit primary key —
  /// callers pass `id == 0` as "unsaved" and the AUTOINCREMENT column must
  /// assign it (same contract as [ClaimsRepository.create]). Inserting the
  /// literal 0 for every new row would violate the UNIQUE id constraint on
  /// the second reminder of any session — the root cause of BUG A.
  Future<int> create(Reminder reminder) {
    final Map<String, Object?> row = Map.of(reminder.toRow())..remove('id');
    return _db.rawDb.insert('reminders', row);
  }

  /// Replaces the claim's reminders with a single new one (spec §10:
  /// reschedule = cancel old + schedule new, no duplicates). Returns the
  /// stored row.
  Future<Reminder> replaceForClaim({
    required int claimId,
    required Reminder next,
  }) async {
    return _db.rawDb.transaction((sqf.Transaction txn) async {
      await txn.delete(
        'reminders',
        where: 'claim_id = ?',
        whereArgs: [claimId],
      );
      // BUG A fix: strip the caller's placeholder `id` (0) so SQLite assigns
      // a fresh AUTOINCREMENT value — inserting an explicit 0 for every new
      // reminder violated the UNIQUE id constraint from the second claim on.
      final Map<String, Object?> row = Map.of(next.toRow())..remove('id');
      final int id = await txn.insert('reminders', row);
      return Reminder(
        id: id,
        claimId: next.claimId,
        fireAtUtcMs: next.fireAtUtcMs,
        notificationId: next.notificationId,
        repeatIntervalHours: next.repeatIntervalHours,
        enabled: next.enabled,
        createdAtUtcMs: next.createdAtUtcMs,
        updatedAtUtcMs: next.updatedAtUtcMs,
      );
    });
  }

  Future<void> disableAllForClaim(int claimId) => _db.rawDb.update(
    'reminders',
    <String, Object?>{'enabled': 0},
    where: 'claim_id = ?',
    whereArgs: [claimId],
  );

  /// Removes all reminders for a claim — used when the claim is closed or
  /// deleted (spec §10). Returns removed rows so the caller can cancel their
  /// scheduled notifications.
  Future<List<Reminder>> removeAllForClaim(int claimId) async {
    final List<Map<String, Object?>> rows = await _db.rawDb.query(
      'reminders',
      where: 'claim_id = ?',
      whereArgs: [claimId],
    );
    if (rows.isEmpty) return const <Reminder>[];
    final List<Reminder> removed = rows
        .map(Reminder.fromRow)
        .toList(growable: false);
    await _db.rawDb.delete(
      'reminders',
      where: 'claim_id = ?',
      whereArgs: [claimId],
    );
    return removed;
  }

  Future<List<Reminder>> enabledAfter(DateTime nowUtc) async {
    final List<Map<String, Object?>> rows = await _db.rawDb.query(
      'reminders',
      where: 'enabled = 1 AND fire_at_utc_ms >= ?',
      whereArgs: [nowUtc.millisecondsSinceEpoch],
      orderBy: 'fire_at_utc_ms ASC',
    );
    return rows.map(Reminder.fromRow).toList();
  }

  Future<List<Reminder>> allEnabled() async {
    final List<Map<String, Object?>> rows = await _db.rawDb.query(
      'reminders',
      where: 'enabled = 1',
      orderBy: 'fire_at_utc_ms ASC',
    );
    return rows.map(Reminder.fromRow).toList();
  }

  /// The claim's most recent reminder row, enabled or not — null when the
  /// claim has none. Used to look up the stable [Reminder.notificationId]
  /// before cancelling/disabling (spec §10).
  Future<Reminder?> latestForClaim(int claimId) async {
    final List<Map<String, Object?>> rows = await _db.rawDb.query(
      'reminders',
      where: 'claim_id = ?',
      whereArgs: [claimId],
      orderBy: 'id DESC',
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return Reminder.fromRow(rows.first);
  }

  /// Marks a one-time reminder as consumed after it fires (spec §10: avoid
  /// duplicate notifications on reboot/reconcile).
  Future<void> markConsumed(int id) => _db.rawDb.update(
    'reminders',
    <String, Object?>{'enabled': 0},
    where: 'id = ?',
    whereArgs: [id],
  );
}
