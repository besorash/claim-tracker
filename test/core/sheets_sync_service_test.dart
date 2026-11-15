/// Google Sheets two-way sync against a real (in-memory) database and an
/// in-memory sheet that follows the same pull/push rules as
/// tools/google_sheets_sync/Code.gs.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart' as ffi;

import 'package:claim_tracker/core/csv/claims_csv_service.dart';
import 'package:claim_tracker/core/database/app_database.dart';
import 'package:claim_tracker/core/database/claims_repository.dart';
import 'package:claim_tracker/core/models/claim.dart';
import 'package:claim_tracker/core/models/reminder.dart';
import 'package:claim_tracker/core/notifications/notification_service.dart';
import 'package:claim_tracker/core/notifications/reminder_scheduler.dart';
import 'package:claim_tracker/core/sync/sheets_sync_service.dart';
import 'package:claim_tracker/core/utils/time_utils.dart';
import 'package:claim_tracker/features/claims/claim_actions.dart';

class _NoopScheduler implements ReminderScheduler {
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

/// The sheet as Code.gs sees it: a header row plus rows of text cells.
class _FakeSheet {
  _FakeSheet(this.header);

  final List<String> header;
  final List<List<String>> rows = <List<String>>[];
  bool failPush = false;
  int pushes = 0;

  int col(String key) => header.indexOf(key);

  List<String> addRow(Map<String, String> values) {
    final List<String> row = <String>[
      for (final String h in header) values[h] ?? '',
    ];
    rows.add(row);
    return row;
  }

  List<String>? rowWithId(Object id) {
    for (final List<String> r in rows) {
      if (r[col('id')] == '$id') return r;
    }
    return null;
  }

