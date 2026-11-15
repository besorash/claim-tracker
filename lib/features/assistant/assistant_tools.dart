/// The functions the assistant may call, their Gemini declarations, and how
/// each one runs against the app's own repositories and [ClaimActions].
///
/// Reads run straight away. Writes are only *prepared* here: the chat shows
/// them as a card and runs them after the user taps Confirm.
library;

import 'package:timezone/timezone.dart' as tz;

import '../../core/constants/accident_types.dart';
import '../../core/constants/loss_types.dart';
import '../../core/constants/app_constants.dart';
import '../../core/constants/insurers.dart';
import '../../core/database/app_database.dart';
import '../../core/database/claims_repository.dart';
import '../../core/l10n/app_strings.dart';
import '../../core/models/claim.dart';
import '../../core/models/claim_status.dart';
import '../../core/notifications/reminder_scheduler.dart';
import '../../core/utils/time_utils.dart';
import '../claims/claim_actions.dart';
import '../claims/claim_form_model.dart';

/// Persists a follow-up for a claim (the chat passes the permission-aware
/// flow the rest of the app uses; tests pass a plain save).
typedef SaveFollowUp = Future<void> Function(int claimId, DateTime whenUtc);

enum AssistantActionKind {
  createClaim,
  setReminder,
  clearReminder,
  status,
  note,
}

/// A write waiting for the user's OK.
class PreparedAction {
  PreparedAction({
    required this.kind,
    required this.rows,
    required this.run,
    this.claimId,
  });

  final AssistantActionKind kind;

  /// Label/value pairs shown on the confirmation card.
  final List<(String, String)> rows;

  /// Existing claim the action touches (null for a new claim).
  final int? claimId;

  /// Performs the write; returns the result handed back to the model.
  final Future<Map<String, Object?>> Function() run;
}

class AssistantTools {
  AssistantTools({
    required this.db,
    required this.scheduler,
    required this.saveFollowUp,
  });

  final AppDatabase db;
  final ReminderScheduler scheduler;
  final SaveFollowUp saveFollowUp;

  ClaimsRepository get _claims => ClaimsRepository(db);
  ClaimActions get _actions => ClaimActions(db, scheduler);

  static const Set<String> writeTools = <String>{
    'create_claim',
    'set_reminder',
    'clear_reminder',
    'change_status',
    'add_note',
  };

  static bool isWrite(String name) => writeTools.contains(name);

  // ---------------------------------------------------------------------------
  // Declarations sent to Gemini.
  // ---------------------------------------------------------------------------

  static Map<String, Object?> _str(String description) => <String, Object?>{
    'type': 'string',
    'description': description,
  };

