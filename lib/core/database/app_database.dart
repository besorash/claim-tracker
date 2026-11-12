/// SQLite database for Claim Tracker (spec §13).
///
/// Library choice: **sqflite** — maintained, minimal, first-class Android
/// support, simple migration API (`onUpgrade`), and a pure-Dart FFI backend
/// (`sqflite_common_ffi`) that lets the exact same schema code run in host
/// unit tests. Drift was considered but adds a code-generation step without
/// benefit at this project's scale (documented per spec §13).
library;

import 'package:sqflite/sqflite.dart' as sqf;

import '../models/attachment.dart';
import '../models/claim.dart';
import '../models/insurance_company.dart';
import '../models/reminder.dart';
import '../models/status_history_entry.dart';

/// Current schema version. Bump and add an upgrade step in [migrate] when the
/// shape of any table changes (spec §13: database migrations).
const int kDatabaseVersion = 1;

class AppDatabase {
  AppDatabase(this._db);

  /// Opens (and migrates) the on-device database.
  static Future<AppDatabase> open({String? path}) async {
    final sqf.Database db = await sqf.openDatabase(
      path ?? '${await sqf.getDatabasesPath()}/claim_tracker.sqlite',
      version: kDatabaseVersion,
      onConfigure: (sqf.Database db) async {
        await db.execute('PRAGMA foreign_keys = ON');
      },
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
    return AppDatabase(db);
  }

  /// Wraps an already-open database (used by tests with the FFI backend).
  factory AppDatabase.fromExisting(sqf.Database db) => AppDatabase(db);

  final sqf.Database _db;

  sqf.Database get rawDb => _db;

  Future<void> close() => _db.close();

  // ---------------------------------------------------------------------------
  // Schema
  // ---------------------------------------------------------------------------

  static Future<void> _onCreate(sqf.Database db, int version) async {
    await migrate(db, from: 0, to: kDatabaseVersion);
  }

  static Future<void> _onUpgrade(
    sqf.Database db,
    int oldVersion,
    int newVersion,
  ) async {
    await migrate(db, from: oldVersion, to: newVersion);
  }

  /// Sequential migration runner. Each step is idempotent within a single
  /// transaction so a failed upgrade rolls back cleanly (spec §13).
  static Future<void> migrate(
    sqf.Database db, {
    required int from,
    required int to,
  }) async {
    if (from >= to) return;

    await db.transaction((sqf.Transaction txn) async {
      for (var v = from + 1; v <= to; v++) {
        switch (v) {
          case 1:
            await _createSchemaV1(txn);
          // Future versions add cases here, e.g.:
          // case 2: await _migrateToV2(txn);
        }
      }
    });
  }

  static Future<void> _createSchemaV1(sqf.Transaction txn) async {
    await txn.execute('''
      CREATE TABLE claims (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        customer_name TEXT NOT NULL,
        customer_mobile TEXT NOT NULL,
        customer_national_id TEXT,
        customer_email TEXT,
        accident_number TEXT,
        accident_date_utc_ms INTEGER NOT NULL,
        accident_city TEXT,
        accident_type TEXT,
        vehicle_plate TEXT,
        claim_number TEXT NOT NULL,
        customer_insurance_company TEXT NOT NULL,
        submitted_to_insurance_company TEXT NOT NULL,
        submission_date_utc_ms INTEGER NOT NULL,
        insurer_reference_number TEXT,
        claim_amount_sar REAL,
        notes TEXT,
        status_key TEXT NOT NULL DEFAULT 'new',
        last_status_update_utc_ms INTEGER NOT NULL,
        next_follow_up_utc_ms INTEGER,
        reminder_enabled INTEGER NOT NULL DEFAULT 0,
        created_at_utc_ms INTEGER NOT NULL,
        updated_at_utc_ms INTEGER NOT NULL
      )
    ''');

    await txn.execute('''
      CREATE TABLE status_history (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        claim_id INTEGER NOT NULL REFERENCES claims(id) ON DELETE CASCADE,
        previous_status_key TEXT NOT NULL,
        new_status_key TEXT NOT NULL,
        changed_at_utc_ms INTEGER NOT NULL,
        note TEXT
      )
    ''');

    await txn.execute('''
      CREATE TABLE reminders (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        claim_id INTEGER NOT NULL REFERENCES claims(id) ON DELETE CASCADE,
        fire_at_utc_ms INTEGER NOT NULL,
        notification_id INTEGER NOT NULL UNIQUE,
        repeat_interval_hours INTEGER,
        enabled INTEGER NOT NULL DEFAULT 1,
        created_at_utc_ms INTEGER NOT NULL,
        updated_at_utc_ms INTEGER NOT NULL
      )
    ''');

    await txn.execute('''
      CREATE TABLE attachments (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        claim_id INTEGER NOT NULL REFERENCES claims(id) ON DELETE CASCADE,
        original_name TEXT NOT NULL,
        mime_type TEXT NOT NULL,
        size_bytes INTEGER NOT NULL,
        relative_path TEXT NOT NULL UNIQUE,
        created_at_utc_ms INTEGER NOT NULL
      )
    ''');

    await txn.execute('''
      CREATE TABLE insurance_companies (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL UNIQUE COLLATE NOCASE
      )
    ''');

    await txn.execute('''
      CREATE TABLE app_settings (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL
      )
    ''');

    // Indexes for frequently searched fields (spec §13).
    await txn.execute(
      'CREATE INDEX idx_claims_claim_number ON claims(claim_number)',
    );
    await txn.execute(
      'CREATE INDEX idx_claims_customer_name ON claims(customer_name)',
    );
    await txn.execute(
      'CREATE INDEX idx_claims_customer_mobile ON claims(customer_mobile)',
    );
    await txn.execute(
      'CREATE INDEX idx_claims_accident_number ON claims(accident_number)',
    );
    await txn.execute(
      'CREATE INDEX idx_claims_insurer_ref '
      'ON claims(insurer_reference_number)',
    );
    await txn.execute('CREATE INDEX idx_claims_status ON claims(status_key)');
    await txn.execute(
      'CREATE INDEX idx_claims_next_follow_up ON claims(next_follow_up_utc_ms)',
    );
    await txn.execute(
      'CREATE INDEX idx_history_claim ON status_history(claim_id, changed_at_utc_ms)',
    );
    await txn.execute(
      'CREATE INDEX idx_reminders_claim ON reminders(claim_id)',
    );
    await txn.execute(
      'CREATE INDEX idx_attachments_claim ON attachments(claim_id)',
    );
  }

  // ---------------------------------------------------------------------------
  // Convenience accessors (kept thin; repositories own the queries).
  // ---------------------------------------------------------------------------

  Future<List<Claim>> allClaims() async {
    final List<Map<String, Object?>> rows = await _db.query('claims');
    return rows.map(Claim.fromRow).toList();
  }

  Future<Claim?> claimById(int id) async {
    final List<Map<String, Object?>> rows = await _db.query(
      'claims',
      where: 'id = ?',
      whereArgs: [id],
    );
    if (rows.isEmpty) return null;
    return Claim.fromRow(rows.first);
  }

  Future<List<StatusHistoryEntry>> historyForClaim(int claimId) async {
    final List<Map<String, Object?>> rows = await _db.query(
      'status_history',
      where: 'claim_id = ?',
      whereArgs: [claimId],
      orderBy: 'changed_at_utc_ms DESC, id DESC',
    );
    return rows.map(StatusHistoryEntry.fromRow).toList();
  }

  Future<List<Reminder>> remindersForClaim(int claimId) async {
    final List<Map<String, Object?>> rows = await _db.query(
      'reminders',
      where: 'claim_id = ?',
      whereArgs: [claimId],
      orderBy: 'fire_at_utc_ms ASC',
    );
    return rows.map(Reminder.fromRow).toList();
  }

  Future<List<Attachment>> attachmentsForClaim(int claimId) async {
    final List<Map<String, Object?>> rows = await _db.query(
      'attachments',
      where: 'claim_id = ?',
      whereArgs: [claimId],
      orderBy: 'created_at_utc_ms ASC, id ASC',
    );
    return rows.map(Attachment.fromRow).toList();
  }

  Future<List<InsuranceCompany>> insuranceCompanies() async {
    final List<Map<String, Object?>> rows = await _db.query(
      'insurance_companies',
      orderBy: 'name COLLATE NOCASE ASC',
    );
    return rows.map(InsuranceCompany.fromRow).toList();
  }

  Future<String?> setting(String key) async {
    final List<Map<String, Object?>> rows = await _db.query(
      'app_settings',
      where: 'key = ?',
      whereArgs: [key],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return rows.first['value'] as String?;
  }

  Future<void> setSetting(String key, String value) => _db.insert(
    'app_settings',
    <String, Object?>{'key': key, 'value': value},
    conflictAlgorithm: sqf.ConflictAlgorithm.replace,
  );
}
