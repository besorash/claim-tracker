/// The assistant's conversation loop: sends the chat to Gemini, runs the
/// read functions it asks for, and pauses on every write until the user
/// confirms or cancels its card.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:timezone/timezone.dart' as tz;

import '../../core/constants/accident_types.dart';
import '../../core/constants/insurers.dart';
import '../../core/models/claim.dart';
import '../../core/models/claim_status.dart';
import '../../core/utils/time_utils.dart';
import 'assistant_tools.dart';
import 'gemini_client.dart';

sealed class ChatItem {}

class UserMessage extends ChatItem {
  UserMessage(this.text);
  final String text;
}

class AssistantMessage extends ChatItem {
  AssistantMessage(this.text);
  final String text;
}

/// Claims a lookup returned, shown as tappable cards.
class ClaimsResult extends ChatItem {
  ClaimsResult(this.claims);
  final List<Claim> claims;
}

/// A failed request; [code] is a [GeminiException.code] or 'empty'.
class ErrorMessage extends ChatItem {
  ErrorMessage(this.code, [this.detail = '']);
  final String code;
  final String detail;
}

enum ActionState { pending, running, done, cancelled, failed }

/// A write waiting for (or past) the user's decision.
class ActionCard extends ChatItem {
  ActionCard(this.action) : claimId = action.claimId;

  final PreparedAction action;
  ActionState state = ActionState.pending;

  /// Claim to open from the card once done (set for a new claim on success).
  int? claimId;
  final Completer<bool> _decision = Completer<bool>();

  /// Called by the Confirm / Cancel buttons.
  void decide(bool confirmed) {
    if (!_decision.isCompleted) _decision.complete(confirmed);
  }
}

class AssistantAgent extends ChangeNotifier {
  AssistantAgent({
    required this.client,
    required this.tools,
    this.onDataChanged,
  });

  final GeminiClient client;
  final AssistantTools tools;

  /// Called after a confirmed write so the other tabs reload.
  final VoidCallback? onDataChanged;

  final List<ChatItem> items = <ChatItem>[];
  final List<Map<String, Object?>> _contents = <Map<String, Object?>>[];
  bool busy = false;
  bool _disposed = false;

  /// Upper bound on model round-trips for one user message (each function
  /// call needs one); stops a model that loops on lookups.
  static const int _maxSteps = 8;

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  /// Starts over: cancels a card still waiting and forgets the conversation.
  void clear() {
    for (final ChatItem i in items) {
      if (i is ActionCard) i.decide(false);
    }
    items.clear();
    _contents.clear();
    _notify();
  }

  Future<void> send(String text) async {
    final String message = text.trim();
    if (message.isEmpty || busy) return;
    final int rollback = _contents.length;
    items.add(UserMessage(message));
    _contents.add(<String, Object?>{
      'role': 'user',
      'parts': <Object?>[
        <String, Object?>{'text': message},
      ],
    });
    busy = true;
    _notify();
    bool wrote = false;
    try {
      for (int step = 0; step < _maxSteps; step++) {
        final Map<String, Object?> res = await client.generate(_body());
        final Map<String, Object?>? content = _firstContent(res);
        if (content == null) {
          items.add(ErrorMessage('empty'));
          _contents.removeRange(rollback, _contents.length);
          break;
        }
        // Echo the model turn back verbatim: newer models attach signatures
        // to their function calls that must come back unchanged.
        _contents.add(<String, Object?>{...content, 'role': 'model'});
        final List<Map<String, Object?>> parts =
            ((content['parts'] as List<Object?>?) ?? const <Object?>[])
                .whereType<Map<String, Object?>>()
                .toList();
        final String reply = parts
            .where((Map<String, Object?> p) => p['thought'] != true)
            .map((Map<String, Object?> p) => p['text'])
            .whereType<String>()
            .join()
            .trim();
        if (reply.isNotEmpty) items.add(AssistantMessage(reply));
        final List<Map<String, Object?>> calls = <Map<String, Object?>>[
          for (final Map<String, Object?> p in parts)
            if (p['functionCall'] is Map<String, Object?>)
              p['functionCall']! as Map<String, Object?>,
        ];
        _notify();
        if (calls.isEmpty) break;

        final List<Object?> responses = <Object?>[];
        for (final Map<String, Object?> call in calls) {
          final String name = '${call['name']}';
          final Map<String, Object?> args =
              (call['args'] as Map<String, Object?>?) ?? <String, Object?>{};
          final Map<String, Object?> result;
          if (AssistantTools.isWrite(name)) {
            final (Map<String, Object?> r, bool ok) = await _write(name, args);
            result = r;
            wrote = wrote || ok;
          } else {
            result = await tools.read(name, args);
            if (tools.lastResults.isNotEmpty) {
              items.add(ClaimsResult(tools.lastResults));
              tools.lastResults = const <Claim>[];
            }
          }
          responses.add(<String, Object?>{
            'functionResponse': <String, Object?>{
              if (call['id'] != null) 'id': call['id'],
              'name': name,
              'response': result,
            },
          });
          _notify();
        }
        _contents.add(<String, Object?>{'role': 'user', 'parts': responses});
      }
    } on GeminiException catch (e) {
      items.add(ErrorMessage(e.code, e.detail));
      // Drop the unanswered turn so the next message starts clean.
      if (!wrote) _contents.removeRange(rollback, _contents.length);
    } on Object catch (e) {
      items.add(ErrorMessage('http', '$e'));
      if (!wrote) _contents.removeRange(rollback, _contents.length);
    } finally {
      busy = false;
      _notify();
      if (wrote) onDataChanged?.call();
    }
  }