  static List<Map<String, Object?>> get declarations => <Map<String, Object?>>[
    <String, Object?>{
      'name': 'search_claims',
      'description':
          'Find claims by any text: plate, customer name, claim number, '
          'insurer, city, status, notes. Use it to resolve which claim the '
          'user means before acting on it.',
      'parameters': <String, Object?>{
        'type': 'object',
        'properties': <String, Object?>{'query': _str('Text to search for.')},
        'required': <String>['query'],
      },
    },
    <String, Object?>{
      'name': 'list_claims',
      'description':
          'List claims in a group: overdue follow-ups, follow-ups due '
          'today, all claims with a follow-up, recently registered (by '
          'submission date), open claims, or every claim with one exact '
          'status (group "status" plus the status key).',
      'parameters': <String, Object?>{
        'type': 'object',
        'properties': <String, Object?>{
          'group': <String, Object?>{
            'type': 'string',
            'enum': <String>[
              'overdue',
              'due_today',
              'with_follow_up',
              'recently_registered',
              'open',
              'status',
            ],
          },
          'status': <String, Object?>{
            'type': 'string',
            'description': 'Only with group "status".',
            'enum': <String>[
              for (final ClaimStatusMeta m in ClaimStatus.all) m.key,
            ],
          },
        },
        'required': <String>['group'],
      },
    },
    <String, Object?>{
      'name': 'get_claim',
      'description': 'Full details of one claim by its id.',
      'parameters': <String, Object?>{
        'type': 'object',
        'properties': <String, Object?>{
          'claim_id': <String, Object?>{'type': 'integer'},
        },
        'required': <String>['claim_id'],
      },
    },
    <String, Object?>{
      'name': 'get_summary',
      'description':
          'Dashboard numbers: total, open, finished, awaiting approval, '
          'follow-ups due today, overdue, and claims per status.',
      'parameters': <String, Object?>{
        'type': 'object',
        'properties': <String, Object?>{},
      },
    },
    <String, Object?>{
      'name': 'set_reminder',
      'description':
          'Set (or move) the follow-up reminder of an existing claim. The '
          'app asks the user to confirm.',
      'parameters': <String, Object?>{
        'type': 'object',
        'properties': <String, Object?>{
          'claim_id': <String, Object?>{'type': 'integer'},
          'when': _str('Riyadh local time, format YYYY-MM-DDTHH:MM (24h).'),
        },
        'required': <String>['claim_id', 'when'],
      },
    },
    <String, Object?>{
      'name': 'clear_reminder',
      'description': 'Remove the follow-up reminder of a claim.',
      'parameters': <String, Object?>{
        'type': 'object',
        'properties': <String, Object?>{
          'claim_id': <String, Object?>{'type': 'integer'},
        },
        'required': <String>['claim_id'],
      },
    },
    <String, Object?>{
      'name': 'change_status',
      'description':
          'Change the status of a claim. Approved, rejected and closed '
          'finish the claim and remove its reminder.',
      'parameters': <String, Object?>{
        'type': 'object',
        'properties': <String, Object?>{
          'claim_id': <String, Object?>{'type': 'integer'},
          'status': <String, Object?>{
            'type': 'string',
            'enum': <String>[
              for (final ClaimStatusMeta m in ClaimStatus.all) m.key,
            ],
          },
          'note': _str('Optional note saved in the status history.'),
        },
        'required': <String>['claim_id', 'status'],
      },
    },
    <String, Object?>{
      'name': 'add_note',
      'description': "Append a note to a claim's notes.",
      'parameters': <String, Object?>{
        'type': 'object',
        'properties': <String, Object?>{
          'claim_id': <String, Object?>{'type': 'integer'},
          'note': _str('The note text.'),
        },
        'required': <String>['claim_id', 'note'],
      },
    },
    <String, Object?>{
      'name': 'create_claim',
      'description':
          'Register a new claim. Required: vehicle_plate and accident_date; '
          'everything else is optional. Ask the user for a missing required '
          'value instead of guessing.',
      'parameters': <String, Object?>{
        'type': 'object',
        'properties': <String, Object?>{
          'customer_name': _str('Customer (company or person) name.'),
          'vehicle_plate': _str('Plate, e.g. "3557 ATR".'),
          'vehicle_type': _str('Make/model, e.g. "Camry 2022".'),
          'insurer': _str(
            'Insurance company. Use one of: '
            '${Insurers.all.map((Insurer i) => i.en).join(', ')} '
            'or the name as given.',
          ),
          'accident_date': _str('YYYY-MM-DD'),
          'claim_number': _str('Optional.'),
          'accident_city': _str('Optional.'),
          'accident_type': <String, Object?>{
            'type': 'string',
            'description': 'Optional.',
            'enum': <String>[
              for (final AccidentType t in AccidentTypes.all) t.en,
            ],
          },
          'customer_mobile': _str('Optional Saudi mobile.'),
          'submission_date': _str('Optional, YYYY-MM-DD.'),
          'notes': _str('Optional.'),
          'loss_type': <String, Object?>{
            'type': 'string',
            'description': 'Optional: total loss or partial loss.',
            'enum': LossTypes.all,
          },
          'follow_up': _str('Optional reminder, YYYY-MM-DDTHH:MM Riyadh time.'),
        },
        'required': <String>['vehicle_plate', 'accident_date'],
      },
    },
  ];

  // ---------------------------------------------------------------------------
  // Reads.
  // ---------------------------------------------------------------------------

