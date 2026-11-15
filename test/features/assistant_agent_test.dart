/// AI assistant: the agent loop against a scripted Gemini, with the real
/// database underneath (lookups, confirmed/cancelled writes, validation,
/// errors) and the Riyadh time parsing the model's dates go through.
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart' as ffi;

import 'package:claim_tracker/core/database/app_database.dart';
import 'package:claim_tracker/core/database/claims_repository.dart';
import 'package:claim_tracker/core/models/claim.dart';
import 'package:claim_tracker/core/models/reminder.dart';
import 'package:claim_tracker/core/notifications/notification_service.dart'
    show AlarmPrecision, NotificationPermissionState;
import 'package:claim_tracker/core/notifications/reminder_scheduler.dart';
import 'package:claim_tracker/core/utils/time_utils.dart';
import 'package:claim_tracker/features/assistant/assistant_agent.dart';
import 'package:claim_tracker/features/assistant/assistant_tools.dart';
import 'package:claim_tracker/features/assistant/gemini_client.dart';
import 'package:claim_tracker/features/claims/claim_actions.dart';

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

/// Gemini that answers from a script and records every request body.
class _ScriptedGemini {
  _ScriptedGemini(this.replies);

  final List<Map<String, Object?>> replies;
  final List<Map<String, Object?>> requests = <Map<String, Object?>>[];

  Future<Map<String, Object?>> call(
    String method,
    Uri url,
    String apiKey,
    Map<String, Object?>? body,
  ) async {
    // Snapshot: the agent keeps appending to the same list afterwards.
    requests.add(
      jsonDecode(jsonEncode(body ?? <String, Object?>{}))
          as Map<String, Object?>,
    );
    if (replies.isEmpty) throw StateError('no scripted reply left');
    return replies.removeAt(0);
  }
}

Map<String, Object?> _text(String text) => <String, Object?>{
  'candidates': <Object?>[
    <String, Object?>{
      'content': <String, Object?>{
        'role': 'model',
        'parts': <Object?>[
          <String, Object?>{'text': text},
        ],
      },
    },
  ],
};

Map<String, Object?> _call(String name, Map<String, Object?> args) =>
    <String, Object?>{
      'candidates': <Object?>[
        <String, Object?>{
          'content': <String, Object?>{
            'role': 'model',
            'parts': <Object?>[
              <String, Object?>{
                'functionCall': <String, Object?>{'name': name, 'args': args},
                'thoughtSignature': 'sig-$name',
              },
            ],
          },
        },
      ],
    };

/// The functionResponse payload the agent sent back in its last request.
Map<String, Object?> _lastResponse(_ScriptedGemini g) {
  final List<Object?> contents = g.requests.last['contents']! as List<Object?>;
  final Map<String, Object?> turn = contents.last! as Map<String, Object?>;
  final Map<String, Object?> part =
      (turn['parts']! as List<Object?>).first! as Map<String, Object?>;
  return (part['functionResponse']! as Map<String, Object?>)['response']!
      as Map<String, Object?>;
}

