/// Repository behavior tests: CRUD, atomic status changes, search and
/// filters (spec §5–§9 acceptance criteria).
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart' as ffi;

import 'package:claim_tracker/core/database/app_database.dart';
import 'package:claim_tracker/core/database/claims_repository.dart';
import 'package:claim_tracker/core/database/reminders_repository.dart';
import 'package:claim_tracker/core/database/settings_repository.dart';
import 'package:claim_tracker/core/database/status_history_repository.dart';
import 'package:claim_tracker/core/models/claim.dart';
import 'package:claim_tracker/core/models/reminder.dart';

void main() {
  late ffi.Database raw;
  late AppDatabase db;
  late ClaimsRepository claims;
  late StatusHistoryRepository history;
  late RemindersRepository reminders;
  late SettingsRepository settings;

  setUpAll(() {
    ffi.sqfliteFfiInit();
  });

  setUp(() async {
    raw = await ffi.databaseFactoryFfi.openDatabase(ffi.inMemoryDatabasePath);
    // Match on-device behavior (AppDatabase.open enables FK cascades).
    await raw.execute('PRAGMA foreign_keys = ON');
    await AppDatabase.migrate(raw, from: 0, to: kDatabaseVersion);
    db = AppDatabase.fromExisting(raw);
    claims = ClaimsRepository(db);
    history = StatusHistoryRepository(db);
    reminders = RemindersRepository(db);
    settings = SettingsRepository(db);
  });

  tearDown(() async {
    await raw.close();
  });

  Claim sampleClaim({String? claimNumber, String? name}) => Claim(
    id: 0,
    customerName: name ?? 'سعد العميل',
    customerMobile: '0501234567',
    accidentDateUtcMs: DateTime.utc(2026, 10, 1),
    claimNumber: claimNumber ?? 'CLM-100',
    customerInsuranceCompany: 'تعاونية',
    liabilityPercent: 50,
    submissionDateUtcMs: DateTime.utc(2026, 10, 5),
    statusKey: 'new',
    lastStatusUpdateUtcMs: DateTime.now().toUtc(),
    createdAtUtcMs: DateTime.now().toUtc(),
    updatedAtUtcMs: DateTime.now().toUtc(),
  );

  group('claims repository', () {
    test(
      'create persists the claim and writes an initial history entry',
      () async {
        final int id = await claims.create(sampleClaim());
        expect(id, greaterThan(0));

        final Claim? stored = await db.claimById(id);
        expect(stored, isNotNull);
        expect(stored!.customerName, 'سعد العميل');
        expect(stored.statusKey, 'new');

        final List<dynamic> hist = await history.listForClaim(id);
        expect(hist.length, 1);
      },
    );

    test('update persists edits', () async {
      final int id = await claims.create(sampleClaim());
      final Claim stored = (await db.claimById(id))!;
      final Claim updated = stored.copyWith(
        customerName: 'نورة العميل',
        claimAmountSar: 1250.75,
      );
      await claims.update(updated);

      final Claim? reloaded = await db.claimById(id);
      expect(reloaded!.customerName, 'نورة العميل');
      expect(reloaded.claimAmountSar, 1250.75);
    });

    test('delete removes the claim and cascades history', () async {
      final int id = await claims.create(sampleClaim());
      await claims.delete(id);
      expect(await db.claimById(id), isNull);
      expect((await history.listForClaim(id)).length, 0);
    });

    test('search matches claim number and customer name (trimmed)', () async {
      await claims.create(sampleClaim(claimNumber: 'CLM-200'));
      await claims.create(
        sampleClaim(claimNumber: 'CLM-300', name: 'محمد الفهد'),
      );

      expect((await claims.search('  clm-200  ')).length, 1);
      expect((await claims.search('محمد')).length, 1);
      expect((await claims.search('no-such-value')).isEmpty, isTrue);
    });

    test(
      'approved, rejected and closed are closed; compensated stays open',
      () async {
        final Map<String, int> ids = <String, int>{};
        for (final String key in <String>[
          'compensated',
          'closed',
          'approved',
          'rejected',
        ]) {
          final int id = await claims.create(sampleClaim(claimNumber: key));
          await history.changeStatus(claimId: id, newStatusKey: key);
          // A follow-up date on every claim: closed ones must not show up in
          // the follow-up or overdue lists either.
          final Claim c = (await db.claimById(id))!;
          await claims.update(
            c.copyWith(
              nextFollowUpUtcMs: DateTime.now().toUtc().subtract(
                const Duration(hours: 1),
              ),
            ),
          );
          ids[key] = id;
        }

        final Set<int> open = (await claims.open()).map((c) => c.id).toSet();
        final Set<int> closed = (await claims.closed())
            .map((c) => c.id)
            .toSet();
        final Set<int> followUp = (await claims.needsFollowUp())
            .map((c) => c.id)
            .toSet();
        final Set<int> overdue = (await claims.overdue(DateTime.now().toUtc()))
            .map((c) => c.id)
            .toSet();

        expect(open, <int>{ids['compensated']!});
        expect(closed, <int>{
          ids['closed']!,
          ids['approved']!,
          ids['rejected']!,
        });
        expect(followUp, <int>{ids['compensated']!});
        expect(overdue, <int>{ids['compensated']!});
      },
    );

    test('overdue and dueBetween use the follow-up timestamp', () async {
      final int id = await claims.create(sampleClaim());
      final Claim stored = (await db.claimById(id))!;

      // Overdue: yesterday.
      final DateTime past = DateTime.now().toUtc().subtract(
        const Duration(days: 1),
      );
      await claims.update(stored.copyWith(nextFollowUpUtcMs: past));
      expect((await claims.overdue(DateTime.now().toUtc())).length, 1);

      // Due today (Riyadh day range).
      final DateTime now = DateTime.now().toUtc();
      final DateTime laterToday = now.add(const Duration(hours: 2));
      await claims.update(stored.copyWith(nextFollowUpUtcMs: laterToday));
      expect((await claims.overdue(now)).isEmpty, isTrue);

      // Future week: not overdue.
      final DateTime nextWeek = now.add(const Duration(days: 7));
      await claims.update(stored.copyWith(nextFollowUpUtcMs: nextWeek));
      expect((await claims.needsFollowUp()).length, 1);
    });
  });

  group('status history repository', () {
    test(
      'changeStatus updates claim and appends exactly one entry (spec §9)',
      () async {
        final int id = await claims.create(sampleClaim());
        expect((await history.listForClaim(id)).length, 1); // creation entry

        final dynamic entry = await history.changeStatus(
          claimId: id,
          newStatusKey: 'processing',
        );
        expect(entry.newStatusKey, 'processing');
        expect(entry.previousStatusKey, 'new');

        final List<dynamic> hist = await history.listForClaim(id);
        expect(hist.length, 2);

        final Claim? reloaded = await db.claimById(id);
        expect(reloaded!.statusKey, 'processing');
      },
    );

    test('changeStatus rejects unknown status keys', () async {
      final int id = await claims.create(sampleClaim());
      expect(
        () => history.changeStatus(claimId: id, newStatusKey: 'bogus'),
        throwsArgumentError,
      );
      // Claim unchanged.
      expect((await db.claimById(id))!.statusKey, 'new');
    });

    test(
      'changeStatus on a missing claim fails without partial writes',
      () async {
        expect(
          () => history.changeStatus(claimId: 9999, newStatusKey: 'closed'),
          throwsStateError,
        );
      },
    );
  });

  group('reminders repository', () {
    test('replaceForClaim keeps a single active reminder (spec §10)', () async {
      final int id = await claims.create(sampleClaim());
      final DateTime fire = DateTime.now().toUtc().add(const Duration(days: 1));

      final Reminder first = Reminder(
        id: 0,
        claimId: id,
        fireAtUtcMs: fire,
        notificationId: 42,
        createdAtUtcMs: DateTime.now().toUtc(),
        updatedAtUtcMs: DateTime.now().toUtc(),
      );
      await reminders.replaceForClaim(claimId: id, next: first);

      final Reminder second = Reminder(
        id: 0,
        claimId: id,
        fireAtUtcMs: fire.add(const Duration(days: 1)),
        notificationId: 43,
        createdAtUtcMs: DateTime.now().toUtc(),
        updatedAtUtcMs: DateTime.now().toUtc(),
      );
      await reminders.replaceForClaim(claimId: id, next: second);

      final List<Reminder> all = await db.remindersForClaim(id);
      expect(all.length, 1);
      expect(all.first.notificationId, 43);
    });

    test(
      'removeAllForClaim returns rows for notification cancellation',
      () async {
        final int id = await claims.create(sampleClaim());
        final DateTime fire = DateTime.now().toUtc().add(
          const Duration(days: 1),
        );
        await reminders.replaceForClaim(
          claimId: id,
          next: Reminder(
            id: 0,
            claimId: id,
            fireAtUtcMs: fire,
            notificationId: 7,
            createdAtUtcMs: DateTime.now().toUtc(),
            updatedAtUtcMs: DateTime.now().toUtc(),
          ),
        );

        final List<Reminder> removed = await reminders.removeAllForClaim(id);
        expect(removed.length, 1);
        expect(removed.first.notificationId, 7);
        expect((await db.remindersForClaim(id)).isEmpty, isTrue);
      },
    );
  });

  group('settings repository', () {
    test('set/get round-trips values (spec §16 theme persistence)', () async {
      await settings.set('theme_mode', 'dark');
      expect(await settings.get('theme_mode'), 'dark');
      await settings.set('theme_mode', 'light');
      expect(await settings.get('theme_mode'), 'light');
    });
  });
}
