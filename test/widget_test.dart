/// Full-shell tests (spec §4): RTL, Arabic navigation labels, both themes,
/// destination switching, and the end-to-end add-claim flow with persistence
/// across a simulated restart (Review Focus #5).
///
/// Harness rules (see dashboard/claims/details/settings test notes): the shell
/// does real FFI SQLite I/O in initState → ONE `tester.runAsync` block + bounded
/// polling; never `pumpAndSettle` while a loading spinner is pending, and keep
/// ALL FFI I/O inside the async zone (it hangs under fake-async otherwise).
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart' as ffi;

import 'package:claim_tracker/core/constants/insurers.dart';
import 'package:claim_tracker/app/home_shell.dart';
import 'package:claim_tracker/core/database/app_database.dart';
import 'package:claim_tracker/core/database/claims_repository.dart';
import 'package:claim_tracker/core/database/settings_repository.dart';
import 'package:claim_tracker/core/l10n/app_strings.dart';
import 'package:claim_tracker/core/models/claim.dart';
import 'package:claim_tracker/core/models/reminder.dart';
import 'package:claim_tracker/core/notifications/notification_service.dart';
import 'package:claim_tracker/core/notifications/reminder_scheduler.dart';
import 'package:claim_tracker/core/theme/app_theme.dart';
import 'package:claim_tracker/core/utils/time_utils.dart';
import 'package:claim_tracker/features/claims/claim_details_screen.dart';
import 'package:claim_tracker/features/claims/claim_form_screen.dart';

/// Recording scheduler for the shell's reminder flows (no method channels on
/// host). Defaults mirror "everything granted, exact alarms allowed" so the
/// permission dialogs never appear in these tests.
class FakeScheduler implements ReminderScheduler {
  final List<Reminder> scheduled = [];
  final List<int> cancelled = [];

  @override
  Future<void> cancelReminder(int notificationId) async =>
      cancelled.add(notificationId);

  @override
  Future<AlarmPrecision> scheduleReminder(Reminder reminder) async {
    scheduled.add(reminder);
    return AlarmPrecision.exact;
  }

  @override
  Future<bool> areNotificationsEnabled() async => true;

  @override
  Future<NotificationPermissionState> requestNotificationsPermission() async =>
      NotificationPermissionState.granted;

  @override
  Future<void> reconcile(List<Reminder> enabledReminders) async {}

  @override
  Future<bool> openAppNotificationSettings() async => true;

  @override
  Future<bool> canScheduleExactAlarms() async => true;

  @override
  Future<bool> requestExactAlarmsPermission() async => true;

  @override
  Future<bool> isIgnoringBatteryOptimizations() async => true;

  @override
  Future<bool> requestIgnoreBatteryOptimizations() async => true;
}

Widget _harness(
  AppDatabase db,
  ThemeMode mode, {
  ReminderScheduler? scheduler,
}) {
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
    themeMode: mode,
    builder: (BuildContext context, Widget? child) {
      // Mirror ClaimTrackerApp: force RTL regardless of device locale.
      return Directionality(
        textDirection: TextDirection.rtl,
        child: child ?? const SizedBox.shrink(),
      );
    },
    home: HomeShell(
      db: db,
      settingsRepo: SettingsRepository(db),
      currentThemeMode: mode == ThemeMode.dark
          ? ThemeMode.dark
          : ThemeMode.light,
      onThemeChanged: (ThemeMode _) {},
      scheduler: scheduler,
    ),
  );
}

