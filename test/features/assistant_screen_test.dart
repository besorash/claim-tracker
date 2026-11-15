/// Assistant tab UI: setup view without a key, key test-and-save, a chat
/// turn with a confirmation card, and the write landing in the database.
library;

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart' as ffi;

import 'package:claim_tracker/core/database/app_database.dart';
import 'package:claim_tracker/core/database/claims_repository.dart';
import 'package:claim_tracker/core/l10n/app_strings.dart';
import 'package:claim_tracker/core/models/claim.dart';
import 'package:claim_tracker/core/models/reminder.dart';
import 'package:claim_tracker/core/notifications/notification_service.dart'
    show AlarmPrecision, NotificationPermissionState;
import 'package:claim_tracker/core/notifications/reminder_scheduler.dart';
import 'package:claim_tracker/core/theme/app_theme.dart';
import 'package:claim_tracker/core/utils/time_utils.dart';
import 'package:claim_tracker/features/assistant/assistant_screen.dart';
import 'package:claim_tracker/features/assistant/gemini_client.dart';

class _NoopScheduler implements ReminderScheduler {
  @override
  Future<void> cancelReminder(int notificationId) async {}
  @override
  Future<AlarmPrecision> scheduleReminder(Reminder reminder) async =>
      AlarmPrecision.exact;
  @override
  Future<bool> areNotificationsEnabled() async => true;
  @override
  Future<NotificationPermissionState> requestNotificationsPermission() async =>
      NotificationPermissionState.granted;
  @override
  Future<void> reconcile(List<Reminder> enabledReminders) async {}
  @override
  Future<bool> openAppNotificationSettings() async => false;
  @override
  Future<bool> canScheduleExactAlarms() async => true;
  @override
  Future<bool> requestExactAlarmsPermission() async => true;
  @override
  Future<bool> isIgnoringBatteryOptimizations() async => true;
  @override
  Future<bool> requestIgnoreBatteryOptimizations() async => true;
}

Map<String, Object?> _reply(Map<String, Object?> part) => <String, Object?>{
  'candidates': <Object?>[
    <String, Object?>{
      'content': <String, Object?>{
        'role': 'model',
        'parts': <Object?>[part],
      },
    },
  ],
};

void main() {
  late ffi.Database raw;
  late AppDatabase db;
  late int claimId;

  setUpAll(() async {
    ffi.sqfliteFfiInit();
    await TimeUtils.ensureInitialized();
  });

  setUp(() async {
    raw = await ffi.databaseFactoryFfi.openDatabase(ffi.inMemoryDatabasePath);
    await raw.execute('PRAGMA foreign_keys = ON');
    await AppDatabase.migrate(raw, from: 0, to: kDatabaseVersion);
    db = AppDatabase.fromExisting(raw);
    final DateTime now = DateTime.now().toUtc();
    claimId = await ClaimsRepository(db).create(
      Claim(
        id: 0,
        customerName: 'LUCID',
        customerMobile: '',
        vehiclePlate: '3557 ATR',
        vehicleType: 'Lucid Air',
        claimNumber: 'C-1',
        customerInsuranceCompany: 'Wataniya',
        statusKey: 'processing',
        lastStatusUpdateUtcMs: now,
        createdAtUtcMs: now,
        updatedAtUtcMs: now,
      ),
    );
  });

  tearDown(() async => raw.close());

  Widget harness(AssistantKeyStore store, GeminiTransport transport) =>
      MaterialApp(
        locale: const Locale('en'),
        supportedLocales: const <Locale>[Locale('en')],
        localizationsDelegates: const <LocalizationsDelegate<Object?>>[
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        theme: AppTheme.light(),
        home: Scaffold(
          body: AssistantScreen(
            db: db,
            scheduler: _NoopScheduler(),
            keyStore: store,
            transport: transport,
          ),
        ),
      );

  testWidgets('no key → setup; test & save stores it and opens the chat', (
    WidgetTester tester,
  ) async {
    final MemoryAssistantKeyStore store = MemoryAssistantKeyStore();
    final List<String> calls = <String>[];
    await tester.runAsync(() async {
      await tester.pumpWidget(
        harness(store, (String method, Uri url, String key, _) async {
          calls.add('$method ${url.path} $key');
          return <String, Object?>{'name': 'models/gemini-flash-latest'};
        }),
      );
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pumpAndSettle();
    expect(find.text(S.assistantSetupTitle), findsOneWidget);
    expect(find.byKey(const Key('assistant-input')), findsNothing);

    await tester.tap(find.byKey(const Key('assistant-add-key')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('assistant-key-field')),
      '  AIzaTEST  ',
    );
    await tester.pump();
    await tester.runAsync(() async {
      await tester.tap(find.byKey(const Key('assistant-test-save')));
      await Future<void>.delayed(const Duration(milliseconds: 900));
    });
    await tester.pumpAndSettle();

    expect(calls.single, 'GET /v1beta/models/gemini-flash-latest AIzaTEST');
    expect(store.key, 'AIzaTEST');
    expect(store.model, AssistantScreen.defaultModel);
    expect(find.byKey(const Key('assistant-input')), findsOneWidget);
    expect(find.text(S.assistantSuggestOverdue), findsOneWidget);
  });

  testWidgets('chat turn: confirm card sets the status in the database', (
    WidgetTester tester,
  ) async {
    final MemoryAssistantKeyStore store = MemoryAssistantKeyStore(key: 'k');
    final List<Map<String, Object?>> script = <Map<String, Object?>>[
      _reply(<String, Object?>{
        'functionCall': <String, Object?>{
          'name': 'change_status',
          'args': <String, Object?>{
            'claim_id': claimId,
            'status': 'awaiting_approval',
          },
        },
      }),
      _reply(<String, Object?>{'text': 'Status updated.'}),
    ];
    await tester.runAsync(() async {
      await tester.pumpWidget(
        harness(store, (_, _, _, _) async => script.removeAt(0)),
      );
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('assistant-input')),
      'move 3557 ATR to awaiting approval',
    );
    await tester.pump();
    await tester.runAsync(() async {
      await tester.tap(find.byKey(const Key('assistant-send')));
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('move 3557 ATR to awaiting approval'), findsOneWidget);
    expect(find.text(S.assistantActionStatus), findsOneWidget);
    expect(
      (await tester.runAsync<Claim?>(() => db.claimById(claimId)))!.statusKey,
      'processing',
      reason: 'nothing written before Confirm',
    );

    await tester.runAsync(() async {
      await tester.tap(find.byKey(const Key('assistant-confirm-action')));
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text(S.assistantStateDone), findsOneWidget);
    expect(find.text('Status updated.'), findsOneWidget);
    final Claim? saved = await tester.runAsync<Claim?>(
      () => db.claimById(claimId),
    );
    expect(saved!.statusKey, 'awaiting_approval');
  });

  testWidgets('mic without a speech service explains instead of crashing', (
    WidgetTester tester,
  ) async {
    await tester.runAsync(() async {
      await tester.pumpWidget(
        harness(
          MemoryAssistantKeyStore(key: 'k'),
          (_, _, _, _) async => <String, Object?>{},
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('assistant-mic')), findsOneWidget);

    // No speech plugin in tests: initialize fails like a phone without one.
    await tester.runAsync(() async {
      await tester.tap(find.byKey(const Key('assistant-mic')));
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pump();
    expect(find.text(S.assistantMicUnavailable), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
