/// Claims list screen tests (spec Â§6): search, filters, balanced card subset.
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
import 'package:claim_tracker/features/claims/claim_card.dart';
import 'package:claim_tracker/features/claims/claims_filter.dart';
import 'package:claim_tracker/features/claims/claims_list_screen.dart';
import 'package:claim_tracker/shared/widgets/status_chip.dart';

Widget _harness(
  ClaimsRepository repo, {
  ClaimsFilter initial = ClaimsFilter.all,
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
  home: ClaimsListScreen(repo: repo, initialFilter: initial),
);

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

  Claim seed({
    required String statusKey,
    DateTime? followUpUtcMs,
    String name = 'Ø¹Ù…ÙŠÙ„',
    String mobile = '0501234567',
    String claimNumber = 'CLM-900',
    String? plate,
  }) => Claim(
    id: 0,
    vehiclePlate: plate,
    customerName: name,
    customerMobile: mobile,
    accidentDateUtcMs: DateTime.utc(2026, 10, 1),
    claimNumber: claimNumber,
    customerInsuranceCompany: 'ØªØ¹Ø§ÙˆÙ†ÙŠØ©',
    liabilityPercent: 50,
    submissionDateUtcMs: DateTime.utc(2026, 10, 5),
    statusKey: statusKey,
    lastStatusUpdateUtcMs: DateTime.now().toUtc(),
    nextFollowUpUtcMs: followUpUtcMs,
    createdAtUtcMs: DateTime.now().toUtc(),
    updatedAtUtcMs: DateTime.now().toUtc(),
  );

  Future<int> create(Claim c) => claims.create(c);

  /// Bounded real-time polling until [done] â€” the screen's load does real FFI
  /// I/O on a background isolate (see dashboard_screen_test.dart harness note).
  Future<void> settle(WidgetTester tester, bool Function() done) async {
    for (int i = 0; i < 300 && !done(); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
      await tester.pump();
    }
  }

  /// The four standard seed claims: A overdue, B closed, C compensated (open),
  /// D searchable by name/mobile.
  Future<int> seedStandard() async {
    final DateTime now = DateTime.now().toUtc();
    final int idA = await create(
      seed(
        statusKey: 'new',
        followUpUtcMs: now.subtract(const Duration(hours: 24)),
        name: 'Ø¹Ù…ÙŠÙ„ Ø£',
        claimNumber: 'CLM-200',
      ),
    );
    await create(seed(statusKey: 'closed', name: 'Ø¹Ù…ÙŠÙ„ Ø¨'));
    await create(seed(statusKey: 'compensated', name: 'Ø¹Ù…ÙŠÙ„ Ø¬'));
    await create(
      seed(
        statusKey: 'new',
        name: 'Ù…Ø­Ù…Ø¯ Ø§Ù„Ø¹ØªÙŠØ¨ÙŠ',
        mobile: '0551234567',
      ),
    );
    return idA;
  }

  testWidgets(
    'default filter shows all claims; the overdue indicator appears only on '
    'the overdue claim',
    (WidgetTester tester) async {
      await tester.runAsync(() async {
        final int idA = await seedStandard();
        await tester.pumpWidget(_harness(claims));
        await settle(
          tester,
          () => find.byType(ClaimCard).evaluate().length == 4,
        );

        expect(find.text(S.claimsEmpty), findsNothing);

        // Exactly one overdue indicator in the whole treeâ€¦
        expect(find.byKey(const Key('card-overdue-indicator')), findsOneWidget);
        // â€¦and it belongs to claim A.
        final Finder cardA = find.byKey(Key('card-$idA'));
        expect(
          find.descendant(
            of: cardA,
            matching: find.byKey(const Key('card-overdue-indicator')),
          ),
          findsOneWidget,
        );
      });
    },
  );

  testWidgets(
    'filter chips narrow the list â€” closed shows only B; open shows A, C, D '
    '(compensated stays open per spec Â§5)',
    (WidgetTester tester) async {
      await tester.runAsync(() async {
        await seedStandard();
        await tester.pumpWidget(_harness(claims));
        await settle(
          tester,
          () => find.byType(ClaimCard).evaluate().length == 4,
        );

        // Tap the filter CHIP specifically — in English its label ("Closed")
        // is identical to a closed claim's status chip, so a bare text finder
        // would be ambiguous.
        await tester.tap(find.widgetWithText(ChoiceChip, S.filterClosed));
        await settle(
          tester,
          () => find.byType(ClaimCard).evaluate().length == 1,
        );
        expect(find.text('Ø¹Ù…ÙŠÙ„ Ø¨'), findsOneWidget);
        expect(find.text('Ø¹Ù…ÙŠÙ„ Ø£'), findsNothing);

        await tester.tap(find.widgetWithText(ChoiceChip, S.filterOpen));
        await settle(
          tester,
          () => find.byType(ClaimCard).evaluate().length == 3,
        );
        expect(find.text('Ø¹Ù…ÙŠÙ„ Ø£'), findsOneWidget);
        expect(
          find.text('Ø¹Ù…ÙŠÙ„ Ø¬'),
          findsOneWidget,
        ); // compensated counts open
        expect(find.text('Ù…Ø­Ù…Ø¯ Ø§Ù„Ø¹ØªÙŠØ¨ÙŠ'), findsOneWidget);
        expect(find.text('Ø¹Ù…ÙŠÙ„ Ø¨'), findsNothing);
      });
    },
  );

  testWidgets(
    'search matches name, mobile and claim number (case-insensitive); '
    'whitespace-only queries are forgiven',
    (WidgetTester tester) async {
      await tester.runAsync(() async {
        await seedStandard();
        await tester.pumpWidget(_harness(claims));
        await settle(
          tester,
          () => find.byType(ClaimCard).evaluate().length == 4,
        );

        final Finder field = find.widgetWithText(TextField, S.searchHint);
        expect(field, findsOneWidget);

        await tester.enterText(field, 'Ù…Ø­Ù…Ø¯');
        await settle(
          tester,
          () => find.byType(ClaimCard).evaluate().length == 1,
        );
        expect(find.text('Ù…Ø­Ù…Ø¯ Ø§Ù„Ø¹ØªÙŠØ¨ÙŠ'), findsOneWidget);

        await tester.enterText(field, '0551234567');
        await settle(
          tester,
          () => find.byType(ClaimCard).evaluate().length == 1,
        );
        expect(find.text('Ù…Ø­Ù…Ø¯ Ø§Ù„Ø¹ØªÙŠØ¨ÙŠ'), findsOneWidget);

        await tester.enterText(field, '   ');
        await settle(
          tester,
          () => find.byType(ClaimCard).evaluate().length == 4,
        );
        expect(find.text('Ø¹Ù…ÙŠÙ„ Ø£'), findsOneWidget);

        // Partial claim number, different case (SQLite LIKE is ASCII-insensitive).
        await tester.enterText(field, 'clm-200');
        await settle(
          tester,
          () => find.byType(ClaimCard).evaluate().length == 1,
        );
        expect(find.text('Ø¹Ù…ÙŠÙ„ Ø£'), findsOneWidget); // A is CLM-200
      });
    },
  );

  testWidgets(
    'claim card shows the balanced subset (number, name, insurer, status) â€” '
    'never notes',
    (WidgetTester tester) async {
      await tester.runAsync(() async {
        final DateTime now = DateTime.now().toUtc();
        final int idA = await create(
          seed(
            statusKey: 'new',
            followUpUtcMs: now.subtract(const Duration(hours: 24)),
            name: 'Ø¹Ù…ÙŠÙ„ Ø£',
            claimNumber: 'CLM-200',
            plate: '1234 ABC',
          ),
        );

        await tester.pumpWidget(_harness(claims));
        await settle(
          tester,
          () => find.byType(ClaimCard).evaluate().length == 1,
        );

        final Finder cardA = find.byKey(Key('card-$idA'));
        // Plate first, then the customer name, then the claim number.
        final Finder plate = find.text('1234 ABC');
        final Finder name = find.text('Ø¹Ù…ÙŠÙ„ Ø£');
        final Finder number = find.text('CLM-200');
        expect(plate, findsOneWidget);
        expect(name, findsOneWidget);
        expect(number, findsOneWidget);
        expect(find.text('${S.claimNumberLabel}: '), findsOneWidget);
        expect(
          tester.getTopLeft(plate).dy,
          lessThan(tester.getTopLeft(name).dy),
        );
        expect(
          tester.getTopLeft(name).dy,
          lessThan(tester.getTopLeft(number).dy),
        );
        // Liability share is no longer on the card.
        expect(find.text('${S.liabilityPercentLabel}: 50%'), findsNothing);
        // Without action callbacks there are no card buttons.
        expect(find.byKey(Key('card-edit-$idA')), findsNothing);
        expect(
          find.descendant(of: cardA, matching: find.byType(StatusChip)),
          findsOneWidget,
        );
        // Balanced subset only â€” notes must NOT appear on the card.
        expect(
          find.descendant(of: cardA, matching: find.text(S.notesLabel)),
          findsNothing,
        );
      });
    },
  );

  testWidgets('a large list only builds the cards on screen', (
    WidgetTester tester,
  ) async {
    await tester.runAsync(() async {
      for (int i = 0; i < 300; i++) {
        await create(seed(statusKey: 'new', claimNumber: 'BULK-$i'));
      }
      await tester.pumpWidget(_harness(claims));
      await settle(tester, () => find.byType(ClaimCard).evaluate().isNotEmpty);
      final int built = find.byType(ClaimCard).evaluate().length;
      expect(built, greaterThan(0));
      expect(built, lessThan(50));
    });
  });

  testWidgets('a status chip shows only claims with that status', (
    WidgetTester tester,
  ) async {
    await tester.runAsync(() async {
      await create(seed(statusKey: 'new', claimNumber: 'ST-NEW'));
      await create(seed(statusKey: 'rejected', claimNumber: 'ST-REJ'));
      await create(
        seed(statusKey: 'awaiting_documents', claimNumber: 'ST-DOC'),
      );
      await tester.pumpWidget(_harness(claims));
      await settle(tester, () => find.byType(ClaimCard).evaluate().length == 3);

      final Finder chip = find.byKey(
        const Key('filter-status-awaiting_documents'),
      );
      await tester.ensureVisible(chip);
      await tester.tap(chip);
      await settle(tester, () => find.byType(ClaimCard).evaluate().length == 1);
      expect(find.text('ST-DOC'), findsOneWidget);

      // "Finished" groups rejected with approved and closed.
      final Finder finished = find.byKey(const Key('filter-closed'));
      await tester.ensureVisible(finished);
      await tester.tap(finished);
      await settle(tester, () => find.text('ST-REJ').evaluate().isNotEmpty);
      expect(find.byType(ClaimCard), findsOneWidget);
    });
  });

  test('date sorts order by submission date or last update', () {
    Claim c(int id, DateTime submitted, DateTime status, [DateTime? notes]) =>
        seed(statusKey: 'new').copyWith(
          id: id,
          submissionDateUtcMs: submitted,
          lastStatusUpdateUtcMs: status,
          notesUpdatedUtcMs: notes,
        );
    final List<Claim> list = <Claim>[
      c(1, DateTime.utc(2026, 1, 1), DateTime.utc(2026, 5, 1)),
      c(2, DateTime.utc(2026, 3, 1), DateTime.utc(2026, 2, 1)),
      // Old status change, but notes written most recently.
      c(
        3,
        DateTime.utc(2026, 2, 1),
        DateTime.utc(2026, 1, 1),
        DateTime.utc(2026, 6, 1),
      ),
    ];
    List<int> ids(ClaimsSort s) => s.apply(list).map((x) => x.id).toList();

    expect(ids(ClaimsSort.submissionNewest), <int>[2, 3, 1]);
    expect(ids(ClaimsSort.submissionOldest), <int>[1, 3, 2]);
    expect(ids(ClaimsSort.updatedNewest), <int>[3, 1, 2]);
    expect(ids(ClaimsSort.updatedOldest), <int>[2, 1, 3]);
    expect(ids(ClaimsSort.smart), <int>[1, 2, 3]); // unchanged
  });

  testWidgets('a claim without a plate shows the no-plate placeholder', (
    WidgetTester tester,
  ) async {
    await tester.runAsync(() async {
      await create(seed(statusKey: 'new'));
      await tester.pumpWidget(_harness(claims));
      await settle(tester, () => find.byType(ClaimCard).evaluate().length == 1);
      expect(find.text(S.noPlate), findsOneWidget);
    });
  });

  testWidgets(
    'card buttons run change-status, edit and delete for that claim',
    (WidgetTester tester) async {
      await tester.runAsync(() async {
        final int id = await create(seed(statusKey: 'new'));
        final List<String> calls = <String>[];
        await tester.pumpWidget(
          MaterialApp(
            home: ClaimsListScreen(
              repo: claims,
              onChangeStatus: (Claim c) async => calls.add('status-${c.id}'),
              onEdit: (Claim c) async => calls.add('edit-${c.id}'),
              onDelete: (Claim c) async => calls.add('delete-${c.id}'),
            ),
          ),
        );
        await settle(
          tester,
          () => find.byType(ClaimCard).evaluate().length == 1,
        );

        for (final String action in <String>['status', 'edit', 'delete']) {
          await tester.tap(find.byKey(Key('card-$action-$id')));
          await tester.pump();
        }
        expect(calls, <String>['status-$id', 'edit-$id', 'delete-$id']);
      });
    },
  );
}
