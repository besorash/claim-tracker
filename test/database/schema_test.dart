/// Schema & migration smoke tests (spec §17, Phase 1 verification).
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart' as ffi;

import 'package:claim_tracker/core/database/app_database.dart';

void main() {
  setUpAll(() {
    // Use the pure-Dart SQLite backend so tests run on the host (no device).
    ffi.sqfliteFfiInit();
  });

  TestWidgetsFlutterBinding.ensureInitialized();

  Future<ffi.Database> openInMemory() async {
    final factory = ffi.databaseFactoryFfi;
    return factory.openDatabase(ffi.inMemoryDatabasePath);
  }

  group('schema v1', () {
    test('creates all six tables (spec §13)', () async {
      final ffi.Database db = await openInMemory();
      await AppDatabase.migrate(db, from: 0, to: kDatabaseVersion);

      final List<Map<String, Object?>> rows = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table'",
      );
      final Set<String> tables = rows.map((r) => r['name']! as String).toSet();

      expect(
        tables,
        containsAll(<String>{
          'claims',
          'status_history',
          'reminders',
          'attachments',
          'insurance_companies',
          'app_settings',
        }),
      );
      await db.close();
    });

    test('creates the spec §13 indexes on claims', () async {
      final ffi.Database db = await openInMemory();
      await AppDatabase.migrate(db, from: 0, to: kDatabaseVersion);

      final List<Map<String, Object?>> rows = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='index'",
      );
      final Set<String> indexes = rows.map((r) => r['name']! as String).toSet();

      expect(
        indexes,
        containsAll(<String>{
          'idx_claims_claim_number',
          'idx_claims_customer_name',
          'idx_claims_customer_mobile',
          'idx_claims_accident_number',
          'idx_claims_insurer_ref',
          'idx_claims_status',
          'idx_claims_next_follow_up',
        }),
      );
      await db.close();
    });

    test('enables foreign keys and cascades deletes (spec §13)', () async {
      final ffi.Database db = await openInMemory();
      // PRAGMA foreign_keys is per-connection: AppDatabase.open() sets it in
      // onConfigure; the raw FFI connection here must do the same.
      await db.execute('PRAGMA foreign_keys = ON');
      await AppDatabase.migrate(db, from: 0, to: kDatabaseVersion);

      final int fk =
          (await db.rawQuery('PRAGMA foreign_keys')).first['foreign_keys']!
              as int;
      expect(fk, 1);

      // Insert a claim + history row, delete the claim, verify cascade.
      final now = DateTime.now().toUtc().millisecondsSinceEpoch;
      await db.insert('claims', <String, Object?>{
        'customer_name': 'عميل تجريبي',
        'customer_mobile': '0501234567',
        'accident_date_utc_ms': now,
        'claim_number': 'CLM-1',
        'customer_insurance_company': 'شركة أ',
        'liability_percent': 50,
        'submission_date_utc_ms': now,
        'status_key': 'new',
        'last_status_update_utc_ms': now,
        'created_at_utc_ms': now,
        'updated_at_utc_ms': now,
      });
      await db.insert('status_history', <String, Object?>{
        'claim_id': 1,
        'previous_status_key': '',
        'new_status_key': 'new',
        'changed_at_utc_ms': now,
      });

      final int before =
          (await db.rawQuery('SELECT COUNT(*) c FROM status_history'))
                  .first['c']!
              as int;
      expect(before, 1);

      await db.delete('claims', where: 'id = ?', whereArgs: [1]);

      final int after =
          (await db.rawQuery('SELECT COUNT(*) c FROM status_history'))
                  .first['c']!
              as int;
      expect(after, 0, reason: 'history must cascade with the claim');
      await db.close();
    });

    test('migration is idempotent when from == to', () async {
      final ffi.Database db = await openInMemory();
      // No-op migration must not throw.
      await AppDatabase.migrate(
        db,
        from: kDatabaseVersion,
        to: kDatabaseVersion,
      );
      await db.close();
    });

    test(
      'AppDatabase.fromExisting exposes repositories over the same DB',
      () async {
        final ffi.Database db = await openInMemory();
        await AppDatabase.migrate(db, from: 0, to: kDatabaseVersion);

        final AppDatabase appDb = AppDatabase.fromExisting(db);
        expect(await appDb.allClaims(), isEmpty);
        expect(await appDb.insuranceCompanies(), isEmpty);
        await appDb.close();
      },
    );
  });
}
