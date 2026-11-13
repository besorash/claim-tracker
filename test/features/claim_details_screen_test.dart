/// ClaimDetailsScreen tests (spec §11): read-only details, edit entry point,
/// and delete with explicit confirmation. The screen does real FFI SQLite I/O
/// in initState → single `tester.runAsync` block + bounded polling (see the
/// harness note in dashboard_screen_test.dart).
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cross_file/cross_file.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart' as ffi;

import 'package:claim_tracker/core/database/app_database.dart';
import 'package:claim_tracker/core/database/claims_repository.dart';
import 'package:claim_tracker/core/l10n/app_strings.dart';
import 'package:claim_tracker/core/models/claim.dart';
import 'package:claim_tracker/core/models/claim_status.dart';
import 'package:claim_tracker/core/theme/app_theme.dart';
import 'package:claim_tracker/core/utils/time_utils.dart';
import 'package:claim_tracker/core/database/reminders_repository.dart';
import 'package:claim_tracker/core/database/status_history_repository.dart';
import 'package:claim_tracker/core/models/status_history_entry.dart';
import 'package:claim_tracker/core/models/reminder.dart';
import 'package:claim_tracker/core/notifications/notification_service.dart';
import 'package:claim_tracker/core/notifications/reminder_scheduler.dart';
import 'package:claim_tracker/core/database/attachments_repository.dart';
import 'package:claim_tracker/core/models/attachment.dart';
import 'package:claim_tracker/features/attachments/attachment_file_service.dart';
import 'package:claim_tracker/features/attachments/attachment_picker_seam.dart';
import 'package:claim_tracker/features/claims/claim_details_screen.dart';
import 'package:claim_tracker/features/claims/claim_form_screen.dart';

/// Parent page that PUSHES the details screen — so a `pop()` after delete is
/// real (popping from the root route would be a no-op and hide bugs).
Widget _harness(
  AppDatabase db,
  int claimId, {
  ReminderScheduler? scheduler,
  AttachmentPicker? picker,
  AttachmentFileService? files,
  Future<bool> Function(Uri)? openExternal,
  Future<bool> Function(String)? callNumber,
}) => MaterialApp(
  locale: const Locale('ar'),
  supportedLocales: const [Locale('ar')],
  localizationsDelegates: const [
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
  ],
  theme: AppTheme.light(),
  darkTheme: AppTheme.dark(),
  home: Builder(
    builder: (BuildContext context) => Scaffold(
      body: Center(
        child: FilledButton(
          key: const Key('open-details'),
          onPressed: () {
            Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => ClaimDetailsScreen(
                  db: db,
                  claimId: claimId,
                  scheduler: scheduler,
                  picker: picker,
                  files: files,
                  openExternal: openExternal,
                  callNumber: callNumber,
                ),
              ),
            );
          },
          child: const Text('فتح'),
        ),
      ),
    ),
  ),
);

/// Opens the details screen from the parent page (must be called INSIDE
/// `runAsync` — a bare pump, never pumpAndSettle: the pushed screen's FFI load
/// keeps real timers pending under fake-async).
/// Recording fake for the status-change flow (no method channels on host).
class FakeScheduler implements ReminderScheduler {
  final List<int> cancelled = [];
  final List<Reminder> scheduled = [];
  final List<List<Reminder>> reconciled = [];

  /// Permission behavior — configurable per test (spec §10 denial path).
  bool notificationsEnabled = true;
  NotificationPermissionState requestResult =
      NotificationPermissionState.granted;

  @override
  Future<void> cancelReminder(int notificationId) async =>
      cancelled.add(notificationId);

  /// Precision reported by [scheduleReminder] — tests can force inexact to
  /// exercise the "reminders may be late" warning (Phase 1 fix #1/#3).
  AlarmPrecision scheduleResult = AlarmPrecision.exact;

  /// When true, [scheduleReminder] throws — exercises the surfaced failure.
  bool throwOnSchedule = false;

  @override
  Future<AlarmPrecision> scheduleReminder(Reminder reminder) async {
    if (throwOnSchedule) throw StateError('OS alarm service unavailable');
    scheduled.add(reminder);
    return scheduleResult;
  }

  @override
  Future<bool> areNotificationsEnabled() async => notificationsEnabled;

  @override
  Future<NotificationPermissionState> requestNotificationsPermission() async =>
      requestResult;

  @override
  Future<void> reconcile(List<Reminder> enabledReminders) async =>
      reconciled.add(enabledReminders);

  /// Records taps on the "open system notification settings" action (BUG B).
  int openedSettings = 0;

  @override
  Future<bool> openAppNotificationSettings() async {
    openedSettings++;
    return true;
  }

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

/// A [PlatformFile] backed by a real temp file so no method channels are
/// touched in tests. `PlatformFile` is an `abstract base class`, which cannot
/// be implemented outside its own package — but it CAN be extended, provided
/// the subclass itself is declared `final`. The concrete `extension` and
/// `path` members are inherited (both derive from [name]/[uri]).
final class _FakePlatformFile extends PlatformFile {
  _FakePlatformFile(this._path);

  final String _path;
  late final File _file = File(_path);

  @override
  String get name => _path.split(RegExp(r'[\\/]')).last;

  @override
  Uri get uri => Uri.file(_path);

  @override
  XFile get xFile => XFile(_path);

  @override
  int? lengthSync() => _file.existsSync() ? _file.lengthSync() : null;

  @override
  Future<int?> length() async => lengthSync();

  @override
  Future<Uint8List> readAsBytes() async => _file.readAsBytes();

  @override
  Stream<Uint8List> readAsByteStream() async* {
    yield await _file.readAsBytes();
  }
}

/// Recording [AttachmentPicker] — returns pre-staged files, no OS picker.
class _FakePicker implements AttachmentPicker {
  List<PlatformFile> next = const [];

  @override
  Future<List<PlatformFile>> pick({required FileType type}) async => next;
}

/// Recording dialer for widget tests — no url_launcher channel touched.
class FakeDialer {
  final List<String> called = [];
  bool result = true; // false → snackbar path
  bool shouldThrow = false;