  /// Runs a read-only tool. Unknown names and bad arguments come back as an
  /// `error` entry so the model can correct itself.
  Future<Map<String, Object?>> read(
    String name,
    Map<String, Object?> args,
  ) async {
    final DateTime now = DateTime.now().toUtc();
    switch (name) {
      case 'search_claims':
        final String q = '${args['query'] ?? ''}'.trim();
        if (q.isEmpty) return _error('query is empty');
        final List<Claim> found = await _claims.search(q);
        return _list(found);
      case 'list_claims':
        final (DateTime start, DateTime end) = TimeUtils.riyadhDayRange(now);
        final List<Claim> found = switch ('${args['group']}') {
          'overdue' => await _claims.overdue(now),
          'due_today' => await _claims.dueBetween(start, end),
          'with_follow_up' => await _claims.needsFollowUp(),
          'recently_registered' => await _claims.recentlySubmitted(10),
          'open' => await _claims.open(),
          'status' => await _claims.withStatus('${args['status']}'),
          _ => const <Claim>[],
        };
        return _list(found);
      case 'get_claim':
        final Claim? c = await _claim(args['claim_id']);
        if (c == null) return _error('no claim with that id');
        return <String, Object?>{'claim': details(c)};
      case 'get_summary':
        final (DateTime start, DateTime end) = TimeUtils.riyadhDayRange(now);
        final Map<String, int> perStatus = <String, int>{};
        for (final ClaimStatusMeta m in ClaimStatus.all) {
          final int n = await _claims.countWithStatus(m.key);
          if (n > 0) perStatus[m.label] = n;
        }
        return <String, Object?>{
          'total': await _claims.countAll(),
          'open': await _claims.countOpen(),
          'finished': await _claims.countClosed(),
          'due_today': await _claims.countDueBetween(start, end),
          'overdue': await _claims.countOverdue(now),
          'per_status': perStatus,
        };
    }
    return _error('unknown function $name');
  }

  /// Claims found by the last read, for the chat to show as cards.
  List<Claim> lastResults = const <Claim>[];

  static const int _maxListed = 10;

  Map<String, Object?> _list(List<Claim> claims) {
    lastResults = claims.take(_maxListed).toList();
    return <String, Object?>{
      'count': claims.length,
      if (claims.length > _maxListed) 'showing_first': _maxListed,
      'claims': <Map<String, Object?>>[
        for (final Claim c in lastResults) brief(c),
      ],
    };
  }

  /// What the model sees of a claim in a list. No national id, mobile or
  /// email: they are not needed to act and stay on the device.
  static Map<String, Object?> brief(Claim c) => <String, Object?>{
    'id': c.id,
    'plate': c.vehiclePlate,
    'customer': c.customerName,
    'claim_number': c.claimNumber,
    'status': ClaimStatus.byKey(c.statusKey).label,
    'insurer': c.customerInsuranceCompany,
    if (c.nextFollowUpUtcMs != null) 'follow_up': _local(c.nextFollowUpUtcMs!),
    if (c.submissionDateUtcMs != null)
      'submission_date': _localDate(c.submissionDateUtcMs!),
  };

  static Map<String, Object?> details(Claim c) => <String, Object?>{
    ...brief(c),
    'vehicle_type': c.vehicleType,
    if (c.accidentDateUtcMs != null)
      'accident_date': _localDate(c.accidentDateUtcMs!),
    'accident_city': c.accidentCity,
    'accident_type': c.accidentType,
    'claim_amount_sar': c.claimAmountSar,
    if (c.lossType != null) 'loss_type': c.lossType,
    'insurer_reference': c.insurerReferenceNumber,
    'notes': c.notes,
    'last_status_update': _local(c.lastStatusUpdateUtcMs),
  };

  // ---------------------------------------------------------------------------
  // Writes: validated and described here, run after the user confirms.
  // ---------------------------------------------------------------------------

