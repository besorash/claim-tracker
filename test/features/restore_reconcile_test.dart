/// Post-restore reminder reconciliation (spec §10/§15): after a successful
/// restore the OS alarm set must match the restored database — stale alarms
/// from deleted claims are cancelled and restored enabled reminders are
/// rescheduled. Pure Dart + FFI, no widget pumping needed.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart' as ffi;

import 'package:claim_tracker/core/database/app_database.dart';
import 'package:claim_tracker/core/database/claims_repository.dart';
import 'package:claim_tracker/core/database/reminders_repository.dart';
import 'package:claim_tracker/core/models/claim.dart';
import 'package:claim_tracker/core/models/reminder.dart';
import 'package:claim_tracker/core/notifications/notification_service.dart';
import 'package:claim_tracker/core/notifications/reconcile_plan.dart'
    show buildReconcilePlan;
import 'package:claim_tracker/core/notifications/reminder_scheduler.dart';
import 'package:claim_tracker/main.dart' show reconcileRemindersAfterRestore;

/// Recording fake — proves the post-restore flow hands the fresh DB's enabled
/// reminders to the scheduler.
class FakeScheduler implements ReminderScheduler {
  final List<List<Reminder>> reconciled = [];

  @override
  Future<void> cancelReminder(int notificationId) async {}

  @override
  Future<AlarmPrecision> scheduleReminder(Reminder reminder) async =>
      AlarmPrecision.exact;

  @override
  Future<bool> areNotificationsEnabled() async => true;

  @override
  Future<NotificationPermissionState> requestNotificationsPermission() async =>
      NotificationPermissionState.granted;

  @override
  Future<void> reconcile(List<Reminder> enabledReminders) async =>
      reconciled.add(enabledReminders);

  @override
  Future<bool> openAppNotificationSettings() async => false;

  @override
  Future<bool> canScheduleExactAlarms() async => true;

  @override
  Future<bool> requestExactAlarmsPermission() async => true;

  @override
  Future<bool> isIgnoringBatteryOptimizations() async => true;

  @override
  Future<bool> requestIgnoreBatteryOptimizations() async => true;
}

/// A scheduler whose reconcile blows up — the post-restore flow must survive.
class ThrowingScheduler implements ReminderScheduler {
  @override
  Future<void> cancelReminder(int notificationId) async {}

  @override
  Future<AlarmPrecision> scheduleReminder(Reminder reminder) async =>
      AlarmPrecision.exact;

  @override
  Future<bool> areNotificationsEnabled() async => true;

  @override
  Future<NotificationPermissionState> requestNotificationsPermission() async =>
      NotificationPermissionState.granted;

  @override
  Future<void> reconcile(List<Reminder> enabledReminders) async {
    throw StateError('OS alarm service unavailable');
  }

  @override
  Future<bool> openAppNotificationSettings() async => false;

  @override
  Future<bool> canScheduleExactAlarms() async => true;

  @override
  Future<bool> requestExactAlarmsPermission() async => true;

  @override
  Future<bool> isIgnoringBatteryOptimizations() async => true;

  @override
  Future<bool> requestIgnoreBatteryOptimizations() async => true;
}

