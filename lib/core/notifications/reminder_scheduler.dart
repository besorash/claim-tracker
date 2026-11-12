/// Injection seam for OS-side reminder scheduling (spec §10).
///
/// Production code uses [NotificationService] (which implements this); widget
/// and orchestration tests inject a recording fake so no method channels are
/// touched on the host. Keeping the four operations behind one interface means
/// `ClaimActions` never depends on flutter_local_notifications directly.
library;

import '../models/reminder.dart';
import 'notification_service.dart'
    show AlarmPrecision, NotificationPermissionState;

abstract class ReminderScheduler {
  /// Requests the Android notification permission and reports the outcome.
  Future<NotificationPermissionState> requestNotificationsPermission();

  /// Whether notifications are currently enabled on this device.
  Future<bool> areNotificationsEnabled();

  /// Schedules [reminder] as a local alarm (idempotent per notificationId)
  /// and reports the precision actually used — callers must surface an
  /// inexact result to the user, because the OS may defer delivery.
  Future<AlarmPrecision> scheduleReminder(Reminder reminder);

  /// Cancels the OS-side alarm for [notificationId]. Implementations must not
  /// throw when the alarm is already gone — callers rely on best-effort cancel.
  Future<void> cancelReminder(int notificationId);

  /// Reconciles the OS alarm set with [enabledReminders]: cancels pending
  /// alarms that no longer correspond to an enabled reminder, then reschedules
  /// the future ones (spec §10: reconcile after restart and after restore).
  Future<void> reconcile(List<Reminder> enabledReminders);

  /// Opens the system notification-settings page for this app so a user who
  /// denied POST_NOTIFICATIONS can re-enable it (spec §10: permission-denied
  /// behavior). [NotificationService] overrides it with the real plugin call;
  /// test fakes that `implements` this seam provide their own recording stub.
  /// Returns false when unavailable.
  Future<bool> openAppNotificationSettings();

  // ---------------------------------------------------------------------------
  // Exact alarms (Phase 1 fix #1): Android 14+ denies SCHEDULE_EXACT_ALARM by
  // default; USE_EXACT_ALARM is auto-granted on API 33+. The UI must be able
  // to check the state and open the system permission screen.
  // ---------------------------------------------------------------------------

  /// Whether exact-alarm scheduling is currently allowed for this app.
  Future<bool> canScheduleExactAlarms();

  /// Opens the system "exact alarms" permission screen (or reports that it is
  /// already granted / not applicable). Returns true when the user ended up
  /// with exact alarms enabled, or when no action was needed.
  Future<bool> requestExactAlarmsPermission();

  // ---------------------------------------------------------------------------
  // Battery optimization (Phase 1 fix #4): OEM battery killers defer closed-
  // app alarms; the exemption is requested through a platform channel.
  // ---------------------------------------------------------------------------

  /// Whether this app currently ignores battery optimizations.
  Future<bool> isIgnoringBatteryOptimizations();

  /// Shows the system "ignore battery optimizations" request for this app.
  /// Returns true when granted (or already exempt); false on denial/failure.
  Future<bool> requestIgnoreBatteryOptimizations();
}
