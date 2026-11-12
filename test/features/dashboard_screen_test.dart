/// Dashboard screen widget tests (spec §5): metric tiles rendered from SQLite,
/// tappable tiles request the right ClaimsFilter, empty state is honest.
library;

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart' as ffi;

import 'package:claim_tracker/core/database/app_database.dart';
import 'package:claim_tracker/core/database/claims_repository.dart';
import 'package:claim_tracker/core/l10n/app_strings.dart';
import 'package:claim_tracker/core/models/claim.dart';
import 'package:claim_tracker/core/theme/app_theme.dart';
import 'package:claim_tracker/core/utils/time_utils.dart';
import 'package:claim_tracker/features/claims/claims_filter.dart';
import 'package:claim_tracker/features/dashboard/dashboard_screen.dart';
import 'package:claim_tracker/features/dashboard/dashboard_service.dart';

Widget _harness(DashboardService service, {List<ClaimsFilter>? tapped}) {
  final List<ClaimsFilter> sink = tapped ?? <ClaimsFilter>[];
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
    home: DashboardScreen(
      service: service,
      onMetricTapped: (ClaimsFilter f) => sink.add(f),
    ),
  );
}

void main() {
  late ffi.Database raw;
  late ClaimsRepository claims;

  setUpAll(() async {
    ffi.sqfliteFfiInit();
    await TimeUtils.ensureInitialized();
  });

  setUp(() async {
    raw = await ffi.databaseFactoryFfi.openDatabase(ffi.inMemoryDatabasePath);
    await raw.execute('PRAGMA foreign_keys = ON');
    await AppDatabase.migrate(raw, from: 0, to: kDatabaseVersion);
    claims = ClaimsRepository(AppDatabase.fromExisting(raw));
  });

  tearDown(() async {
    await raw.close();
  });

  Claim seed({required String statusKey, DateTime? followUpUtcMs}) => Claim(
    id: 0,
    customerName: 'عميل',
    customerMobile: '0501234567',
    accidentDateUtcMs: DateTime.utc(2026, 10, 1),
    claimNumber: 'CLM-${DateTime.now().microsecondsSinceEpoch % 900 + 100}',
    customerInsuranceCompany: 'تعاونية',
    submittedToInsuranceCompany: 'بوبا',
    submissionDateUtcMs: DateTime.utc(2026, 10, 5),
    statusKey: statusKey,
    lastStatusUpdateUtcMs: DateTime.now().toUtc(),
    nextFollowUpUtcMs: followUpUtcMs,
    createdAtUtcMs: DateTime.now().toUtc(),
    updatedAtUtcMs: DateTime.now().toUtc(),
  );

  Future<void> seedFive() async {
    final DateTime now = DateTime.now().toUtc();
    await claims.create(seed(statusKey: 'new'));
    await claims.create(seed(statusKey: 'compensated'));
    await claims.create(seed(statusKey: 'closed'));
    await claims.create(
      seed(
        statusKey: 'new',
        followUpUtcMs: now.subtract(const Duration(hours: 24)),
      ),
    ); // overdue
    await claims.create(
      seed(statusKey: 'new', followUpUtcMs: now.add(const Duration(hours: 2))),
    ); // due today
  }

  /// Waits (bounded, real time) until [finder] matches — the screen's
  /// initState load does real FFI I/O on a background isolate.
  Future<void> pumpUntil(WidgetTester tester, Finder f) async {
    for (int i = 0; i < 300 && f.evaluate().isEmpty; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
      await tester.pump();
    }
  }

  testWidgets('renders all five metric tiles with values from the database', (
    WidgetTester tester,
  ) async {
    final DashboardService service = DashboardService(claims);

    // Real FFI SQLite I/O (seed + initState load) must run outside the
    // fake-async zone; bounded real-time polling instead of pumpAndSettle.
    await tester.runAsync(() async {
      await seedFive();
      await tester.pumpWidget(_harness(service));
      await pumpUntil(tester, find.text(S.dashTotalClaims));
    });

    for (final String label in <String>[
      S.dashTotalClaims,
      S.dashOpenClaims,
      S.dashClosedClaims,
      S.dashDueToday,
      S.dashOverdue,
    ]) {
      expect(find.text(label), findsOneWidget, reason: label);
    }

    // Values come from the seeded DB (5 total / 4 open / 1 closed).
    expect(find.text('5'), findsWidgets);
    expect(find.text('4'), findsWidgets);
    expect(find.text('1'), findsWidgets);
  });

  testWidgets('tapping a metric tile requests the matching ClaimsFilter', (
    WidgetTester tester,
  ) async {
    final DashboardService service = DashboardService(claims);
    final List<ClaimsFilter> tapped = <ClaimsFilter>[];

    await tester.runAsync(() async {
      await seedFive();
      await tester.pumpWidget(_harness(service, tapped: tapped));
      await pumpUntil(tester, find.text(S.dashTotalClaims));
    });

    // Row 1 is in the initial viewport — tap it first.
    await tester.tap(find.byKey(const Key('metric-open')));
    await tester.pump();
    expect(tapped, <ClaimsFilter>[ClaimsFilter.open]);

    tapped.clear();
    // The overdue tile (last row) is below the fold in the 600px viewport.
    await tester.ensureVisible(find.byKey(const Key('metric-overdue')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('metric-overdue')));
    await tester.pump();
    expect(tapped, <ClaimsFilter>[ClaimsFilter.overdue]);
  });

  testWidgets('empty database shows the empty state and zero values', (
    WidgetTester tester,
  ) async {
    final DashboardService service = DashboardService(claims);

    await tester.runAsync(() async {
      await tester.pumpWidget(_harness(service));
      await pumpUntil(tester, find.text(S.dashEmpty));
    });

    expect(find.text(S.dashEmpty), findsOneWidget);
    // Tiles still render with zero values — no crash, no hardcoded numbers.
    expect(find.text('0'), findsWidgets);
  });
}
