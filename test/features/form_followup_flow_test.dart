/// Reminder flows wired to the claim FORM (add + edit) — spec §10.
///
/// Regression background: picking a follow-up date on the add/edit form used
/// to save only `claims.next_follow_up_utc_ms` — no reminder row, no OS alarm
/// — so a "reminder" set while creating a claim never fired (and its time of
/// day was silently midnight). These tests pin the wired behavior: a follow-up
/// saved from the form persists an enabled reminder AND schedules it through
/// the injected [ReminderScheduler], and an edit reconciles the existing one.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart' as ffi;

import 'package:claim_tracker/core/database/app_database.dart';
import 'package:claim_tracker/core/database/claims_repository.dart';
import 'package:claim_tracker/core/database/reminders_repository.dart';
import 'package:claim_tracker/core/models/claim.dart';
import 'package:claim_tracker/core/models/reminder.dart';
import 'package:claim_tracker/core/notifications/notification_service.dart';
import 'package:claim_tracker/core/notifications/reminder_scheduler.dart';
import 'package:claim_tracker/features/claims/reminder_save_flow.dart';

/// Recording scheduler (same contract as the details-screen tests' fake): no
/// method channels on host, permission state configurable per test.
class FakeScheduler implements ReminderScheduler {
  final List<Reminder> scheduled = [];
  final List<int> cancelled = [];

  bool notificationsEnabled = true;
  bool exactAllowed = true;
  AlarmPrecision scheduleResult = AlarmPrecision.exact;
  int openedSettings = 0;

  @override
  Future<void> cancelReminder(int notificationId) async =>
      cancelled.add(notificationId);

  @override
  Future<AlarmPrecision> scheduleReminder(Reminder reminder) async {
    scheduled.add(reminder);
    return scheduleResult;
  }

  @override
  Future<bool> areNotificationsEnabled() async => notificationsEnabled;

  @override
  Future<NotificationPermissionState> requestNotificationsPermission() async =>
      NotificationPermissionState.granted;

  @override
  Future<void> reconcile(List<Reminder> enabledReminders) async {}

  @override
  Future<bool> openAppNotificationSettings() async {
    openedSettings++;
    return true;
  }

  @override
  Future<bool> canScheduleExactAlarms() async => exactAllowed;

  @override
  Future<bool> requestExactAlarmsPermission() async => true;

  @override
  Future<bool> isIgnoringBatteryOptimizations() async => true;

  @override
  Future<bool> requestIgnoreBatteryOptimizations() async => true;
}

/// Fresh in-memory DB with the full schema (proven pattern from widget_test).
Future<ffi.Database> _openInMemory() async {
  final ffi.Database raw = await ffi.databaseFactoryFfi.openDatabase(
    ffi.inMemoryDatabasePath,
    options: ffi.OpenDatabaseOptions(singleInstance: false),
  );
  await raw.execute('PRAGMA foreign_keys = ON');
  await AppDatabase.migrate(raw, from: 0, to: kDatabaseVersion);
  return raw;
}

Claim _claim(int id) => Claim(
  id: id,
  customerName: 'خالد',
  customerMobile: '0559876543',
  vehiclePlate: '4051 VJD',
  vehicleType: 'Camry 2022',
  accidentDateUtcMs: DateTime.utc(2026, 10, 1),
  claimNumber: 'CLM-FLOW-$id',
  customerInsuranceCompany: 'Tawuniya',
  statusKey: 'new',
  lastStatusUpdateUtcMs: DateTime.utc(2026, 10, 1),
  createdAtUtcMs: DateTime.utc(2026, 10, 1),
  updatedAtUtcMs: DateTime.utc(2026, 10, 1),
);

/// Pumps a minimal tree and hands back a live [BuildContext] for the flows'
/// dialog seams. On the happy paths exercised here no dialog is shown (all
/// permissions granted, scheduling exact) — the context only needs to exist.
Future<BuildContext> _context(WidgetTester tester) async {
  late BuildContext captured;
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (BuildContext ctx) {
          captured = ctx;
          return const SizedBox.shrink();
        },
      ),
    ),
  );
  return captured;
}

