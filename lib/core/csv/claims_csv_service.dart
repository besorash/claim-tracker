/// Spreadsheet export and import against the live database (CSV, see
/// [ClaimsCsv] for the format).
///
/// Import runs in two phases:
///  1. Read and validate EVERY row (form rules, known ids, no duplicate ids).
///     If anything fails, nothing is written and all problems are reported.
///  2. Apply the rows: create new claims, update existing ones. Status changes
///     go through [StatusHistoryRepository] so the timeline stays complete, and
///     follow-up changes go through [ClaimActions] so alarms stay in sync.
library;

import 'dart:convert';
import 'dart:typed_data';

import '../../features/claims/claim_actions.dart';
import '../../features/claims/claim_form_model.dart';
import '../database/app_database.dart';
import '../database/claims_repository.dart';
import '../database/status_history_repository.dart';
import '../l10n/app_strings.dart';
import '../models/claim.dart';
import '../notifications/reminder_scheduler.dart';
import 'claims_csv.dart';

/// Result of an import. [hasErrors] means nothing was written.
class CsvImportReport {
  const CsvImportReport({
    this.created = 0,
    this.updated = 0,
    this.unchanged = 0,
    this.reminderFailures = 0,
    this.errors = const <String>[],
    this.databaseError = false,
    this.unknownIdsAdded = 0,
    this.extraColumns = const <String>[],
    this.dateOrderAssumed = false,
  });

  /// Rows whose id the app does not have; they were created as new claims
  /// (and are included in [created]).
  final int unknownIdsAdded;

  final int created;
  final int updated;

  /// Rows that matched an existing claim exactly — nothing was written.
  final int unchanged;

  /// Follow-ups saved but whose OS alarm could not be scheduled (future dates
  /// only — past dates are saved without an alarm on purpose).
  final int reminderFailures;

  /// Validation problems. When non-empty, nothing was written.
  final List<String> errors;

  /// Set when the apply phase failed midway; earlier rows may be saved.
  final bool databaseError;

  /// Headers of the file's extra columns, saved as extra fields.
  final List<String> extraColumns;

  /// Slash dates fitted both day/month orders and were read month first.
  final bool dateOrderAssumed;

  bool get hasErrors => errors.isNotEmpty || databaseError;

  /// True when the file had no data rows at all.
  bool get isEmpty => !hasErrors && created + updated + unchanged == 0;
}

class ClaimsCsvService {
  ClaimsCsvService(this.db, this.scheduler);

  final AppDatabase db;
  final ReminderScheduler scheduler;

  ClaimsRepository get _claims => ClaimsRepository(db);
  ClaimActions get _actions => ClaimActions(db, scheduler);

  /// The whole claims table as a CSV file: UTF-8 with a BOM so Excel shows
  /// Arabic correctly.
  Future<Uint8List> buildExport() async {
    final List<Claim> all = await _claims.all();
    final List<int> body = utf8.encode(ClaimsCsv.encode(all));
    return Uint8List.fromList(<int>[0xEF, 0xBB, 0xBF, ...body]);
  }

  /// Imports CSV [text]. Validates the whole file before writing anything.
  Future<CsvImportReport> importText(String text) async {
    final CsvDocument doc = ClaimsCsv.parse(text);
    if (doc.headerError != null) {
      return CsvImportReport(errors: <String>[doc.headerError!]);
    }

    // Phase 1 — validate everything, write nothing.
    final List<String> errors = <String>[];
    final Set<int> seenIds = <int>{};
    int unknownIds = 0;
    final List<_PlannedRow> plan = <_PlannedRow>[];
    for (final CsvRecord record in doc.records) {
      // Existing claim first: columns left out of the file keep its values.
      final int? id = ClaimsCsv.idOf(record);
      final Claim? existing = id == null ? null : await db.claimById(id);
      final CsvRecord full = existing == null
          ? record
          : CsvRecord(record.line, <String, String>{
              ...ClaimsCsv.valuesOf(existing),
              ...record.values,
            }, extras: record.extras);

      final CsvRowResult row = ClaimsCsv.toForm(full, dateOrder: doc.dateOrder);
      if (row.errors.isNotEmpty || row.model == null) {
        errors.addAll(row.errors);
        continue;
      }
      if (row.id != null) {
        if (!seenIds.add(row.id!)) {
          errors.add(
            '${S.csvRowLabel} ${record.line} (id): ${S.csvErrorDuplicateId}',
          );
          continue;
        }
        // An id the app does not have (claim deleted, or the file comes from
        // another device or an older backup) is added as a new claim.
        if (existing == null) unknownIds++;
      }
      final ClaimFormModel model = row.model!
        ..extraFields = _mergeExtras(existing, record.extras);
      if (existing != null) _keepStoredForms(model, existing);
      plan.add(_PlannedRow(model, existing));
    }
    if (errors.isNotEmpty) {
      return CsvImportReport(errors: errors);
    }

    // Phase 2 — apply.
    final DateTime now = DateTime.now().toUtc();
    int created = 0;
    int updated = 0;
    int unchanged = 0;
    int reminderFailures = 0;
    try {
      for (final _PlannedRow item in plan) {
        if (item.existing == null) {
          final bool failed = await _createClaim(item.model, now);
          created++;
          if (failed) reminderFailures++;
        } else {
          final _UpdateOutcome outcome = await _updateClaim(
            item.model,
            item.existing!,
            now,
          );
          if (outcome == _UpdateOutcome.unchanged) {
            unchanged++;
          } else {
            updated++;
          }
          if (outcome == _UpdateOutcome.reminderFailed) reminderFailures++;
        }
      }
    } on Object catch (_) {
      return CsvImportReport(
        created: created,
        updated: updated,
        unchanged: unchanged,
        reminderFailures: reminderFailures,
        databaseError: true,
      );
    }
    return CsvImportReport(
      created: created,
      updated: updated,
      unchanged: unchanged,
      reminderFailures: reminderFailures,
      unknownIdsAdded: unknownIds,
      extraColumns: doc.extraColumns,
      dateOrderAssumed: doc.dateOrderAssumed,
    );
  }