/// Bounded real-time polling until [done] — the screens' FFI loads run on a
/// background isolate; never pumpAndSettle over an indeterminate spinner.
///
/// Each iteration pumps WITH a duration: a bare `pump()` never elapses the
/// test clock, so route transitions would stay frozen mid-slide and swallow
/// taps meant for the newly pushed page (observed on the e2e date-row tap).
///
/// 450 iterations ≈ up to ~9 s of real time: under full-suite parallel load
/// the FFI isolate's message queue is contended, so a screen's initial load
/// can take far longer than in isolation. (A bare pump loop — no real-time
/// delay — starves that queue and leaves loads pending forever.)
Future<void> settle(WidgetTester tester, bool Function() done) async {
  for (int i = 0; i < 450 && !done(); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 5));
    await tester.pump(const Duration(milliseconds: 16));
  }
}

/// Pumps a fixed amount of real frame-time so route transitions and inertial
/// scrolls fully settle. Bounded, so it can never hang on an indeterminate
/// spinner (which schedules frames forever) — unlike pumpAndSettle.
Future<void> _settle(WidgetTester tester, {int frames = 60}) async {
  for (int i = 0; i < frames; i++) {
    await Future<void>.delayed(const Duration(milliseconds: 5));
    await tester.pump(const Duration(milliseconds: 16));
  }
}

/// Opens a fresh in-memory DB with the full schema (proven setUp pattern).
///
/// `singleInstance: false` is REQUIRED here: sqflite_common caches open
/// helpers per path (`databaseOpenHelpers[':memory:']`) and re-opens return
/// the SAME already-open database. Every test file in this suite shares that
/// one ':memory:' key, so without it a later `_openInMemory()` would hand
/// back an earlier test's migrated connection and `AppDatabase.migrate`
/// would throw "table claims already exists" (observed under parallel load).
Future<ffi.Database> _openInMemory() async {
  final ffi.Database raw = await ffi.databaseFactoryFfi.openDatabase(
    ffi.inMemoryDatabasePath,
    options: ffi.OpenDatabaseOptions(singleInstance: false),
  );
  await raw.execute('PRAGMA foreign_keys = ON');
  await AppDatabase.migrate(raw, from: 0, to: kDatabaseVersion);
  return raw;
}

/// Opens (creating on first use) a FILE-backed DB at [path] — the same
/// contract as `AppDatabase.open`, over the FFI factory. Reopening an existing
/// file must NOT re-run the schema and MUST keep its data (restart simulation).
/// Uses the global `openDatabase` (named-param form), which delegates to the
/// active FFI factory after `sqfliteFfiInit()`.
Future<ffi.Database> _openAt(String path) {
  return ffi.openDatabase(
    path,
    version: kDatabaseVersion,
    onConfigure: (ffi.Database db) async =>
        db.execute('PRAGMA foreign_keys = ON'),
    onCreate: (ffi.Database db, int _) =>
        AppDatabase.migrate(db, from: 0, to: kDatabaseVersion),
  );
}

/// The form's own scroll view (the shell has several — scope to the form).
Finder _formScroll() => find.descendant(
  of: find.byType(ClaimFormScreen),
  matching: find.byType(SingleChildScrollView),
);

/// Scrolls [f] into the free viewport inside the pushed form.
Future<void> _tappableInForm(WidgetTester tester, Finder f) async {
  for (int i = 0; i < 40; i++) {
    // Settle any in-flight route transition / inertial scroll BEFORE measuring,
    // mirroring the proven pumpAndSettle-per-iteration approach.
    await _settle(tester, frames: 30);
    final Offset c = tester.getCenter(f);
    if (c.dy > 100 && c.dy < 495) return;
    await tester.drag(_formScroll(), Offset(0, c.dy < 300 ? 260 : -260));
  }
}

/// Opens the date picker for [row] and accepts the default (today).
Future<void> _pickDate(WidgetTester tester, String row) async {
  final Finder rowFinder = find.byKey(Key('date-$row'));
  FocusManager.instance.primaryFocus?.unfocus();
  // Let the focus change (and its auto-scroll) settle before measuring.
  await tester.pump(const Duration(milliseconds: 16));
  await _tappableInForm(tester, rowFinder);
  await tester.tap(rowFinder);
  await settle(
    tester,
    () => find.byType(DatePickerDialog).evaluate().isNotEmpty,
  );
  expect(find.byType(DatePickerDialog), findsOneWidget);
  // ar locale OK label (GlobalMaterialLocalizations.ar okButtonLabel).
  await tester.tap(find.text('حسنًا'));
  await settle(tester, () => find.byType(DatePickerDialog).evaluate().isEmpty);
}