void main() {
  setUpAll(() async {
    ffi.sqfliteFfiInit();
    // This sqflite_common_ffi version does not wire the global factory in
    // sqfliteFfiInit (documented in widget_test.dart).
    ffi.databaseFactory = ffi.databaseFactoryFfi;
  });

  testWidgets(
    'create flow: a follow-up saved from the form persists an ENABLED reminder '
    'and schedules it for exactly that instant',
    (WidgetTester tester) async {
      await tester.runAsync(() async {
        final ffi.Database raw = await _openInMemory();
        final AppDatabase db = AppDatabase.fromExisting(raw);

        // The shell creates the claim first — mirror that, then run the flow.
        final int id = await ClaimsRepository(db).create(_claim(0));
        final DateTime whenUtc = DateTime.utc(2026, 12, 20, 9, 30);
        final FakeScheduler fake = FakeScheduler();

        final BuildContext ctx = await _context(tester);
        await scheduleFollowUpOnCreate(ctx, db, fake, id, whenUtc);

        // Reminder row: enabled, stable notificationId == claimId (spec §10).
        final List<Reminder> rows = (await raw.query(
          'reminders',
          where: 'claim_id = ?',
          whereArgs: [id],
        )).map(Reminder.fromRow).toList();
        expect(rows, hasLength(1));
        expect(rows.single.enabled, isTrue);
        expect(rows.single.fireAtUtcMs, whenUtc.toUtc());
        expect(rows.single.notificationId, id);

        // The claim's follow-up column matches the same instant (details/list
        // UIs read it).
        final Claim stored = (await db.claimById(id))!;
        expect(stored.nextFollowUpUtcMs, whenUtc.toUtc());

        // Exactly one OS alarm scheduled — for that row at that time.
        expect(fake.scheduled, hasLength(1));
        expect(fake.scheduled.single.notificationId, id);
        expect(fake.scheduled.single.fireAtUtcMs, whenUtc.toUtc());

        await raw.close();
      });
    },
  );

  testWidgets(
    'edit flow: changing the follow-up replaces (never duplicates) the reminder',
    (WidgetTester tester) async {
      await tester.runAsync(() async {
        final ffi.Database raw = await _openInMemory();
        final AppDatabase db = AppDatabase.fromExisting(raw);
        final int id = await ClaimsRepository(db).create(_claim(0));

        // Pre-existing enabled reminder (as set via the details screen).
        final DateTime t1 = DateTime.utc(2026, 12, 18, 8, 0);
        await RemindersRepository(db).replaceForClaim(
          claimId: id,
          next: Reminder(
            id: 0,
            claimId: id,
            fireAtUtcMs: t1,
            notificationId: id,
            enabled: true,
            createdAtUtcMs: DateTime.utc(2026, 11, 1),
            updatedAtUtcMs: DateTime.utc(2026, 11, 1),
          ),
        );

        final DateTime t2 = DateTime.utc(2026, 12, 22, 14, 30);
        final FakeScheduler fake = FakeScheduler();

        final BuildContext ctx = await _context(tester);
        await syncFollowUpAfterEdit(
          ctx,
          db,
          fake,
          before: _claim(id).copyWith(nextFollowUpUtcMs: t1),
          saved: _claim(id).copyWith(nextFollowUpUtcMs: t2),
        );

        // Replaced — exactly ONE row for the claim, at the NEW instant.
        final List<Map<String, Object?>> rows = await raw.query(
          'reminders',
          where: 'claim_id = ?',
          whereArgs: [id],
        );
        expect(rows, hasLength(1));
        expect(rows.single['fire_at_utc_ms'], t2.millisecondsSinceEpoch);
        // And one (re)schedule went to the OS under the stable id.
        expect(fake.scheduled, hasLength(1));
        expect(fake.scheduled.single.fireAtUtcMs, t2.toUtc());

        await raw.close();
      });
    },
  );

  testWidgets(
    'edit flow: clearing the follow-up cancels the OS alarm and removes the row',
    (WidgetTester tester) async {
      await tester.runAsync(() async {
        final ffi.Database raw = await _openInMemory();
        final AppDatabase db = AppDatabase.fromExisting(raw);
        final int id = await ClaimsRepository(db).create(_claim(0));

        final DateTime t1 = DateTime.utc(2026, 12, 18, 8, 0);
        await RemindersRepository(db).replaceForClaim(
          claimId: id,
          next: Reminder(
            id: 0,
            claimId: id,
            fireAtUtcMs: t1,
            notificationId: id,
            enabled: true,
            createdAtUtcMs: DateTime.utc(2026, 11, 1),
            updatedAtUtcMs: DateTime.utc(2026, 11, 1),
          ),
        );

        final FakeScheduler fake = FakeScheduler();
        final BuildContext ctx = await _context(tester);
        // `_claim` leaves nextFollowUpUtcMs null — the "user cleared it" case.
        await syncFollowUpAfterEdit(
          ctx,
          db,
          fake,
          before: _claim(id).copyWith(nextFollowUpUtcMs: t1),
          saved: _claim(id),
        );

        final List<Map<String, Object?>> rows = await raw.query(
          'reminders',
          where: 'claim_id = ?',
          whereArgs: [id],
        );
        expect(rows, isEmpty);
        expect(
          fake.cancelled,
          contains(id),
        ); // stable notificationId == claimId
        expect(fake.scheduled, isEmpty);

        await raw.close();
      });
    },
  );

  testWidgets(
    'edit flow: an UNCHANGED follow-up touches nothing (no re-schedule)',
    (WidgetTester tester) async {
      await tester.runAsync(() async {
        final ffi.Database raw = await _openInMemory();
        final AppDatabase db = AppDatabase.fromExisting(raw);
        final int id = await ClaimsRepository(db).create(_claim(0));

        final DateTime t1 = DateTime.utc(2026, 12, 18, 8, 0);
        await RemindersRepository(db).replaceForClaim(
          claimId: id,
          next: Reminder(
            id: 0,
            claimId: id,
            fireAtUtcMs: t1,
            notificationId: id,
            enabled: true,
            createdAtUtcMs: DateTime.utc(2026, 11, 1),
            updatedAtUtcMs: DateTime.utc(2026, 11, 1),
          ),
        );

        final FakeScheduler fake = FakeScheduler();
        final BuildContext ctx = await _context(tester);
        await syncFollowUpAfterEdit(
          ctx,
          db,
          fake,
          before: _claim(id).copyWith(nextFollowUpUtcMs: t1),
          saved: _claim(id).copyWith(nextFollowUpUtcMs: t1),
        );

        // No OS traffic at all — the existing alarm keeps running.
        expect(fake.scheduled, isEmpty);
        expect(fake.cancelled, isEmpty);
        final List<Map<String, Object?>> rows = await raw.query(
          'reminders',
          where: 'claim_id = ?',
          whereArgs: [id],
        );
        expect(rows, hasLength(1));

        await raw.close();
      });
    },
  );
}
