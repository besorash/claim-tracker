/// Persistent status-change history record (spec §9).
library;

class StatusHistoryEntry {
  const StatusHistoryEntry({
    required this.id,
    required this.claimId,
    required this.previousStatusKey,
    required this.newStatusKey,
    required this.changedAtUtcMs,
    this.note,
  });

  final int id;
  final int claimId;

  /// Status key before the change (null-equivalent represented as empty
  /// string for initial creation entries).
  final String previousStatusKey;
  final String newStatusKey;
  final DateTime changedAtUtcMs;
  final String? note;

  Map<String, Object?> toRow() => <String, Object?>{
    'id': id,
    'claim_id': claimId,
    'previous_status_key': previousStatusKey,
    'new_status_key': newStatusKey,
    'changed_at_utc_ms': changedAtUtcMs.millisecondsSinceEpoch,
    'note': note,
  };

  factory StatusHistoryEntry.fromRow(Map<String, Object?> row) =>
      StatusHistoryEntry(
        id: row['id']! as int,
        claimId: row['claim_id']! as int,
        previousStatusKey: row['previous_status_key']! as String,
        newStatusKey: row['new_status_key']! as String,
        changedAtUtcMs: DateTime.fromMillisecondsSinceEpoch(
          row['changed_at_utc_ms']! as int,
          isUtc: true,
        ),
        note: row['note'] as String?,
      );
}
