/// Regression test — post-restore database swap (spec §15).
///
/// Production sequence that crashed on device (logcat 2026-11-12, 4× unhandled
/// `DatabaseException(error database_closed)`):
///   1. Settings → restore: `BackupService.restoreFrom` closes the live DB
///      handle during its swap.
///   2. `_ClaimTrackerAppState.reconnectAfterRestore` opens a fresh
///      [AppDatabase] and rebuilds `HomeShell(db: fresh)`.
///   3. The shell refreshes its destinations (key bump), so each screen
///      re-runs `initState → _load()` — but the shell's cached repositories
///      still wrapped the CLOSED pre-restore database.
///
/// This test drives that exact contract: same [HomeShell] State instance,
/// `widget.db` swapped to a fresh handle, then a destination remount (metric
/// tile tap changes the claims-list key — the shell's own refresh mechanism).
/// The remounted screen must settle against the fresh database and no
/// unhandled exception may escape.
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart' as ffi;

import 'package:claim_tracker/app/home_shell.dart';
import 'package:claim_tracker/core/database/app_database.dart';
import 'package:claim_tracker/core/database/claims_repository.dart';
import 'package:claim_tracker/core/database/settings_repository.dart';
import 'package:claim_tracker/core/l10n/app_strings.dart';
import 'package:claim_tracker/core/models/claim.dart';
import 'package:claim_tracker/core/theme/app_theme.dart';
import 'package:claim_tracker/core/utils/time_utils.dart';
import 'package:claim_tracker/features/dashboard/dashboard_screen.dart';

Widget _harness(AppDatabase db) {
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
      currentThemeMode: ThemeMode.light,
      onThemeChanged: (ThemeMode _) {},
    ),
  );
}

/// Bounded real-time polling until [done] — the screens' FFI loads run on a
/// background isolate; never pumpAndSettle over an indeterminate spinner.
Future<void> settle(WidgetTester tester, bool Function() done) async {
  for (int i = 0; i < 450 && !done(); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 5));
    await tester.pump(const Duration(milliseconds: 16));
  }
}

/// Opens (creating on first use) a FILE-backed DB at [path] — the same
/// contract as `AppDatabase.open`, over the FFI factory. Reopening an existing
/// file must NOT re-run the schema and MUST keep its data.
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

Claim _seedClaim() {
  final DateTime nowUtc = DateTime.utc(2026, 11, 1);
  return Claim(
    id: 0,
    customerName: 'سعد العميل',
    customerMobile: '0501234567',
    accidentDateUtcMs: DateTime.utc(2026, 10, 1),
    claimNumber: 'CLM-900',
    customerInsuranceCompany: 'تعاونية',
    liabilityPercent: 50,
    submissionDateUtcMs: DateTime.utc(2026, 10, 5),
    statusKey: 'new',
    lastStatusUpdateUtcMs: nowUtc,
    createdAtUtcMs: nowUtc,
    updatedAtUtcMs: nowUtc,
  );
}

void main() {
  setUpAll(() async {
    ffi.sqfliteFfiInit();
    // BackupService-style global openDatabase must resolve to the FFI backend.
    ffi.databaseFactory = ffi.databaseFactoryFfi;
    await TimeUtils.ensureInitialized();
  });

  testWidgets(
    'after a restore swap, remounted destinations load from the fresh DB '
    '(no database_closed)',
    (WidgetTester tester) async {
      late Directory dir;
      late String dbPath;
      final List<ffi.Database> openHandles = <ffi.Database>[];

      await tester.runAsync(() async {
        dir = await Directory.systemTemp.createTemp('ct_restore_swap');
        dbPath = '${dir.path}${Platform.pathSeparator}live.sqlite';

        // ---- Pre-restore session: one claim in the live DB. ---------------
        final ffi.Database oldRaw = await _openAt(dbPath);
        openHandles.add(oldRaw);
        final AppDatabase oldDb = AppDatabase.fromExisting(oldRaw);
        await ClaimsRepository(oldDb).create(_seedClaim());

        await tester.pumpWidget(_harness(oldDb));
        // Dashboard settles against the live DB (proves pre-swap health).
        await settle(
          tester,
          () => find.text(S.dashTotalClaims).evaluate().isNotEmpty,
        );
        expect(find.byKey(const Key('metric-overdue')), findsOneWidget);

        // ---- The restore swap (mirrors BackupService.restoreFrom + -------
        // reconnectAfterRestore): the live handle is closed and a fresh one
        // takes over the same file.
        await oldRaw.close();
        final ffi.Database reopened = await _openAt(dbPath);
        openHandles.add(reopened);
        final AppDatabase freshDb = AppDatabase.fromExisting(reopened);

        // ---- Shell rebuilds around the fresh instance (same State). -------
        await tester.pumpWidget(_harness(freshDb));
        await settle(
          tester,
          () => find.text(S.dashTotalClaims).evaluate().isNotEmpty,
        );

        // ---- The shell's own refresh mechanism: a metric tap remounts the --
        // claims list (key bump) — exactly what `onDataRestored` does after a
        // restore. With stale repositories this throws database_closed.
        final Finder overdueTile = find.byKey(const Key('metric-overdue'));
        await _scrollIntoView(tester, overdueTile);
        await tester.tap(overdueTile);
        final bool settled = await _settleList(tester);

        expect(
          tester.takeException(),
          isNull,
          reason: 'remounted claims list must not throw after the swap',
        );
        // The remounted list shows its honest empty state (the restored DB has
        // no overdue claims) — proof it queried the FRESH database.
        expect(settled, isTrue, reason: 'claims list settled against fresh DB');
        expect(find.text(S.claimsEmpty), findsOneWidget);

        // Release every handle before deleting the temp tree (Windows locks
        // open SQLite files). FFI I/O must stay inside the async zone —
        // awaiting it under fake-async hangs.
        for (final ffi.Database h in openHandles) {
          try {
            await h.close();
          } catch (_) {}
        }
      });

      if (dir.existsSync()) dir.deleteSync(recursive: true);
    },
  );
}

/// Scrolls [f] into the free viewport of the dashboard's own scroll view —
/// the metric grid sits below the title and may be off-screen at 800x600.
Future<void> _scrollIntoView(WidgetTester tester, Finder f) async {
  final Finder scroller = find.descendant(
    of: find.byType(DashboardScreen),
    matching: find.byType(SingleChildScrollView),
  );
  for (int i = 0; i < 40; i++) {
    await tester.pump(const Duration(milliseconds: 16));
    final Offset c = tester.getCenter(f);
    if (c.dy > 80 && c.dy < 520) return;
    await tester.drag(scroller, Offset(0, c.dy < 300 ? 240 : -240));
  }
}

/// Polls until the claims-list destination has finished loading (its empty
/// state is visible) or gives up. Returns whether it settled in time.
Future<bool> _settleList(WidgetTester tester) async {
  for (int i = 0; i < 450; i++) {
    await Future<void>.delayed(const Duration(milliseconds: 5));
    await tester.pump(const Duration(milliseconds: 16));
    if (find.text(S.claimsEmpty).evaluate().isNotEmpty) return true;
  }
  return false;
}
