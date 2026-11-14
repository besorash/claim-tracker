/// Claim mutation orchestration (spec §9–§12): every flow that touches more
/// than one table — status+history, reminders, close, delete, attachments —
/// lives here so screens stay router-free and the flows are testable without
/// widgets.
library;

import '../../core/database/app_database.dart';
import '../../core/database/attachments_repository.dart';
import '../../core/database/claims_repository.dart';
import '../../core/database/reminders_repository.dart';
import '../../core/database/status_history_repository.dart';
import '../../core/models/attachment.dart';
import '../../core/models/claim_status.dart';
import '../../core/models/reminder.dart';
import '../../core/notifications/notification_service.dart' show AlarmPrecision;
import '../../core/notifications/reminder_scheduler.dart';
import '../attachments/attachment_file_service.dart';

/// What a status change does to the claim's follow-up (spec §9: optional).
sealed class FollowUpChange {
  const FollowUpChange();
}

/// Keep whatever follow-up date is currently stored — no reminder work.
class KeepFollowUp extends FollowUpChange {
  const KeepFollowUp();
}

/// Set a new follow-up date and (re)schedule the claim's single reminder.
class SetFollowUp extends FollowUpChange {
  const SetFollowUp(this.atUtc);
  final DateTime atUtc;
}

/// Clear the follow-up: cancel the alarm, remove the row, null the date.
class ClearFollowUp extends FollowUpChange {
  const ClearFollowUp();
}

/// Outcome of [ClaimActions.saveReminder] (Phase 1 fix #3): the UI must
/// surface scheduling failures and inexact alarms instead of hiding them —
/// a reminder saved while the OS alarm could not be scheduled is otherwise
/// silently lost.
class ScheduleResult {
  const ScheduleResult({required this.reminder, required this.precision});

  /// The persisted reminder row (always present when saveReminder returns).
  final Reminder reminder;

  /// Whether an OS alarm was actually scheduled for it.
  bool get scheduled => precision != null;

  /// The precision used — [AlarmPrecision.inexact] means the OS may defer
  /// delivery and the user must be warned. Null when no alarm was scheduled.
  final AlarmPrecision? precision;
}

class ClaimActions {
  const ClaimActions(this._db, this.scheduler, {this.files});

  final AppDatabase _db;
  final ReminderScheduler scheduler;

  /// Physical attachment file handling (spec §12). Optional so existing
  /// constructions keep working: when null, [attachFile] throws and
  /// [deleteClaim] skips the per-file cleanup.
  final AttachmentFileService? files;

  ClaimsRepository get _claims => ClaimsRepository(_db);
  RemindersRepository get _reminders => RemindersRepository(_db);
  StatusHistoryRepository get _history => StatusHistoryRepository(_db);
  AttachmentsRepository get _attachments => AttachmentsRepository(_db);

  /// Atomic status+history write (spec §9), then applies [followUp]:
  /// Keep = no reminder change; Set(atUtc) = saveReminder(claimId, atUtc);
  /// Clear = clearFollowUp(claimId). A closed status always clears.
  Future<void> changeStatus(
    int claimId,
    String newStatusKey, {
    String? note,
    required FollowUpChange followUp,
  }) async {
    await _history.changeStatus(
      claimId: claimId,
      newStatusKey: newStatusKey,
      changedAtUtc: DateTime.now().toUtc(),
      note: (note == null || note.trim().isEmpty) ? null : note.trim(),
    );
    // A closed outcome (Closed, Approved, Rejected) needs no more follow-up:
    // its reminder and notification are removed whatever was chosen.
    if (ClaimStatus.isClosedKey(newStatusKey)) {
      followUp = const ClearFollowUp();
    }
    switch (followUp) {
      case KeepFollowUp():
        break;
      case SetFollowUp(:final atUtc):
        await saveReminder(claimId: claimId, fireAtUtc: atUtc);
      case ClearFollowUp():
        await clearFollowUp(claimId);
    }
  }