/// Taps a bottom-navigation destination unambiguously (screen AppBars reuse
/// the same Arabic labels, so scope to the NavigationBar).
Future<void> _tapNav(WidgetTester tester, String label) async {
  await tester.tap(
    find.descendant(of: find.byType(NavigationBar), matching: find.text(label)),
  );
}

void main() {
  // The notification-tap hook is a static — reset it between tests so no test
  // can observe another shell's handler.
  tearDown(() {
    HomeShell.openClaimFromNotification = null;
  });

  setUpAll(() async {
    ffi.sqfliteFfiInit();
    // This sqflite_common_ffi version does not wire the global factory in
    // sqfliteFfiInit — required for the global `openDatabase` (named-param)
    // API used by `_openAt`.
    ffi.databaseFactory = ffi.databaseFactoryFfi;
    await TimeUtils.ensureInitialized();
  });

  testWidgets('shell renders RTL with Arabic navigation labels (light)', (
    WidgetTester tester,
  ) async {
    await tester.runAsync(() async {
      final ffi.Database raw = await _openInMemory();
      final AppDatabase db = AppDatabase.fromExisting(raw);

      await tester.pumpWidget(_harness(db, ThemeMode.light));
      // Dashboard loads via real FFI I/O — poll until its content is in.
      await settle(
        tester,
        () => find.text(S.dashTotalClaims).evaluate().isNotEmpty,
      );

      // Each destination label appears in the bottom navigation bar.
      final Finder nav = find.byType(NavigationBar);
      for (final String label in <String>[
        S.navDashboard,
        S.navClaims,
        S.navSettings,
      ]) {
        expect(
          find.descendant(of: nav, matching: find.text(label)),
          findsOneWidget,
          reason: label,
        );
      }
      // The Follow-ups tab was removed (its filter lives on the claims page).
      expect(
        find.descendant(of: nav, matching: find.text(S.navReminders)),
        findsNothing,
      );

      // RTL direction is applied to the shell.
      final Directionality dir = tester.firstWidget<Directionality>(
        find.byType(Directionality).first,
      );
      expect(dir.textDirection, TextDirection.rtl);

      await raw.close();
    });
  });

  testWidgets('shell renders in dark theme without errors', (
    WidgetTester tester,
  ) async {
    await tester.runAsync(() async {
      final ffi.Database raw = await _openInMemory();
      final AppDatabase db = AppDatabase.fromExisting(raw);

      await tester.pumpWidget(_harness(db, ThemeMode.dark));
      await settle(
        tester,
        () => find.text(S.dashTotalClaims).evaluate().isNotEmpty,
      );

      expect(find.byType(Material), findsWidgets);
      expect(tester.takeException(), isNull);

      await raw.close();
    });
  });

  testWidgets('navigation switches to the claims list', (
    WidgetTester tester,
  ) async {
    await tester.runAsync(() async {
      final ffi.Database raw = await _openInMemory();
      final AppDatabase db = AppDatabase.fromExisting(raw);

      await tester.pumpWidget(_harness(db, ThemeMode.light));
      await settle(
        tester,
        () => find.text(S.dashTotalClaims).evaluate().isNotEmpty,
      );

      await _tapNav(tester, S.navClaims);
      // Empty database → the list's honest empty state (spec §6).
      await settle(
        tester,
        () => find.text(S.claimsEmpty).evaluate().isNotEmpty,
      );
      expect(find.text(S.claimsEmpty), findsOneWidget);
      expect(tester.takeException(), isNull);

      await raw.close();
    });
  });

  testWidgets(
    'add claim end-to-end: FAB → form → save → card visible, and the claim '
    'survives a restart (Review Focus #5)',
    (WidgetTester tester) async {
      late Directory dir;
      late String dbPath;

      await tester.runAsync(() async {
        dir = await Directory.systemTemp.createTemp('claim_tracker_e2e');
        dbPath = '${dir.path}${Platform.pathSeparator}claim_tracker.sqlite';

        // ---- Session 1: add a claim through the real UI. -------------------
        final ffi.Database raw1 = await _openAt(dbPath);
        final AppDatabase db1 = AppDatabase.fromExisting(raw1);

        await tester.pumpWidget(_harness(db1, ThemeMode.light));
        // Prominent Add Claim FAB (spec §4) on the dashboard destination.
        await settle(tester, () => find.text(S.addClaim).evaluate().isNotEmpty);
        expect(find.text(S.addClaim), findsOneWidget);

        await tester.tap(find.text(S.addClaim));
        await settle(
          tester,
          () => find.byType(ClaimFormScreen).evaluate().isNotEmpty,
        );
        // The pushed route is still animating in — settle the transition fully
        // before any tap-based interaction (enterText masked this because it
        // needs no hit-testing).
        await _settle(tester);

        // Fill the five required text fields (enterText needs no visibility).
        await tester.enterText(
          find.byKey(const Key('field-customerName')),
          'خالد',
        );
        await tester.enterText(
          find.byKey(const Key('field-mobile')),
          '0559876543',
        );
        await tester.enterText(
          find.byKey(const Key('field-claimNumber')),
          'CLM-E2E',
        );
        await tester.enterText(
          find.byKey(const Key('field-plate')),
          '4051 VJD',
        );
        await tester.enterText(
          find.byKey(const Key('field-vehicleType')),
          'Camry 2022',
        );
        // Insurer comes from the list.
        final Finder insurer = find.byKey(const Key('field-insurerChoice'));
        FocusManager.instance.primaryFocus?.unfocus();
        await tester.pump(const Duration(milliseconds: 16));
        await _tappableInForm(tester, insurer);
        await tester.tap(insurer);
        await _settle(tester);
        await tester.tap(find.text(Insurers.all.first.label).last);
        await _settle(tester);
        // And the two required dates.
        await _pickDate(tester, 'accident');
        await _pickDate(tester, 'submission');

        // Save persists (real FFI I/O) and closes the form — poll for both.
        await tester.tap(find.text(S.save));
        await settle(
          tester,
          () => find.byType(ClaimFormScreen).evaluate().isEmpty,
        );

        // Back on the shell → claims list shows the new card (same session).
        await _tapNav(tester, S.navClaims);
        await settle(tester, () => find.text('CLM-E2E').evaluate().isNotEmpty);
        expect(find.text('CLM-E2E'), findsOneWidget);

        // ---- Restart simulation: unmount tree, close DB, reopen fresh. -----
        await tester.pumpWidget(const SizedBox.shrink());
        await raw1.close();

        final ffi.Database raw2 = await _openAt(dbPath);
        final AppDatabase db2 = AppDatabase.fromExisting(raw2);

        await tester.pumpWidget(_harness(db2, ThemeMode.light));
        await settle(
          tester,
          () => find.text(S.dashTotalClaims).evaluate().isNotEmpty,
        );
        await _tapNav(tester, S.navClaims);
        // The claim is still there after the "restart".
        await settle(tester, () => find.text('CLM-E2E').evaluate().isNotEmpty);
        expect(find.text('CLM-E2E'), findsOneWidget);

        // And it is really in SQLite, not just rendered.
        final List<Claim> all = await ClaimsRepository(db2).all();
        expect(all.any((c) => c.claimNumber == 'CLM-E2E'), isTrue);

        await raw2.close();
        await dir.delete(recursive: true);
      });
    },
  );

  testWidgets(
    'add claim WITH a follow-up: date+time pickers appear, and the saved '
    'reminder is persisted ENABLED with its OS alarm scheduled (the original bug)',
    (WidgetTester tester) async {
      await tester.runAsync(() async {
        final ffi.Database raw = await _openInMemory();
        final AppDatabase db = AppDatabase.fromExisting(raw);
        final FakeScheduler fake = FakeScheduler();

        await tester.pumpWidget(_harness(db, ThemeMode.light, scheduler: fake));
        await settle(tester, () => find.text(S.addClaim).evaluate().isNotEmpty);
        expect(find.text(S.addClaim), findsOneWidget);

        // Open the form through the real FAB.
        await tester.tap(find.text(S.addClaim));
        await settle(
          tester,
          () => find.byType(ClaimFormScreen).evaluate().isNotEmpty,
        );
        await _settle(tester);

        // Required fields (same flow as the plain add e2e above).
        await tester.enterText(
          find.byKey(const Key('field-customerName')),
          'خالد',
        );
        await tester.enterText(
          find.byKey(const Key('field-plate')),
          '4051 VJD',
        );
        await tester.enterText(
          find.byKey(const Key('field-vehicleType')),
          'Camry 2022',
        );
        final Finder insurer = find.byKey(const Key('field-insurerChoice'));
        FocusManager.instance.primaryFocus?.unfocus();
        await tester.pump(const Duration(milliseconds: 16));
        await _tappableInForm(tester, insurer);
        await tester.tap(insurer);
        await _settle(tester);
        await tester.tap(find.text(Insurers.all.first.label).last);
        await _settle(tester);
        await _pickDate(tester, 'accident');

        // THE follow-up pick: date dialog … then a TIME dialog must appear.
        final Finder followUp = find.byKey(const Key('date-followup'));
        FocusManager.instance.primaryFocus?.unfocus();
        await tester.pump(const Duration(milliseconds: 16));
        await _tappableInForm(tester, followUp);
        await tester.tap(followUp);
        await settle(
          tester,
          () => find.byType(DatePickerDialog).evaluate().isNotEmpty,
        );
        expect(find.byType(DatePickerDialog), findsOneWidget);
        await tester.tap(find.text('حسنًا')); // accept the date …
        await settle(
          tester,
          () => find.byType(TimePickerDialog).evaluate().isNotEmpty,
        );
        // The regression under test: no time picker used to appear at all.
        expect(find.byType(TimePickerDialog), findsOneWidget);
        await tester.tap(find.text('حسنًا').last); // … and the time.
        await settle(
          tester,
          () => find.byType(TimePickerDialog).evaluate().isEmpty,
        );

        // Save — persists AND schedules through the injected scheduler.
        FocusManager.instance.primaryFocus?.unfocus();
        await _tappableInForm(tester, find.text(S.save));
        await tester.tap(find.text(S.save));
        await settle(
          tester,
          () => find.byType(ClaimFormScreen).evaluate().isEmpty,
        );

        // Exactly one claim … with an enabled reminder row at the SAME instant.
        final List<Claim> claims = await ClaimsRepository(db).all();
        expect(claims, hasLength(1));
        final Claim c = claims.single;
        expect(c.nextFollowUpUtcMs, isNotNull);

        final List<Map<String, Object?>> rows = await raw.query(
          'reminders',
          where: 'claim_id = ?',
          whereArgs: [c.id],
        );
        expect(rows, hasLength(1));
        expect(rows.single['enabled'], 1);
        expect(
          rows.single['fire_at_utc_ms'],
          c.nextFollowUpUtcMs!.millisecondsSinceEpoch,
        );

        // … and exactly ONE OS alarm scheduled for it (stable id == claimId).
        expect(fake.scheduled, hasLength(1));
        expect(fake.scheduled.single.notificationId, c.id);
        expect(fake.scheduled.single.fireAtUtcMs, c.nextFollowUpUtcMs!.toUtc());

        await raw.close();
      });
    },
  );

  testWidgets('notification tap opens the correct claim details', (
    WidgetTester tester,
  ) async {
    await tester.runAsync(() async {
      final ffi.Database raw = await _openInMemory();
      final AppDatabase db = AppDatabase.fromExisting(raw);
      // Seed one known claim.
      final int id = await ClaimsRepository(db).create(
        Claim(
          id: 0,
          customerName: 'سلمان',
          customerMobile: '0551234567',
          accidentDateUtcMs: DateTime.utc(2026, 10, 1),
          claimNumber: 'CLM-NTF',
          customerInsuranceCompany: 'تعاونية',
          liabilityPercent: 50,
          submissionDateUtcMs: DateTime.utc(2026, 10, 1),
          statusKey: 'new',
          lastStatusUpdateUtcMs: DateTime.utc(2026, 10, 2),
          createdAtUtcMs: DateTime.utc(2026, 10, 2),
          updatedAtUtcMs: DateTime.utc(2026, 10, 2),
        ),
      );

      await tester.pumpWidget(_harness(db, ThemeMode.light));
      await settle(
        tester,
        () => find.text(S.dashTotalClaims).evaluate().isNotEmpty,
      );

      // Simulate the plugin's response handler invoking the app hook.
      HomeShell.openClaimFromNotification!(id);
      await settle(
        tester,
        () => find.byType(ClaimDetailsScreen).evaluate().isNotEmpty,
      );
      expect(find.byType(ClaimDetailsScreen), findsOneWidget);

      // The route is still animating in (RTL slide) — let it finish so the
      // content is laid out and hit-testable before asserting on text.
      for (int i = 0; i < 60; i++) {
        await tester.pump(const Duration(milliseconds: 50));
        final AnimationStatus status =
            ModalRoute.of(tester.element(find.byType(ClaimDetailsScreen)))
                ?.animation
                ?.status ??
            AnimationStatus.completed;
        if (status == AnimationStatus.completed) break;
      }

      // The seeded claim number is visible on the details screen. Poll for it:
      // the load runs on the FFI isolate, and under parallel-suite load a bare
      // pump loop above can end before that load completes.
      await settle(tester, () => find.text('CLM-NTF').evaluate().isNotEmpty);
      expect(find.text('CLM-NTF'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await raw.close();
    });
  });

  testWidgets('routing to an unknown claim lands on the not-found state', (
    WidgetTester tester,
  ) async {
    await tester.runAsync(() async {
      final ffi.Database raw = await _openInMemory();
      final AppDatabase db = AppDatabase.fromExisting(raw);

      await tester.pumpWidget(_harness(db, ThemeMode.light));
      await settle(
        tester,
        () => find.text(S.dashTotalClaims).evaluate().isNotEmpty,
      );

      // Unknown id — must land on the not-found state, never crash.
      HomeShell.openClaimFromNotification!(999999);
      await settle(
        tester,
        () => find.byType(ClaimDetailsScreen).evaluate().isNotEmpty,
      );
      for (int i = 0; i < 60; i++) {
        await tester.pump(const Duration(milliseconds: 50));
        final AnimationStatus status =
            ModalRoute.of(tester.element(find.byType(ClaimDetailsScreen)))
                ?.animation
                ?.status ??
            AnimationStatus.completed;
        if (status == AnimationStatus.completed) break;
      }

      // Poll for the not-found state: it only renders once the FFI load has
      // resolved to null, which under parallel-suite load can outlast the
      // bare pump loop above.
      await settle(
        tester,
        () => find.text(S.claimNotFound).evaluate().isNotEmpty,
      );
      expect(find.text(S.claimNotFound), findsOneWidget);
      expect(tester.takeException(), isNull);

      await raw.close();
    });
  });
}