  Future<bool> call(String phone) async {
    if (shouldThrow) throw StateError('dialer unavailable');
    called.add(phone);
    return result;
  }
}

Future<void> openDetails(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('open-details')));
  // The screen exists in the tree as soon as the route starts pushing, but
  // during the MaterialPageRoute transition it is still sliding in from the
  // right (RTL), so taps on its bottom bar would land off-screen. Keep
  // pumping until the transition animation has fully completed.
  // NOTE: pump() must be given an explicit duration — under runAsync a
  // duration-less pump does not advance tickers, which leaves the route
  // frozen mid-transition (animation stuck at forward/0.0).
  for (int i = 0; i < 60; i++) {
    await tester.pump(const Duration(milliseconds: 50));
    if (!tester.any(find.byType(ClaimDetailsScreen))) continue;
    final AnimationStatus status =
        ModalRoute.of(tester.element(find.byType(ClaimDetailsScreen)))
            ?.animation
            ?.status ??
        AnimationStatus.completed;
    if (status == AnimationStatus.completed) break;
  }
}

/// The reminder section sits below the fold on the 600px test surface —
/// scroll it into view before tapping its buttons. Small bidirectional steps
/// so a fling overshoot is corrected on the next iteration (the content is
/// rendered eagerly, so `scrollUntilVisible`'s existence check would not
/// work here).
Future<void> scrollToReminder(WidgetTester tester) async {
  for (int i = 0; i < 30; i++) {
    final Offset center = tester.getCenter(find.text(S.reminderSet));
    if (center.dy > 48 && center.dy < 552) return;
    await tester.drag(
      find.byType(SingleChildScrollView),
      Offset(0, center.dy > 552 ? -150.0 : 150.0),
    );
    await tester.pump();
  }
}

/// The attachments section sits below the fold on the 600px test surface —
/// scroll a specific [target] into the safe middle band before tapping it
/// (same approach as [scrollToReminder]). Targeting the tapped widget itself
/// matters: the add button is the LAST element of the section, so scrolling
/// only to the section label can leave it clipped by the bottom bar.
Future<void> scrollTo(WidgetTester tester, Finder target) async {
  for (int i = 0; i < 60; i++) {
    final Offset center = tester.getCenter(target);
    if (center.dy > 90 && center.dy < 480) return;
    await tester.drag(
      find.byType(SingleChildScrollView),
      Offset(0, center.dy > 480 ? -150.0 : 150.0),
    );
    await tester.pump();
  }
}

