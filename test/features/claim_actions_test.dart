/// ClaimActions orchestration tests (spec §9–§10): close/delete cancel the
/// OS-side alarms, status changes stay atomic with history, and follow-up
/// choices persist correctly. Pure Dart + FFI — no widget pumping needed.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart' as ffi;

import 'package:claim_tracker/core/database/app_database.dart';
import 'package:claim_tracker/core/database/claims_repository.dart';
import 'package:claim_tracker/core/database/reminders_repository.dart';
import 'package:claim_tracker/core/database/status_history_repository.dart';
import 'package:claim_tracker/core/models/claim.dart';
import 'package:claim_tracker/core/models/reminder.dart';
import 'package:claim_tracker/core/notifications/notification_service.dart';
import 'package:claim_tracker/core/notifications/reminder_scheduler.dart';
import 'package:claim_tracker/core/utils/time_utils.dart';
import 'package:claim_tracker/features/claims/claim_actions.dart';

/// Recording fake — proves which OS-side calls the orchestration makes.
class FakeScheduler implements ReminderScheduler {
  final List<int> cancelled = [];
  final List<Reminder> scheduled = [];
  final List<List<Reminder>> reconciled = [];
  bool enabled = true;
  bool throwOnCancel = false;

  @override
  Future<void> cancelReminder(int notificationId) async {
    if (throwOnCancel) throw StateError('OS alarm service unavailable');
    cancelled.add(notificationId);
  }

  @override
  Future<AlarmPrecision> scheduleReminder(Reminder reminder) async {
    scheduled.add(reminder);
    return AlarmPrecision.exact;
  }

