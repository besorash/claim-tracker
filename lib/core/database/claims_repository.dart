/// Claims CRUD, search, filters and sorting (spec §5–§7).
library;

import 'package:sqflite/sqflite.dart' as sqf;

import '../models/attachment.dart';
import '../models/claim.dart';
import '../models/claim_status.dart';
import 'app_database.dart';

class ClaimsRepository {
  const ClaimsRepository(this._db);

  final AppDatabase _db;

  Future<int> create(Claim claim) async {
    return _db.rawDb.transaction((sqf.Transaction txn) async {
      // Never insert an explicit primary key: new claims get the next
      // auto-increment id (spec §13). Callers pass id == 0 as "unsaved".
      final Map<String, Object?> row = Map.of(claim.toRow())..remove('id');
      final int id = await txn.insert('claims', row);
      // Initial history entry so the timeline always starts at creation
      // (spec §9: every status change is recorded; creation is the first one).
      await txn.insert('status_history', <String, Object?>{
        'claim_id': id,
        'previous_status_key': '',
        'new_status_key': claim.statusKey,
        'changed_at_utc_ms': claim.lastStatusUpdateUtcMs.millisecondsSinceEpoch,
        'note': null,
      });
      return id;
    });
  }

  Future<void> update(Claim claim) => _db.rawDb.update(
    'claims',
    claim.toRow(),
    where: 'id = ?',
    whereArgs: [claim.id],
  );

  /// Deletes the claim and (via FK cascade) its history, reminders and
  /// attachment rows. Returns the attachments that were removed so the caller
  /// can delete their physical files safely (spec §12–§13).
  Future<List<Attachment>> delete(int id) async {
    final List<Map<String, Object?>> rows = await _db.rawDb.query(
      'attachments',
      where: 'claim_id = ?',
      whereArgs: [id],
    );
    final List<Attachment> removed = rows
        .map(Attachment.fromRow)
        .toList(growable: false);
    await _db.rawDb.delete('claims', where: 'id = ?', whereArgs: [id]);
    return removed;
  }

  // ---------------------------------------------------------------------------
  // Search & filters (spec §6)
  // ---------------------------------------------------------------------------

  /// Forgiving search across the supported fields (spec §6). The query is
  /// trimmed and matched case-insensitively with LIKE.
  Future<List<Claim>> search(String rawQuery) async {
    final String q = rawQuery.trim();
    if (q.isEmpty) return all();

    // SQLite LIKE has no default escape character; for a personal app the
    // forgiving behavior (spec §6) is trimming, which we already do.
    final String like = '%$q%';
    const List<String> fields = [
      'vehicle_plate',
      'claim_number',
      'customer_name',
      'customer_mobile',
      'accident_number',
      'customer_insurance_company',
      'insurer_reference_number',
    ];
    final String where = fields.map((f) => '$f LIKE ?').join(' OR ');

    final List<Map<String, Object?>> rows = await _db.rawDb.query(
      'claims',
      where: where,
      whereArgs: List<Object>.filled(fields.length, like),
    );
    return sortDefault(rows.map(Claim.fromRow).toList());
  }

  Future<List<Claim>> all() async {
    final List<Map<String, Object?>> rows = await _db.rawDb.query('claims');
    return sortDefault(rows.map(Claim.fromRow).toList());
  }

  /// Claims whose status is not a closed one (Closed, Approved, Rejected —
  /// see [ClaimStatus.closedKeys]); Compensated stays open.
  Future<List<Claim>> open() => _byStatus(closedOnly: false);

  Future<List<Claim>> closed() => _byStatus(closedOnly: true);

  /// `(?, ?, ...)` placeholder list for [ClaimStatus.closedKeys].
  static String get _closedIn =>
      '(${List<String>.filled(ClaimStatus.closedKeys.length, '?').join(', ')})';

  Future<List<Claim>> _byStatus({required bool closedOnly}) async {
    final List<Map<String, Object?>> rows = await _db.rawDb.query(
      'claims',
      where: closedOnly
          ? 'status_key IN $_closedIn'
          : 'status_key NOT IN $_closedIn',
      whereArgs: ClaimStatus.closedKeys,
    );
    return sortDefault(rows.map(Claim.fromRow).toList());
  }

  /// Claims with a scheduled next follow-up (spec §6 "Needs follow-up").
  Future<List<Claim>> needsFollowUp() async {
    final List<Map<String, Object?>> rows = await _db.rawDb.query(
      'claims',
      where:
          'next_follow_up_utc_ms IS NOT NULL AND status_key NOT IN $_closedIn',
      whereArgs: ClaimStatus.closedKeys,
    );
    return sortDefault(rows.map(Claim.fromRow).toList());
  }