  /// A spreadsheet rewrites values without changing them (`0569896589` →
  /// `569896589`, a stored date → that day at midnight). Keep the stored
  /// form when the meaning is the same, so such rows count as unchanged.
  static void _keepStoredForms(ClaimFormModel model, Claim existing) {
    if (ClaimFormModel.normalizeMobile(model.customerMobile) ==
        ClaimFormModel.normalizeMobile(existing.customerMobile)) {
      model.customerMobile = existing.customerMobile;
    }
    if (_sameLocalDay(model.accidentDateUtcMs, existing.accidentDateUtcMs)) {
      model.accidentDateUtcMs = existing.accidentDateUtcMs;
    }
    if (_sameLocalDay(
      model.submissionDateUtcMs,
      existing.submissionDateUtcMs,
    )) {
      model.submissionDateUtcMs = existing.submissionDateUtcMs;
    }
  }

  static bool _sameLocalDay(DateTime? a, DateTime b) {
    if (a == null) return false;
    final DateTime x = a.toLocal();
    final DateTime y = b.toLocal();
    return x.year == y.year && x.month == y.month && x.day == y.day;
  }

  /// Extra fields after the import: a filled cell sets the field, an empty
  /// cell removes it, and fields whose column is not in the file are kept.
  static Map<String, String> _mergeExtras(
    Claim? existing,
    Map<String, String> fromFile,
  ) {
    final Map<String, String> merged = <String, String>{
      ...?existing?.extraFields,
    };
    fromFile.forEach((String key, String value) {
      if (value.isEmpty) {
        merged.remove(key);
      } else {
        merged[key] = value;
      }
    });
    return merged;
  }

  /// Creates a claim from [model]. Returns true when a future follow-up could
  /// not be scheduled as an OS alarm.
  Future<bool> _createClaim(ClaimFormModel model, DateTime now) async {
    final DateTime? followUp = model.nextFollowUpUtcMs;
    model.nextFollowUpUtcMs = null; // set through ClaimActions below
    final int id = await _claims.create(model.buildNew(now));
    if (followUp == null) return false;
    return _applyFollowUp(id, followUp, now);
  }

  /// Updates an existing claim from [model]. Writes nothing when the row
  /// matches the stored claim.
  Future<_UpdateOutcome> _updateClaim(
    ClaimFormModel model,
    Claim existing,
    DateTime now,
  ) async {
    final DateTime? wanted = model.nextFollowUpUtcMs;
    final bool followUpUnchanged = _sameMinute(
      wanted,
      existing.nextFollowUpUtcMs,
    );

    // Keep the stored follow-up for the row write; it is reconciled below.
    model.nextFollowUpUtcMs = existing.nextFollowUpUtcMs;
    final Claim target = model.applyTo(existing, now);
    if (followUpUnchanged && _sameContent(target, existing)) {
      return _UpdateOutcome.unchanged;
    }

    if (target.statusKey != existing.statusKey) {
      await StatusHistoryRepository(db).changeStatus(
        claimId: existing.id,
        newStatusKey: target.statusKey,
        changedAtUtc: now,
      );
    }
    await _claims.update(target);

    if (followUpUnchanged) return _UpdateOutcome.updated;
    if (wanted == null) {
      await _actions.clearFollowUp(existing.id);
      return _UpdateOutcome.updated;
    }
    return await _applyFollowUp(existing.id, wanted, now)
        ? _UpdateOutcome.reminderFailed
        : _UpdateOutcome.updated;
  }

  /// Same stored values, ignoring the bookkeeping timestamps.
  static bool _sameContent(Claim a, Claim b) {
    final Map<String, Object?> x = a.toRow();
    final Map<String, Object?> y = b.toRow();
    for (final String key in x.keys) {
      if (key == 'updated_at_utc_ms' || key == 'last_status_update_utc_ms') {
        continue;
      }
      if (x[key] != y[key]) return false;
    }
    return true;
  }

  /// Sets a follow-up through [ClaimActions]. Schedules an alarm only for
  /// future times; returns true when a future alarm could not be scheduled.
  Future<bool> _applyFollowUp(
    int claimId,
    DateTime fireAtUtc,
    DateTime now,
  ) async {
    final bool future = fireAtUtc.isAfter(now);
    final ScheduleResult result = await _actions.saveReminder(
      claimId: claimId,
      fireAtUtc: fireAtUtc,
      schedule: future,
    );
    return future && !result.scheduled;
  }

  /// Follow-ups are exported to the minute, so compare to the minute and keep
  /// the stored value when they match.
  static bool _sameMinute(DateTime? a, DateTime? b) {
    if (a == null || b == null) return a == b;
    return a.millisecondsSinceEpoch ~/ 60000 ==
        b.millisecondsSinceEpoch ~/ 60000;
  }
}

class _PlannedRow {
  const _PlannedRow(this.model, this.existing);

  final ClaimFormModel model;
  final Claim? existing;
}

enum _UpdateOutcome { updated, unchanged, reminderFailed }