  /// Returns a [PreparedAction], or an error map to send straight back to the
  /// model (bad id, bad date, missing required field...).
  Future<Object> prepare(String name, Map<String, Object?> args) async {
    switch (name) {
      case 'set_reminder':
        final Claim? c = await _claim(args['claim_id']);
        if (c == null) return _error('no claim with that id');
        final DateTime? when = parseLocalDateTime('${args['when']}');
        if (when == null) return _error('when must be YYYY-MM-DDTHH:MM');
        if (!when.isAfter(DateTime.now().toUtc())) {
          return _error(
            'that time is in the past; ask the user for a future time',
          );
        }
        return PreparedAction(
          kind: AssistantActionKind.setReminder,
          claimId: c.id,
          rows: <(String, String)>[
            ..._claimRows(c),
            (S.reminderWhenLabel, TimeUtils.formatDateTime(when)),
          ],
          run: () async {
            await saveFollowUp(c.id, when);
            return <String, Object?>{'ok': true, 'reminder': _local(when)};
          },
        );
      case 'clear_reminder':
        final Claim? c = await _claim(args['claim_id']);
        if (c == null) return _error('no claim with that id');
        if (c.nextFollowUpUtcMs == null) {
          return _error('this claim has no reminder');
        }
        return PreparedAction(
          kind: AssistantActionKind.clearReminder,
          claimId: c.id,
          rows: <(String, String)>[
            ..._claimRows(c),
            (
              S.reminderWhenLabel,
              TimeUtils.formatDateTime(c.nextFollowUpUtcMs!),
            ),
          ],
          run: () async {
            await _actions.clearFollowUp(c.id);
            return <String, Object?>{'ok': true};
          },
        );
      case 'change_status':
        final Claim? c = await _claim(args['claim_id']);
        if (c == null) return _error('no claim with that id');
        final String key = '${args['status']}';
        if (!ClaimStatus.all.any((ClaimStatusMeta m) => m.key == key)) {
          return _error('unknown status $key');
        }
        final String note = '${args['note'] ?? ''}'.trim();
        return PreparedAction(
          kind: AssistantActionKind.status,
          claimId: c.id,
          rows: <(String, String)>[
            ..._claimRows(c),
            (
              S.statusLabel,
              '${ClaimStatus.byKey(c.statusKey).label}  →  '
                  '${ClaimStatus.byKey(key).label}',
            ),
            if (note.isNotEmpty) (S.notesLabel, note),
          ],
          run: () async {
            await _actions.changeStatus(
              c.id,
              key,
              note: note,
              followUp: const KeepFollowUp(),
            );
            return <String, Object?>{'ok': true};
          },
        );
      case 'add_note':
        final Claim? c = await _claim(args['claim_id']);
        if (c == null) return _error('no claim with that id');
        final String note = '${args['note'] ?? ''}'.trim();
        if (note.isEmpty) return _error('note is empty');
        return PreparedAction(
          kind: AssistantActionKind.note,
          claimId: c.id,
          rows: <(String, String)>[..._claimRows(c), (S.notesLabel, note)],
          run: () async {
            // Re-read: the claim may have changed since the card was shown.
            final Claim fresh = await db.claimById(c.id) ?? c;
            final DateTime now = DateTime.now().toUtc();
            final String old = fresh.notes?.trim() ?? '';
            await _claims.update(
              fresh.copyWith(
                notes: old.isEmpty ? note : '$old\n$note',
                notesUpdatedUtcMs: now,
                updatedAtUtcMs: now,
              ),
            );
            return <String, Object?>{'ok': true};
          },
        );
      case 'create_claim':
        return _prepareCreate(args);
    }
    return _error('unknown function $name');
  }

  Object _prepareCreate(Map<String, Object?> args) {
    String s(String k) => '${args[k] ?? ''}'.trim();
    final ClaimFormModel m = ClaimFormModel()
      ..customerName = s('customer_name')
      ..vehiclePlate = s('vehicle_plate')
      ..vehicleType = s('vehicle_type')
      ..customerInsuranceCompany = _insurer(s('insurer'))
      ..claimNumber = s('claim_number')
      ..accidentCity = s('accident_city')
      ..accidentType =
          AccidentTypes.match(s('accident_type'))?.en ?? s('accident_type')
      ..customerMobile = s('customer_mobile')
      ..notes = s('notes')
      ..lossType = LossTypes.parse(s('loss_type'));
    m.accidentDateUtcMs = parseLocalDate(s('accident_date'));
    if (s('submission_date').isNotEmpty) {
      m.submissionDateUtcMs = parseLocalDate(s('submission_date'));
      if (m.submissionDateUtcMs == null) {
        return _error('submission_date must be YYYY-MM-DD');
      }
    }
    DateTime? followUp;
    if (s('follow_up').isNotEmpty) {
      followUp = parseLocalDateTime(s('follow_up'));
      if (followUp == null) return _error('follow_up must be YYYY-MM-DDTHH:MM');
    }

    // Same rules as the claim form.
    final List<String> missing = <String>[
      if (m.validateVehiclePlate() != null) 'vehicle_plate',
      if (m.accidentDateUtcMs == null) 'accident_date (YYYY-MM-DD)',
    ];
    if (missing.isNotEmpty) {
      return _error('missing or invalid: ${missing.join(', ')}. Ask the user.');
    }
    if (m.validateMobile() != null) {
      return _error('customer_mobile is not a valid Saudi mobile number');
    }

    return PreparedAction(
      kind: AssistantActionKind.createClaim,
      rows: <(String, String)>[
        (S.vehiclePlateLabel, m.vehiclePlate),
        (S.accidentDateLabel, TimeUtils.formatDate(m.accidentDateUtcMs!)),
        if (m.customerName.isNotEmpty) (S.customerNameLabel, m.customerName),
        if (m.vehicleType.isNotEmpty) (S.vehicleTypeLabel, m.vehicleType),
        if (m.customerInsuranceCompany.isNotEmpty)
          (
            S.customerInsurerLabel,
            Insurers.display(m.customerInsuranceCompany),
          ),
        if (m.lossType != null) (S.lossTypeLabel, LossTypes.label(m.lossType!)),
        if (m.claimNumber.isNotEmpty) (S.claimNumberLabel, m.claimNumber),
        if (m.accidentCity.isNotEmpty) (S.cityLabel, m.accidentCity),
        if (m.accidentType.isNotEmpty)
          (S.accidentTypeLabel, AccidentTypes.display(m.accidentType)),
        if (m.customerMobile.isNotEmpty) (S.mobileLabel, m.customerMobile),
        if (m.submissionDateUtcMs != null)
          (S.submissionDateLabel, TimeUtils.formatDate(m.submissionDateUtcMs!)),
        if (m.notes.isNotEmpty) (S.notesLabel, m.notes),
        if (followUp != null)
          (S.reminderWhenLabel, TimeUtils.formatDateTime(followUp)),
      ],
      run: () async {
        final int id = await _claims.create(m.buildNew(DateTime.now().toUtc()));
        if (followUp != null) await saveFollowUp(id, followUp);
        return <String, Object?>{'ok': true, 'claim_id': id};
      },
    );
  }

