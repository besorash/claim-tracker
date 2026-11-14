/// ClaimActions attachment flow tests (spec §12): attach copies bytes into the
/// app-private store and records a row; a failed insert leaves no orphan file;
/// deleting a claim removes only that claim's files. Pure Dart + FFI — no
/// widget pumping needed.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart' as ffi;

import 'package:claim_tracker/core/database/app_database.dart';
import 'package:claim_tracker/core/database/attachments_repository.dart';
import 'package:claim_tracker/core/database/claims_repository.dart';
import 'package:claim_tracker/core/models/attachment.dart';
import 'package:claim_tracker/core/models/claim.dart';
import 'package:claim_tracker/core/models/reminder.dart';
import 'package:claim_tracker/core/notifications/notification_service.dart';
import 'package:claim_tracker/core/notifications/reminder_scheduler.dart';
import 'package:claim_tracker/features/attachments/attachment_file_service.dart';
import 'package:claim_tracker/features/claims/claim_actions.dart';

/// Recording fake — same contract as the one in claim_actions_test.dart.
class FakeScheduler implements ReminderScheduler {
  final List<int> cancelled = [];
  final List<Reminder> scheduled = [];
  final List<List<Reminder>> reconciled = [];
  bool enabled = true;

  @override
  Future<void> cancelReminder(int notificationId) async =>
      cancelled.add(notificationId);

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
  late FakeScheduler fake;
  late Directory tmp; // per-test temp root (sources + store)
  late Directory store; // the attachment store inside [tmp]
  late AttachmentFileService files;
  late ClaimActions actions;

  setUpAll(() async {
    ffi.sqfliteFfiInit();
    ffi.databaseFactory = ffi.databaseFactoryFfi;
  });

  setUp(() async {
    raw = await ffi.databaseFactoryFfi.openDatabase(ffi.inMemoryDatabasePath);
    await raw.execute('PRAGMA foreign_keys = ON');
    await AppDatabase.migrate(raw, from: 0, to: kDatabaseVersion);
    db = AppDatabase.fromExisting(raw);
    claims = ClaimsRepository(db);
    fake = FakeScheduler();

    tmp = Directory.systemTemp.createTempSync('ct_claim_attach_test');
    store = Directory('${tmp.path}/store')..createSync();
    files = AttachmentFileService(baseDir: store);
    actions = ClaimActions(db, fake, files: files);
  });

  tearDown(() async {
    await raw.close();
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  Future<int> seedClaim() => claims.create(
    Claim(
      id: 0,
      customerName: 'عميل',
      customerMobile: '0501234567',
      accidentDateUtcMs: DateTime.utc(2026, 10, 1),
      claimNumber: 'CLM-ATT-${DateTime.now().microsecondsSinceEpoch % 9999}',
      customerInsuranceCompany: 'تعاونية',
      liabilityPercent: 50,
      submissionDateUtcMs: DateTime.utc(2026, 10, 5),
      statusKey: 'new',
      lastStatusUpdateUtcMs: DateTime.now().toUtc(),
      createdAtUtcMs: DateTime.now().toUtc(),
      updatedAtUtcMs: DateTime.now().toUtc(),
    ),
  );

  File makeSource(String name, List<int> bytes) {
    final File f = File('${tmp.path}/$name');
    f.writeAsBytesSync(bytes);
    return f;
  }

  test('attachFile stores bytes, inserts a row linked to the claim, and returns it', () async {
    final int claimId = await seedClaim();
    final List<int> payload = utf8.encode('صورة الحادث');
    final File src = makeSource('accident.png', payload);

    final Attachment stored = await actions.attachFile(
      claimId,
      src.path,
      originalName: 'accident.png',
      mimeType: 'image/png',
    );

    expect(stored.id, greaterThan(0));
    expect(stored.claimId, claimId);
    expect(stored.originalName, 'accident.png');
    expect(stored.mimeType, 'image/png');
    expect(stored.sizeBytes, payload.length);
    expect(stored.relativePath, isNot(startsWith('/')));

    // Bytes copied into the store, source left untouched.
    final File inStore = files.fileFor(stored);
    expect(inStore.existsSync(), isTrue);
    expect(files.isInsideStore(inStore.path), isTrue);
    expect(inStore.readAsBytesSync(), payload);
    expect(src.existsSync(), isTrue);

    // Row persisted and linked to the claim.
    final List<Attachment> rows = await AttachmentsRepository(db)
        .listForClaim(claimId);
    expect(rows, hasLength(1));
    expect(rows.single.id, stored.id);
    expect(rows.single.relativePath, stored.relativePath);
  });

  test('attachFile cleans up the copied file when the insert fails', () async {
    final File src = makeSource('orphan.png', [10, 20, 30]);

    Object? error;
    try {
      // No claim with id 999 exists → FK violation on the row insert.
      await actions.attachFile(999, src.path);
    } on Object catch (e) {
      error = e;
    }

    expect(error, isNotNull, reason: 'insert into a missing claim must fail');

    // No orphan bytes in the store — the copied file was rolled back.
    final List<FileSystemEntity> leftovers = store
        .listSync(recursive: true)
        .toList();
    expect(leftovers.whereType<File>(), isEmpty);
  });

  test('deleteClaim removes only that claim\'s files', () async {
    final int a = await seedClaim();
    final int b = await seedClaim();
    final List<int> bytesA = [1, 2, 3];
    final List<int> bytesB = [9, 8, 7];

    final Attachment attA = await actions.attachFile(
      a,
      makeSource('a.png', bytesA).path,
    );
    final Attachment attB = await actions.attachFile(
      b,
      makeSource('b.pdf', bytesB).path,
    );
    final File fileA = files.fileFor(attA);
    final File fileB = files.fileFor(attB);

    await actions.deleteClaim(a);

    // Claim A: gone with its attachment file.
    expect(
      fileA.existsSync(),
      isFalse,
      reason: 'claim A\'s file must be removed',
    );
    expect(await db.claimById(a), isNull);

    // Claim B untouched: row and bytes intact.
    expect(await db.claimById(b), isNotNull);
    expect(fileB.existsSync(), isTrue);
    expect(fileB.readAsBytesSync(), bytesB);
    final List<Attachment> rowsB = await AttachmentsRepository(db)
        .listForClaim(b);
    expect(rowsB, hasLength(1));
    expect(rowsB.single.id, attB.id);
  });

  test('attachFile rejects a missing source path gracefully', () async {
    final int claimId = await seedClaim();
    final String missing = '${tmp.path}/no-such-file.bin';

    expect(
      () => actions.attachFile(claimId, missing),
      throwsA(isA<ArgumentError>()),
    );

    // No partial state: no row, no bytes in the store.
    expect(await AttachmentsRepository(db).listForClaim(claimId), isEmpty);
    final List<FileSystemEntity> leftovers = store
        .listSync(recursive: true)
        .toList();
    expect(leftovers.whereType<File>(), isEmpty);
  });

  test(
    'without a file service, attachFile throws and deleteClaim still works',
    () async {
      final ClaimActions bare = ClaimActions(db, fake); // no `files`

      expect(
        () => bare.attachFile(1, makeSource('x.png', [1]).path),
        throwsA(isA<StateError>()),
      );

      // deleteClaim must not require a file service.
      final int id = await seedClaim();
      await bare.deleteClaim(id);
      expect(await db.claimById(id), isNull);
    },
  );
}