  Future<Map<String, Object?>> call(Uri url, Map<String, Object?> body) async {
    expect(body['token'], 'secret');
    if (body['action'] == 'pull') {
      return <String, Object?>{
        'ok': true,
        'header': List<String>.of(header),
        'rows': <List<String>>[for (final r in rows) List<String>.of(r)],
      };
    }
    pushes++;
    if (failPush) throw const SheetsSyncException('boom');
    int misses = 0;
    for (final Object? s in body['setIds']! as List<Object?>) {
      final Map<String, Object?> m = s! as Map<String, Object?>;
      final int i = (m['row']! as int) - 2;
      if (i >= 0 && i < rows.length && rows[i][col('id')] == m['old']) {
        rows[i][col('id')] = '${m['id']}';
      } else {
        misses++;
      }
    }
    for (final Object? u in body['upserts']! as List<Object?>) {
      final Map<String, String> m = u! as Map<String, String>;
      for (final String k in m.keys) {
        if (!header.contains(k)) {
          header.add(k);
          for (final List<String> r in rows) {
            r.add('');
          }
        }
      }
      final List<String> row =
          rowWithId(m['id']!) ?? addRow(<String, String>{});
      m.forEach((String k, String v) => row[col(k)] = v);
    }
    for (final Object? id in body['deletes']! as List<Object?>) {
      rows.remove(rowWithId(id!));
    }
    return <String, Object?>{'ok': true, 'idMisses': misses};
  }
}

void main() {
  late ffi.Database raw;
  late AppDatabase db;
  late ClaimsRepository claims;
  late SheetsSyncService sync;
  late _FakeSheet sheet;

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
    // The user's sheet: the app's export columns (no insurance_mobile) plus
    // the script's updated_at stamp.
    sheet = _FakeSheet(<String>[
      'id',
      'customer_name',
      'customer_mobile',
      'accident_date',
      'vehicle_plate',
      'vehicle_type',
      'claim_number',
      'customer_insurance_company',
      'notes',
      'status_key',
      'updated_at',
    ]);
    final ClaimsCsvService csv = ClaimsCsvService(db, _NoopScheduler());
    sync = SheetsSyncService(db, csv, transport: sheet.call);
    await db.setSetting(SheetsSyncService.urlKey, 'https://example.test/exec');
    await db.setSetting(SheetsSyncService.tokenKey, 'secret');
  });

  tearDown(() => raw.close());

  Future<int> seed(String name, {String notes = ''}) {
    final DateTime t = DateTime.utc(2026, 1, 1);
    return claims.create(
      Claim(
        id: 0,
        customerName: name,
        customerMobile: '',
        vehiclePlate: '1234 ABC',
        vehicleType: 'Camry',
        accidentDateUtcMs: DateTime(2026, 10, 1).toUtc(),
        claimNumber: 'C-$name',
        customerInsuranceCompany: 'GIG',
        notes: notes.isEmpty ? null : notes,
        statusKey: 'new',
        lastStatusUpdateUtcMs: t,
        createdAtUtcMs: t,
        updatedAtUtcMs: t,
      ),
    );
  }

  Future<void> editNotes(int id, String notes, DateTime at) async {
    final Claim c = (await db.claimById(id))!;
    await claims.update(c.copyWith(notes: notes, updatedAtUtcMs: at));
  }

  test(
    'http transport follows the 302 Apps Script answers a POST with',
    () async {
      final HttpServer server = await HttpServer.bind('127.0.0.1', 0);
      String? posted;
      server.listen((HttpRequest req) async {
        if (req.method == 'POST') {
          posted = await utf8.decoder.bind(req).join();
          req.response
            ..statusCode = 302
            ..headers.set('location', '/echo');
        } else {
          req.response.write('{"ok":true,"header":["id"],"rows":[]}');
        }
        await req.response.close();
      });
      final Map<String, Object?> answer = await SheetsSyncService.httpTransport(
        Uri.parse('http://127.0.0.1:${server.port}/exec'),
        <String, Object?>{'token': 't', 'action': 'pull'},
      );
      await server.close();
      expect(answer['ok'], isTrue);
      expect(posted, contains('"action":"pull"'));
    },
  );

  test('not configured: refuses before any network call', () async {
    await db.setSetting(SheetsSyncService.tokenKey, '');
    await expectLater(
      sync.sync(),
      throwsA(
        isA<SheetsSyncException>().having(
          (SheetsSyncException e) => e.message,
          'message',
          'not-configured',
        ),
      ),
    );
    expect(sheet.pushes, 0);
  });

  test('first sync: sparse row becomes a claim, ids written back, '
      'app-only claims sent, sheet wins on differences', () async {
    final int kept = await seed('ALPHA');
    final int appOnly = await seed('BRAVO');
    sheet.addRow(<String, String>{
      'id': '$kept',
      'customer_name': 'ALPHA',
      'accident_date': '2026-10-01',
      'vehicle_plate': '1234 ABC',
      'vehicle_type': 'Camry',
      'claim_number': 'C-ALPHA',
      'customer_insurance_company': 'GIG',
      'notes': 'from sheet',
      'status_key': 'new',
    });
    sheet.addRow(<String, String>{'claim_number': 'ONLY-NUMBER'});

    final SheetsSyncReport r = await sync.sync();

    expect(r.created, 1);
    expect(r.updated, 1);
    expect(r.sent, 1);
    expect(r.skipped, isEmpty);
    expect((await db.claimById(kept))!.notes, 'from sheet');

    final Claim sparse = (await db.allClaims()).singleWhere(
      (Claim c) => c.claimNumber == 'ONLY-NUMBER',
    );
    expect(sparse.customerName, '');
    expect(sparse.accidentDateUtcMs, isNull);
    expect(sheet.rows[1][sheet.col('id')], '${sparse.id}');

    final List<String> sent = sheet.rowWithId(appOnly)!;
    expect(sent[sheet.col('customer_name')], 'BRAVO');
    expect(sheet.header, contains('insurance_mobile')); // column added

    // Nothing changed since: a second sync moves nothing.
    final int pushes = sheet.pushes;
    final SheetsSyncReport again = await sync.sync();
    expect(again.created + again.updated + again.sent, 0);
    expect(sheet.pushes, pushes);
  });

  test('later syncs: each side takes the other side\'s edits', () async {
    final int a = await seed('ALPHA');
    final int b = await seed('BRAVO');
    await sync.sync(); // both rows go to the sheet

    await editNotes(a, 'edited in app', DateTime.now().toUtc());
    sheet.rowWithId(b)![sheet.col('notes')] = 'edited in sheet';

    final SheetsSyncReport r = await sync.sync();
    expect(r.sent, 1);
    expect(r.updated, 1);
    expect(r.conflicts, 0);
    expect(sheet.rowWithId(a)![sheet.col('notes')], 'edited in app');
    expect((await db.claimById(b))!.notes, 'edited in sheet');
  });

  test(
    'deleted in app → removed from sheet; removed from sheet → sent back',
    () async {
      final int a = await seed('ALPHA');
      final int b = await seed('BRAVO');
      await sync.sync();

      await ClaimActions(db, _NoopScheduler()).deleteClaim(a);
      sheet.rows.remove(sheet.rowWithId(b));

      final SheetsSyncReport r = await sync.sync();
      expect(r.deleted, 1);
      expect(sheet.rowWithId(a), isNull);
      expect(sheet.rowWithId(b), isNotNull);
      expect(await db.claimById(b), isNotNull);
    },
  );

  test('conflict: the newer edit wins', () async {
    final int a = await seed('ALPHA');
    await sync.sync();

    final DateTime appEdit = DateTime.now().toUtc();
    await editNotes(a, 'app version', appEdit);
    final List<String> row = sheet.rowWithId(a)!;
    row[sheet.col('notes')] = 'sheet version';
    row[sheet.col('updated_at')] = appEdit
        .subtract(const Duration(hours: 1))
        .toIso8601String();

    SheetsSyncReport r = await sync.sync();
    expect(r.conflicts, 1);
    expect(sheet.rowWithId(a)![sheet.col('notes')], 'app version');

    await editNotes(a, 'app again', appEdit);
    row
      ..[sheet.col('notes')] = 'sheet newer'
      ..[sheet.col('updated_at')] = appEdit
          .add(const Duration(hours: 1))
          .toIso8601String();
    r = await sync.sync();
    expect(r.conflicts, 1);
    expect((await db.claimById(a))!.notes, 'sheet newer');
  });

  test('push failure undoes claims created from the sheet', () async {
    sheet.addRow(<String, String>{'claim_number': 'NEW-1'});
    sheet.failPush = true;

    await expectLater(sync.sync(), throwsA(isA<SheetsSyncException>()));
    expect(await db.allClaims(), isEmpty);
    expect(sheet.rows.single[sheet.col('id')], '');

    sheet.failPush = false;
    final SheetsSyncReport r = await sync.sync();
    expect(r.created, 1);
    expect((await db.allClaims()).length, 1);
  });

  test('invalid row is skipped, the rest still syncs', () async {
    sheet.addRow(<String, String>{'claim_number': 'OK-1'});
    sheet.addRow(<String, String>{
      'claim_number': 'BAD-1',
      'accident_date': 'not a date',
    });

    final SheetsSyncReport r = await sync.sync();
    expect(r.created, 1);
    expect(r.skipped, hasLength(1));
    expect(r.skipped.single, contains('accident_date'));
  });

  test('a repeated id in the sheet becomes its own claim', () async {
    final int a = await seed('ALPHA');
    await sync.sync();
    final List<String> copy = List<String>.of(sheet.rowWithId(a)!);
    copy[sheet.col('notes')] = 'copied row';
    sheet.rows.add(copy);

    final SheetsSyncReport r = await sync.sync();
    expect(r.created, 1);
    final Claim made = (await db.allClaims()).singleWhere(
      (Claim c) => c.notes == 'copied row',
    );
    expect(made.id, isNot(a));
    expect(sheet.rows.last[sheet.col('id')], '${made.id}');
  });
}