void main() {
  late ffi.Database raw;
  late AppDatabase db;
  late ClaimsRepository claims;

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
  });

  tearDown(() async {
    await raw.close();
  });

  /// One claim with every field populated (amount + notes per plan).
  Future<int> seedFull() => claims.create(
    Claim(
      id: 0,
      customerName: 'خالد العتيبي',
      customerMobile: '0559876543',
      accidentDateUtcMs: DateTime.utc(2026, 10, 1),
      claimNumber: 'CLM-500',
      customerInsuranceCompany: 'تعاونية',
      liabilityPercent: 50,
      submissionDateUtcMs: DateTime.utc(2026, 10, 5),
      claimAmountSar: 12500.5,
      notes: 'ملاحظة تجريبية',
      statusKey: 'new',
      lastStatusUpdateUtcMs: DateTime.utc(2026, 10, 6),
      createdAtUtcMs: DateTime.utc(2026, 10, 1),
      updatedAtUtcMs: DateTime.utc(2026, 10, 6),
    ),
  );

  /// Bounded real-time polling until [done] (real FFI I/O on a background
  /// isolate — never pumpAndSettle the loading spinner).
  Future<void> settle(WidgetTester tester, bool Function() done) async {
    for (int i = 0; i < 300 && !done(); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
      await tester.pump();
    }
  }

  testWidgets(
    'shows all sections, the customer value, SAR amount and status chip',
    (WidgetTester tester) async {
      await tester.runAsync(() async {
        final int id = await seedFull();
        await tester.pumpWidget(_harness(db, id));
        await openDetails(tester);
        await settle(
          tester,
          () => find.text('خالد العتيبي').evaluate().isNotEmpty,
        );

        // All required section labels (spec §11 display list).
        expect(find.text(S.customerNameLabel), findsWidgets);
        expect(find.text(S.accidentDateLabel), findsWidgets);
        expect(find.text(S.submissionDateLabel), findsWidgets);
        expect(find.text(S.statusLabel), findsOneWidget);
        expect(find.text(S.lastStatusUpdateLabel), findsOneWidget);

        // Amount rendered with the SAR label via TimeUtils.formatSar.
        expect(find.text(TimeUtils.formatSar(12500.5)), findsOneWidget);

        // Status chip shows the seeded Arabic status (never color alone).
        final Claim c = (await db.claimById(id))!;
        expect(find.text(ClaimStatus.byKey(c.statusKey).label), findsWidgets);
      });
    },
  );

  /// One claim in the insurer area; [insuranceMobile] optional.
  Future<int> seedInsurer(String? insuranceMobile) {
    final DateTime now = DateTime.utc(2026, 10, 6);
    return claims.create(Claim(
      id: 0,
      customerName: 'خالد',
      customerMobile: '0501234567',
      accidentDateUtcMs: DateTime.utc(2026, 10, 1),
      claimNumber: 'CLM-INS',
      customerInsuranceCompany: 'تعاونية',
      insuranceMobile: insuranceMobile,
      statusKey: 'new',
      lastStatusUpdateUtcMs: now,
      createdAtUtcMs: now,
      updatedAtUtcMs: now,
    ));
  }

  testWidgets('insurer mobile is shown in the claim section when set', (
    WidgetTester tester,
  ) async {
    await tester.runAsync(() async {
      final int id = await seedInsurer('0561234567');
      await tester.pumpWidget(_harness(db, id));
      await openDetails(tester);
      await settle(
        tester,
        () => find.text(S.insuranceMobileLabel).evaluate().isNotEmpty,
      );
      expect(find.text('0561234567'), findsOneWidget);
    });
  });

  testWidgets('insurer mobile: no row when the claim has none', (
    WidgetTester tester,
  ) async {
    await tester.runAsync(() async {
      final int id = await seedInsurer(null);
      await tester.pumpWidget(_harness(db, id));
      await openDetails(tester);
      await settle(tester, () => find.text('خالد').evaluate().isNotEmpty);
      expect(find.text(S.insuranceMobileLabel), findsNothing);
    });
  });

  testWidgets('tapping the customer mobile row dials it', (
    WidgetTester tester,
  ) async {
    await tester.runAsync(() async {
      final int id = await seedFull(); // customerMobile '0559876543'
      final FakeDialer dialer = FakeDialer();
      await tester.pumpWidget(_harness(db, id, callNumber: dialer.call));
      await openDetails(tester);
      await settle(
        tester,
        () => find.text('0559876543').evaluate().isNotEmpty,
      );

      await tester.tap(find.byKey(const Key('call-customerMobile')));
      await tester.pump();

      expect(dialer.called, <String>['0559876543']); // exact number passed
    });
  });

  testWidgets('both phone rows dial their own numbers', (WidgetTester tester) async {
    await tester.runAsync(() async {
      final int id = await seedInsurer(
        '0561234567',
      ); // customer '0501234567'
      final FakeDialer dialer = FakeDialer();
      await tester.pumpWidget(_harness(db, id, callNumber: dialer.call));
      await openDetails(tester);
      await settle(
        tester,
        () => find.text('0561234567').evaluate().isNotEmpty,
      );

      // Insurer row first (below the fold on the test surface), then customer.
      await scrollTo(tester, find.byKey(const Key('call-insuranceMobile')));
      await tester.tap(find.byKey(const Key('call-insuranceMobile')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('call-customerMobile')));
      await tester.pump();

      // Each row dials ITS OWN number, in tap order — no cross-wiring.
      expect(dialer.called, <String>['0561234567', '0501234567']);
    });
  });

  testWidgets('a failed dial shows callFailed', (WidgetTester tester) async {
    await tester.runAsync(() async {
      final int id = await seedFull();
      final FakeDialer dialer = FakeDialer()..result = false;
      await tester.pumpWidget(_harness(db, id, callNumber: dialer.call));
      await openDetails(tester);
      await settle(
        tester,
        () => find.text('0559876543').evaluate().isNotEmpty,
      );

      await tester.tap(find.byKey(const Key('call-customerMobile')));
      await tester.pump();

      expect(dialer.called, <String>['0559876543']); // attempt was made…
      expect(find.text(S.callFailed), findsOneWidget); // …and reported.
      expect(tester.takeException(), isNull); // …without crashing.
    });
  });

  testWidgets('a throwing dialer is caught and reported', (
    WidgetTester tester,
  ) async {
    await tester.runAsync(() async {
      final int id = await seedFull();
      final FakeDialer dialer = FakeDialer()..shouldThrow = true;
      await tester.pumpWidget(_harness(db, id, callNumber: dialer.call));
      await openDetails(tester);
      await settle(
        tester,
        () => find.text('0559876543').evaluate().isNotEmpty,
      );

      await tester.tap(find.byKey(const Key('call-customerMobile')));
      await tester.pump();

      expect(find.text(S.callFailed), findsOneWidget);
      expect(tester.takeException(), isNull); // a throw must never crash
    });
  });

  testWidgets('delete: confirm removes the claim from the DB and pops', (
    WidgetTester tester,
  ) async {
    await tester.runAsync(() async {
      final int id = await seedFull();
      await tester.pumpWidget(_harness(db, id));
      await openDetails(tester);
      await settle(tester, () => find.text(S.delete).evaluate().isNotEmpty);

      await tester.tap(find.text(S.delete));
      await settle(
        tester,
        () => find.text(S.deleteClaimTitle).evaluate().isNotEmpty,
      );
      expect(find.text(S.deleteClaimBody), findsOneWidget);

      await tester.tap(find.text(S.confirm));
      await settle(
        tester,
        () => find.byType(ClaimDetailsScreen).evaluate().isEmpty,
      );

      // The claim is really gone from SQLite.
      expect(await db.claimById(id), isNull);
    });
  });

  testWidgets('delete: cancel keeps the claim in the DB', (
    WidgetTester tester,
  ) async {
    await tester.runAsync(() async {
      final int id = await seedFull();
      await tester.pumpWidget(_harness(db, id));
      await openDetails(tester);
      await settle(tester, () => find.text(S.delete).evaluate().isNotEmpty);

      await tester.tap(find.text(S.delete));
      await settle(
        tester,
        () => find.text(S.deleteClaimTitle).evaluate().isNotEmpty,
      );
      await tester.tap(find.text(S.cancel));
      await settle(tester, () => find.byType(AlertDialog).evaluate().isEmpty);

      expect(await db.claimById(id), isNotNull);
    });
  });

  testWidgets('edit pushes the claim form pre-populated with current values', (
    WidgetTester tester,
  ) async {
    await tester.runAsync(() async {
      final int id = await seedFull();
      await tester.pumpWidget(_harness(db, id));
      await openDetails(tester);
      await settle(tester, () => find.text(S.edit).evaluate().isNotEmpty);

      await tester.tap(find.text(S.edit));
      await settle(
        tester,
        () => find.byType(ClaimFormScreen).evaluate().isNotEmpty,
      );
      // The seeded customer name is pre-filled in the form.
      expect(find.text('خالد العتيبي'), findsWidgets);
    });
  });

  testWidgets('unknown id shows the not-found state', (
    WidgetTester tester,
  ) async {
    await tester.runAsync(() async {
      await tester.pumpWidget(_harness(db, 999));
      await openDetails(tester);
      await settle(
        tester,
        () => find.text(S.claimNotFound).evaluate().isNotEmpty,
      );
      expect(find.text(S.claimNotFound), findsOneWidget);
    });
  });

  testWidgets(
    'status change persists atomically with history and a new follow-up',
    (WidgetTester tester) async {
      await tester.runAsync(() async {
        final FakeScheduler fake = FakeScheduler();
        final int id = await seedFull();
        await tester.pumpWidget(_harness(db, id, scheduler: fake));
        await openDetails(tester);
        await settle(
          tester,
          () => find.text(S.changeStatus).evaluate().isNotEmpty,
        );

        // Open the dialog.
        await tester.tap(find.text(S.changeStatus));
        await settle(
          tester,
          () => find.text(S.changeStatusTitle).evaluate().isNotEmpty,
        );

        // Pick a new status from the dropdown (Arabic label only — spec §8).
        await tester.tap(find.byType(DropdownButton<String>));
        await tester.pumpAndSettle();
        await tester.tap(find.text(ClaimStatus.byKey('submitted').label));
        await tester.pumpAndSettle();

        // Optional note on the change.
        await tester.enterText(
          find.byKey(const Key('status-note')),
          'تم التقديم',
        );

        // Choose "set a new follow-up".
        await tester.tap(find.text(S.setNextFollowUp));
        await tester.pumpAndSettle();

        // Confirm — the date + time pickers open before the dialog closes.
        await tester.tap(find.text(S.save));
        await tester.pumpAndSettle();
        expect(find.byType(DatePickerDialog), findsOneWidget);
        // ar locale OK label (GlobalMaterialLocalizations.ar okButtonLabel).
        await tester.tap(find.text('حسنًا'));
        await tester.pumpAndSettle();
        expect(find.byType(TimePickerDialog), findsOneWidget);
        await tester.tap(find.text('حسنًا'));
        await tester.pumpAndSettle();
        // Strong convergence signal: the dialog only pops AFTER the full
        // persist chain (history + follow-up write + schedule) has completed —
        // matching the working pattern in the keep-follow-up test below.
        await settle(tester, () => find.byType(AlertDialog).evaluate().isEmpty);

        final Claim updated = (await db.claimById(id))!;
        expect(updated.statusKey, 'submitted');
        expect(updated.nextFollowUpUtcMs, isNotNull);
        // Creation entry + this change — history only grows (spec §9).
        final List<StatusHistoryEntry> history = await StatusHistoryRepository(
          db,
        ).listForClaim(id);
        expect(history.length, 2);
        expect(history.first.note, 'تم التقديم');
        expect(fake.scheduled.single.notificationId, id);
      });
    },
  );

  testWidgets('status change keeps the existing follow-up when chosen', (
    WidgetTester tester,
  ) async {
    await tester.runAsync(() async {
      final FakeScheduler fake = FakeScheduler();
      // Seed at millisecond precision — SQLite stores INTEGER ms, so any
      // microseconds in the seed would be truncated on round-trip.
      final DateTime now = DateTime.now();
      final DateTime fireAt = DateTime.utc(
        now.year,
        now.month,
        now.day,
        now.hour,
        now.minute,
        now.second,
      ).add(const Duration(days: 3));
      final int id = await seedFull();
      // Give the claim a follow-up date + an enabled reminder to preserve.
      await claims.update(
        (await db.claimById(id))!.copyWith(nextFollowUpUtcMs: fireAt),
      );
      await RemindersRepository(db).replaceForClaim(
        claimId: id,
        next: Reminder(
          id: 0,
          claimId: id,
          fireAtUtcMs: fireAt,
          notificationId: id,
          enabled: true,
          createdAtUtcMs: DateTime.now().toUtc(),
          updatedAtUtcMs: DateTime.now().toUtc(),
        ),
      );

      await tester.pumpWidget(_harness(db, id, scheduler: fake));
      await openDetails(tester);
      await settle(
        tester,
        () => find.text(S.changeStatus).evaluate().isNotEmpty,
      );

      await tester.tap(find.text(S.changeStatus));
      await settle(
        tester,
        () => find.text(S.changeStatusTitle).evaluate().isNotEmpty,
      );

      await tester.tap(find.byType(DropdownButton<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text(ClaimStatus.byKey('submitted').label));
      await tester.pumpAndSettle();

      // Keep the existing follow-up — no date pickers involved.
      await tester.tap(find.text(S.keepExistingFollowUp));
      await tester.pumpAndSettle();

      await tester.tap(find.text(S.save));
      await settle(tester, () => find.byType(AlertDialog).evaluate().isEmpty);

      final Claim updated = (await db.claimById(id))!;
      expect(updated.statusKey, 'submitted');
      // Follow-up date untouched.
      expect(updated.nextFollowUpUtcMs, fireAt);
      // Reminder still enabled — nothing cancelled or re-scheduled.
      final Reminder? reminder = await RemindersRepository(db)
          .latestForClaim(id);
      expect(reminder, isNotNull);
      expect(reminder!.enabled, true);
      expect(fake.cancelled, isEmpty);
      expect(fake.scheduled, isEmpty);
    });
  });

  testWidgets('status history section lists changes newest-first with notes', (
    WidgetTester tester,
  ) async {
    await tester.runAsync(() async {
      final int id = await seedFull(); // status 'new' + creation entry
      final StatusHistoryRepository history = StatusHistoryRepository(db);
      await history.changeStatus(
        claimId: id,
        newStatusKey: 'submitted',
        note: 'أولى',
      );
      await history.changeStatus(claimId: id, newStatusKey: 'approved');

      await tester.pumpWidget(_harness(db, id));
      await openDetails(tester);
      await settle(
        tester,
        () => find.text(S.statusHistoryLabel).evaluate().isNotEmpty,
      );

      // Section title visible.
      expect(find.text(S.statusHistoryLabel), findsOneWidget);

      // Scope to the history card so the status chip (same label) does not
      // interfere with the row assertions.
      final Finder historyCard = find.ancestor(
        of: find.text(S.statusHistoryLabel),
        matching: find.byType(Card),
      );
      final Finder approvedRow = find.descendant(
        of: historyCard,
        matching: find.text(ClaimStatus.byKey('approved').label),
      );
      final Finder submittedRow = find.descendant(
        of: historyCard,
        matching: find.text(ClaimStatus.byKey('submitted').label),
      );
      expect(approvedRow, findsOneWidget);
      expect(submittedRow, findsOneWidget);
      // Newest first (spec §11): the approved row sits above submitted.
      expect(
        tester.getTopLeft(approvedRow).dy,
        lessThan(tester.getTopLeft(submittedRow).dy),
      );

      // The note on the change is visible.
      expect(find.text('أولى'), findsOneWidget);

      // Current-status chip matches the claim's status after two changes.
      final Claim updated = (await db.claimById(id))!;
      expect(
        find.text(ClaimStatus.byKey(updated.statusKey).label),
        findsWidgets,
      );
    });
  });

  testWidgets('saving a reminder persists it and schedules with the stable id', (
    WidgetTester tester,
  ) async {
    await tester.runAsync(() async {
      final FakeScheduler fake = FakeScheduler();
      final int id = await seedFull();
      await tester.pumpWidget(_harness(db, id, scheduler: fake));
      await openDetails(tester);
      await settle(
        tester,
        () => find.text(S.reminderSet).evaluate().isNotEmpty,
      );

      // Set the reminder — date + time pickers (ar OK label is حسنًا).
      await scrollToReminder(tester);
      await tester.tap(find.text(S.reminderSet));
      await tester.pumpAndSettle();
      expect(find.byType(DatePickerDialog), findsOneWidget);
      await tester.tap(find.text('حسنًا'));
      await tester.pumpAndSettle();
      expect(find.byType(TimePickerDialog), findsOneWidget);
      await tester.tap(find.text('حسنًا'));
      // Persist-before-pop: the section flips to enabled only after the write.
      await settle(
        tester,
        () => find.text(S.reminderEnabled).evaluate().isNotEmpty,
      );

      final Reminder? reminder = await RemindersRepository(db)
          .latestForClaim(id);
      expect(reminder, isNotNull);
      expect(reminder!.enabled, true);
      // Stable id convention (spec §10): notificationId == claimId.
      expect(reminder.notificationId, id);
      expect(fake.scheduled.single.notificationId, id);
    });
  });

  testWidgets(
    'rescheduling reuses the same notification id and keeps one row',
    (WidgetTester tester) async {
      await tester.runAsync(() async {
        final FakeScheduler fake = FakeScheduler();
        final int id = await seedFull();
        await tester.pumpWidget(_harness(db, id, scheduler: fake));
        await openDetails(tester);
        await settle(
          tester,
          () => find.text(S.reminderSet).evaluate().isNotEmpty,
        );

        Future<void> saveOnce(int expectedScheduled) async {
          await scrollToReminder(tester);
          await tester.tap(find.text(S.reminderSet));
          await tester.pumpAndSettle();
          expect(find.byType(DatePickerDialog), findsOneWidget);
          await tester.tap(find.text('حسنًا'));
          await tester.pumpAndSettle();
          expect(find.byType(TimePickerDialog), findsOneWidget);
          await tester.tap(find.text('حسنًا'));
          // Strong convergence: the fake records a schedule only once the full
          // persist chain has completed (a text signal would already be visible
          // after the first save and race ahead of the second write).
          await settle(
            tester,
            () => fake.scheduled.length == expectedScheduled,
          );
        }

        await saveOnce(1);
        // Second save with a different date — same flow.
        await saveOnce(2);

        final RemindersRepository reminders = RemindersRepository(db);
        final Reminder? latest = await reminders.latestForClaim(id);
        expect(latest, isNotNull);
        expect(fake.scheduled.length, 2);
        // Review Focus #2: both schedules reuse the SAME stable id.
        for (final Reminder r in fake.scheduled) {
          expect(r.notificationId, id);
        }
        // Exactly one row survives two saves (replace semantics).
        final List<Reminder> all = await reminders.allEnabled();
        expect(all.where((r) => r.claimId == id), hasLength(1));

        // The screen's trailing refresh (_load after save) is fire-and-forget;
        // give it a bounded window to finish so no query outlives tearDown's
        // raw.close() (which would surface as database_closed).
        for (int i = 0; i < 100; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
          await tester.pump();
        }
      });
    },
  );

  testWidgets('cancel reminder clears the alarm and the overdue follow-up', (
    WidgetTester tester,
  ) async {
    await tester.runAsync(() async {
      final FakeScheduler fake = FakeScheduler();
      final int id = await seedFull();
      // Seed an enabled reminder that is already overdue — at ms precision
      // (SQLite stores INTEGER ms; microseconds would truncate).
      final DateTime now = DateTime.now();
      final DateTime fireAt = DateTime.utc(
        now.year,
        now.month,
        now.day,
        now.hour,
        now.minute,
        now.second,
      ).subtract(const Duration(days: 2));
      await claims.update(
        (await db.claimById(id))!.copyWith(nextFollowUpUtcMs: fireAt),
      );
      await RemindersRepository(db).replaceForClaim(
        claimId: id,
        next: Reminder(
          id: 0,
          claimId: id,
          fireAtUtcMs: fireAt,
          notificationId: id,
          enabled: true,
          createdAtUtcMs: DateTime.now().toUtc(),
          updatedAtUtcMs: DateTime.now().toUtc(),
        ),
      );

      await tester.pumpWidget(_harness(db, id, scheduler: fake));
      await openDetails(tester);
      await settle(
        tester,
        () => find.text(S.reminderEnabled).evaluate().isNotEmpty,
      );
      await scrollToReminder(tester);
      expect(find.text(S.reminderDisable), findsOneWidget);

      await tester.tap(find.text(S.reminderDisable));
      // Persist-before-pop: the section flips to disabled after the write.
      await settle(
        tester,
        () => find.text(S.reminderDisabled).evaluate().isNotEmpty,
      );

      expect(fake.cancelled, contains(id));
      final Reminder? reminder = await RemindersRepository(db)
          .latestForClaim(id);
      expect(reminder, isNull, reason: 'reminder row is removed');
      // The follow-up date is cleared, so the claim leaves the overdue list.
      final Claim updated = (await db.claimById(id))!;
      expect(updated.nextFollowUpUtcMs, isNull);
      expect(await claims.overdue(DateTime.now().toUtc()), isEmpty);
    });
  });

  testWidgets('denied permission still persists the reminder and explains', (
    WidgetTester tester,
  ) async {
    await tester.runAsync(() async {
      final FakeScheduler fake = FakeScheduler()
        ..notificationsEnabled = false
        ..requestResult = NotificationPermissionState.denied;
      final int id = await seedFull();
      await tester.pumpWidget(_harness(db, id, scheduler: fake));
      await openDetails(tester);
      await settle(
        tester,
        () => find.text(S.reminderSet).evaluate().isNotEmpty,
      );

      // Save — notifications are disabled on this device, so the permission
      // explanation appears first (Review Focus #4).
      await scrollToReminder(tester);
      await tester.tap(find.text(S.reminderSet));
      await tester.pumpAndSettle();
      expect(find.byType(DatePickerDialog), findsOneWidget);
      await tester.tap(find.text('حسنًا'));
      await tester.pumpAndSettle();
      expect(find.byType(TimePickerDialog), findsOneWidget);
      await tester.tap(find.text('حسنًا'));
      // Permission explanation with an allow action.
      await settle(
        tester,
        () => find.text(S.notificationsPermissionBody).evaluate().isNotEmpty,
      );
      await tester.tap(find.text(S.confirm)); // allow → request permission
      // Still denied: the reminder persists in-app and the Arabic
      // explanation is shown afterwards.
      await settle(
        tester,
        () => find.text(S.notificationsDeniedBody).evaluate().isNotEmpty,
      );
      await tester.tap(find.text(S.confirm));
      await tester.pumpAndSettle();

      // In-app state persisted even though scheduling was skipped.
      final Reminder? reminder = await RemindersRepository(db)
          .latestForClaim(id);
      expect(reminder, isNotNull);
      expect(reminder!.enabled, true);
      expect(fake.scheduled, isEmpty);
    });
  });

  testWidgets(
    'BUG B: denial dialog offers opening the system notification settings',
    (WidgetTester tester) async {
      final FakeScheduler fake = FakeScheduler()
        ..notificationsEnabled = false
        ..requestResult = NotificationPermissionState.denied;

      await tester.runAsync(() async {
        final int id = await seedFull();
        await tester.pumpWidget(_harness(db, id, scheduler: fake));
        await openDetails(tester);
        await settle(
          tester,
          () => find.text(S.reminderSet).evaluate().isNotEmpty,
        );

        await scrollToReminder(tester);
        await tester.tap(find.text(S.reminderSet));
        await tester.pumpAndSettle();
        expect(find.byType(DatePickerDialog), findsOneWidget);
        await tester.tap(find.text('حسنًا'));
        await tester.pumpAndSettle();
        expect(find.byType(TimePickerDialog), findsOneWidget);
        await tester.tap(find.text('حسنًا'));
        // Permission explanation → allow → still denied.
        await settle(
          tester,
          () => find.text(S.notificationsPermissionBody).evaluate().isNotEmpty,
        );
        await tester.tap(find.text(S.confirm));
        // The denial dialog must now offer a direct jump into the system
        // notification settings (BUG B: previously static text only).
        await settle(
          tester,
          () => find.text(S.notificationsDeniedBody).evaluate().isNotEmpty,
        );
        expect(
          find.byKey(const Key('open-notification-settings')),
          findsOneWidget,
        );

        await tester.tap(find.byKey(const Key('open-notification-settings')));
        // The action pops the dialog and invokes the OS settings page — the
        // invocation lands in an async continuation after the pop, so poll.
        for (int i = 0; i < 200 && fake.openedSettings == 0; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 5));
          await tester.pump();
        }
      });

      expect(fake.openedSettings, 1);
    },
  );

  // ---------------------------------------------------------------------
  // Phase 1 fix #1/#3 — exact-alarm request flow + surfaced scheduling
  // outcomes (inexact warning / failure) on the reminder-save path.
  // ---------------------------------------------------------------------

  testWidgets(
    'Phase 1: denied exact alarms → explanation dialog, then request',
    (WidgetTester tester) async {
      final FakeScheduler fake = FakeScheduler()..exactAllowed = false;

      await tester.runAsync(() async {
        final int id = await seedFull();
        await tester.pumpWidget(_harness(db, id, scheduler: fake));
        await openDetails(tester);
        await settle(
          tester,
          () => find.text(S.reminderSet).evaluate().isNotEmpty,
        );

        await scrollToReminder(tester);
        await tester.tap(find.text(S.reminderSet));
        await tester.pumpAndSettle();
        expect(find.byType(DatePickerDialog), findsOneWidget);
        await tester.tap(find.text('حسنًا'));
        await tester.pumpAndSettle();
        expect(find.byType(TimePickerDialog), findsOneWidget);
        await tester.tap(find.text('حسنًا'));

        // The exact-alarm explanation must appear BEFORE the system request.
        await settle(
          tester,
          () => find.text(S.exactAlarmExplainBody).evaluate().isNotEmpty,
        );
        expect(find.byKey(const Key('request-exact-alarms')), findsOneWidget);

        // Allow → the permission is requested exactly once.
        await tester.tap(find.byKey(const Key('request-exact-alarms')));
        for (int i = 0; i < 200 && fake.exactRequestCalls == 0; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 5));
          await tester.pump();
        }

        // The reminder still persisted with the stable id.
        final Reminder? reminder = await RemindersRepository(db)
            .latestForClaim(id);
        expect(reminder, isNotNull);
        expect(reminder!.enabled, true);
        expect(reminder.notificationId, id);
      });

      expect(fake.exactRequestCalls, 1);
    },
  );

  testWidgets('Phase 1: inexact schedule → visible "may be late" warning', (
    WidgetTester tester,
  ) async {
    final FakeScheduler fake = FakeScheduler()
      ..scheduleResult = AlarmPrecision.inexact;

    await tester.runAsync(() async {
      final int id = await seedFull();
      await tester.pumpWidget(_harness(db, id, scheduler: fake));
      await openDetails(tester);
      await settle(
        tester,
        () => find.text(S.reminderSet).evaluate().isNotEmpty,
      );

      await scrollToReminder(tester);
      await tester.tap(find.text(S.reminderSet));
      await tester.pumpAndSettle();
      expect(find.byType(DatePickerDialog), findsOneWidget);
      await tester.tap(find.text('حسنًا'));
      await tester.pumpAndSettle();
      expect(find.byType(TimePickerDialog), findsOneWidget);
      await tester.tap(find.text('حسنًا'));

      // The user must be told the reminder may arrive late (Phase 1 fix #3).
      await settle(
        tester,
        () => find.text(S.reminderInexactWarning).evaluate().isNotEmpty,
      );

      // ...and the reminder is still persisted + scheduled.
      final Reminder? reminder = await RemindersRepository(db)
          .latestForClaim(id);
      expect(reminder, isNotNull);
      expect(reminder!.enabled, true);
      expect(fake.scheduled.single.notificationId, id);
    });
  });

  testWidgets('Phase 1: scheduling failure → visible error, state persisted', (
    WidgetTester tester,
  ) async {
    final FakeScheduler fake = FakeScheduler()..throwOnSchedule = true;

    await tester.runAsync(() async {
      final int id = await seedFull();
      await tester.pumpWidget(_harness(db, id, scheduler: fake));
      await openDetails(tester);
      await settle(
        tester,
        () => find.text(S.reminderSet).evaluate().isNotEmpty,
      );

      await scrollToReminder(tester);
      await tester.tap(find.text(S.reminderSet));
      await tester.pumpAndSettle();
      expect(find.byType(DatePickerDialog), findsOneWidget);
      await tester.tap(find.text('حسنًا'));
      await tester.pumpAndSettle();
      expect(find.byType(TimePickerDialog), findsOneWidget);
      await tester.tap(find.text('حسنًا'));

      // The failure must be surfaced — not silently swallowed (Phase 1 fix #3).
      await settle(
        tester,
        () => find.text(S.reminderScheduleFailed).evaluate().isNotEmpty,
      );

      // In-app state persisted even though the OS alarm could not be set.
      final Reminder? reminder = await RemindersRepository(db)
          .latestForClaim(id);
      expect(reminder, isNotNull);
      expect(reminder!.enabled, true);
      expect(fake.scheduled, isEmpty);
    });
  });

  // ---------------------------------------------------------------------
  // Attachments (spec §12): list / add / open / delete on the details screen.
  // ---------------------------------------------------------------------

  testWidgets('attachments section shows the empty state and an add button', (
    WidgetTester tester,
  ) async {
    await tester.runAsync(() async {
      final int id = await seedFull();
      await tester.pumpWidget(_harness(db, id));
      await openDetails(tester);
      await settle(
        tester,
        () => find.text(S.attachmentsLabel).evaluate().isNotEmpty,
      );

      expect(find.text(S.attachmentsEmpty), findsOneWidget);
      expect(find.byKey(const Key('attach-add')), findsOneWidget);
    });
  });

  testWidgets('add: copies the picked file into the store and records it', (
    WidgetTester tester,
  ) async {
    await tester.runAsync(() async {
      final int id = await seedFull();
      final Directory store = Directory.systemTemp.createTempSync('ct-store');
      final File source = File('${store.path}/source/صورة الحادث.png')
        ..createSync(recursive: true)
        ..writeAsBytesSync(<int>[1, 2, 3]);

      final _FakePicker picker = _FakePicker()
        ..next = [_FakePlatformFile(source.path)];
      await tester.pumpWidget(
        _harness(
          db,
          id,
          picker: picker,
          files: AttachmentFileService(baseDir: store),
        ),
      );
      await openDetails(tester);
      await settle(
        tester,
        () => find.text(S.attachmentsLabel).evaluate().isNotEmpty,
      );

      await scrollTo(tester, find.byKey(const Key('attach-add')));
      await tester.tap(find.byKey(const Key('attach-add')));
      await settle(
        tester,
        () => find.text('صورة الحادث.png').evaluate().isNotEmpty,
      );

      // The row is recorded with the copied size and a real MIME type.
      final List<Attachment> rows = await AttachmentsRepository(db)
          .listForClaim(id);
      expect(rows, hasLength(1));
      expect(rows.single.originalName, 'صورة الحادث.png');
      expect(rows.single.sizeBytes, 3);
      expect(rows.single.mimeType, 'image/png');

      // The file was COPIED into the app-private store; source stays put.
      final Attachment a = rows.single;
      final File stored = File('${store.path}/${a.relativePath}');
      expect(stored.existsSync(), true);
      expect(await stored.readAsBytes(), <int>[1, 2, 3]);
      expect(source.existsSync(), true);

      // A delete affordance exists for the new row.
      expect(find.byKey(Key('attach-del-${a.id}')), findsOneWidget);
    });
  });

  testWidgets('open: an image attachment previews in-app', (
    WidgetTester tester,
  ) async {
    await tester.runAsync(() async {
      final int id = await seedFull();
      final Directory store = Directory.systemTemp.createTempSync('ct-store');
      // A real 1x1 PNG so Image.file can actually decode it.
      final File stored = File('${store.path}/1-test/pixel.png')
        ..createSync(recursive: true)
        ..writeAsBytesSync(
          base64Decode(
            'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJ'
            'AAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==',
          ),
        );

      final int rowId = await AttachmentsRepository(db).create(
        Attachment(
          id: 0,
          claimId: id,
          originalName: 'pixel.png',
          mimeType: 'image/png',
          sizeBytes: stored.lengthSync(),
          relativePath: '1-test/pixel.png',
          createdAtUtcMs: DateTime.utc(2026, 10, 1),
        ),
      );

      await tester.pumpWidget(
        _harness(db, id, files: AttachmentFileService(baseDir: store)),
      );
      await openDetails(tester);
      await settle(tester, () => find.text('pixel.png').evaluate().isNotEmpty);

      await scrollTo(tester, find.text('pixel.png'));
      await tester.tap(find.text('pixel.png'));
      // The preview dialog shows the image and a close action.
      await settle(
        tester,
        () =>
            find.byType(Image).evaluate().isNotEmpty &&
            find.text(S.close).evaluate().isNotEmpty,
      );

      // Close before leaving so no decode/timer work is left pending.
      await tester.tap(find.text(S.close));
      await settle(tester, () => find.byType(Image).evaluate().isEmpty);
      expect(rowId, greaterThan(0));
    });
  });

  testWidgets(
    'open: a non-image without an external app explains the failure',
    (WidgetTester tester) async {
      await tester.runAsync(() async {
        final int id = await seedFull();
        final Directory store = Directory.systemTemp.createTempSync('ct-store');
        File('${store.path}/2-pdf/تقرير.pdf')
          ..createSync(recursive: true)
          ..writeAsBytesSync(<int>[1, 37]);

        await AttachmentsRepository(db).create(
          Attachment(
            id: 0,
            claimId: id,
            originalName: 'تقرير.pdf',
            mimeType: 'application/pdf',
            sizeBytes: 2,
            relativePath: '2-pdf/تقرير.pdf',
            createdAtUtcMs: DateTime.utc(2026, 10, 1),
          ),
        );

        await tester.pumpWidget(
          _harness(
            db,
            id,
            files: AttachmentFileService(baseDir: store),
            openExternal: (Uri uri) async => false,
          ),
        );
        await openDetails(tester);
        await settle(
          tester,
          () => find.text('تقرير.pdf').evaluate().isNotEmpty,
        );

        await scrollTo(tester, find.text('تقرير.pdf'));
        await tester.tap(find.text('تقرير.pdf'));
        await settle(
          tester,
          () => find.text(S.attachmentOpenFailed).evaluate().isNotEmpty,
        );

        // Let the SnackBar's auto-dismiss timer fire AND its exit animation
        // complete before the test ends — under runAsync a duration-less pump
        // does not advance tickers, so the exit would hang forever.
        for (
          int i = 0;
          i < 900 && find.text(S.attachmentOpenFailed).evaluate().isNotEmpty;
          i++
        ) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
          await tester.pump(const Duration(milliseconds: 16));
        }
        expect(find.text(S.attachmentOpenFailed), findsNothing);
      });
    },
  );

  testWidgets('delete attachment: confirms, removes the row and the file', (
    WidgetTester tester,
  ) async {
    await tester.runAsync(() async {
      final int id = await seedFull();
      final Directory store = Directory.systemTemp.createTempSync('ct-store');
      final File stored = File('${store.path}/3-del/doc.txt')
        ..createSync(recursive: true)
        ..writeAsBytesSync(<int>[9, 8]);

      final int rowId = await AttachmentsRepository(db).create(
        Attachment(
          id: 0,
          claimId: id,
          originalName: 'doc.txt',
          mimeType: 'text/plain',
          sizeBytes: 2,
          relativePath: '3-del/doc.txt',
          createdAtUtcMs: DateTime.utc(2026, 10, 1),
        ),
      );

      await tester.pumpWidget(
        _harness(db, id, files: AttachmentFileService(baseDir: store)),
      );
      await openDetails(tester);
      await settle(tester, () => find.text('doc.txt').evaluate().isNotEmpty);

      await scrollTo(tester, find.byKey(Key('attach-del-$rowId')));
      await tester.tap(find.byKey(Key('attach-del-$rowId')));
      await settle(
        tester,
        () => find.text(S.deleteAttachmentTitle).evaluate().isNotEmpty,
      );
      expect(find.text(S.deleteAttachmentBody), findsOneWidget);

      await tester.tap(find.text(S.confirm));
      await settle(
        tester,
        () => find.text(S.attachmentsEmpty).evaluate().isNotEmpty,
      );

      // Row and physical file are both gone.
      expect(await AttachmentsRepository(db).listForClaim(id), isEmpty);
      expect(stored.existsSync(), false);
    });
  });

  testWidgets(
    'a row whose file is missing still lists, flags and stays usable',
    (WidgetTester tester) async {
      await tester.runAsync(() async {
        final int id = await seedFull();
        final Directory store = Directory.systemTemp.createTempSync('ct-store');

        // A row pointing at a file that does not exist on disk.
        await AttachmentsRepository(db).create(
          Attachment(
            id: 0,
            claimId: id,
            originalName: 'ghost.png',
            mimeType: 'image/png',
            sizeBytes: 10,
            relativePath: '999/ghost.png',
            createdAtUtcMs: DateTime.utc(2026, 10, 1),
          ),
        );

        final File source = File('${store.path}/source/new.txt')
          ..createSync(recursive: true)
          ..writeAsBytesSync(<int>[7]);
        final _FakePicker picker = _FakePicker()
          ..next = [_FakePlatformFile(source.path)];

        await tester.pumpWidget(
          _harness(
            db,
            id,
            picker: picker,
            files: AttachmentFileService(baseDir: store),
          ),
        );
        await openDetails(tester);
        await settle(
          tester,
          () => find.text('ghost.png').evaluate().isNotEmpty,
        );

        // The missing file is flagged next to the name.
        expect(find.text(S.attachmentMissing), findsOneWidget);

        // Adding still works alongside the broken row.
        await scrollTo(tester, find.byKey(const Key('attach-add')));
        await tester.tap(find.byKey(const Key('attach-add')));
        await settle(tester, () => find.text('new.txt').evaluate().isNotEmpty);
        expect(await AttachmentsRepository(db).listForClaim(id), hasLength(2));
      });
    },
  );
}
