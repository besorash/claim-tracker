/// Regression test — claims-list filter must survive a details round-trip.
///
/// Reported bug: on the claims page, pick a filter (e.g. "Finished"), open a
/// filtered claim, go back → the selection silently reset to "All". Root cause:
/// `HomeShell._openClaim` bumps the generation counter on return and remounts
/// every destination; the list rebuilt with the shell's remembered selection,
/// which it had never been told about (chip taps were local state only).
///
/// Contract under test: the shell learns each chip selection through
/// `onSelectionChanged`, restores it on the post-details remount, and the new
/// clear-filters control resets both the live list and the shell's memory.
library;

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
import 'package:claim_tracker/features/claims/claim_card.dart';
import 'package:claim_tracker/features/claims/claim_details_screen.dart';

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

Claim _seed(String claimNumber, String statusKey) {
  final DateTime nowUtc = DateTime.utc(2026, 11, 1);
  return Claim(
    id: 0,
    customerName: 'سعد العميل',
    customerMobile: '0501234567',
    accidentDateUtcMs: DateTime.utc(2026, 10, 1),
    claimNumber: claimNumber,
    customerInsuranceCompany: 'تعاونية',
    liabilityPercent: 50,
    submissionDateUtcMs: DateTime.utc(2026, 10, 5),
    statusKey: statusKey,
    lastStatusUpdateUtcMs: nowUtc,
    createdAtUtcMs: nowUtc,
    updatedAtUtcMs: nowUtc,
  );
}

void main() {
  setUpAll(() async {
    ffi.sqfliteFfiInit();
    // HomeShell code paths resolve the global factory — point it at FFI so no
    // method channel is touched (same contract as the restore-swap test).
    ffi.databaseFactory = ffi.databaseFactoryFfi;
    await TimeUtils.ensureInitialized();
  });

  testWidgets(
    'a selected filter survives opening a claim and going back, and the '
    'clear-filters button resets it',
    (WidgetTester tester) async {
      late ffi.Database raw;
      await tester.runAsync(() async {
        raw = await ffi.databaseFactoryFfi.openDatabase(
          ffi.inMemoryDatabasePath,
        );
        await raw.execute('PRAGMA foreign_keys = ON');
        await AppDatabase.migrate(raw, from: 0, to: kDatabaseVersion);
        final AppDatabase db = AppDatabase.fromExisting(raw);

        final int openId = await ClaimsRepository(db)
            .create(_seed('OPEN-1', 'new'));
        final int closedId = await ClaimsRepository(db)
            .create(_seed('CLOSED-1', 'closed'));

        // ---- Arrive on the claims tab (both claims visible). --------------
        await tester.pumpWidget(_harness(db));
        await settle(
          tester,
          () => find.text(S.navClaims).evaluate().isNotEmpty,
        );
        await tester.tap(find.text(S.navClaims));
        await settle(
          tester,
          () => find.byType(ClaimCard).evaluate().length == 2,
        );
        expect(find.text('OPEN-1'), findsOneWidget);
        expect(find.text('CLOSED-1'), findsOneWidget);

        // ---- Filter to "Finished": only the closed claim remains. ---------
        await tester.tap(find.byKey(const Key('filter-closed')));
        await settle(
          tester,
          () => find.byType(ClaimCard).evaluate().length == 1,
        );
        final ChoiceChip closedChip = tester.widget<ChoiceChip>(
          find.byKey(const Key('filter-closed')),
        );
        expect(closedChip.selected, isTrue);

        // ---- Open the filtered claim (details screen pushes on top). ------
        await tester.tap(find.byKey(Key('card-$closedId')));
        // The screen widget exists while its async FFI load still shows a
        // spinner — settle on rendered content, not the screen type (race
        // under load: "Customer Information" found 0 widgets intermittently).
        await settle(
          tester,
          () => find.text(S.sectionCustomerInfo).evaluate().isNotEmpty,
        );
        expect(find.text(S.sectionCustomerInfo), findsOneWidget);

        // ---- Go back: the shell remounts every destination on return. -----
        final NavigatorState navigator = tester.state<NavigatorState>(
          find.byType(Navigator),
        );
        navigator.pop();
        await settle(
          tester,
          () =>
              find.byType(ClaimDetailsScreen).evaluate().isEmpty &&
              find.byType(ClaimCard).evaluate().length == 1,
        );

        // THE REGRESSION: the "Finished" selection must still be active after
        // the round-trip (previously it silently reset to "All").
        final ChoiceChip restored = tester.widget<ChoiceChip>(
          find.byKey(const Key('filter-closed')),
        );
        expect(
          restored.selected,
          isTrue,
          reason: 'filter must persist across the details round-trip',
        );
        expect(find.text('CLOSED-1'), findsOneWidget);
        expect(find.text('OPEN-1'), findsNothing);

        // ---- The clear control resets the list and the shell's memory. ---
        await tester.tap(find.byKey(const Key('clear-filters')));
        await settle(
          tester,
          () => find.byType(ClaimCard).evaluate().length == 2,
        );
        final ChoiceChip all = tester.widget<ChoiceChip>(
          find.byKey(const Key('filter-all')),
        );
        expect(all.selected, isTrue);
        expect(find.text('OPEN-1'), findsOneWidget);

        // And a second round-trip stays on "All" — no stale selection leaks.
        await tester.tap(find.byKey(Key('card-$openId')));
        // Same content-based settle as above (screen type exists pre-load).
        await settle(
          tester,
          () => find.text(S.sectionCustomerInfo).evaluate().isNotEmpty,
        );
        navigator.pop();
        await settle(
          tester,
          () => find.byType(ClaimCard).evaluate().length == 2,
        );
        final ChoiceChip stillAll = tester.widget<ChoiceChip>(
          find.byKey(const Key('filter-all')),
        );
        expect(stillAll.selected, isTrue);

        await raw.close();
      });
    },
  );
}