void main() {
  late ffi.Database raw;
  late AppDatabase db;
  late ClaimsRepository claims;
  late RemindersRepository reminders;

  setUpAll(() {
    ffi.sqfliteFfiInit();
    ffi.databaseFactory = ffi.databaseFactoryFfi;
  });

  setUp(() async {
    raw = await ffi.databaseFactoryFfi.openDatabase(ffi.inMemoryDatabasePath);
    await raw.execute('PRAGMA foreign_keys = ON');
    await AppDatabase.migrate(raw, from: 0, to: kDatabaseVersion);
    db = AppDatabase.fromExisting(raw);
    claims = ClaimsRepository(db);
    reminders = RemindersRepository(db);
  });

  tearDown(() async {
    await raw.close();
  });

  Future<int> seedClaim() => claims.create(
    Claim(
      id: 0,
      customerName: 'عميل',
      customerMobile: '0501234567',
      accidentDateUtcMs: DateTime.utc(2026, 10, 1),
      claimNumber:
          'CLM-RESTORE-${DateTime.now().microsecondsSinceEpoch % 9999}',
      customerInsuranceCompany: 'تعاونية',
      submittedToInsuranceCompany: 'بوبا',
      submissionDateUtcMs: DateTime.utc(2026, 10, 5),
      statusKey: 'new',
      lastStatusUpdateUtcMs: DateTime.now().toUtc(),
      createdAtUtcMs: DateTime.now().toUtc(),
      updatedAtUtcMs: DateTime.now().toUtc(),
    ),
  );

  test(
    'reconcile receives exactly the enabled reminders from the fresh DB',
    () async {
      final int claimId = await seedClaim();
      final DateTime nowUtc = DateTime.now().toUtc();
      await reminders.create(
        Reminder(
          id: 0,
          claimId: claimId,
          fireAtUtcMs: nowUtc.add(const Duration(days: 1)),
          notificationId: 7788,
          enabled: true,
          createdAtUtcMs: nowUtc,
          updatedAtUtcMs: nowUtc,
        ),
      );

      final FakeScheduler fake = FakeScheduler();
      await reconcileRemindersAfterRestore(db, fake);

      expect(fake.reconciled, hasLength(1));
      expect(fake.reconciled.single, hasLength(1));
      expect(fake.reconciled.single.first.notificationId, 7788);
    },
  );

  test('disabled reminders are not handed to the scheduler', () async {
    final int claimId = await seedClaim();
    final DateTime nowUtc = DateTime.now().toUtc();
    await reminders.create(
      Reminder(
        id: 0,
        claimId: claimId,
        fireAtUtcMs: nowUtc.add(const Duration(days: 1)),
        notificationId: 7789,
        enabled: false,
        createdAtUtcMs: nowUtc,
        updatedAtUtcMs: nowUtc,
      ),
    );

    final FakeScheduler fake = FakeScheduler();
    await reconcileRemindersAfterRestore(db, fake);

    expect(fake.reconciled, hasLength(1));
    expect(fake.reconciled.single, isEmpty);
  });

  test('a failing scheduler never breaks the post-restore flow', () async {
    final int claimId = await seedClaim();
    final DateTime nowUtc = DateTime.now().toUtc();
    await reminders.create(
      Reminder(
        id: 0,
        claimId: claimId,
        fireAtUtcMs: nowUtc.add(const Duration(days: 1)),
        notificationId: 7790,
        enabled: true,
        createdAtUtcMs: nowUtc,
        updatedAtUtcMs: nowUtc,
      ),
    );

    Object? error;
    try {
      await reconcileRemindersAfterRestore(db, ThrowingScheduler());
    } on Object catch (e) {
      error = e;
    }

    expect(error, isNull, reason: 'reconciliation must never break restore');
  });

  // ---------------------------------------------------------------------------
  // Reconcile decision logic (Phase 1 fix #2): the plan must NEVER cancel an
  // enabled reminder's pending alarm — orphaned ids only. Past-due reminders
  // with a live alarm are left to fire; without one they reschedule late.
  // ---------------------------------------------------------------------------

  Reminder rem(int id, DateTime fireUtc, {bool enabled = true}) => Reminder(
    id: id,
    claimId: id,
    fireAtUtcMs: fireUtc.toUtc(),
    notificationId: id,
    enabled: enabled,
    createdAtUtcMs: fireUtc.toUtc().subtract(const Duration(days: 1)),
    updatedAtUtcMs: fireUtc.toUtc(),
  );

  group('reconcile plan (pure decision logic)', () {
    final DateTime now = DateTime.utc(2026, 11, 12, 9); // fixed "now"

    test(
      'cancels only pending ids that no longer map to an enabled reminder',
      () {
        final plan = buildReconcilePlan(
          pendingIds: const [1, 2, 3],
          enabledReminders: [rem(2, now.add(const Duration(hours: 5)))],
          nowUtc: now,
        );

        expect(plan.cancelIds, unorderedEquals([1, 3]));
        // The surviving reminder is (re)scheduled — idempotent replace.
        expect(plan.reschedule.map((r) => r.notificationId), [2]);
      },
    );

    test('keeps a past-due enabled reminder whose alarm is still pending', () {
      final plan = buildReconcilePlan(
        pendingIds: const [5],
        enabledReminders: [rem(5, now.subtract(const Duration(hours: 1)))],
        nowUtc: now,
      );

      expect(plan.cancelIds, isEmpty, reason: 'must not destroy a live alarm');
      expect(
        plan.reschedule,
        isEmpty,
        reason: 'the pending alarm will fire on its own — do not double-post',
      );
    });

    test(
      'leaves a past-due enabled reminder without a live alarm untouched',
      () {
        final plan = buildReconcilePlan(
          pendingIds: const <int>[],
          enabledReminders: [rem(5, now.subtract(const Duration(hours: 1)))],
          nowUtc: now,
        );

        expect(plan.cancelIds, isEmpty);
        // Re-posting would duplicate a reminder that may already have fired —
        // the DB has no reliable "fired" flag (spec §10: avoid duplicates).
        expect(
          plan.reschedule,
          isEmpty,
          reason: 'past-due rows are never re-scheduled by reconcile',
        );
      },
    );

    test('always reschedules future enabled reminders (idempotent replace)', () {
      final plan = buildReconcilePlan(
        pendingIds: const [7],
        enabledReminders: [rem(7, now.add(const Duration(hours: 2)))],
        nowUtc: now,
      );

      expect(plan.cancelIds, isEmpty);
      // Re-scheduling an existing alarm with the same id replaces it — this is
      // what lets a language switch refresh pending notification text.
      expect(plan.reschedule.map((r) => r.notificationId), [7]);
    });

    test('earliest duplicate wins for a shared notificationId', () {
      final List<Reminder> dupes = [
        Reminder(
          id: 10,
          claimId: 10,
          fireAtUtcMs: now.subtract(const Duration(hours: 1)), // past-due
          notificationId: 9,
          enabled: true,
          createdAtUtcMs: now.toUtc(),
          updatedAtUtcMs: now.toUtc(),
        ),
        Reminder(
          id: 11,
          claimId: 11,
          fireAtUtcMs: now.add(const Duration(hours: 2)), // future
          notificationId: 9,
          enabled: true,
          createdAtUtcMs: now.toUtc(),
          updatedAtUtcMs: now.toUtc(),
        ),
      ];

      final plan = buildReconcilePlan(
        pendingIds: const [9],
        enabledReminders: dupes,
        nowUtc: now,
      );

      expect(plan.cancelIds, isEmpty);
      // The live alarm (id 9) belongs to an enabled reminder — never cancel.
      // Both rows are past-due-or-future under one id; the earliest wins and
      // is past-due → left untouched (no duplicate re-post).
      expect(plan.reschedule, isEmpty);
    });

    test('disabled reminders never survive and their alarms are cancelled', () {
      final plan = buildReconcilePlan(
        pendingIds: const [7],
        enabledReminders: [
          rem(7, now.add(const Duration(hours: 2)), enabled: false),
        ],
        nowUtc: now,
      );

      expect(plan.cancelIds, [7]);
      expect(plan.reschedule, isEmpty);
    });
  });
}