void main() {
  late ffi.Database raw;
  late AppDatabase db;
  late ClaimsRepository claims;
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
    claims = ClaimsRepository(db);
    final DateTime now = DateTime.now().toUtc();
    claimId = await claims.create(
      Claim(
        id: 0,
        customerName: 'LUCID',
        customerMobile: '0500000005',
        customerNationalId: '1105860199',
        vehiclePlate: '3557 ATR',
        vehicleType: 'Lucid Air',
        accidentDateUtcMs: DateTime.utc(2026, 11, 1),
        claimNumber: 'C-01-014679',
        customerInsuranceCompany: 'Wataniya',
        statusKey: 'processing',
        lastStatusUpdateUtcMs: now,
        createdAtUtcMs: now,
        updatedAtUtcMs: now,
      ),
    );
  });

  tearDown(() async => raw.close());

  AssistantAgent agentWith(_ScriptedGemini g, {void Function()? onData}) {
    final _NoopScheduler scheduler = _NoopScheduler();
    return AssistantAgent(
      client: GeminiClient(apiKey: 'k', model: 'm', transport: g.call),
      tools: AssistantTools(
        db: db,
        scheduler: scheduler,
        saveFollowUp: (int id, DateTime when) => ClaimActions(
          db,
          scheduler,
        ).saveReminder(claimId: id, fireAtUtc: when),
      ),
      onDataChanged: onData,
    );
  }

  /// Answers every confirmation card with [confirm] as soon as it appears.
  void autoDecide(AssistantAgent agent, bool confirm) {
    agent.addListener(() {
      for (final ChatItem i in agent.items) {
        if (i is ActionCard && i.state == ActionState.pending) {
          i.decide(confirm);
        }
      }
    });
  }

  String future(int days, String hhmm) {
    final DateTime d = TimeUtils.toRiyadh(DateTime.now().toUtc())
        .add(Duration(days: days));
    String two(int n) => n.toString().padLeft(2, '0');
    return '${d.year}-${two(d.month)}-${two(d.day)}T$hhmm';
  }

  test('search then confirmed reminder: saved on the claim', () async {
    final String when = future(2, '10:00');
    final _ScriptedGemini g = _ScriptedGemini(<Map<String, Object?>>[
      _call('search_claims', <String, Object?>{'query': '3557'}),
      _call('set_reminder', <String, Object?>{
        'claim_id': claimId,
        'when': when,
      }),
      _text('Done, reminder set.'),
    ]);
    int refreshed = 0;
    final AssistantAgent agent = agentWith(g, onData: () => refreshed++);
    autoDecide(agent, true);

    await agent.send('remind me about 3557 ATR');

    // The lookup gave the model the claim, without private fields.
    final List<Object?> contents = g.requests[1]['contents']! as List<Object?>;
    final String sent = '$contents';
    expect(sent.contains('3557 ATR'), isTrue);
    expect(sent.contains('1105860199'), isFalse, reason: 'national id stays');
    expect(sent.contains('0500000005'), isFalse, reason: 'mobile stays');
    // Model turns are echoed back with their signatures.
    expect(sent.contains('sig-search_claims'), isTrue);

    final Claim saved = (await db.claimById(claimId))!;
    expect(saved.nextFollowUpUtcMs, AssistantTools.parseLocalDateTime(when));
    expect(
      agent.items.whereType<ClaimsResult>().single.claims.single.id,
      claimId,
    );
    expect(agent.items.whereType<ActionCard>().single.state, ActionState.done);
    expect((agent.items.last as AssistantMessage).text, 'Done, reminder set.');
    expect(refreshed, 1);
    expect(agent.busy, isFalse);
  });

  test('cancelled card writes nothing and tells the model', () async {
    final _ScriptedGemini g = _ScriptedGemini(<Map<String, Object?>>[
      _call('change_status', <String, Object?>{
        'claim_id': claimId,
        'status': 'approved',
      }),
      _text('OK, left as is.'),
    ]);
    int refreshed = 0;
    final AssistantAgent agent = agentWith(g, onData: () => refreshed++);
    autoDecide(agent, false);

    await agent.send('approve it');

    expect((await db.claimById(claimId))!.statusKey, 'processing');
    expect(_lastResponse(g), <String, Object?>{'cancelled_by_user': true});
    expect(
      agent.items.whereType<ActionCard>().single.state,
      ActionState.cancelled,
    );
    expect(refreshed, 0);
  });

  test(
    'create_claim with a missing field asks instead of showing a card',
    () async {
      final _ScriptedGemini g = _ScriptedGemini(<Map<String, Object?>>[
        _call('create_claim', <String, Object?>{
          'customer_name': 'Fraikin',
          'vehicle_plate': '1234 ABC',
          'insurer': 'Tawuniya',
          'accident_date': '2026-11-10',
        }),
        _text('What is the vehicle type?'),
      ]);
      final AssistantAgent agent = agentWith(g);
      autoDecide(agent, true);

      await agent.send('new claim for Fraikin');

      expect(agent.items.whereType<ActionCard>(), isEmpty);
      expect('${_lastResponse(g)['error']}', contains('vehicle_type'));
      expect(await claims.countAll(), 1);
    },
  );

  test('confirmed create_claim registers it like the form does', () async {
    final _ScriptedGemini g = _ScriptedGemini(<Map<String, Object?>>[
      _call('create_claim', <String, Object?>{
        'customer_name': 'Fraikin',
        'vehicle_plate': '1234 ABC',
        'vehicle_type': 'Hilux',
        'insurer': 'التعاونية',
        'accident_date': '2026-11-10',
        'accident_type': 'najem',
        'submission_date': '2026-11-12',
      }),
      _text('Registered.'),
    ]);
    final AssistantAgent agent = agentWith(g);
    autoDecide(agent, true);

    await agent.send('register it');

    final List<Claim> found = await claims.search('1234 ABC');
    expect(found, hasLength(1));
    final Claim c = found.single;
    expect(
      c.customerInsuranceCompany,
      'Tawuniya',
      reason: 'stored English name',
    );
    expect(c.accidentType, 'Najem');
    expect(c.statusKey, 'new');
    expect(TimeUtils.formatDate(c.accidentDateUtcMs!), contains('10'));
    expect(c.submissionDateUtcMs, AssistantTools.parseLocalDate('2026-11-12'));
    final ActionCard card = agent.items.whereType<ActionCard>().single;
    expect(card.claimId, c.id, reason: 'card can open the new claim');
  });

  test(
    'a rejected key becomes an error item and the turn is dropped',
    () async {
      final AssistantAgent agent = AssistantAgent(
        client: GeminiClient(
          apiKey: 'bad',
          model: 'm',
          transport: (_, _, _, _) async =>
              throw const GeminiException('invalid-key'),
        ),
        tools: AssistantTools(
          db: db,
          scheduler: _NoopScheduler(),
          saveFollowUp: (_, _) async {},
        ),
      );
      await agent.send('hello');
      expect((agent.items.last as ErrorMessage).code, 'invalid-key');
      expect(agent.busy, isFalse);
    },
  );

  test('reminders in the past are refused before any card', () async {
    final _ScriptedGemini g = _ScriptedGemini(<Map<String, Object?>>[
      _call('set_reminder', <String, Object?>{
        'claim_id': claimId,
        'when': '2020-01-01T09:00',
      }),
      _text('That time has passed.'),
    ]);
    final AssistantAgent agent = agentWith(g);
    autoDecide(agent, true);
    await agent.send('remind me in 2020');
    expect(agent.items.whereType<ActionCard>(), isEmpty);
    expect((await db.claimById(claimId))!.nextFollowUpUtcMs, isNull);
  });

  test('model dates are Riyadh local time', () {
    expect(
      AssistantTools.parseLocalDateTime('2026-11-19T10:00'),
      DateTime.utc(2026, 11, 19, 7),
    );
    expect(
      AssistantTools.parseLocalDate('2026-11-19'),
      DateTime.utc(2026, 11, 18, 21),
    );
    expect(AssistantTools.parseLocalDateTime('19/11/2026 10:00'), isNull);
    expect(AssistantTools.parseLocalDateTime('2026-13-01T10:00'), isNull);
  });

  test('system prompt carries today and the coming week', () {
    final String p = AssistantAgent.systemPrompt(DateTime.utc(2026, 11, 15, 9));
    expect(p, contains('2026-11-15 Sunday 12:00'));
    expect(p, contains('2026-11-19 Thursday'));
  });
}
