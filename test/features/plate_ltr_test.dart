/// Vehicle plate LTR regression tests (owner requirement): the plate — the
/// form's input field and every display site (list card, dashboard, details)
/// — must always render left-to-right in BOTH the English and Arabic
/// interfaces.
///
/// Each test asserts that the NEAREST Directionality ancestor of a plate
/// widget is LTR: this fails if any site regresses to inheriting the ambient
/// direction (the pre-fix behavior in the AR UI, where the plate rendered
/// right-aligned with an RTL base direction).
///
/// Harness rules mirror claim_details_screen_test.dart / dashboard_screen_test.
/// dart: ONE `tester.runAsync` block per screen that does real FFI SQLite I/O
/// (seed + load inside it), bounded real-time polling instead of pumpAndSettle,
/// and all expectations INSIDE the runAsync block.
library;

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart' as ffi;

import 'package:claim_tracker/core/database/app_database.dart';
import 'package:claim_tracker/core/database/claims_repository.dart';
import 'package:claim_tracker/core/models/claim.dart';
import 'package:claim_tracker/core/theme/app_theme.dart';
import 'package:claim_tracker/core/utils/time_utils.dart';
import 'package:claim_tracker/features/claims/claim_card.dart';
import 'package:claim_tracker/features/claims/claim_details_screen.dart';
import 'package:claim_tracker/features/claims/claim_form_screen.dart';
import 'package:claim_tracker/features/claims/claims_filter.dart';
import 'package:claim_tracker/features/dashboard/dashboard_screen.dart';
import 'package:claim_tracker/features/dashboard/dashboard_service.dart';

/// A plate with mixed letters/digits — the shape an RTL base direction would
/// actually reorder differently from LTR.
const String _plate = 'ABC-1234';