  /// Claims whose next follow-up is before [nowUtc] (spec §6 "Overdue").
  Future<List<Claim>> overdue(DateTime nowUtc) async {
    final List<Map<String, Object?>> rows = await _db.rawDb.query(
      'claims',
      where:
          'next_follow_up_utc_ms IS NOT NULL AND next_follow_up_utc_ms < ? AND status_key NOT IN $_closedIn',
      whereArgs: [nowUtc.millisecondsSinceEpoch, ...ClaimStatus.closedKeys],
    );
    return sortDefault(rows.map(Claim.fromRow).toList());
  }

  /// Claims whose next follow-up falls inside [startUtc, endUtc] — used for
  /// "due today" in the app's Asia/Riyadh day (spec §5–§6).
  Future<List<Claim>> dueBetween(DateTime startUtc, DateTime endUtc) async {
    final List<Map<String, Object?>> rows = await _db.rawDb.query(
      'claims',
      where:
          'next_follow_up_utc_ms IS NOT NULL AND next_follow_up_utc_ms >= ? AND next_follow_up_utc_ms <= ? AND status_key NOT IN $_closedIn',
      whereArgs: [
        startUtc.millisecondsSinceEpoch,
        endUtc.millisecondsSinceEpoch,
        ...ClaimStatus.closedKeys,
      ],
    );
    return sortDefault(rows.map(Claim.fromRow).toList());
  }

  // ---------------------------------------------------------------------------
  // Counts for the dashboard — counted in SQL so no claim rows are loaded.
  // Each uses the same condition as the list query of the same name.
  // ---------------------------------------------------------------------------

  Future<int> _count(String? where, List<Object?> args) async {
    final List<Map<String, Object?>> rows = await _db.rawDb.query(
      'claims',
      columns: <String>['COUNT(*) AS n'],
      where: where,
      whereArgs: args.isEmpty ? null : args,
    );
    return (rows.first['n'] as int?) ?? 0;
  }

  Future<int> countAll() => _count(null, const <Object?>[]);

  Future<int> countOpen() =>
      _count('status_key NOT IN $_closedIn', ClaimStatus.closedKeys);

  Future<int> countClosed() =>
      _count('status_key IN $_closedIn', ClaimStatus.closedKeys);

  Future<int> countOverdue(DateTime nowUtc) => _count(
    'next_follow_up_utc_ms IS NOT NULL AND next_follow_up_utc_ms < ? AND status_key NOT IN $_closedIn',
    <Object?>[nowUtc.millisecondsSinceEpoch, ...ClaimStatus.closedKeys],
  );

  Future<int> countDueBetween(DateTime startUtc, DateTime endUtc) => _count(
    'next_follow_up_utc_ms IS NOT NULL AND next_follow_up_utc_ms >= ? AND next_follow_up_utc_ms <= ? AND status_key NOT IN $_closedIn',
    <Object?>[
      startUtc.millisecondsSinceEpoch,
      endUtc.millisecondsSinceEpoch,
      ...ClaimStatus.closedKeys,
    ],
  );

  /// The [limit] most recently updated claims, newest first.
  Future<List<Claim>> recentlyUpdated(int limit) async {
    final List<Map<String, Object?>> rows = await _db.rawDb.query(
      'claims',
      orderBy: 'updated_at_utc_ms DESC, id DESC',
      limit: limit,
    );
    return rows.map(Claim.fromRow).toList();
  }

  // ---------------------------------------------------------------------------
  // Sorting (spec §6)
  // ---------------------------------------------------------------------------

  /// Default order: overdue / due-soon claims first (earliest follow-up
  /// first), then the most recently updated. Closed claims sink to the end.
  List<Claim> sortDefault(List<Claim> claims, {DateTime? nowUtc}) {
    final DateTime now = nowUtc ?? DateTime.now().toUtc();

    int priority(Claim c) {
      if (ClaimStatus.isClosedKey(c.statusKey)) return 3;
      final DateTime? fu = c.nextFollowUpUtcMs;
      if (fu != null && !fu.isAfter(now)) return 0; // overdue or due now
      if (fu != null) return 1; // upcoming follow-up
      return 2; // no follow-up scheduled
    }

    final List<Claim> sorted = List<Claim>.of(claims);
    sorted.sort((a, b) {
      final int pa = priority(a);
      final int pb = priority(b);
      if (pa != pb) return pa.compareTo(pb);
      switch (pa) {
        case 0:
          // Earliest follow-up first.
          return a.nextFollowUpUtcMs!.compareTo(b.nextFollowUpUtcMs!);
        case 1:
          return a.nextFollowUpUtcMs!.compareTo(b.nextFollowUpUtcMs!);
        default:
          // Most recently updated first.
          return b.updatedAtUtcMs.compareTo(a.updatedAtUtcMs);
      }
    });
    return sorted;
  }
}
