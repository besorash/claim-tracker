/// Local notifications foundation (spec §10) — Android and iOS.
///
/// Phase 1 establishes: initialization, channel setup, permission handling,
/// and the schedule/cancel/reconcile API used by the reminders feature.
/// UI wiring (reminder dialogs, settings) arrives in Phase 3.
library;

import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;

import '../constants/app_constants.dart';
import '../l10n/app_strings.dart';
import '../models/claim.dart';
import '../models/reminder.dart';
import 'reconcile_plan.dart';
import 'reminder_scheduler.dart';
import '../utils/time_utils.dart';

/// Result of a permission request (spec §10: explain + handle denial).
enum NotificationPermissionState { granted, denied, unknown }

/// The precision actually used when scheduling an alarm (Phase 1 fix #1):
/// the UI must warn the user when only [inexact] was possible, because the
/// OS may defer delivery by a large window under app-standby/doze.
enum AlarmPrecision { exact, inexact }

/// Production implementation of [ReminderScheduler] — the injection seam used
/// by `ClaimActions` and screens (widget tests substitute a recording fake).
class NotificationService implements ReminderScheduler {
  NotificationService._();

  static final NotificationService instance = NotificationService._();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  bool _initialized = false;

  /// Android-specific implementation (null off-Android).
  AndroidFlutterLocalNotificationsPlugin? get _android => _plugin
      .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin
      >();

  /// iOS-specific implementation (null off-iOS). iOS has no notification
  /// channels, exact-alarm permission, or battery-optimization concept: a
  /// calendar-triggered local notification fires at its scheduled time.
  IOSFlutterLocalNotificationsPlugin? get _ios => _plugin
      .resolvePlatformSpecificImplementation<
        IOSFlutterLocalNotificationsPlugin
      >();

  /// Initializes the plugin and creates the reminder channel (spec §10:
  /// Android notification channels). Idempotent.
  Future<void> init() async {
    if (_initialized) return;
    await TimeUtils.ensureInitialized();

    // Monochrome small icon (Phase 1 fix #5): the full-color launcher asset
    // rendered as a white square in the status bar on many devices.
    const AndroidInitializationSettings androidSettings =
        AndroidInitializationSettings('drawable/ic_stat_reminder');
    // iOS: do NOT prompt at startup — permission is requested only after the
    // in-app explanation dialog (spec §10), via [requestNotificationsPermission].
    const DarwinInitializationSettings iosSettings =
        DarwinInitializationSettings(
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
        );
    const InitializationSettings settings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    await _plugin.initialize(
      settings: settings,
      onDidReceiveNotificationResponse: (NotificationResponse response) {
        // Routing is handled by the app shell via [onClaimTapped].
        final String? payload = response.payload;
        if (payload != null &&
            payload.startsWith(AppConstants.payloadClaimPrefix)) {
          final int claimId =
              int.tryParse(
                payload.substring(AppConstants.payloadClaimPrefix.length),
              ) ??
              -1;
          onClaimTapped?.call(claimId);
        }
      },
    );

    // Channel must be created before any notification is posted (spec §10).
    // Name/description follow the active UI language (bilingual EN/AR).
    await _android?.createNotificationChannel(
      AndroidNotificationChannel(
        AppConstants.reminderChannelId,
        S.reminderChannelName,
        description: S.reminderChannelDescription,
        importance: Importance.high,
      ),
    );

    _initialized = true;
  }

  /// Set by the app shell to route notification taps to a claim (spec §10).
  static void Function(int claimId)? onClaimTapped;

  /// Set by `main.dart` (and again after a restore) so a reminder can show
  /// the claim's plate, customer name and claim number. When null, or when
  /// the claim cannot be read, the generic reminder text is used.
  static Future<Claim?> Function(int claimId)? claimLookup;

  // ---------------------------------------------------------------------------
  // Permissions (spec §10)
  // ---------------------------------------------------------------------------

  @override
  Future<NotificationPermissionState> requestNotificationsPermission() async {
    final IOSFlutterLocalNotificationsPlugin? ios = _ios;
    if (ios != null) {
      await init();
      try {
        final bool? granted = await ios.requestPermissions(
          alert: true,
          badge: true,
          sound: true,
        );
        if (granted == true) return NotificationPermissionState.granted;
        if (granted == false) return NotificationPermissionState.denied;
      } catch (_) {
        // Fall through to the unknown state.
      }
      return NotificationPermissionState.unknown;
    }
    final AndroidFlutterLocalNotificationsPlugin? android = _android;
    if (android == null) return NotificationPermissionState.unknown;
    try {
      final bool? granted = await android.requestNotificationsPermission();
      if (granted == true) return NotificationPermissionState.granted;
      if (granted == false) return NotificationPermissionState.denied;
    } catch (_) {
      // Older Android versions don't require the permission.
    }
    final bool? enabled = await android.areNotificationsEnabled();
    if (enabled == true) return NotificationPermissionState.granted;
    if (enabled == false) return NotificationPermissionState.denied;
    return NotificationPermissionState.unknown;
  }