  /// Validates, shows the card, waits for the user, runs it. Returns what the
  /// model is told and whether anything was written.
  Future<(Map<String, Object?>, bool)> _write(
    String name,
    Map<String, Object?> args,
  ) async {
    final Object prepared = await tools.prepare(name, args);
    if (prepared is! PreparedAction) {
      return (prepared as Map<String, Object?>, false);
    }
    final ActionCard card = ActionCard(prepared);
    items.add(card);
    _notify();
    final bool confirmed = await card._decision.future;
    if (!confirmed) {
      card.state = ActionState.cancelled;
      _notify();
      return (<String, Object?>{'cancelled_by_user': true}, false);
    }
    card.state = ActionState.running;
    _notify();
    try {
      final Map<String, Object?> result = await prepared.run();
      card.claimId ??= result['claim_id'] as int?;
      card.state = ActionState.done;
      return (result, true);
    } on Object catch (e) {
      card.state = ActionState.failed;
      return (<String, Object?>{'error': 'failed: $e'}, false);
    } finally {
      _notify();
    }
  }

  static Map<String, Object?>? _firstContent(Map<String, Object?> res) {
    final List<Object?> candidates =
        (res['candidates'] as List<Object?>?) ?? const <Object?>[];
    if (candidates.isEmpty) return null;
    final Object? first = candidates.first;
    if (first is! Map<String, Object?>) return null;
    final Object? content = first['content'];
    if (content is! Map<String, Object?>) return null;
    final List<Object?>? parts = content['parts'] as List<Object?>?;
    return (parts == null || parts.isEmpty) ? null : content;
  }

  Map<String, Object?> _body() => <String, Object?>{
    'systemInstruction': <String, Object?>{
      'parts': <Object?>[
        <String, Object?>{'text': systemPrompt(DateTime.now().toUtc())},
      ],
    },
    'contents': _contents,
    'tools': <Object?>[
      <String, Object?>{'functionDeclarations': AssistantTools.declarations},
    ],
    'generationConfig': <String, Object?>{'temperature': 0.2},
  };

  static const List<String> _weekdays = <String>[
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
    'Sunday',
  ];

  /// Instructions plus today's date and the coming week, so "Thursday" or
  /// "الخميس" resolve to the right date.
  static String systemPrompt(DateTime nowUtc) {
    final tz.TZDateTime now = TimeUtils.toRiyadh(nowUtc);
    String two(int n) => n.toString().padLeft(2, '0');
    String day(tz.TZDateTime d) =>
        '${d.year}-${two(d.month)}-${two(d.day)} ${_weekdays[d.weekday - 1]}';
    final String week = <String>[
      for (int i = 1; i <= 7; i++) day(now.add(Duration(days: i))),
    ].join('; ');
    return '''
You are the assistant inside "Claim Tracker Pro", a private app where one user tracks vehicle insurance claims in Saudi Arabia. You act on the user's claims through the functions provided.

Now (Asia/Riyadh): ${day(now)} ${two(now.hour)}:${two(now.minute)}.
Next 7 days: $week.

Rules:
- Reply in the language the user writes in (Arabic or English). Keep replies short and friendly. Plain text only: no markdown, no tables, no asterisks.
- Never invent claim ids or claim data. To act on a claim, first find it with search_claims (plate, customer name or claim number). If several claims match, list them briefly and ask which one. If none match, say so.
- For changes (create_claim, set_reminder, clear_reminder, change_status, add_note) call the function directly: the app shows the user a confirmation card. Do not ask "are you sure" in text first. If the result says cancelled_by_user, acknowledge briefly and do nothing else.
- All times are Riyadh time. Reminder times use YYYY-MM-DDTHH:MM, 24-hour. Morning without an hour means 09:00, evening means 18:00; say which time you used. Never set a reminder in the past.
- For a new claim you need customer name, vehicle plate, vehicle type, insurer and accident date. Ask for whatever is missing in one short message; do not guess. "Today"/"yesterday" are fine for dates.
- Statuses: ${ClaimStatus.all.map((ClaimStatusMeta m) => '${m.key} (${m.label})').join(', ')}.
- Insurers: ${Insurers.all.map((Insurer i) => '${i.en} = ${i.ar}').join(', ')}.
- Accident types: ${AccidentTypes.all.map((AccidentType t) => '${t.en} = ${t.ar}').join(', ')}.
- You cannot delete claims or attachments; tell the user to do that in the app.
- After a successful change, confirm in one sentence what was done.''';
  }

  @override
  void dispose() {
    _disposed = true;
    clear();
    super.dispose();
  }
}
