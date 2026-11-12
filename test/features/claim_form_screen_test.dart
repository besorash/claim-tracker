/// ClaimFormScreen tests (spec §7): Arabic validation, input preservation on a
/// failed save (Review Focus #1), and add/edit semantics. The screen is pure
/// state — no repository access — so plain `testWidgets` works here.
library;

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:claim_tracker/core/l10n/app_strings.dart';
import 'package:claim_tracker/core/models/claim.dart';
import 'package:claim_tracker/core/theme/app_theme.dart';
import 'package:claim_tracker/core/utils/time_utils.dart';
import 'package:claim_tracker/features/claims/claim_form_screen.dart';

Widget _harness({Claim? claim, List<Claim>? saved}) => MaterialApp(
  locale: const Locale('ar'),
  supportedLocales: const [Locale('ar')],
  localizationsDelegates: const [
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
  ],
  theme: AppTheme.light(),
  darkTheme: AppTheme.dark(),
  home: ClaimFormScreen(
    claim: claim,
    onSaved: (Claim c) {
      saved?.add(c);
    },
  ),
);

Finder field(String name) => find.byKey(Key('field-$name'));

/// Scrolls [f] fully into the viewport (center within bounds). Robust where
/// `ensureVisible` is a no-op for partially-visible rows, and against the
/// focus auto-scroll that pushes rows off-screen after `enterText`.
Future<void> tappable(WidgetTester tester, Finder f) async {
  for (int i = 0; i < 40; i++) {
    await tester.pumpAndSettle();
    final Offset c = tester.getCenter(f);
    // Keep the center strictly inside the free viewport: below the AppBar
    // (~80px) and above the bottom action bar (~75px), so the tap cannot be
    // obscured by either.
    if (c.dy > 100 && c.dy < 495) return;
    // Target above the top edge → drag content down; below → up.
    await tester.drag(
      find.byType(SingleChildScrollView),
      Offset(0, c.dy < 300 ? 260 : -260),
    );
  }
}

/// Opens the date picker for [row] and accepts the default (today).
Future<void> pickDate(WidgetTester tester, String row) async {
  final Finder rowFinder = find.byKey(Key('date-$row'));
  FocusManager.instance.primaryFocus?.unfocus();
  await tappable(tester, rowFinder);
  await tester.tap(rowFinder);
  await tester.pumpAndSettle();
  expect(find.byType(DatePickerDialog), findsOneWidget);
  // ar locale OK button label (GlobalMaterialLocalizations.ar okButtonLabel).
  await tester.tap(find.text('حسنًا'));
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() async {
    await TimeUtils.ensureInitialized();
  });

  testWidgets(
    'add mode: saving with empty fields shows required errors and does not call onSaved',
    (WidgetTester tester) async {
      final List<Claim> saved = [];
      await tester.pumpWidget(_harness(saved: saved));
      await tester.pumpAndSettle();

      await tester.tap(find.text(S.save));
      await tester.pumpAndSettle();

      // Four required text fields + two required dates → at least 4 messages
      // (the liability share is optional and has no required error).
      expect(
        find.text(S.requiredField).evaluate().length,
        greaterThanOrEqualTo(4),
      );
      expect(saved, isEmpty);
    },
  );

  testWidgets(
    'failed save preserves typed input (Review Focus #1): name stays in the field',
    (WidgetTester tester) async {
      final List<Claim> saved = [];
      await tester.pumpWidget(_harness(saved: saved));
      await tester.pumpAndSettle();

      await tester.enterText(field('customerName'), 'خالد');
      await tester.enterText(field('mobile'), 'abc');
      await tester.tap(find.text(S.save));
      await tester.pumpAndSettle();

      expect(find.text(S.invalidNumber), findsOneWidget); // mobile error shown
      final TextField name = tester.widget<TextField>(field('customerName'));
      expect(name.controller!.text, 'خالد'); // input preserved
      expect(saved, isEmpty);
    },
  );

  testWidgets(
    'valid add: onSaved called once with a Claim matching the inputs',
    (WidgetTester tester) async {
      final List<Claim> saved = [];
      await tester.pumpWidget(_harness(saved: saved));
      await tester.pumpAndSettle();

      await tester.enterText(field('customerName'), 'خالد');
      await tester.enterText(field('mobile'), '0559876543');
      await tester.enterText(field('claimNumber'), 'CLM-1');
      await tester.enterText(field('custInsurer'), 'تعاونية');
      await pickDate(tester, 'accident');
      await pickDate(tester, 'submission');

      await tester.tap(find.text(S.save));
      await tester.pumpAndSettle();

      expect(saved, hasLength(1));
      final Claim c = saved.single;
      expect(c.customerName, 'خالد');
      expect(c.customerMobile, '0559876543');
      expect(c.claimNumber, 'CLM-1');
      expect(c.customerInsuranceCompany, 'تعاونية');
      expect(c.liabilityPercent, isNull);
      expect(c.accidentDateUtcMs, isNotNull);
      expect(c.submissionDateUtcMs, isNotNull);
    },
  );

  testWidgets(
    'edit mode: fields pre-populated; save keeps id/createdAt and applies changes',
    (WidgetTester tester) async {
      final DateTime created = DateTime.utc(2026, 9, 1);
      final Claim existing = Claim(
        id: 9,
        customerName: 'سعد',
        customerMobile: '0501112233',
        accidentDateUtcMs: DateTime.utc(2026, 8, 1),
        claimNumber: 'CLM-77',
        customerInsuranceCompany: 'تعاونية',
        liabilityPercent: 50,
        submissionDateUtcMs: DateTime.utc(2026, 8, 5),
        statusKey: 'new',
        lastStatusUpdateUtcMs: created,
        createdAtUtcMs: created,
        updatedAtUtcMs: created,
      );

      final List<Claim> saved = [];
      await tester.pumpWidget(_harness(claim: existing, saved: saved));
      await tester.pumpAndSettle();

      // Pre-populated from the seeded claim.
      expect(find.widgetWithText(TextField, 'سعد'), findsOneWidget);
      expect(find.widgetWithText(TextField, 'CLM-77'), findsOneWidget);

      await tester.enterText(field('claimNumber'), 'CLM-88');
      await tester.tap(find.text(S.save));
      await tester.pumpAndSettle();

      expect(saved, hasLength(1));
      final Claim c = saved.single;
      expect(c.id, 9); // preserved
      expect(c.createdAtUtcMs, created); // preserved
      expect(c.claimNumber, 'CLM-88'); // changed
      expect(c.customerName, 'سعد'); // untouched field kept
    },
  );
}