  @override
  Future<bool> areNotificationsEnabled() async {
    final IOSFlutterLocalNotificationsPlugin? ios = _ios;
    if (ios != null) {
      await init();
      try {
        final NotificationsEnabledOptions? opts = await ios.checkPermissions();
        return opts?.isEnabled ?? false;
      } catch (_) {
        return false;
      }
    }
    final AndroidFlutterLocalNotificationsPlugin? android = _android;
    if (android == null) return false;
    final bool? enabled = await android.areNotificationsEnabled();
    return enabled ?? false;
  }

  /// Whether the OS allows exact-alarm scheduling (spec §10: respect
  /// Android exact-alarm restrictions; Phase 1 fix #1).
  @override
  Future<bool> canScheduleExactAlarms() async {
    // iOS calendar triggers are exact; there is no permission to grant.
    if (_ios != null) return true;
    final AndroidFlutterLocalNotificationsPlugin? android = _android;
    if (android == null) return false;
    try {
      final bool? ok = await android.canScheduleExactNotifications();
      return ok ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Requests the exact-alarm permission when available (Android 12+). On
  /// Android 14+ this opens the system alarm-permission screen for this app.
  @override
  Future<bool> requestExactAlarmsPermission() async {
    if (_ios != null) return true;
    final AndroidFlutterLocalNotificationsPlugin? android = _android;
    if (android == null) return false;
    try {
      final bool? granted = await android.requestExactAlarmsPermission();
      if (granted != null) return granted;
    } catch (_) {
      // Older Android versions don't expose the request — fall through.
    }
    return canScheduleExactAlarms();
  }

  /// Battery-optimization exemption state (Phase 1 fix #4). Off-Android or a
  /// missing channel reports false so the UI simply offers no action.
  @override
  Future<bool> isIgnoringBatteryOptimizations() async {
    // No battery-optimization killer on iOS — nothing to exempt.
    if (_ios != null) return true;
    try {
      final bool? ok = await _permissionsChannel.invokeMethod<bool>(
        'isIgnoringBatteryOptimizations',
      );
      return ok ?? false;
    } on Object catch (_) {
      return false;
    }
  }

  /// Shows the system "ignore battery optimizations" request (Phase 1 fix #4).
  @override
  Future<bool> requestIgnoreBatteryOptimizations() async {
    if (_ios != null) return true;
    try {
      final bool? ok = await _permissionsChannel.invokeMethod<bool>(
        'requestIgnoreBatteryOptimizations',
      );
      return ok ?? false;
    } on Object catch (_) {
      return false;
    }
  }

  /// Platform channel for OS permission helpers (MainActivity.kt). Kept as a
  /// static so it is shared by every [NotificationService] instance.
  static const MethodChannel _permissionsChannel = MethodChannel(
    'com.claimtracker/permissions',
  );

  /// Opens the system notification-settings page for this app so the user can
  /// re-enable notifications after a denial (spec §10: permission-denied
  /// behavior). Returns true if the settings page was opened.
  @override
  Future<bool> openAppNotificationSettings() async {
    try {
      final bool? ok = await _plugin.openAppNotificationSettings();
      return ok ?? false;
    } catch (_) {
      return false;
    }
  }

  // ---------------------------------------------------------------------------
  // Scheduling (spec §10)
  // ---------------------------------------------------------------------------

  /// Notification details for reminder posts. Monochrome small icon (Phase 1
  /// fix #5) — status-bar icons must be single-color on Android. Built per
  /// call so the channel name/description follow the active UI language.
  ///
  /// The notification stays until the follow-up is handled: it cannot be
  /// swiped away ([ongoing]), tapping it opens the claim without removing it
  /// ([autoCancel] off), and its full text shows on the lock screen
  /// ([NotificationVisibility.public]). It is removed when the reminder is
  /// cleared, rescheduled, or the claim is closed or deleted.
  static AndroidNotificationDetails _details(String? bigText) =>
      AndroidNotificationDetails(
        AppConstants.reminderChannelId,
        S.reminderChannelName,
        channelDescription: S.reminderChannelDescription,
        importance: Importance.high,
        priority: Priority.high,
        icon: 'drawable/ic_stat_reminder',
        ongoing: true,
        autoCancel: false,
        visibility: NotificationVisibility.public,
        category: AndroidNotificationCategory.reminder,
        styleInformation: bigText == null
            ? null
            : BigTextStyleInformation(bigText),
      );

  /// Title and text for a claim's reminder: plate and customer name in the
  /// title, claim number below; the expanded view lists all three.
  static ({String title, String body, String bigText}) _contentFor(
    Claim claim,
  ) {
    final String plate = claim.vehiclePlate ?? S.noPlate;
    return (
      title: '$plate • ${claim.customerName}',
      body: '${S.claimNumberLabel}: ${claim.claimNumberDisplay}',
      bigText:
          '${S.vehiclePlateLabel}: $plate\n'
          '${S.customerNameLabel}: ${claim.customerName}\n'
          '${S.claimNumberLabel}: ${claim.claimNumberDisplay}',
    );
  }

  /// iOS presentation: show the banner/sound even when the app is in the
  /// foreground (iOS hides foreground notifications by default).
  static const DarwinNotificationDetails _iosDetails =
      DarwinNotificationDetails(
        presentAlert: true,
        presentBanner: true,
        presentList: true,
        presentSound: true,
      );

  /// Schedules a one-time reminder at [reminder.fireAtUtcMs] in Asia/Riyadh,
  /// showing the claim's plate, customer name and claim number (the user
  /// asked for these on the lock screen too). Falls back to the generic text
  /// when the claim cannot be read. Returns the precision actually used so
  /// the UI can warn when only an inexact alarm was possible (Phase 1 fix
  /// #1): [AlarmPrecision.inexact] means the OS may defer delivery.
  @override
  Future<AlarmPrecision> scheduleReminder(Reminder reminder) async {
    await init();

    final tz.TZDateTime fireLocal = TimeUtils.toRiyadh(reminder.fireAtUtcMs);
    if (!fireLocal.isAfter(tz.TZDateTime.now(tz.local))) {
      // Already in the past — nothing to schedule (reconcile handles these).
      return AlarmPrecision.inexact;
    }

    final bool exactOk = await canScheduleExactAlarms();

    Claim? claim;
    try {
      claim = await claimLookup?.call(reminder.claimId);
    } on Object catch (_) {
      claim = null;
    }
    final content = claim == null ? null : _contentFor(claim);

    // A reminder that already fired stays on screen (ongoing); rescheduling
    // replaces it, so remove the shown one first.
    await _plugin.cancel(id: reminder.notificationId);

    await _plugin.zonedSchedule(
      id: reminder.notificationId,
      scheduledDate: fireLocal,
      notificationDetails: NotificationDetails(
        android: _details(content?.bigText),
        iOS: _iosDetails,
      ),
      androidScheduleMode: exactOk
          ? AndroidScheduleMode.exactAllowWhileIdle
          : AndroidScheduleMode.inexactAllowWhileIdle,
      title: content?.title ?? S.genericReminderTitle,
      body: content?.body ?? S.genericReminderBody,
      payload: '${AppConstants.payloadClaimPrefix}${reminder.claimId}',
    );
    return exactOk ? AlarmPrecision.exact : AlarmPrecision.inexact;
  }

  /// Cancels a scheduled notification by its stable id (spec §10).
  @override
  Future<void> cancelReminder(int notificationId) async {
    await init();
    await _plugin.cancel(id: notificationId);
  }

  /// Reconciles OS-scheduled notifications with the database after app start
  /// or device reboot (spec §10). Thin adapter over [buildReconcilePlan]:
  /// cancels ONLY orphaned pending alarms, re-schedules enabled future
  /// reminders (same id → replace, no duplicates), and never destroys an
  /// enabled reminder whose delayed alarm is still pending.
  @override
  Future<void> reconcile(List<Reminder> enabledReminders) async {
    await init();

    final List<PendingNotificationRequest> pending = await _plugin
        .pendingNotificationRequests();
    final ReconcilePlan plan = buildReconcilePlan(
      pendingIds: pending.map((p) => p.id).toList(),
      enabledReminders: enabledReminders,
      nowUtc: DateTime.now().toUtc(),
    );

    for (final int id in plan.cancelIds) {
      await _plugin.cancel(id: id);
    }
    // Each reminder is scheduled independently — one failing alarm must not
    // abort the rest (Phase 1 fix #3). Callers surface per-reminder failures.
    for (final Reminder r in plan.reschedule) {
      try {
        await scheduleReminder(r);
      } on Object catch (_) {
        // Swallowed here: reconcile is best-effort at startup/restore; the
        // user-facing failure path is the reminder-save flow, which reports.
      }
    }
  }

  /// Cancels every pending notification (used on full restore, spec §15).
  Future<void> cancelAll() async {
    await init();
    await _plugin.cancelAll();
  }
}