  /// Replaces the claim's single reminder (enabled=1, notificationId ==
  /// claimId — stable across reschedules), sets claims.next_follow_up_utc_ms,
  /// then schedules unless [schedule] is false. The in-app state persists
  /// regardless of OS permission (spec §10); only scheduling depends on it.
  Future<ScheduleResult> saveReminder({
    required int claimId,
    required DateTime fireAtUtc,
    bool schedule = true,
  }) async {
    final DateTime now = DateTime.now().toUtc();
    final Reminder stored = await _reminders.replaceForClaim(
      claimId: claimId,
      next: Reminder(
        id: 0,
        claimId: claimId,
        fireAtUtcMs: fireAtUtc.toUtc(),
        notificationId: claimId,
        enabled: true,
        createdAtUtcMs: now,
        updatedAtUtcMs: now,
      ),
    );
    await _setClaimFollowUp(claimId, stored.fireAtUtcMs);
    if (!schedule) {
      return ScheduleResult(reminder: stored, precision: null);
    }
    try {
      final AlarmPrecision precision = await scheduler.scheduleReminder(stored);
      return ScheduleResult(reminder: stored, precision: precision);
    } on Object catch (_) {
      // Persisted but NOT scheduled — the caller must tell the user (Phase 1
      // fix #3). The error is swallowed here so the DB state stays consistent.
      return ScheduleResult(reminder: stored, precision: null);
    }
  }

  /// Cancels the OS alarm and disables the DB row; keeps the follow-up date
  /// visible in-app (spec §10: disable ≠ delete).
  Future<void> disableReminder(int claimId) async {
    final Reminder? existing = await _reminders.latestForClaim(claimId);
    if (existing != null) {
      await _safeCancel(existing.notificationId);
      await _reminders.disableAllForClaim(claimId);
    }
  }

  /// Cancels the OS alarm, removes the reminder row and nulls the claim's
  /// follow-up date.
  Future<void> clearFollowUp(int claimId) async {
    final Reminder? existing = await _reminders.latestForClaim(claimId);
    if (existing != null) {
      await _safeCancel(existing.notificationId);
    }
    await _reminders.removeAllForClaim(claimId);
    await _setClaimFollowUp(claimId, null);
  }

  /// changeStatus(closed) + cancel & remove all reminders (spec §10).
  Future<void> closeClaim(int claimId) async {
    final List<Reminder> pending = await _reminders.allEnabled();
    for (final Reminder r in pending.where((r) => r.claimId == claimId)) {
      await _safeCancel(r.notificationId);
    }
    await changeStatus(claimId, 'closed', followUp: const ClearFollowUp());
  }

  /// Copies [sourcePath] into the app-private store, records an attachment row
  /// linked to [claimId], and returns the stored [Attachment]. If the DB insert
  /// fails (e.g. FK violation), the copied file is deleted — no orphans
  /// (spec §12). Throws [ArgumentError] when the source path does not exist,
  /// and [StateError] when constructed without a [files] service.
  Future<Attachment> attachFile(
    int claimId,
    String sourcePath, {
    String originalName = '',
    String mimeType = '',
  }) async {
    final AttachmentFileService? svc = files;
    if (svc == null) {
      throw StateError(
        'ClaimActions constructed without an AttachmentFileService',
      );
    }

    // Copy first — importFile throws ArgumentError for a missing source, so no
    // partial state can exist before this point.
    final String relativePath = await svc.importFile(
      sourcePath,
      originalName: originalName,
    );
    // Resolve the stored file through the null-safe storeDir() — never force-
    // unwrap baseDir (Phase 5 regression fix).
    final int sizeBytes = (await svc.storedFileFor(relativePath)).lengthSync();

    final String name = originalName.isNotEmpty
        ? originalName
        : relativePath.split('/').last;
    final String mime = mimeType.isEmpty
        ? 'application/octet-stream'
        : mimeType;

    try {
      final DateTime now = DateTime.now().toUtc();
      final int id = await _attachments.create(
        Attachment(
          id: 0,
          claimId: claimId,
          originalName: name,
          mimeType: mime,
          sizeBytes: sizeBytes,
          relativePath: relativePath,
          createdAtUtcMs: now,
        ),
      );
      return Attachment(
        id: id,
        claimId: claimId,
        originalName: name,
        mimeType: mime,
        sizeBytes: sizeBytes,
        relativePath: relativePath,
        createdAtUtcMs: now,
      );
    } on Object {
      // Roll back the copied file so a failed insert leaves no orphan bytes.
      await _safeDeleteFile(svc, relativePath);
      rethrow;
    }
  }

