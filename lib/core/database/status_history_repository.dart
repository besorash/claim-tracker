/// Status change + history persistence (spec §9).
///
/// [changeStatus] updates the claim's current status and inserts the history
/// row inside a single transaction — if either write fails, both roll back.
library;

import 'package:sqflite/sqflite.dart' as sqf;

import '../models/claim_status.dart';
import '../models/status_history_entry.dart';
import 'app_database.dart';

class StatusHistoryRepository {
  const StatusHistoryRepository(this._db);

  final AppDatabase _db;

  /// Atomically applies a status change and records it in history (spec §9).
  /// Returns the created history entry.
  Future<StatusHistoryEntry> changeStatus({
    required int claimId,
    required String newStatusKey,
    DateTime? changedAtUtc,
    String? note,
  }) async {
    ClaimStatus.byKey(newStatusKey); // validate early

    final DateTime now = (changedAtUtc ?? DateTime.now()).toUtc();

    return _db.rawDb.transaction((sqf.Transaction txn) async {
      final List<Map<String, Object?>> rows = await txn.query(
        'claims',
        columns: const ['status_key'],
        where: 'id = ?',
        whereArgs: [claimId],
        limit: 1,
      );
      if (rows.isEmpty) {
        throw StateError('Claim $claimId does not exist');
      }
      final String previousKey = rows.first['status_key']! as String;

      await txn.update(
        'claims',
        <String, Object?>{
          'status_key': newStatusKey,
          'last_status_update_utc_ms': now.millisecondsSinceEpoch,
          'updated_at_utc_ms': now.millisecondsSinceEpoch,
        },
        where: 'id = ?',
        whereArgs: [claimId],
      );

      final int historyId = await txn.insert(
        'status_history',
        <String, Object?>{
          'claim_id': claimId,
          'previous_status_key': previousKey,
          'new_status_key': newStatusKey,
          'changed_at_utc_ms': now.millisecondsSinceEpoch,
          'note': note,
        },
      );

      return StatusHistoryEntry(
        id: historyId,
        claimId: claimId,
        previousStatusKey: previousKey,
        newStatusKey: newStatusKey,
        changedAtUtcMs: now,
        note: note,
      );
    });
  }

  /// Chronological history for a claim, newest first (spec §11).
  Future<List<StatusHistoryEntry>> listForClaim(int claimId) =>
      _db.historyForClaim(claimId);
}
