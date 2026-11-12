/// Claims CSV import/export against a real (in-memory) database: validation
/// blocks all writes, updates keep history and alarms in sync, new rows are
/// created. Pure Dart + FFI — no widget pumping needed.
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart' as ffi;

import 'package:claim_tracker/core/csv/claims_csv_service.dart';
import 'package:claim_tracker/core/database/app_database.dart';
import 'package:claim_tracker/core/database/claims_repository.dart';
import 'package:claim_tracker/core/database/status_history_repository.dart';
import 'package:claim_tracker/core/l10n/app_strings.dart';
import 'package:claim_tracker/core/models/claim.dart';
import 'package:claim_tracker/core/models/reminder.dart';
import 'package:claim_tracker/core/notifications/notification_service.dart';
import 'package:claim_tracker/core/notifications/reminder_scheduler.dart';
import 'package:claim_tracker/core/utils/time_utils.dart';
import 'package:claim_tracker/features/claims/claim_actions.dart';

/// Recording fake — proves which OS-side alarm calls the import makes.
class _FakeScheduler implements ReminderScheduler {
  final List<int> cancelled = <int>[];
  final List<Reminder> scheduled = <Reminder>[];

  @override
  Future<void> cancelReminder(int notificationId) async =>
      cancelled.add(notificationId);

  @override
  Future<AlarmPrecision> scheduleReminder(Reminder reminder) async {
    scheduled.add(reminder);
    return AlarmPrecision.exact;
  }

  @override
  Future<bool> areNotificationsEnabled() async => true;

  @override
  Future<NotificationPermissionState> requestNotificationsPermission() async =>
      NotificationPermissionState.granted;