  @override
  Future<bool> areNotificationsEnabled() async => enabled;

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

void main() {
  late ffi.Database raw;
  late AppDatabase db;
  late ClaimsRepository claims;
  late RemindersRepository reminders;
  late FakeScheduler fake;
  late ClaimActions actions;

  setUpAll(() async {
    ffi.sqfliteFfiInit();
    ffi.databaseFactory = ffi.databaseFactoryFfi;
    await TimeUtils.ensureInitialized();
  });

  setUp(() async {
    raw = await ffi.databaseFactoryFfi.openDatabase(ffi.inMemoryDatabasePath);
    await raw.execute('PRAGMA foreign_keys = ON');
    await AppDatabase.migrate(raw, from: 0, to: kDatabaseVersion);
    db = AppDatabase.fromExisting(raw);
    claims = ClaimsRepository(db);
    reminders = RemindersRepository(db);
    fake = FakeScheduler();
    actions = ClaimActions(db, fake);
  });

  tearDown(() async {
    await raw.close();
  });

  Future<int> seedClaim({String statusKey = 'new'}) => claims.create(
    Claim(
      id: 0,
      customerName: 'عميل',
      customerMobile: '0501234567',
      accidentDateUtcMs: DateTime.utc(2026, 10, 1),
      claimNumber: 'CLM-ACT-${DateTime.now().microsecondsSinceEpoch % 9999}',
      customerInsuranceCompany: 'تعاونية',
      submittedToInsuranceCompany: 'بوبا',
      submissionDateUtcMs: DateTime.utc(2026, 10, 5),
      statusKey: statusKey,
      lastStatusUpdateUtcMs: DateTime.now().toUtc(),
      createdAtUtcMs: DateTime.now().toUtc(),
      updatedAtUtcMs: DateTime.now().toUtc(),
    ),
  );

  Future<Reminder> seedReminder(int claimId) => reminders.replaceForClaim(
    claimId: claimId,
    next: Reminder(
      id: 0,
      claimId: claimId,
      fireAtUtcMs: DateTime.now().toUtc().add(const Duration(days: 1)),
      notificationId: claimId,
      enabled: true,
      createdAtUtcMs: DateTime.now().toUtc(),
      updatedAtUtcMs: DateTime.now().toUtc(),
    ),
  );

  test('closeClaim cancels the pending reminder and records history', () async {
    final int id = await seedClaim();
    await seedReminder(id);

    await actions.closeClaim(id);

    expect((await db.claimById(id))!.statusKey, 'closed');
    // Creation entry (spec §9) + the close change.
    final List<dynamic> history = await StatusHistoryRepository(db)
        .listForClaim(id);
    expect(history.length, 2);
    expect(await reminders.allEnabled(), isEmpty);
    expect(fake.cancelled, contains(id));
  });

  test('closeClaim survives a throwing scheduler', () async {
    final int id = await seedClaim();
    await seedReminder(id);
    fake.throwOnCancel = true;

    await actions.closeClaim(id); // must not throw

    expect((await db.claimById(id))!.statusKey, 'closed');
    expect(await reminders.allEnabled(), isEmpty);
  });

  test('deleteClaim cancels reminders before deleting the row', () async {
    final int id = await seedClaim();
    await seedReminder(id);

    await actions.deleteClaim(id);

    expect(await db.claimById(id), isNull);
    expect(await reminders.allEnabled(), isEmpty);
    expect(fake.cancelled, contains(id));
  });

  test('changeStatus with SetFollowUp persists status AND schedules', () async {
    final int id = await seedClaim();
    final DateTime fireAt = DateTime.now().toUtc().add(const Duration(days: 2));

    await actions.changeStatus(
      id,
      'submitted',
      note: 'ملاحظة',
      followUp: SetFollowUp(fireAt),
    );

    final Claim updated = (await db.claimById(id))!;
    expect(updated.statusKey, 'submitted');
    expect(updated.nextFollowUpUtcMs, isNotNull);
    // Creation entry (spec §9) + the status change.
    final List<dynamic> history = await StatusHistoryRepository(db)
        .listForClaim(id);
    expect(history.length, 2);
    expect(fake.scheduled.single.notificationId, id);
  });

  test('changeStatus with KeepFollowUp does not touch reminders', () async {
    final int id = await seedClaim();
    await seedReminder(id);

    await actions.changeStatus(id, 'submitted', followUp: const KeepFollowUp());

    expect((await db.claimById(id))!.statusKey, 'submitted');
    expect((await reminders.allEnabled()).length, 1);
    expect(fake.cancelled, isEmpty);
  });

  // ---------------------------------------------------------------------------
  // BUG A regression guard (spec §10): multiple claims must each own an
  // independent reminder — creating/editing/deleting one never touches the
  // others, and every row stays bound to its claim id.
  // ---------------------------------------------------------------------------

  test('BUG A: three claims keep independent reminders end-to-end', () async {
    final int a = await seedClaim();
    final int b = await seedClaim();
    final int c = await seedClaim();
    final DateTime t1 = DateTime.now().toUtc().add(const Duration(days: 1));
    final DateTime t2 = DateTime.now().toUtc().add(const Duration(days: 2));
    final DateTime t3 = DateTime.now().toUtc().add(const Duration(days: 3));

    // Create one reminder per claim — all three must be scheduled.
    await actions.saveReminder(claimId: a, fireAtUtc: t1);
    await actions.saveReminder(claimId: b, fireAtUtc: t2);
    await actions.saveReminder(claimId: c, fireAtUtc: t3);

    final List<Reminder> all = await reminders.allEnabled();
    expect(all.length, 3);
    // Each reminder is bound to its own claim with a unique notification id.
    for (final Reminder r in all) {
      expect(r.claimId, anyOf(a, b, c));
      expect(r.notificationId, r.claimId); // stable per-claim alarm identity
    }
    final Set<int> ids = all.map((Reminder r) => r.notificationId).toSet();
    expect(ids.length, 3); // no id collisions across claims
    expect(fake.scheduled.length, 3);

    // EDIT claim b's reminder — a and c must be untouched.
    await actions.saveReminder(
      claimId: b,
      fireAtUtc: t2.add(const Duration(hours: 5)),
    );
    final List<Reminder> afterEdit = await reminders.allEnabled();
    expect(afterEdit.length, 3); // no rows added or removed by the edit
    final Reminder aRow = afterEdit.firstWhere((r) => r.claimId == a);
    final Reminder bRow = afterEdit.firstWhere((r) => r.claimId == b);
    final Reminder cRow = afterEdit.firstWhere((r) => r.claimId == c);
    // The DB stores millisecond precision — compare epoch millis.
    expect(
      aRow.fireAtUtcMs.millisecondsSinceEpoch,
      t1.toUtc().millisecondsSinceEpoch,
    ); // a unchanged
    expect(
      cRow.fireAtUtcMs.millisecondsSinceEpoch,
      t3.toUtc().millisecondsSinceEpoch,
    ); // c unchanged
    expect(
      bRow.fireAtUtcMs.millisecondsSinceEpoch,
      t2.add(const Duration(hours: 5)).toUtc().millisecondsSinceEpoch,
    );

    // DELETE claim b's reminder — a and c must survive.
    await actions.clearFollowUp(b);
    final List<Reminder> afterDelete = await reminders.allEnabled();
    expect(afterDelete.length, 2);
    expect(afterDelete.map((r) => r.claimId).toSet(), <int>{a, c});
    // Only b's alarm was cancelled — a and c alarms were never touched.
    expect(fake.cancelled, contains(b));
    expect(fake.cancelled, isNot(contains(a)));
    expect(fake.cancelled, isNot(contains(c)));

    // Persistence across "restart": the rows are plain SQLite state keyed by
    // claim id — re-reading through a fresh repository sees all three claims'
    // data intact (a and c reminders enabled, b cleared).
    final RemindersRepository fresh = RemindersRepository(db);
    expect((await fresh.latestForClaim(a))?.enabled, isTrue);
    expect(await fresh.latestForClaim(b), isNull);
    expect((await fresh.latestForClaim(c))?.enabled, isTrue);
  });

  test('BUG A: closing one claim cancels only its own alarm', () async {
    final int a = await seedClaim();
    final int b = await seedClaim();
    await actions.saveReminder(
      claimId: a,
      fireAtUtc: DateTime.now().toUtc().add(const Duration(days: 1)),
    );
    await actions.saveReminder(
      claimId: b,
      fireAtUtc: DateTime.now().toUtc().add(const Duration(days: 2)),
    );

    await actions.closeClaim(a);

    expect((await db.claimById(a))!.statusKey, 'closed');
    // b's reminder and alarm are untouched by a's close.
    final List<Reminder> remaining = await reminders.allEnabled();
    expect(remaining.length, 1);
    expect(remaining.single.claimId, b);
    expect(fake.cancelled, contains(a));
    expect(fake.cancelled, isNot(contains(b)));
  });
}