  /// Bulk variant of [deleteClaim] for the claims list's selection mode:
  /// deletes every claim in [claimIds] with the same guarantees as a single
  /// deletion — pending OS alarms are cancelled FIRST (so no stale alarm
  /// survives), attachment files are removed best-effort per file (one failing
  /// file never blocks the rest or any row), and the claim rows go last, all
  /// in one transaction. FK cascade removes each claim's history and
  /// attachment rows. The enabled-reminder table is queried once for the whole
  /// selection instead of once per claim.
  Future<void> deleteClaims(Iterable<int> claimIds) async {
    final Set<int> ids = claimIds.toSet();
    if (ids.isEmpty) return;

    // One pass over every enabled reminder: cancel the selected claims' alarms,
    // then drop all of their reminder rows.
    final List<Reminder> pending = await _reminders.allEnabled();
    for (final Reminder r in pending.where((r) => ids.contains(r.claimId))) {
      await _safeCancel(r.notificationId);
    }

    final AttachmentFileService? svc = files;
    if (svc != null) {
      for (final int id in ids) {
        for (final Attachment a in await _attachments.listForClaim(id)) {
          await _safeDeleteAttachment(svc, a);
        }
        await _reminders.removeAllForClaim(id);
      }
    } else {
      for (final int id in ids) {
        await _reminders.removeAllForClaim(id);
      }
    }

    // Delete the claim rows last; FK cascade removes each claim's status
    // history and attachment rows.
    final List<int> list = ids.toList();
    await _db.rawDb.transaction((txn) async {
      for (final int id in list) {
        await txn.delete('claims', where: 'id = ?', whereArgs: [id]);
      }
    });
  }

  /// Cancel & remove all reminders FIRST (so no stale alarm survives), then
  /// delete the claim's attachment files (best-effort per file — one failure
  /// must not block the rest or the row), then delete the claim. FK cascade
  /// removes its history and attachment rows.
  Future<void> deleteClaim(int claimId) async {
    final List<Reminder> pending = await _reminders.allEnabled();
    for (final Reminder r in pending.where((r) => r.claimId == claimId)) {
      await _safeCancel(r.notificationId);
    }
    await _reminders.removeAllForClaim(claimId);

    final AttachmentFileService? svc = files;
    if (svc != null) {
      for (final Attachment a in await _attachments.listForClaim(claimId)) {
        await _safeDeleteAttachment(svc, a);
      }
    }

    await _claims.delete(claimId);
  }

  Future<void> _setClaimFollowUp(int claimId, DateTime? atUtc) =>
      _db.rawDb.update(
        'claims',
        <String, Object?>{
          'next_follow_up_utc_ms': atUtc?.millisecondsSinceEpoch,
        },
        where: 'id = ?',
        whereArgs: [claimId],
      );

  /// Best-effort cancel — a failing OS call must never abort the user flow.
  Future<void> _safeCancel(int notificationId) async {
    try {
      await scheduler.cancelReminder(notificationId);
    } on Object catch (_) {
      // Intentionally swallowed: DB state is already consistent; the alarm, if
      // any, will simply never fire (or was already gone).
    }
  }

  /// Best-effort delete of a stored file by relative path — used to roll back
  /// an orphan after a failed insert. A failure here must not mask the
  /// original error being rethrown.
  Future<void> _safeDeleteFile(
    AttachmentFileService svc,
    String relativePath,
  ) async {
    try {
      await svc.deleteFile(
        Attachment(
          id: 0,
          claimId: 0,
          originalName: '',
          mimeType: '',
          sizeBytes: 0,
          relativePath: relativePath,
          createdAtUtcMs: DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
        ),
      );
    } on Object catch (_) {
      // Intentionally swallowed — the caller rethrows the real error.
    }
  }

  /// Best-effort delete of one attachment's file (spec §12): a single failing
  /// file must not block deletion of the rest or of the claim row itself.
  Future<void> _safeDeleteAttachment(
    AttachmentFileService svc,
    Attachment a,
  ) async {
    try {
      await svc.deleteFile(a);
    } on Object catch (_) {
      // Intentionally swallowed: DB state stays consistent; the orphan file, if
      // any, is unreachable from any row and will be swept by the next restore.
    }
  }
}
