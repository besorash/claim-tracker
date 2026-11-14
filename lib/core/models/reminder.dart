/// Reminder definition persisted in SQLite (spec §10).
///
/// [notificationId] is the stable id used with flutter_local_notifications so
/// rescheduling/cancelling never collides or duplicates.
library;

class Reminder {
  const Reminder({
    required this.id,
    required this.claimId,
    required this.fireAtUtcMs,
    required this.notificationId,
    this.repeatIntervalHours,
    this.enabled = true,
    required this.createdAtUtcMs,
    required this.updatedAtUtcMs,
  });

  final int id;
  final int claimId;

  /// When the reminder fires (UTC).
  final DateTime fireAtUtcMs;

  /// Stable notification id for scheduling/cancelling.
  final int notificationId;

  /// Optional recurrence interval in hours (spec §10: recurring reminders if
  /// technically reliable). Null = one-time.
  final int? repeatIntervalHours;

  final bool enabled;
  final DateTime createdAtUtcMs;
  final DateTime updatedAtUtcMs;

  Map<String, Object?> toRow() => <String, Object?>{
    'id': id,
    'claim_id': claimId,
    'fire_at_utc_ms': fireAtUtcMs.millisecondsSinceEpoch,
    'notification_id': notificationId,
    'repeat_interval_hours': repeatIntervalHours,
    'enabled': enabled ? 1 : 0,
    'created_at_utc_ms': createdAtUtcMs.millisecondsSinceEpoch,
    'updated_at_utc_ms': updatedAtUtcMs.millisecondsSinceEpoch,
  };

  factory Reminder.fromRow(Map<String, Object?> row) => Reminder(
    id: row['id']! as int,
    claimId: row['claim_id']! as int,
    fireAtUtcMs: DateTime.fromMillisecondsSinceEpoch(
      row['fire_at_utc_ms']! as int,
      isUtc: true,
    ),
    notificationId: row['notification_id']! as int,
    repeatIntervalHours: row['repeat_interval_hours'] as int?,
    enabled: (row['enabled'] as int) == 1,
    createdAtUtcMs: DateTime.fromMillisecondsSinceEpoch(
      row['created_at_utc_ms']! as int,
      isUtc: true,
    ),
    updatedAtUtcMs: DateTime.fromMillisecondsSinceEpoch(
      row['updated_at_utc_ms']! as int,
      isUtc: true,
    ),
  );
}