  // ---------------------------------------------------------------------------
  // Helpers.
  // ---------------------------------------------------------------------------

  Future<Claim?> _claim(Object? id) async {
    final int? n = id is int ? id : int.tryParse('${id ?? ''}');
    if (n == null) return null;
    return db.claimById(n);
  }

  static List<(String, String)> _claimRows(Claim c) => <(String, String)>[
    (S.vehiclePlateLabel, c.vehiclePlate ?? S.noPlate),
    (S.customerNameLabel, c.customerName),
    if (c.claimNumber.isNotEmpty) (S.claimNumberLabel, c.claimNumberDisplay),
  ];

  static Map<String, Object?> _error(String message) => <String, Object?>{
    'error': message,
  };

  static tz.Location get _riyadh => tz.getLocation(AppConstants.timeZoneId);

  /// `YYYY-MM-DDTHH:MM` in Riyadh time → UTC. Null when malformed.
  static DateTime? parseLocalDateTime(String raw) {
    final RegExpMatch? m = RegExp(
      r'^(\d{4})-(\d{2})-(\d{2})[T ](\d{2}):(\d{2})',
    ).firstMatch(raw.trim());
    if (m == null) return null;
    final List<int> v = <int>[for (int i = 1; i <= 5; i++) int.parse(m[i]!)];
    if (v[1] < 1 || v[1] > 12 || v[2] < 1 || v[2] > 31) return null;
    if (v[3] > 23 || v[4] > 59) return null;
    return _plainUtc(tz.TZDateTime(_riyadh, v[0], v[1], v[2], v[3], v[4]));
  }

  /// `YYYY-MM-DD` → midnight Riyadh time in UTC (what the form's date picker
  /// stores). Null when malformed.
  static DateTime? parseLocalDate(String raw) {
    final RegExpMatch? m = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$')
        .firstMatch(raw.trim());
    if (m == null) return null;
    final int month = int.parse(m[2]!), day = int.parse(m[3]!);
    if (month < 1 || month > 12 || day < 1 || day > 31) return null;
    return _plainUtc(tz.TZDateTime(_riyadh, int.parse(m[1]!), month, day));
  }

  /// Same instant as a plain UTC [DateTime], like the rest of the app stores.
  static DateTime _plainUtc(DateTime t) => DateTime.fromMillisecondsSinceEpoch(
    t.millisecondsSinceEpoch,
    isUtc: true,
  );

  /// A listed insurer by exact name, or by a unique partial name ("التعاونية"
  /// → Tawuniya); anything else is kept as given.
  static String _insurer(String raw) {
    final Insurer? exact = Insurers.match(raw);
    if (exact != null) return exact.en;
    final List<String> partial = Insurers.namesContaining(raw);
    return partial.length == 1 ? partial.single : raw;
  }

  static String _local(DateTime utc) {
    final tz.TZDateTime l = TimeUtils.toRiyadh(utc);
    String two(int n) => n.toString().padLeft(2, '0');
    return '${l.year}-${two(l.month)}-${two(l.day)}T${two(l.hour)}:${two(l.minute)}';
  }

  static String _localDate(DateTime utc) => _local(utc).substring(0, 10);
}
