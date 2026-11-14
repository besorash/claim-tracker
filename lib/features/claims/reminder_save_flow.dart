/// Reminder-save flows shared by EVERY reminder entry point (spec §10): the
/// details screen's set/reschedule, and the claim form's add/edit path. One
/// implementation of the permission sequence and outcome reporting — so a
/// reminder saved from the form behaves exactly like one saved from the
/// details screen (same explain/request dialogs, same surfaced failures).
library;

import 'package:flutter/material.dart';

import '../../core/database/app_database.dart';
import '../../core/l10n/app_strings.dart';
import '../../core/models/claim.dart';
import '../../core/notifications/notification_service.dart'
    show AlarmPrecision, NotificationPermissionState;
import '../../core/notifications/reminder_scheduler.dart';
import 'claim_actions.dart';

/// Resolves notification permissions BEFORE a reminder is persisted (spec §10):
/// exact-alarm explanation + request when the OS allows notifications but not
/// exact alarms (Android 14+ default), then the notification-permission
/// explain + explicit request when disabled. Returns whether scheduling should
/// be attempted — the in-app state persists regardless of this result.
Future<bool> resolveReminderPermissions(
  BuildContext context,
  ReminderScheduler scheduler,
) async {
  bool enabled = await scheduler.areNotificationsEnabled();

  // Phase 1 fix #1: exact alarms are denied by default on Android 14+ —
  // explain and request before scheduling, in the same dialog style as the
  // notification-permission flow.
  if (enabled && context.mounted) {
    final bool exactOk = await scheduler.canScheduleExactAlarms();
    if (!exactOk && context.mounted) {
      final bool? allowed = await showDialog<bool>(
        context: context,
        builder: (BuildContext ctx) => AlertDialog(
          title: Text(S.exactAlarmExplainTitle),
          content: Text(S.exactAlarmExplainBody),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text(S.cancel),
            ),
            FilledButton(
              key: const Key('request-exact-alarms'),
              onPressed: () => Navigator.of(ctx).pop(true),
              child: Text(S.exactAlarmsRequestAction),
            ),
          ],
        ),
      );
      if (allowed == true) {
        await scheduler.requestExactAlarmsPermission();
      }
    }
  }

  // Explain first, then let the user request permission explicitly.
  if (!enabled && context.mounted) {
    final bool? allowed = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: Text(S.notificationsPermissionTitle),
        content: Text(S.notificationsPermissionBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(S.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(S.confirm),
          ),
        ],
      ),
    );
    if (allowed == true) {
      enabled =
          await scheduler.requestNotificationsPermission() ==
          NotificationPermissionState.granted;
    }
  }

  return enabled;
}

/// Surfaces a reminder-save outcome INSTEAD of hiding it (Phase 1 fix #3): a
/// failed schedule, an inexact alarm (the OS may defer delivery), or the
/// still-denied state with a direct path into system notification settings.
Future<void> reportReminderSaveOutcome(
  BuildContext context, {
  required ReminderScheduler scheduler,
  required bool enabled,
  required ScheduleResult result,
}) async {
  if (!context.mounted) return;

  if (enabled && !result.scheduled) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(S.reminderScheduleFailed)));
    return;
  }
  if (enabled && result.precision == AlarmPrecision.inexact) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(S.reminderInexactWarning)));
    return;
  }

  // Still denied — explain how to enable notifications on the device and
  // offer a direct jump into the system notification settings (BUG B: this
  // dialog must carry a recovery path, not just static text).
  if (!enabled && context.mounted) {
    await showDialog<void>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: Text(S.notificationsDeniedTitle),
        content: Text(S.notificationsDeniedBody),
        actions: [
          TextButton(
            key: const Key('open-notification-settings'),
            onPressed: () async {
              Navigator.of(ctx).pop();
              await scheduler.openAppNotificationSettings();
            },
            child: Text(S.notificationsOpenSettingsAction),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(S.confirm),
          ),
        ],
      ),
    );
  }
}

/// Add mode (spec §10): the caller has just created [claimId] — persist its
/// enabled reminder for [whenUtc] and schedule the OS alarm when permission
/// allows. The in-app state persists regardless of OS permission; only the
/// scheduling depends on it, and any failure is surfaced to the user (never
/// silently lost).
Future<void> scheduleFollowUpOnCreate(
  BuildContext context,
  AppDatabase db,
  ReminderScheduler scheduler,
  int claimId,
  DateTime whenUtc,
) async {
  final bool enabled = await resolveReminderPermissions(context, scheduler);
  // Persist FIRST — the in-app state must not depend on OS permission.
  final ScheduleResult result = await ClaimActions(db, scheduler).saveReminder(
    claimId: claimId,
    fireAtUtc: whenUtc.toUtc(),
    schedule: enabled,
  );
  if (!context.mounted) return;
  await reportReminderSaveOutcome(
    context,
    scheduler: scheduler,
    enabled: enabled,
    result: result,
  );
}

/// Edit mode (spec §10): after a form save, reconciles the claim's single
/// reminder with [saved]'s follow-up —
/// - changed or newly set → reschedule (replace semantics: one row per claim,
///   stable `notificationId == claimId`, the shown/old alarm is replaced);
/// - cleared → cancel the OS alarm and remove the row;
/// - unchanged → nothing at all, so a plain edit never re-triggers alarms.
Future<void> syncFollowUpAfterEdit(
  BuildContext context,
  AppDatabase db,
  ReminderScheduler scheduler, {
  required Claim before,
  required Claim saved,
}) async {
  final DateTime? previous = before.nextFollowUpUtcMs?.toUtc();
  final DateTime? next = saved.nextFollowUpUtcMs;

  if (next == null) {
    if (previous != null) {
      await ClaimActions(db, scheduler).clearFollowUp(saved.id);
    }
    return;
  }

  // Unchanged instant — the existing alarm keeps running untouched.
  if (previous?.millisecondsSinceEpoch == next.toUtc().millisecondsSinceEpoch) {
    return;
  }

  await scheduleFollowUpOnCreate(context, db, scheduler, saved.id, next);
}
