/// Settings screen tests (spec §16): theme selection persisted via the
/// settings repository, live `onThemeChanged` callback, notifications status
/// line and about/version card. Plus the backup/restore + security cards
/// (spec §15) driven through real [BackupService] over an on-disk FFI DB.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart'
    show debugDefaultTargetPlatformOverride;
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart' as sqf;
import 'package:sqflite_common_ffi/sqflite_ffi.dart' as ffi;

import 'package:claim_tracker/core/constants/app_constants.dart';
import 'package:claim_tracker/core/database/app_database.dart';
import 'package:claim_tracker/core/database/attachments_repository.dart';
import 'package:claim_tracker/core/database/claims_repository.dart';
import 'package:claim_tracker/core/database/reminders_repository.dart';
import 'package:claim_tracker/core/database/settings_repository.dart';
import 'package:claim_tracker/core/database/status_history_repository.dart';
import 'package:claim_tracker/core/l10n/app_strings.dart';
import 'package:claim_tracker/core/models/attachment.dart';
import 'package:claim_tracker/core/models/claim.dart';
import 'package:claim_tracker/core/models/reminder.dart';
import 'package:claim_tracker/core/security/backup_service.dart';
import 'package:claim_tracker/core/notifications/notification_service.dart'
    show AlarmPrecision, NotificationPermissionState;
import 'package:claim_tracker/core/notifications/reminder_scheduler.dart';
import 'package:claim_tracker/core/theme/app_theme.dart';
import 'package:claim_tracker/features/attachments/attachment_file_service.dart';
import 'package:claim_tracker/features/settings/settings_screen.dart';