  @override
  Future<void> reconcile(List<Reminder> enabledReminders) async {}

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
  late _FakeScheduler scheduler;
  late ClaimsCsvService service;

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
    scheduler = _FakeScheduler();
    service = ClaimsCsvService(db, scheduler);
  });

  tearDown(() async {
    await raw.close();
  });

  Future<int> seed({
    String name = 'عميل',
    String status = 'new',
    DateTime? followUp,
  }) {
    final DateTime t = DateTime.now().toUtc();
    return claims.create(
      Claim(
        id: 0,
        customerName: name,
        customerMobile: '0501234567',
        accidentDateUtcMs: DateTime(2026, 10, 1).toUtc(),
        claimNumber: 'CLM-${name.hashCode.abs()}-${t.microsecondsSinceEpoch}',
        customerInsuranceCompany: 'تعاونية',
        submissionDateUtcMs: DateTime(2026, 10, 5).toUtc(),
        liabilityPercent: 100,
        statusKey: status,
        lastStatusUpdateUtcMs: t,
        nextFollowUpUtcMs: followUp,
        createdAtUtcMs: t,
        updatedAtUtcMs: t,
      ),
    );
  }

  /// Export → text, so tests edit the same file the user would edit.
  Future<String> exportText() async {
    final List<int> bytes = await service.buildExport();
    // Skip the 3-byte BOM before decoding.
    return utf8.decode(bytes.sublist(3));
  }

  /// Replaces every cell of column [key] in the single data row of [csv].
  String setCell(String csv, String key, String value) {
    final List<String> lines = csv.split('\r\n');
    final List<String> header = lines.first.split(',');
    final List<String> cells = lines[1].split(',');
    cells[header.indexOf(key)] = value;
    return '${lines.first}\r\n${cells.join(',')}\r\n';
  }

  test('export writes a UTF-8 BOM and one row per claim', () async {
    await seed(name: 'أحمد');
    await seed(name: 'سالم');
    final List<int> bytes = await service.buildExport();

    expect(bytes.sublist(0, 3), <int>[0xEF, 0xBB, 0xBF]);
    final String text = utf8.decode(bytes.sublist(3));
    expect(text.split('\r\n').where((String l) => l.isNotEmpty), hasLength(3));
  });

  test('exporting and importing the same file changes nothing', () async {
    await seed(name: 'أحمد');
    await seed(name: 'سالم');

    final CsvImportReport report = await service.importText(await exportText());

    expect(report.hasErrors, isFalse);
    expect(report.created, 0);
    expect(report.updated, 2);
    expect(await claims.all(), hasLength(2));
  });

  test(
    'editing a row updates the claim and records the status change',
    () async {
      final int id = await seed(name: 'أحمد', status: 'new');
      final String csv = setCell(
        setCell(await exportText(), 'notes', 'ملاحظة جديدة'),
        'status_key',
        'approved',
      );

      final CsvImportReport report = await service.importText(csv);

      expect(report.hasErrors, isFalse);
      expect(report.updated, 1);
      final Claim updated = (await db.claimById(id))!;
      expect(updated.notes, 'ملاحظة جديدة');
      expect(updated.statusKey, 'approved');
      final history = await StatusHistoryRepository(db).listForClaim(id);
      expect(history.first.newStatusKey, 'approved');
      expect(history.first.previousStatusKey, 'new');
    },
  );

  test('a row without an id creates a new claim', () async {
    await seed(name: 'أحمد');
    final String file = setCell(await exportText(), 'id', '');

    final CsvImportReport report = await service.importText(file);

    expect(report.hasErrors, isFalse, reason: report.errors.join('\n'));
    expect(report.created, 1);
    expect(await claims.all(), hasLength(2));
  });

  test('an unknown id blocks the whole import and writes nothing', () async {
    final int id = await seed(name: 'أحمد');
    final String csv = setCell(await exportText(), 'id', '999999');

    final CsvImportReport report = await service.importText(csv);

    expect(report.hasErrors, isTrue);
    expect(report.errors.single, contains(S.csvErrorUnknownId));
    expect(report.created + report.updated, 0);
    expect((await db.claimById(id))!.customerName, 'أحمد');
  });

  test('one bad row among good rows writes nothing at all', () async {
    final int first = await seed(name: 'أحمد');
    await seed(name: 'سالم');
    final List<String> lines = (await exportText()).split('\r\n');
    // Break the second data row (liability 75 is not an allowed share).
    final List<String> header = lines.first.split(',');
    final List<String> bad = lines[2].split(',');
    bad[header.indexOf('liability_percent')] = '75';
    final String csv = '${lines.first}\r\n${lines[1]}\r\n${bad.join(',')}\r\n';

    final CsvImportReport report = await service.importText(csv);

    expect(report.hasErrors, isTrue);
    expect(report.updated, 0);
    // The good row was not applied either.
    expect((await db.claimById(first))!.notes, isNull);
  });

  test('duplicate ids in one file are rejected', () async {
    await seed(name: 'أحمد');
    final List<String> lines = (await exportText()).split('\r\n');
    final String csv = '${lines[0]}\r\n${lines[1]}\r\n${lines[1]}\r\n';

    final CsvImportReport report = await service.importText(csv);

    expect(report.hasErrors, isTrue);
    expect(report.updated, 0);
  });

  test('a future follow-up is saved and its alarm scheduled', () async {
    final int id = await seed(name: 'أحمد');
    final DateTime later = DateTime.now().toUtc().add(const Duration(days: 3));
    final String csv = setCell(
      await exportText(),
      'next_follow_up',
      _localStamp(later),
    );

    final CsvImportReport report = await service.importText(csv);

    expect(report.hasErrors, isFalse);
    expect(report.reminderFailures, 0);
    expect(scheduler.scheduled, hasLength(1));
    expect((await db.claimById(id))!.nextFollowUpUtcMs, isNotNull);
  });

  test('a past follow-up is saved without scheduling an alarm', () async {
    final int id = await seed(name: 'أحمد');
    final DateTime past = DateTime.now().toUtc().subtract(
      const Duration(days: 3),
    );
    final String csv = setCell(
      await exportText(),
      'next_follow_up',
      _localStamp(past),
    );

    final CsvImportReport report = await service.importText(csv);

    expect(report.hasErrors, isFalse);
    expect(report.reminderFailures, 0);
    expect(scheduler.scheduled, isEmpty);
    expect((await db.claimById(id))!.nextFollowUpUtcMs, isNotNull);
  });

  test(
    'clearing the follow-up cell cancels the alarm and clears the date',
    () async {
      final int id = await seed(name: 'أحمد');
      // A real follow-up: stored date plus its reminder row and alarm.
      await ClaimActions(db, scheduler).saveReminder(
        claimId: id,
        fireAtUtc: DateTime.now().toUtc().add(const Duration(days: 2)),
      );
      final String csv = setCell(await exportText(), 'next_follow_up', '');

      final CsvImportReport report = await service.importText(csv);

      expect(report.hasErrors, isFalse);
      expect(scheduler.cancelled, contains(id));
      expect((await db.claimById(id))!.nextFollowUpUtcMs, isNull);
    },
  );

  test('a follow-up exported and re-imported keeps its stored value', () async {
    final DateTime fireAt = DateTime(2026, 11, 20, 14, 30).toUtc();
    final int id = await seed(name: 'أحمد', followUp: fireAt);

    final CsvImportReport report = await service.importText(await exportText());

    expect(report.hasErrors, isFalse);
    expect((await db.claimById(id))!.nextFollowUpUtcMs, fireAt);
    expect(scheduler.scheduled, isEmpty);
  });
}

/// Local `yyyy-MM-dd HH:mm` stamp, the format the file uses for follow-ups.
String _localStamp(DateTime utc) {
  final DateTime l = utc.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${l.year}-${two(l.month)}-${two(l.day)} ${two(l.hour)}:${two(l.minute)}';
}
