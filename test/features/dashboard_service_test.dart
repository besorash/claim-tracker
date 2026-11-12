/// Dashboard metrics tests: every number must come from SQLite (spec §5).
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart' as ffi;

import 'package:claim_tracker/core/database/app_database.dart';
import 'package:claim_tracker/core/database/claims_repository.dart';
import 'package:claim_tracker/core/models/claim.dart';
import 'package:claim_tracker/core/utils/time_utils.dart';
import 'package:claim_tracker/features/dashboard/dashboard_service.dart';

void main() {
  late ffi.Database raw;
  late AppDatabase db;
  late ClaimsRepository claims;
  late DashboardService service;

  setUpAll(() async {
    ffi.sqfliteFfiInit();
    await TimeUtils.ensureInitialized();
  });

  setUp(() async {
    raw = await ffi.databaseFactoryFfi.openDatabase(ffi.inMemoryDatabasePath);
    await raw.execute('PRAGMA foreign_keys = ON');
    await AppDatabase.migrate(raw, from: 0, to: kDatabaseVersion);
    db = AppDatabase.fromExisting(raw);
    claims = ClaimsRepository(db);
    service = DashboardService(claims);
  });

  tearDown(() async {
    await raw.close();
  });

  Claim seed({
    required String statusKey,
    DateTime? followUpUtcMs,
    String name = 'عميل',
  }) => Claim(
    id: 0,
    customerName: name,
    customerMobile: '0501234567',
    accidentDateUtcMs: DateTime.utc(2026, 10, 1),
    claimNumber: 'CLM-${name.hashCode.abs() % 900 + 100}',
    customerInsuranceCompany: 'تعاونية',
    submittedToInsuranceCompany: 'بوبا',
    submissionDateUtcMs: DateTime.utc(2026, 10, 5),
    statusKey: statusKey,
    lastStatusUpdateUtcMs: DateTime.now().toUtc(),
    nextFollowUpUtcMs: followUpUtcMs,
    createdAtUtcMs: DateTime.now().toUtc(),
    updatedAtUtcMs: DateTime.now().toUtc(),
  );

  Future<int> create(Claim c) => claims.create(c);

  group('DashboardService.metrics', () {
    test('counts total/open/closed/due-today/overdue from the database — '
        'compensated stays OPEN (spec §5)', () async {
      final DateTime now = DateTime.now().toUtc();
      // "Due today" must be seeded inside the current Riyadh day regardless of
      // what time the test runs: a fixed `now + 2h` offset crosses midnight
      // after ~22:00 local and silently stops counting as due-today.
      final DateTime dayEnd = TimeUtils.riyadhDayRange(now).$2;
      await create(seed(statusKey: 'new')); // plain open, no follow-up
      await create(seed(statusKey: 'compensated')); // open per spec §5
      await create(seed(statusKey: 'closed')); // the only closed one
      await create(
        seed(
          statusKey: 'new',
          followUpUtcMs: now.subtract(const Duration(hours: 24)),
        ),
      ); // overdue
      await create(
        seed(statusKey: 'new', followUpUtcMs: dayEnd),
      ); // due today (within the Riyadh day)

      final DashboardMetrics m = await service.metrics();
      expect(m.total, 5);
      expect(m.open, 4);
      expect(m.closed, 1);
      expect(m.dueToday, 1);
      expect(m.overdue, 1);
    });

    test('empty database reports all zeros (no hardcoded values)', () async {
      final DashboardMetrics m = await service.metrics();
      expect(m.total, 0);
      expect(m.open, 0);
      expect(m.closed, 0);
      expect(m.dueToday, 0);
      expect(m.overdue, 0);
    });
  });

  group('DashboardService.needsAttention', () {
    test('overdue first, then due-today, capped at limit (spec §5)', () async {
      final DateTime now = DateTime.now().toUtc();
      final DateTime dayEnd = TimeUtils.riyadhDayRange(now).$2;
      await create(seed(statusKey: 'new')); // filler
      await create(
        seed(
          statusKey: 'new',
          followUpUtcMs: now.subtract(const Duration(hours: 24)),
          name: 'متأخر',
        ),
      );
      await create(
        seed(statusKey: 'new', followUpUtcMs: dayEnd, name: 'اليوم'),
      );

      final List<NeedsAttentionItem> items = await service.needsAttention(
        limit: 3,
      );
      expect(items.length, lessThanOrEqualTo(3));
      expect(items.first.claim.customerName, 'متأخر');
      expect(items.first.isOverdue, isTrue);
      expect(items[1].claim.customerName, 'اليوم');
      expect(items[1].isOverdue, isFalse);
    });

    test('empty database returns an empty list', () async {
      final List<NeedsAttentionItem> items = await service.needsAttention();
      expect(items, isEmpty);
    });
  });
}
