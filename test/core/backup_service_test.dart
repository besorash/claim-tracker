/// BackupService behavior: export, staged restore with validation, and the
/// fail-closed guarantees of spec §15 (wrong passphrase / corrupt archive /
/// incompatible version must never touch existing data).
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart' as sqf;
import 'package:sqflite_common_ffi/sqflite_ffi.dart' as ffi;

import 'package:claim_tracker/core/database/app_database.dart';
import 'package:claim_tracker/core/database/attachments_repository.dart';
import 'package:claim_tracker/core/database/claims_repository.dart';
import 'package:claim_tracker/core/database/reminders_repository.dart';
import 'package:claim_tracker/core/database/status_history_repository.dart';
import 'package:claim_tracker/core/models/attachment.dart';
import 'package:claim_tracker/core/models/claim.dart';
import 'package:claim_tracker/core/models/reminder.dart';
import 'package:claim_tracker/core/security/backup_crypto.dart';
import 'package:claim_tracker/core/security/backup_service.dart';
import 'package:claim_tracker/features/attachments/attachment_file_service.dart';

void main() {
  late Directory tmp; // root for this test's temp state
  late String dbPath;
  late ffi.Database raw;
  late AppDatabase db;
  late ClaimsRepository claims;
  late StatusHistoryRepository history;
  late RemindersRepository reminders;
  late AttachmentsRepository attachments;
  late Directory storeDir; // live attachment store (app-private equivalent)
  late AttachmentFileService files;
  late BackupService service;

  setUpAll(() {
    ffi.sqfliteFfiInit();
    // BackupService opens the staged DB through the global sqflite API —
    // point it at the FFI backend for host tests (documented pattern from
    // sqflite_common_ffi).
    sqf.databaseFactory = ffi.databaseFactoryFfi;
  });

  setUp(() async {
    tmp = Directory.systemTemp.createTempSync('ct_backup_test');
    dbPath = '${tmp.path}${Platform.pathSeparator}live.sqlite';
    storeDir = Directory('${tmp.path}${Platform.pathSeparator}store')
      ..createSync(recursive: true);

    raw = await ffi.databaseFactoryFfi.openDatabase(dbPath);
    await raw.execute('PRAGMA foreign_keys = ON');
    await AppDatabase.migrate(raw, from: 0, to: kDatabaseVersion);
    db = AppDatabase.fromExisting(raw);
    claims = ClaimsRepository(db);
    history = StatusHistoryRepository(db);
    reminders = RemindersRepository(db);
    attachments = AttachmentsRepository(db);

    files = AttachmentFileService(baseDir: storeDir);
    service = BackupService(db, files);
  });

  tearDown(() async {
    try {
      await raw.close();
    } catch (_) {}
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  Claim sampleClaim() => Claim(
    id: 0,
    customerName: 'سعد العميل',
    customerMobile: '0501234567',
    accidentDateUtcMs: DateTime.utc(2026, 10, 1),
    claimNumber: 'CLM-100',
    customerInsuranceCompany: 'تعاونية',
    submittedToInsuranceCompany: 'بوبا',
    submissionDateUtcMs: DateTime.utc(2026, 10, 5),
    statusKey: 'new',
    lastStatusUpdateUtcMs: DateTime.utc(2026, 10, 6),
    createdAtUtcMs: DateTime.utc(2026, 10, 6),
    updatedAtUtcMs: DateTime.utc(2026, 10, 6),
  );

  /// Seeds one claim (with a status change + reminder) and two attachment
  /// files with known bytes. Returns the created ids/rows for assertions.
  Future<({int claimId, List<Attachment> attachments})> seedLive() async {
    final int id = await claims.create(sampleClaim());
    await history.changeStatus(
      claimId: id,
      newStatusKey: 'submitted',
      changedAtUtc: DateTime.utc(2026, 10, 7),
      note: 'أُرسلت للجهة',
    );
    await reminders.replaceForClaim(
      claimId: id,
      next: Reminder(
        id: 0,
        claimId: id,
        fireAtUtcMs: DateTime.utc(2026, 11, 1),
        notificationId: 9001,
        enabled: true,
        createdAtUtcMs: DateTime.utc(2026, 10, 8),
        updatedAtUtcMs: DateTime.utc(2026, 10, 8),
      ),
    );

    final List<Attachment> atts = [];
    for (final spec in const [
      ('photo.jpg', 'image/jpeg', 'claim_1/att_a/photo.jpg'),
      ('report.pdf', 'application/pdf', 'claim_1/att_b/report.pdf'),
    ]) {
      final bytes = utf8.encode('attachment-bytes:${spec.$2}');
      final rel = spec.$3;
      File('${storeDir.path}/${rel.replaceAll('/', Platform.pathSeparator)}')
        ..createSync(recursive: true)
        ..writeAsBytesSync(bytes);
      atts.add(
        Attachment(
          id: 0,
          claimId: id,
          originalName: spec.$1,
          mimeType: spec.$2,
          sizeBytes: bytes.length,
          relativePath: rel,
          createdAtUtcMs: DateTime.utc(2026, 10, 8),
        ),
      );
    }
    for (final a in atts) {
      await attachments.create(a);
    }
    return (claimId: id, attachments: atts);
  }

  /// Reopens the database at [dbPath] after a restore swapped it out.
  Future<AppDatabase> reopenLive() async {
    final raw2 = await ffi.databaseFactoryFfi.openDatabase(dbPath);
    await raw2.execute('PRAGMA foreign_keys = ON');
    return AppDatabase.fromExisting(raw2);
  }

  /// Asserts the live claim is still readable and its attachment files are
  /// byte-identical — i.e. a failed restore left existing data untouched.
  Future<void> expectLiveIntact(int claimId, List<Attachment> atts) async {
    final Claim? stored = await db.claimById(claimId);
    expect(stored, isNotNull);
    expect(stored!.customerName, 'سعد العميل');
    for (final a in atts) {
      final f = files.fileFor(a);
      expect(
        f.existsSync(),
        isTrue,
        reason: 'live file missing: ${a.relativePath}',
      );
      expect(
        utf8.decode(f.readAsBytesSync()),
        equals('attachment-bytes:${a.mimeType}'),
      );
    }
  }

  group('BackupService', () {
    test('export produces a file that is not plaintext', () async {
      final seeded = await seedLive();
      final dest = File('${tmp.path}${Platform.pathSeparator}backup.ctbk');
      await service.exportTo(dest, 'passphrase-123');

      expect(dest.existsSync(), isTrue);
      final bytes = dest.readAsBytesSync();
      expect(bytes.length, greaterThan(64));
      // Magic header "CTBK".
      expect(bytes.sublist(0, 4), equals([0x43, 0x54, 0x42, 0x4B]));
      // The customer name and attachment contents must NOT appear in clear.
      final asText = utf8.decode(bytes, allowMalformed: true);
      expect(asText.contains('سعد العميل'), isFalse);
      for (final a in seeded.attachments) {
        expect(asText.contains('attachment-bytes:${a.mimeType}'), isFalse);
      }
    });

    test('restore into clean state reproduces claims, history, reminders, attachments', () async {
      final seeded = await seedLive();
      final dest = File('${tmp.path}${Platform.pathSeparator}backup.ctbk');
      await service.exportTo(dest, 'passphrase-123');

      // Clean target: fresh empty DB at the same path + empty store.
      await raw.close();
      File(dbPath).deleteSync();
      for (final e in storeDir.listSync(recursive: true)) {
        if (e is File) e.deleteSync();
      }
      final raw2 = await ffi.databaseFactoryFfi.openDatabase(dbPath);
      await raw2.execute('PRAGMA foreign_keys = ON');
      await AppDatabase.migrate(raw2, from: 0, to: kDatabaseVersion);
      final cleanDb = AppDatabase.fromExisting(raw2);

      final report = await BackupService(
        cleanDb,
        files,
      ).restoreFrom(dest, 'passphrase-123');
      expect(report.claims, equals(1));
      expect(report.attachmentsRestored, equals(2));

      // Reopen the swapped-in database and verify every table.
      final restored = await reopenLive();
      try {
        final Claim? claim = await restored.claimById(seeded.claimId);
        expect(claim, isNotNull);
        expect(claim!.customerName, 'سعد العميل');
        expect(claim.customerMobile, '0501234567');
        expect(claim.claimNumber, 'CLM-100');
        expect(claim.statusKey, 'submitted');

        final hist = await StatusHistoryRepository(restored)
            .listForClaim(seeded.claimId);
        expect(hist.length, greaterThanOrEqualTo(2)); // initial + changeStatus

        final rem = await restored.remindersForClaim(seeded.claimId);
        expect(rem.length, equals(1));
        expect(rem.first.notificationId, equals(9001));

        final atts = await AttachmentsRepository(restored).listAll();
        expect(atts.length, equals(2));
        for (final a in atts) {
          final f = files.fileFor(a);
          expect(
            f.existsSync(),
            isTrue,
            reason: 'restored file missing: ${a.relativePath}',
          );
          expect(
            utf8.decode(f.readAsBytesSync()),
            equals('attachment-bytes:${a.mimeType}'),
          );
        }
      } finally {
        await restored.close();
      }
    });

    test('restore with wrong passphrase leaves current db rows AND attachment files intact', () async {
      final seeded = await seedLive();
      final dest = File('${tmp.path}${Platform.pathSeparator}backup.ctbk');
      await service.exportTo(dest, 'passphrase-123');

      // Route this restore's staging dir into a private temp root: the
      // shared system temp also holds `ct_restore*` dirs from other test
      // files running in parallel, which made a global scan flaky.
      final Directory privateTemp = Directory(
        '${tmp.path}${Platform.pathSeparator}systemp',
      )..createSync();
      await IOOverrides.runZoned(
        () => expectLater(
          service.restoreFrom(dest, 'WRONG-passphrase'),
          throwsA(isA<WrongPassphraseError>()),
        ),
        getSystemTempDirectory: () => privateTemp,
      );

      await expectLiveIntact(seeded.claimId, seeded.attachments);
      // No staging leftovers from this restore.
      expect(
        privateTemp.listSync().where((e) => e.path.contains('ct_restore')),
        isEmpty,
      );
    });

    test(
      'flipped payload byte rejects restore, existing data untouched',
      () async {
        final seeded = await seedLive();
        final dest = File('${tmp.path}${Platform.pathSeparator}backup.ctbk');
        await service.exportTo(dest, 'passphrase-123');

        // Flip one byte inside the ciphertext region (after header + IV).
        final bytes = dest.readAsBytesSync();
        bytes[34 + 16 + 2048] ^= 0xff;
        dest.writeAsBytesSync(bytes);

        expect(
          () => service.restoreFrom(dest, 'passphrase-123'),
          throwsA(isA<BackupError>()),
        );
        await expectLiveIntact(seeded.claimId, seeded.attachments);
      },
    );

    test('incompatible version is rejected before touching data', () async {
      final seeded = await seedLive();
      final dest = File('${tmp.path}${Platform.pathSeparator}backup.ctbk');
      await service.exportTo(dest, 'passphrase-123');

      // Overwrite the u16 format version at offset 4 with an unsupported value.
      final bytes = dest.readAsBytesSync();
      bytes[4] = (99 >> 8) & 0xff;
      bytes[5] = 99 & 0xff;
      dest.writeAsBytesSync(bytes);

      expect(
        () => service.restoreFrom(dest, 'passphrase-123'),
        throwsA(isA<IncompatibleVersionError>()),
      );
      await expectLiveIntact(seeded.claimId, seeded.attachments);
    });

    test('restore validates every attachment row has its file; a missing file aborts safely', () async {
      final seeded = await seedLive();
      // Add an attachments row whose backing file does not exist in the store.
      await db.rawDb.insert('attachments', {
        'claim_id': seeded.claimId,
        'original_name': 'ghost.bin',
        'mime_type': 'application/octet-stream',
        'size_bytes': 10,
        'relative_path': 'claim_1/att_c/ghost.bin',
        'created_at_utc_ms': DateTime.utc(2026, 10, 9).millisecondsSinceEpoch,
      });

      // Export now: the archive contains a zero-length entry for the ghost.
      final dest = File('${tmp.path}${Platform.pathSeparator}backup.ctbk');
      await service.exportTo(dest, 'passphrase-123');

      expect(
        () => service.restoreFrom(dest, 'passphrase-123'),
        throwsA(isA<BackupError>()),
      );
      await expectLiveIntact(seeded.claimId, seeded.attachments);
    });

    test('restore swaps atomically after validation', () async {
      final seeded = await seedLive();
      final dest = File('${tmp.path}${Platform.pathSeparator}backup.ctbk');
      await service.exportTo(dest, 'passphrase-123');

      // Clean target state.
      await raw.close();
      File(dbPath).deleteSync();
      for (final e in storeDir.listSync(recursive: true)) {
        if (e is File) e.deleteSync();
      }
      final raw2 = await ffi.databaseFactoryFfi.openDatabase(dbPath);
      await raw2.execute('PRAGMA foreign_keys = ON');
      await AppDatabase.migrate(raw2, from: 0, to: kDatabaseVersion);
      final cleanDb = AppDatabase.fromExisting(raw2);

      await BackupService(cleanDb, files).restoreFrom(dest, 'passphrase-123');

      // New files present at their relative paths…
      for (final a in seeded.attachments) {
        expect(files.fileFor(a).existsSync(), isTrue);
      }
      // …and no duplicate accumulation: exactly the restored set of files.
      final allFiles = storeDir
          .listSync(recursive: true)
          .whereType<File>()
          .map(
            (f) => f.path.replaceFirst(
              '${storeDir.path}${Platform.pathSeparator}',
              '',
            ),
          )
          .toList();
      expect(allFiles.length, equals(2));
    });
  });
}
