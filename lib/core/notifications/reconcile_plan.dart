/// Pure reconcile decision logic (spec §10, Phase 1 fix #2).
///
/// The previous implementation cancelled EVERY pending OS alarm on app start
/// and only re-scheduled future reminders — so a reminder that the OS had
/// delayed past its fire time was destroyed instead of delivered. This module
/// isolates the decision from the plugin so it is unit-testable without any
/// method channels:
///
///  * cancel ONLY pending ids that no longer correspond to an enabled
///    reminder (orphaned alarms — e.g. after a restore or claim delete);
///  * (re)schedule enabled reminders whose fire time is still in the future —
///    re-scheduling with the same id replaces the existing alarm, which keeps
///    the "no duplicates" guarantee (`notificationId == claimId` stays stable)
///    and lets a language switch refresh pending notification text;
///  * NEVER cancel an enabled reminder whose time has passed but whose alarm
///    is still pending — leave it so it can still fire (late beats lost);
///  * never re-schedule past-due reminders — the DB has no reliable "fired"
///    flag, and re-posting would duplicate a notification that may already
///    have been delivered.
library;

import '../models/reminder.dart';

/// The outcome of [buildReconcilePlan]: which pending alarms to cancel and
/// which enabled reminders to (re)schedule.
class ReconcilePlan {
  const ReconcilePlan({required this.cancelIds, required this.reschedule});

  /// Pending notification ids that must be cancelled (orphaned only).
  final List<int> cancelIds;

  /// Enabled future reminders to schedule/replace (one per notificationId).
  final List<Reminder> reschedule;
}

/// Decides the reconcile actions for [enabledReminders] given the set of
/// currently pending OS alarm ids. Pure and deterministic — no I/O, no clock
/// reads ([nowUtc] is injected so tests can pin "now").
ReconcilePlan buildReconcilePlan({
  required List<int> pendingIds,
  required List<Reminder> enabledReminders,
  required DateTime nowUtc,
}) {
  // Defensive: honor the enabled flag even if a caller passes unfiltered rows.
  final Set<int> pending = pendingIds.toSet();

  // One OS slot per notificationId (zonedSchedule replaces by id). If several
  // enabled rows ever shared an id, the earliest fire time owns the slot —
  // deterministic and duplicate-free. In practice this cannot happen because
  // `notificationId == claimId` and replaceForClaim keeps one row per claim.
  final Map<int, Reminder> winnerById = <int, Reminder>{};
  for (final Reminder r in enabledReminders) {
    if (!r.enabled) continue;
    final Reminder? current = winnerById[r.notificationId];
    if (current == null ||
        r.fireAtUtcMs.isBefore(current.fireAtUtcMs) ||
        (r.fireAtUtcMs == current.fireAtUtcMs && r.id < current.id)) {
      winnerById[r.notificationId] = r;
    }
  }

  // Cancel only what is orphaned — never an enabled reminder's live alarm.
  final List<int> cancelIds =
      pending.where((int id) => !winnerById.containsKey(id)).toList()..sort();

  // (Re)schedule the future ones; past-due winners are left untouched so a
  // still-pending delayed alarm can fire and an already-fired one is not
  // posted twice.
  final List<Reminder> reschedule =
      winnerById.values
          .where((Reminder r) => r.fireAtUtcMs.isAfter(nowUtc))
          .toList()
        ..sort((a, b) => a.notificationId.compareTo(b.notificationId));

  return ReconcilePlan(cancelIds: cancelIds, reschedule: reschedule);
}
