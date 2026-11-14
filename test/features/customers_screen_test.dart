/// Customers tab: pick a customer, see their per-status counts, filter the
/// claim list by tapping a status, and keep that selection after opening a
/// claim and coming back.
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

Widget _harness(AppDatabase db) => MaterialApp(
  locale: const Locale('ar'),
  supportedLocales: const [Locale('ar')],
  localizationsDelegates: const [
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
  ],
  theme: AppTheme.light(),
  home: HomeShell(
    db: db,
    settingsRepo: SettingsRepository(db),
    currentThemeMode: ThemeMode.light,
    onThemeChanged: (ThemeMode _) {},
  ),
);

Future<void> settle(WidgetTester tester, bool Function() done) async {
  for (int i = 0; i < 450 && !done(); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 5));
    await tester.pump(const Duration(milliseconds: 16));
  }
}

Claim _seed(String customer, String claimNumber, String statusKey) {
  final DateTime nowUtc = DateTime.utc(2026, 11, 1);
  return Claim(
    id: 0,
    customerName: customer,
    customerMobile: '0501234567',
    accidentDateUtcMs: DateTime.utc(2026, 10, 1),
    claimNumber: claimNumber,
    customerInsuranceCompany: 'تعاونية',
    statusKey: statusKey,
    lastStatusUpdateUtcMs: nowUtc,
    createdAtUtcMs: nowUtc,
    updatedAtUtcMs: nowUtc,
  );
}

int _cards() => find.byType(ClaimCard).evaluate().length;

void main() {
  setUpAll(() async {
    ffi.sqfliteFfiInit();
    ffi.databaseFactory = ffi.databaseFactoryFfi;
    await TimeUtils.ensureInitialized();
  });

  testWidgets('customer status breakdown filters and survives a round-trip', (
    WidgetTester tester,
  ) async {
    // Tall phone viewport so the status grid and claim cards are all built.
    tester.view.physicalSize = const Size(1080, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.runAsync(() async {
      final ffi.Database raw = await ffi.databaseFactoryFfi.openDatabase(
        ffi.inMemoryDatabasePath,
      );
      await raw.execute('PRAGMA foreign_keys = ON');
      await AppDatabase.migrate(raw, from: 0, to: kDatabaseVersion);
      final AppDatabase db = AppDatabase.fromExisting(raw);
      final ClaimsRepository repo = ClaimsRepository(db);
      await repo.create(_seed('سعد', 'S-NEW', 'new'));
      final int rejectedId = await repo.create(
        _seed('سعد', 'S-REJ1', 'rejected'),
      );
      await repo.create(_seed(' سعد ', 'S-REJ2', 'rejected')); // trimmed → same
      await repo.create(_seed('خالد', 'K-1', 'submitted'));

      await tester.pumpWidget(_harness(db));
      await settle(
        tester,
        () => find.text(S.navCustomers).evaluate().isNotEmpty,
      );
      await tester.tap(find.text(S.navCustomers));
      await settle(
        tester,
        () => find.byKey(const Key('customer-سعد')).evaluate().isNotEmpty,
      );
      expect(find.byKey(const Key('customer-خالد')), findsOneWidget);
      expect(find.text(S.customersCount(2)), findsOneWidget);

      // Pick the customer: all their claims, with per-status counts.
      await tester.tap(find.byKey(const Key('customer-سعد')));
      await settle(tester, () => _cards() == 3);
      expect(find.byKey(const Key('customer-status-rejected')), findsOneWidget);
      expect(find.byKey(const Key('customer-status-new')), findsOneWidget);
      expect(find.byKey(const Key('customer-status-submitted')), findsNothing);

      // Tap "Rejected" → only the two rejected claims.
      await tester.tap(find.byKey(const Key('customer-status-rejected')));
      await settle(tester, () => _cards() == 2);
      expect(find.text('S-NEW'), findsNothing);

      // Open one and come back: same customer + filter.
      await tester.ensureVisible(find.byKey(Key('customer-claim-$rejectedId')));
      await tester.tap(find.byKey(Key('customer-claim-$rejectedId')));
      await settle(
        tester,
        () => find.text(S.sectionCustomerInfo).evaluate().isNotEmpty,
      );
      tester.state<NavigatorState>(find.byType(Navigator)).pop();
      await settle(
        tester,
        () =>
            find.byType(ClaimDetailsScreen).evaluate().isEmpty && _cards() == 2,
      );
      expect(_cards(), 2);

      // Back to the customer list.
      await tester.tap(find.byKey(const Key('customers-back')));
      await settle(
        tester,
        () => find.byKey(const Key('customer-خالد')).evaluate().isNotEmpty,
      );
      expect(_cards(), 0);

      await raw.close();
    });
  });
}