Widget _harness(
  SettingsRepository repo, {
  ThemeMode current = ThemeMode.system,
  List<ThemeMode>? changed,
  BackupService? backupService,
  Future<Uri?> Function(Uint8List archive)? saveArchive,
  Future<File?> Function()? pickRestoreSource,
  VoidCallback? onDataRestored,
  ReminderScheduler? notifications,
}) {
  final List<ThemeMode> sink = changed ?? <ThemeMode>[];
  return MaterialApp(
    locale: const Locale('ar'),
    supportedLocales: const [Locale('ar')],
    localizationsDelegates: const [
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    theme: AppTheme.light(),
    darkTheme: AppTheme.dark(),
    home: SettingsScreen(
      settingsRepo: repo,
      currentThemeMode: current,
      onThemeChanged: (ThemeMode m) => sink.add(m),
      backupService: backupService,
      saveArchive: saveArchive,
      pickRestoreSource: pickRestoreSource,
      onDataRestored: onDataRestored,
      notifications: notifications,
    ),
  );
}

/// Recording permission seam (BUG B) — no method channels on the host.
class _FakeNotifications implements ReminderScheduler {
  int requestCalls = 0;
  bool enabledAfterRequest = false;

  @override
  Future<NotificationPermissionState> requestNotificationsPermission() async {
    requestCalls++;
    return NotificationPermissionState.granted;
  }

  @override
  Future<bool> areNotificationsEnabled() async => enabledAfterRequest;

  @override
  Future<AlarmPrecision> scheduleReminder(Reminder reminder) async =>
      AlarmPrecision.exact;

  @override
  Future<void> cancelReminder(int notificationId) async {}

  @override
  Future<void> reconcile(List<Reminder> enabledReminders) async {}

  @override
  Future<bool> openAppNotificationSettings() async => false;

  // Phase 1 fix #1/#4 — exact alarms + battery optimization seams.
  bool exactAllowed = true;
  int exactRequestCalls = 0;
  bool batteryExempt = true;
  int batteryRequestCalls = 0;

  @override
  Future<bool> canScheduleExactAlarms() async => exactAllowed;

  @override
  Future<bool> requestExactAlarmsPermission() async {
    exactRequestCalls++;
    return true;
  }

  @override
  Future<bool> isIgnoringBatteryOptimizations() async => batteryExempt;

  @override
  Future<bool> requestIgnoreBatteryOptimizations() async {
    batteryRequestCalls++;
    return true;
  }
}

void main() {
  late ffi.Database raw;
  late SettingsRepository settings;

  setUpAll(() async {
    ffi.sqfliteFfiInit();
    // BackupService.restoreFrom opens the staged DB through the global sqflite
    // API — point it at the FFI backend for host tests (same pattern as
    // backup_service_test.dart).
    sqf.databaseFactory = ffi.databaseFactoryFfi;
  });

  setUp(() async {
    raw = await ffi.databaseFactoryFfi.openDatabase(ffi.inMemoryDatabasePath);
    await raw.execute('PRAGMA foreign_keys = ON');
    await AppDatabase.migrate(raw, from: 0, to: kDatabaseVersion);
    settings = SettingsRepository(AppDatabase.fromExisting(raw));
  });

  tearDown(() async {
    await raw.close();
  });

  /// Waits (bounded, real time) until [finder] matches — the screen's
  /// initState load does real FFI I/O on a background isolate.
  Future<void> pumpUntil(WidgetTester tester, Finder f) async {
    for (int i = 0; i < 300 && f.evaluate().isEmpty; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
      await tester.pump();
    }
  }

  testWidgets('shows the three theme options with Arabic labels', (
    WidgetTester tester,
  ) async {
    await tester.runAsync(() async {
      await tester.pumpWidget(_harness(settings));
      await pumpUntil(tester, find.text(S.settingsTheme));
    });

    expect(find.text(S.themeLight), findsOneWidget);
    expect(find.text(S.themeDark), findsOneWidget);
    expect(find.text(S.themeSystem), findsOneWidget);
  });

  testWidgets(
    'selecting dark persists the setting and notifies onThemeChanged',
    (WidgetTester tester) async {
      final List<ThemeMode> changed = <ThemeMode>[];
      String? stored;

      await tester.runAsync(() async {
        await tester.pumpWidget(_harness(settings, changed: changed));
        await pumpUntil(tester, find.text(S.settingsTheme));
        await tester.tap(find.byKey(const Key('theme-dark')));
        // The tap handler persists (real FFI I/O) before notifying — poll.
        for (int i = 0; i < 300 && changed.isEmpty; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
          await tester.pump();
        }
        // Read-back must stay in the async zone too (FFI I/O under fake-async hangs).
        stored = await settings.get(AppConstants.settingThemeMode);
      });

      expect(changed, <ThemeMode>[ThemeMode.dark]);
      expect(stored, 'dark');
    },
  );

  // ---------------------------------------------------------------------
  // Phase 1 fix #1/#4 — exact-alarm + battery-optimization status rows.
  // ---------------------------------------------------------------------

  testWidgets(
    'Phase 1: denied exact alarms show a status row with a request button',
    (WidgetTester tester) async {
      final _FakeNotifications fake = _FakeNotifications()
        ..exactAllowed = false;

      await tester.runAsync(() async {
        await tester.pumpWidget(_harness(settings, notifications: fake));
        // The state load is async — poll until the denied row appears.
        for (
          int i = 0;
          i < 300 && find.text(S.exactAlarmsStatusDenied).evaluate().isEmpty;
          i++
        ) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
          await tester.pump();
        }

        expect(find.text(S.exactAlarmsStatusDenied), findsOneWidget);
        final Finder button = find.byKey(const Key('request-exact-alarms'));
        expect(button, findsOneWidget);

        // Tap → the permission is requested exactly once.
        await tester.tap(button);
        for (int i = 0; i < 300 && fake.exactRequestCalls == 0; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
          await tester.pump();
        }
      });

      expect(fake.exactRequestCalls, 1);
    },
  );

  testWidgets(
    'Phase 1: battery exemption row shows state and requests on tap',
    (WidgetTester tester) async {
      final _FakeNotifications fake = _FakeNotifications()
        ..batteryExempt = false;

      await tester.runAsync(() async {
        await tester.pumpWidget(_harness(settings, notifications: fake));
        for (
          int i = 0;
          i < 300 && find.text(S.batteryStatusNotExempt).evaluate().isEmpty;
          i++
        ) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
          await tester.pump();
        }

        expect(find.text(S.batteryStatusNotExempt), findsOneWidget);
        final Finder button = find.byKey(
          const Key('request-battery-exemption'),
        );
        expect(button, findsOneWidget);

        await tester.tap(button);
        for (int i = 0; i < 300 && fake.batteryRequestCalls == 0; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
          await tester.pump();
        }
      });

      expect(fake.batteryRequestCalls, 1);
    },
  );

  testWidgets('iOS: Android-only exact-alarm and battery rows are hidden', (
    WidgetTester tester,
  ) async {
    final _FakeNotifications fake = _FakeNotifications()
      ..exactAllowed = false
      ..batteryExempt = false;

    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    try {
      await tester.runAsync(() async {
        await tester.pumpWidget(_harness(settings, notifications: fake));
        await pumpUntil(tester, find.text(S.settingsTheme));
        // Let the async state load settle (it would surface the rows).
        for (int i = 0; i < 50; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
          await tester.pump();
        }
      });

      expect(find.text(S.exactAlarmsStatusDenied), findsNothing);
      expect(find.byKey(const Key('request-exact-alarms')), findsNothing);
      expect(find.text(S.batteryStatusNotExempt), findsNothing);
      expect(find.byKey(const Key('request-battery-exemption')), findsNothing);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('re-pumping the screen reads back the persisted selection', (
    WidgetTester tester,
  ) async {
    await tester.runAsync(() async {
      // Persist a choice first — real FFI I/O must stay in this zone.
      await settings.set(AppConstants.settingThemeMode, 'dark');

      await tester.pumpWidget(_harness(settings));
      // The stored-value read is async FFI I/O — poll until it lands and the
      // selection converges to the persisted value.
      for (
        int i = 0;
        i < 300 &&
            find.byKey(const Key('theme-dark-selected')).evaluate().isEmpty;
        i++
      ) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
        await tester.pump();
      }
    });

    expect(find.byKey(const Key('theme-dark-selected')), findsOneWidget);
  });

  testWidgets(
    'shows notifications status and the about card with app name + version',
    (WidgetTester tester) async {
      await tester.runAsync(() async {
        await tester.pumpWidget(_harness(settings));
        await pumpUntil(tester, find.text(S.settingsAbout));
      });

      expect(find.text(S.appName), findsOneWidget);
      // Version line rendered from the S.appVersion template.
      expect(find.textContaining(AppConstants.appVersionLabel), findsOneWidget);
    },
  );

  testWidgets(
    'BUG B: disabled notifications show a request button that grants + refreshes',
    (WidgetTester tester) async {
      final _FakeNotifications fake = _FakeNotifications();

      await tester.runAsync(() async {
        await tester.pumpWidget(_harness(settings, notifications: fake));
        await pumpUntil(tester, find.text(S.settingsNotifications));
        // Initially disabled → the explicit request action must be visible.
        expect(find.byKey(const Key('request-notifications')), findsOneWidget);

        // Grant on tap — then the status line flips to enabled and the
        // button disappears (no dead controls once granted, spec §3.3).
        fake.enabledAfterRequest = true;
        await tester.tap(find.byKey(const Key('request-notifications')));
        for (
          int i = 0;
          i < 300 && find.text(S.notificationsStatusEnabled).evaluate().isEmpty;
          i++
        ) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
          await tester.pump();
        }
      });

      expect(fake.requestCalls, 1); // permission was actually requested
      expect(find.text(S.notificationsStatusEnabled), findsOneWidget);
      expect(find.byKey(const Key('request-notifications')), findsNothing);
    },
  );

  testWidgets('BUG B: request that stays denied keeps the button for retry', (
    WidgetTester tester,
  ) async {
    final _FakeNotifications fake = _FakeNotifications()
      ..enabledAfterRequest = false; // user denies in the system dialog

    await tester.runAsync(() async {
      await tester.pumpWidget(_harness(settings, notifications: fake));
      await pumpUntil(tester, find.text(S.settingsNotifications));
      await tester.tap(find.byKey(const Key('request-notifications')));
      for (
        int i = 0;
        i < 300 && find.text(S.notificationsStatusDisabled).evaluate().isEmpty;
        i++
      ) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
        await tester.pump();
      }
    });

    expect(fake.requestCalls, 1);
    // Still disabled → the retry path must remain available (BUG B root
    // cause was that there was NO re-request path at all).
    expect(find.text(S.notificationsStatusDisabled), findsOneWidget);
    expect(find.byKey(const Key('request-notifications')), findsOneWidget);
  });

  group('backup & restore (spec §15)', () {
    late Directory tmp;
    late String dbPath;
    late ffi.Database raw2;
    late AppDatabase appDb;
    late ClaimsRepository claims;
    late StatusHistoryRepository history;
    late RemindersRepository reminders;
    late AttachmentsRepository attachments;
    late Directory storeDir;
    late AttachmentFileService files;
    late BackupService service;

    setUp(() async {
      // BackupService reads the DB bytes from its on-disk path, so this group
      // uses a real file-backed database (in-memory has no readable path).
      tmp = Directory.systemTemp.createTempSync('ct_settings_backup');
      dbPath = '${tmp.path}${Platform.pathSeparator}live.sqlite';
      storeDir = Directory('${tmp.path}${Platform.pathSeparator}store')
        ..createSync(recursive: true);

      raw2 = await ffi.databaseFactoryFfi.openDatabase(dbPath);
      await raw2.execute('PRAGMA foreign_keys = ON');
      await AppDatabase.migrate(raw2, from: 0, to: kDatabaseVersion);
      appDb = AppDatabase.fromExisting(raw2);
      claims = ClaimsRepository(appDb);
      history = StatusHistoryRepository(appDb);
      reminders = RemindersRepository(appDb);
      attachments = AttachmentsRepository(appDb);

      files = AttachmentFileService(baseDir: storeDir);
      service = BackupService(appDb, files);
    });

    tearDown(() async {
      try {
        await raw2.close(); // already closed by a successful restore — safe
      } catch (_) {}
      if (tmp.existsSync()) tmp.deleteSync(recursive: true);
    });

    /// Seeds one claim with a status change, a reminder and two attachment
    /// files with known bytes. Returns the created claim id.
    Future<int> seed() async {
      final int id = await claims.create(
        Claim(
          id: 0,
          customerName: 'سعد العميل',
          customerMobile: '0501234567',
          accidentDateUtcMs: DateTime.utc(2026, 10, 1),
          claimNumber: 'CLM-900',
          customerInsuranceCompany: 'تعاونية',
          liabilityPercent: 50,
          submissionDateUtcMs: DateTime.utc(2026, 10, 5),
          statusKey: 'new',
          lastStatusUpdateUtcMs: DateTime.utc(2026, 10, 6),
          createdAtUtcMs: DateTime.utc(2026, 10, 6),
          updatedAtUtcMs: DateTime.utc(2026, 10, 6),
        ),
      );
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
          notificationId: 9100,
          enabled: true,
          createdAtUtcMs: DateTime.utc(2026, 10, 8),
          updatedAtUtcMs: DateTime.utc(2026, 10, 8),
        ),
      );

      for (final spec in const [
        ('photo.jpg', 'image/jpeg', 'claim_9/att_a/photo.jpg'),
        ('report.pdf', 'application/pdf', 'claim_9/att_b/report.pdf'),
      ]) {
        final List<int> bytes = utf8.encode('attachment-bytes:${spec.$2}');
        File(
            '${storeDir.path}/${spec.$3.replaceAll('/', Platform.pathSeparator)}',
          )
          ..createSync(recursive: true)
          ..writeAsBytesSync(bytes);
        await attachments.create(
          Attachment(
            id: 0,
            claimId: id,
            originalName: spec.$1,
            mimeType: spec.$2,
            sizeBytes: bytes.length,
            relativePath: spec.$3,
            createdAtUtcMs: DateTime.utc(2026, 10, 8),
          ),
        );
      }
      return id;
    }

    testWidgets(
      'renders backup card with both actions and the security info card',
      (WidgetTester tester) async {
        await tester.runAsync(() async {
          await tester.pumpWidget(_harness(settings, backupService: service));
          await pumpUntil(tester, find.text(S.settingsBackupRestore));
        });

        expect(find.byKey(const Key('backup-export')), findsOneWidget);
        expect(find.byKey(const Key('backup-restore')), findsOneWidget);
        expect(find.byKey(const Key('security-info')), findsOneWidget);
        expect(find.text(S.securityInfoBody), findsOneWidget);
      },
    );

    testWidgets(
      'export: passphrase + confirm → save destination → success; file starts with CTBK',
      (WidgetTester tester) async {
        String? savedPath;

        // Stand-in for FilePicker.saveFile: writes the bytes to a temp path.
        Future<Uri?> fakeSave(Uint8List archive) async {
          savedPath =
              '${tmp.path}${Platform.pathSeparator}out'
              '${Platform.pathSeparator}claim-tracker-backup.ctbk';
          File(savedPath!)
            ..createSync(recursive: true)
            ..writeAsBytesSync(archive);
          return Uri.file(savedPath!);
        }

        await tester.runAsync(() async {
          await seed();
          await tester.pumpWidget(
            _harness(settings, backupService: service, saveArchive: fakeSave),
          );
          await pumpUntil(tester, find.text(S.settingsBackupRestore));

          await tester.tap(find.byKey(const Key('backup-export')));
          await pumpUntil(tester, find.text(S.backupPassphraseTitle));
          await tester.enterText(find.byType(TextField).first, 'secret-123');
          await tester.tap(find.text(S.confirm));

          await pumpUntil(tester, find.text(S.backupPassphraseConfirmTitle));
          await tester.enterText(find.byType(TextField).first, 'secret-123');
          await tester.tap(find.text(S.confirm));

          // buildArchive does real FFI I/O — poll for the success text.
          await pumpUntil(tester, find.text(S.backupExportedOk));
        });

        expect(savedPath, isNotNull);
        final List<int> head = File(savedPath!)
            .readAsBytesSync()
            .take(4)
            .toList();
        expect(head, AppConstants.backupMagic); // "CTBK" — a valid v1 archive
      },
    );

    testWidgets(
      'restore: source picked → warning dialog → confirm → success shows counts',
      (WidgetTester tester) async {
        final String archivePath =
            '${tmp.path}${Platform.pathSeparator}archive.ctbk';
        bool bumped = false;

        await tester.runAsync(() async {
          await seed(); // 1 claim, 2 attachments
          await File(archivePath)
              .writeAsBytes(await service.buildArchive('good-pass'));

          await tester.pumpWidget(
            _harness(
              settings,
              backupService: service,
              pickRestoreSource: () async => File(archivePath),
              onDataRestored: () => bumped = true,
            ),
          );
          await pumpUntil(tester, find.text(S.settingsBackupRestore));

          await tester.tap(find.byKey(const Key('backup-restore')));
          // The explicit warning must appear BEFORE any passphrase entry.
          await pumpUntil(tester, find.text(S.restoreWarningTitle));
          expect(find.text(S.restoreWarningBody), findsOneWidget);
          await tester.tap(find.text(S.confirm));

          await pumpUntil(tester, find.text(S.backupPassphraseTitle));
          await tester.enterText(find.byType(TextField).first, 'good-pass');
          await tester.tap(find.text(S.confirm));

          // restoreFrom does real I/O (staged open + swap) — poll for success.
          final String expected = S.restoredOk(1, 2);
          await pumpUntil(tester, find.text(expected));
        });

        expect(bumped, isTrue); // shell hook fired so destinations can reload
      },
    );

    testWidgets(
      'wrong passphrase shows the failure text and leaves existing data intact',
      (WidgetTester tester) async {
        final String archivePath =
            '${tmp.path}${Platform.pathSeparator}archive.ctbk';
        int claimId = 0;

        await tester.runAsync(() async {
          claimId = await seed();
          await File(archivePath)
              .writeAsBytes(await service.buildArchive('good-pass'));

          await tester.pumpWidget(
            _harness(
              settings,
              backupService: service,
              pickRestoreSource: () async => File(archivePath),
            ),
          );
          await pumpUntil(tester, find.text(S.settingsBackupRestore));

          await tester.tap(find.byKey(const Key('backup-restore')));
          await pumpUntil(tester, find.text(S.restoreWarningTitle));
          await tester.tap(find.text(S.confirm));
          await pumpUntil(tester, find.text(S.backupPassphraseTitle));
          await tester.enterText(find.byType(TextField).first, 'WRONG-PASS');
          await tester.tap(find.text(S.confirm));

          await pumpUntil(tester, find.text(S.backupFailedWrongPassphrase));

          // The live DB must still be open and readable — the failed restore
          // threw before any mutation (spec §15 fail-closed).
          final Claim? c = await appDb.claimById(claimId);
          expect(c, isNotNull);
        });

        expect(find.textContaining('تمت الاستعادة'), findsNothing);
      },
    );

    testWidgets('passphrase mismatch blocks the export and writes no file', (
      WidgetTester tester,
    ) async {
      bool saveCalled = false;

      await tester.runAsync(() async {
        await seed();
        await tester.pumpWidget(
          _harness(
            settings,
            backupService: service,
            saveArchive: (Uint8List archive) async {
              saveCalled = true; // must never be reached on mismatch
              return Uri.file('${tmp.path}${Platform.pathSeparator}never.ctbk');
            },
          ),
        );
        await pumpUntil(tester, find.text(S.settingsBackupRestore));

        await tester.tap(find.byKey(const Key('backup-export')));
        await pumpUntil(tester, find.text(S.backupPassphraseTitle));
        await tester.enterText(find.byType(TextField).first, 'aaa');
        await tester.tap(find.text(S.confirm));

        await pumpUntil(tester, find.text(S.backupPassphraseConfirmTitle));
        await tester.enterText(find.byType(TextField).first, 'bbb');
        await tester.tap(find.text(S.confirm));

        await pumpUntil(tester, find.text(S.backupPassphraseMismatch));
      });

      expect(saveCalled, isFalse);
    });

    testWidgets(
      'passphrase dialog: confirm pumps through the close animation without a disposed-controller exception',
      (WidgetTester tester) async {
        // Regression test for BUG 1: the controller used to be disposed by
        // the caller as soon as showDialog returned, while the exit animation
        // was still running — the TextField then threw "A TextEditingController
        // was used after being disposed" (red error screen). The dialog now
        // owns its controller; pumping through the close animation must not
        // throw.
        await tester.runAsync(() async {
          await seed();
          await tester.pumpWidget(_harness(settings, backupService: service));
          await pumpUntil(tester, find.text(S.settingsBackupRestore));

          // Open the passphrase dialog via the export flow (restore uses the
          // same dialog).
          await tester.tap(find.byKey(const Key('backup-export')));
          await pumpUntil(tester, find.text(S.backupPassphraseTitle));

          await tester.enterText(
            find.byType(TextField).first,
            'dialog-pass-123',
          );
          await tester.tap(find.text(S.confirm));

          // Pump through the dialog's exit animation to completion.
          await tester.pumpAndSettle();

          expect(tester.takeException(), isNull);
        });
      },
    );
  });
}