/// MaterialApp for [locale] with the app's ambient direction for that language
/// (AR = RTL, mirroring production where Arabic drives RTL layout).
Widget _harness(Locale locale, TextDirection ambient, Widget home) {
  return MaterialApp(
    locale: locale,
    supportedLocales: const [Locale('en'), Locale('ar')],
    localizationsDelegates: const [
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    theme: AppTheme.light(),
    darkTheme: AppTheme.dark(),
    builder: (BuildContext context, Widget? child) => Directionality(
      textDirection: ambient,
      child: child ?? const SizedBox.shrink(),
    ),
    home: home,
  );
}

/// Nearest [Directionality] ancestor of the first widget matching [f] —
/// i.e. the direction context that actually renders it.
TextDirection _direction(WidgetTester tester, Finder f) {
  final Element e = tester.element(f);
  Directionality? nearest;
  // Visits from the closest ancestor outward; stop at the first one found.
  e.visitAncestorElements((Element ancestor) {
    if (ancestor.widget is Directionality) {
      nearest = ancestor.widget as Directionality;
      return false;
    }
    return true;
  });
  expect(nearest, isNotNull); // a rendered Text always has one
  return nearest!.textDirection;
}

/// One claim with the plate set (and nothing else special), for any screen.
Claim seed() => Claim(
  id: 0,
  customerName: 'عميل',
  customerMobile: '0501234567',
  accidentDateUtcMs: DateTime.utc(2026, 10, 1),
  vehiclePlate: _plate,
  claimNumber: 'CLM-900',
  customerInsuranceCompany: 'تعاونية',
  statusKey: 'new',
  lastStatusUpdateUtcMs: DateTime.now().toUtc(),
  createdAtUtcMs: DateTime.now().toUtc(),
  updatedAtUtcMs: DateTime.now().toUtc(),
);

void main() {
  late ffi.Database raw;
  late AppDatabase db;
  late ClaimsRepository claims;

  setUpAll(() async {
    ffi.sqfliteFfiInit();
    await TimeUtils.ensureInitialized();
  });

  // Same per-test in-memory DB pattern as the other screen test files.
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

  /// Bounded real-time polling until [done] (real FFI I/O on a background
  /// isolate — never pumpAndSettle the loading spinner).
  Future<void> settle(WidgetTester tester, bool Function() done) async {
    for (int i = 0; i < 300 && !done(); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
      await tester.pump();
    }
  }

  /// Waits for the details push transition to fully complete so no ticker is
  /// left running at teardown (same wait as claim_details_screen_test).
  Future<void> openDetails(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('open-details')));
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

  group('plate renders LTR in the AR interface (ambient RTL)', () {
    testWidgets('claim card pins an LTR context on the plate', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        _harness(
          const Locale('ar'),
          TextDirection.rtl,
          ClaimCard(claim: seed()),
        ),
      );

      expect(find.text(_plate), findsOneWidget);
      expect(
        _direction(tester, find.byKey(const Key('card-plate'))),
        TextDirection.ltr,
      );
    });

    testWidgets('form plate field is an LTR input in both label and text', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        _harness(
          const Locale('ar'),
          TextDirection.rtl,
          ClaimFormScreen(onSaved: (_) {}),
        ),
      );

      final Finder field = find.byKey(const Key('field-plate'));
      expect(_direction(tester, field), TextDirection.ltr);
      // The editable region itself must be LTR too.
      final Finder editable = find.descendant(
        of: field,
        matching: find.byType(EditableText),
      );
      expect(_direction(tester, editable.first), TextDirection.ltr);

      await tester.enterText(field, _plate);
      await tester.pump();
      expect(find.text(_plate), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('dashboard needs-attention pins an LTR context', (
      WidgetTester tester,
    ) async {
      // Real FFI SQLite I/O (seed + initState load) must run outside the
      // fake-async zone; bounded real-time polling instead of pumpAndSettle.
      await tester.runAsync(() async {
        final Claim saved = seed();
        await claims.create(saved);
        await tester.pumpWidget(
          _harness(
            const Locale('ar'),
            TextDirection.rtl,
            DashboardScreen(
              service: DashboardService(claims),
              onMetricTapped: (ClaimsFilter _, String? _) {},
            ),
          ),
        );
        await settle(tester, () => find.text(_plate).evaluate().isNotEmpty);

        expect(find.text(_plate), findsOneWidget);
        expect(_direction(tester, find.text(_plate)), TextDirection.ltr);
      });
    });

    testWidgets('details row pins an LTR context on the plate value', (
      WidgetTester tester,
    ) async {
      // Same shape as claim_details_screen_test.dart: push from a parent page
      // inside runAsync; seed and expectations all inside it.
      await tester.runAsync(() async {
        final int id = await claims.create(seed());
        await tester.pumpWidget(
          _harness(
            const Locale('ar'),
            TextDirection.rtl,
            Builder(
              builder: (BuildContext context) => Scaffold(
                body: Center(
                  child: FilledButton(
                    key: const Key('open-details'),
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) =>
                              ClaimDetailsScreen(db: db, claimId: id),
                        ),
                      );
                    },
                    child: const Text('فتح'),
                  ),
                ),
              ),
            ),
          ),
        );
        await openDetails(tester);
        await settle(tester, () => find.text(_plate).evaluate().isNotEmpty);

        expect(find.text(_plate), findsOneWidget);
        expect(_direction(tester, find.text(_plate)), TextDirection.ltr);
        // Row convention (AR): value sits on the left like sibling rows.
        expect(
          tester.widget<Text>(find.text(_plate)).textAlign,
          TextAlign.left,
        );
      });
    });
  });

  group('plate renders LTR in the EN interface (ambient LTR)', () {
    testWidgets('claim card keeps the plate left-to-right', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        _harness(
          const Locale('en'),
          TextDirection.ltr,
          ClaimCard(claim: seed()),
        ),
      );

      expect(find.text(_plate), findsOneWidget);
      expect(
        _direction(tester, find.byKey(const Key('card-plate'))),
        TextDirection.ltr,
      );
    });

    testWidgets('form plate field accepts LTR input', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        _harness(
          const Locale('en'),
          TextDirection.ltr,
          ClaimFormScreen(onSaved: (_) {}),
        ),
      );

      final Finder field = find.byKey(const Key('field-plate'));
      expect(_direction(tester, field), TextDirection.ltr);
      await tester.enterText(field, _plate);
      await tester.pump();
      expect(find.text(_plate), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('details row keeps the plate value flush-right like siblings', (
      WidgetTester tester,
    ) async {
      // Regression guard for the EN details screen: the plate must stay an
      // explicit LTR run while its alignment matches sibling rows (flush
      // right) — it must not sit left-aligned next to its label.
      await tester.runAsync(() async {
        final int id = await claims.create(seed());
        await tester.pumpWidget(
          _harness(
            const Locale('en'),
            TextDirection.ltr,
            Builder(
              builder: (BuildContext context) => Scaffold(
                body: Center(
                  child: FilledButton(
                    key: const Key('open-details'),
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) =>
                              ClaimDetailsScreen(db: db, claimId: id),
                        ),
                      );
                    },
                    child: const Text('Open'),
                  ),
                ),
              ),
            ),
          ),
        );
        await openDetails(tester);
        await settle(tester, () => find.text(_plate).evaluate().isNotEmpty);

        expect(find.text(_plate), findsOneWidget);
        // Still an explicit LTR context...
        expect(_direction(tester, find.text(_plate)), TextDirection.ltr);
        // ...and the EN row convention: value flush-right.
        expect(tester.widget<Text>(find.text(_plate)).textAlign, TextAlign.end);
      });
    });
  });
}
