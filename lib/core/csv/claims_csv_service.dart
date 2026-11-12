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
    this.reminderFailures = 0,
    this.errors = const <String>[],
    this.databaseError = false,
  });

  final int created;
  final int updated;

  /// Follow-ups saved but whose OS alarm could not be scheduled (future dates
  /// only — past dates are saved without an alarm on purpose).
  final int reminderFailures;

  /// Validation problems. When non-empty, nothing was written.
  final List<String> errors;

  /// Set when the apply phase failed midway; earlier rows may be saved.
  final bool databaseError;

  bool get hasErrors => errors.isNotEmpty || databaseError;
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
    final List<_PlannedRow> plan = <_PlannedRow>[];
    for (final CsvRecord record in doc.records) {
      final CsvRowResult row = ClaimsCsv.toForm(record);
      if (row.errors.isNotEmpty || row.model == null) {
        errors.addAll(row.errors);
        continue;
      }
      Claim? existing;
      if (row.id != null) {
        if (!seenIds.add(row.id!)) {
          errors.add(
            '${S.csvRowLabel} ${record.line} (id): ${S.csvErrorDuplicateId}',
          );
          continue;
        }
        existing = await db.claimById(row.id!);
        if (existing == null) {
          errors.add(
            '${S.csvRowLabel} ${record.line} (id): ${S.csvErrorUnknownId}',
          );
          continue;
        }
      }
      plan.add(_PlannedRow(row.model!, existing));
    }
    if (errors.isNotEmpty) {
      return CsvImportReport(errors: errors);
    }

    // Phase 2 — apply.
    final DateTime now = DateTime.now().toUtc();
    int created = 0;
    int updated = 0;
    int reminderFailures = 0;
    try {
      for (final _PlannedRow item in plan) {
        if (item.existing == null) {
          final bool failed = await _createClaim(item.model, now);
          created++;
          if (failed) reminderFailures++;
        } else {
          final bool failed = await _updateClaim(
            item.model,
            item.existing!,
            now,
          );
          updated++;
          if (failed) reminderFailures++;
        }
      }
    } on Object catch (_) {
      return CsvImportReport(
        created: created,
        updated: updated,
        reminderFailures: reminderFailures,
        databaseError: true,
      );
    }
    return CsvImportReport(
      created: created,
      updated: updated,
      reminderFailures: reminderFailures,
    );
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

  /// Updates an existing claim from [model]. Returns true when a future
  /// follow-up could not be scheduled.
  Future<bool> _updateClaim(
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

    if (target.statusKey != existing.statusKey) {
      await StatusHistoryRepository(db).changeStatus(
        claimId: existing.id,
        newStatusKey: target.statusKey,
        changedAtUtc: now,
      );
    }
    await _claims.update(target);

    if (followUpUnchanged) return false;
    if (wanted == null) {
      await _actions.clearFollowUp(existing.id);
      return false;
    }
    return _applyFollowUp(existing.id, wanted, now);
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
