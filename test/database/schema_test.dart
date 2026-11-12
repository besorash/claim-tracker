/// Schema & migration smoke tests (spec §17, Phase 1 verification).
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart' as ffi;

import 'package:claim_tracker/core/database/app_database.dart';
import 'package:claim_tracker/core/models/claim.dart';

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

    test(
      'v1 → v2 rebuild keeps claims and history, swaps the column',
      () async {
        final ffi.Database db = await openInMemory();
        // Production runs migrations with foreign keys OFF (they are switched
        // on in onOpen), so mirror that here.
        await AppDatabase.migrate(db, from: 0, to: 1);
        final now = DateTime.now().toUtc().millisecondsSinceEpoch;
        await db.insert('claims', <String, Object?>{
          'customer_name': 'عميل قديم',
          'customer_mobile': '0501234567',
          'accident_date_utc_ms': now,
          'claim_number': 'CLM-OLD',
          'customer_insurance_company': 'شركة أ',
          'submitted_to_insurance_company': 'شركة ب',
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

        await AppDatabase.migrate(db, from: 1, to: 2);
        await db.execute('PRAGMA foreign_keys = ON');

        final List<String> columns = (await db.rawQuery(
          'PRAGMA table_info(claims)',
        )).map((r) => r['name']! as String).toList();
        expect(columns, contains('liability_percent'));
        expect(columns, isNot(contains('submitted_to_insurance_company')));

        final claims = await db.query('claims');
        expect(claims.single['claim_number'], 'CLM-OLD');
        expect(claims.single['liability_percent'], isNull);
        expect(
          (await db.rawQuery('SELECT COUNT(*) c FROM status_history'))
              .first['c'],
          1,
          reason: 'the rebuild must not cascade-delete history',
        );

        // Foreign keys still point at the rebuilt table: delete cascades.
        await db.delete('claims', where: 'id = ?', whereArgs: [1]);
        expect(
          (await db.rawQuery('SELECT COUNT(*) c FROM status_history'))
              .first['c'],
          0,
        );
        await db.close();
      },
    );

    test('v2 → v3 adds extra_fields and keeps existing claims', () async {
      final ffi.Database db = await openInMemory();
      await AppDatabase.migrate(db, from: 0, to: 2);
      final now = DateTime.now().toUtc().millisecondsSinceEpoch;
      await db.insert('claims', <String, Object?>{
        'customer_name': 'عميل',
        'customer_mobile': '0501234567',
        'accident_date_utc_ms': now,
        'claim_number': 'CLM-V2',
        'customer_insurance_company': 'شركة أ',
        'submission_date_utc_ms': now,
        'status_key': 'new',
        'last_status_update_utc_ms': now,
        'created_at_utc_ms': now,
        'updated_at_utc_ms': now,
      });

      await AppDatabase.migrate(db, from: 2, to: 3);

      final List<Claim> claims = (await db.query('claims'))
          .map(Claim.fromRow)
          .toList();
      expect(claims.single.claimNumber, 'CLM-V2');
      expect(claims.single.extraFields, isEmpty);

      // v3 → v4: vehicle type added, accident number kept.
      await db.update('claims', <String, Object?>{'accident_number': 'A-1'});
      await AppDatabase.migrate(db, from: 3, to: 4);
      final Claim v4 = Claim.fromRow((await db.query('claims')).single);
      expect(v4.claimNumber, 'CLM-V2');
      expect(v4.accidentNumber, 'A-1');
      expect(v4.vehicleType, isNull);
      await db.close();
    });

    test('v2 migration does not use ALTER TABLE DROP COLUMN', () async {
      // Android 13 and older ship SQLite < 3.35, where DROP COLUMN is a
      // syntax error and crashed the app on start. The host test SQLite is
      // newer, so check the migration source itself.
      final String source = File('lib/core/database/app_database.dart')
          .readAsStringSync();
      expect(
        RegExp(r"execute\([^)]*DROP COLUMN", dotAll: true).hasMatch(source),
        isFalse,
      );
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
