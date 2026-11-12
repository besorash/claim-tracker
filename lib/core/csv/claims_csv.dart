/// Claims spreadsheet (CSV) format — pure Dart, no database and no Flutter.
///
/// Export writes one row per claim using [kClaimsCsvColumns]. The `id` column
/// is the claim's identity on import: a row with an id updates that claim, a
/// row without one creates a new claim.
///
/// Parsing is strict on the header and lenient on empty rows. Every data row
/// is mapped into a [ClaimFormModel] and checked with the same validators as
/// the claim form, so a file can never store a claim the form would reject.
/// Nothing is written here — [ClaimsCsvService] does the database work once
/// the whole file has been accepted.
library;

import '../../features/claims/claim_form_model.dart';
import '../l10n/app_strings.dart';
import '../models/claim.dart';
import '../models/claim_status.dart';

/// Column order of the exported file. Import requires every one of these
/// headers; extra columns are ignored.
const List<String> kClaimsCsvColumns = <String>[
  'id',
  'customer_name',
  'customer_mobile',
  'customer_national_id',
  'customer_email',
  'accident_number',
  'accident_date',
  'accident_city',
  'accident_type',
  'vehicle_plate',
  'claim_number',
  'customer_insurance_company',
  'submission_date',
  'insurer_reference_number',
  'claim_amount_sar',
  'liability_percent',
  'notes',
  'status_key',
  'next_follow_up',
];

/// One data row of a parsed file.
class CsvRecord {
  const CsvRecord(this.line, this.values);

  /// 1-based row number in the file (the header is row 1).
  final int line;

  /// Cell values keyed by header name, trimmed by the caller when needed.
  final Map<String, String> values;
}

/// A parsed file: either a header problem (nothing else is read) or records.
class CsvDocument {
  const CsvDocument({this.headerError, this.records = const <CsvRecord>[]});

  /// Non-null when the file cannot be used at all (bad encoding, malformed
  /// quotes, or missing columns). Shown to the user as-is.
  final String? headerError;

  final List<CsvRecord> records;
}

/// Outcome of mapping one [CsvRecord] into claim form data.
class CsvRowResult {
  const CsvRowResult({this.id, this.model, this.errors = const <String>[]});

  /// The claim id from the file, or null for a new claim.
  final int? id;

  /// The validated form data. Non-null only when [errors] is empty.
  final ClaimFormModel? model;

  /// Human-readable problems, each prefixed with the row number.
  final List<String> errors;
}

abstract final class ClaimsCsv {
  // ---------------------------------------------------------------------------
  // Export
  // ---------------------------------------------------------------------------

  /// Serializes [claims] as CSV text (CRLF line endings, RFC 4180 quoting).
  static String encode(List<Claim> claims) {
    final StringBuffer out = StringBuffer()
      ..write(kClaimsCsvColumns.map(_cell).join(','))
      ..write('\r\n');
    for (final Claim claim in claims) {
      out
        ..write(_encodeClaim(claim).map(_cell).join(','))
        ..write('\r\n');
    }
    return out.toString();
  }

  static List<String> _encodeClaim(Claim c) => <String>[
    c.id.toString(),
    c.customerName,
    c.customerMobile,
    c.customerNationalId ?? '',
    c.customerEmail ?? '',
    c.accidentNumber ?? '',
    _formatDate(c.accidentDateUtcMs),
    c.accidentCity ?? '',
    c.accidentType ?? '',
    c.vehiclePlate ?? '',
    c.claimNumber,
    c.customerInsuranceCompany,
    _formatDate(c.submissionDateUtcMs),
    c.insurerReferenceNumber ?? '',
    c.claimAmountSar == null ? '' : _formatNumber(c.claimAmountSar!),
    c.liabilityPercent == null ? '' : c.liabilityPercent!.toStringAsFixed(0),
    c.notes ?? '',
    c.statusKey,
    c.nextFollowUpUtcMs == null ? '' : _formatDateTime(c.nextFollowUpUtcMs!),
  ];

  static String _cell(String value) {
    final bool needsQuotes =
        value.contains(',') ||
        value.contains('"') ||
        value.contains('\n') ||
        value.contains('\r');
    return needsQuotes ? '"${value.replaceAll('"', '""')}"' : value;
  }

  // ---------------------------------------------------------------------------
  // Parse
  // ---------------------------------------------------------------------------

  /// Parses [text] into a [CsvDocument]. Never throws.
  static CsvDocument parse(String text) {
    final List<_RawRow> rows;
    try {
      rows = _tokenize(text);
    } on FormatException {
      return CsvDocument(headerError: S.csvErrorMalformed);
    }
    if (rows.isEmpty) {
      return CsvDocument(headerError: S.csvErrorMalformed);
    }

    final List<String> header = rows.first.cells
        .map((String c) => c.trim())
        .toList(growable: false);
    final List<String> missing = kClaimsCsvColumns
        .where((String c) => !header.contains(c))
        .toList(growable: false);
    if (missing.isNotEmpty) {
      return CsvDocument(
        headerError: '${S.csvErrorMissingColumns} ${missing.join(', ')}',
      );
    }

    final Map<String, int> index = <String, int>{
      for (int i = 0; i < header.length; i++) header[i]: i,
    };
    final List<CsvRecord> records = <CsvRecord>[];
    for (final _RawRow row in rows.skip(1)) {
      final Map<String, String> values = <String, String>{
        for (final String column in kClaimsCsvColumns)
          column: index[column]! < row.cells.length
              ? row.cells[index[column]!]
              : '',
      };
      // A row where every known column is empty is treated as blank.
      if (values.values.every((String v) => v.trim().isEmpty)) continue;
      records.add(CsvRecord(row.row, values));
    }
    return CsvDocument(records: records);
  }

  /// Maps one record into form data and validates it with the form's rules.
  static CsvRowResult toForm(CsvRecord record) {
    final Map<String, String> v = record.values;
    final List<String> errors = <String>[];

    String text(String column) => (v[column] ?? '').trim();
    void fail(String column, String message) =>
        errors.add('${S.csvRowLabel} ${record.line} ($column): $message');

    int? id;
    final String rawId = text('id');
    if (rawId.isNotEmpty) {
      id = int.tryParse(rawId);
      if (id == null || id <= 0) fail('id', S.csvErrorBadId);
    }

    final ClaimFormModel m = ClaimFormModel()
      ..customerName = text('customer_name')
      ..customerMobile = text('customer_mobile')
      ..customerNationalId = text('customer_national_id')
      ..customerEmail = text('customer_email')
      ..accidentNumber = text('accident_number')
      ..accidentCity = text('accident_city')
      ..accidentType = text('accident_type')
      ..vehiclePlate = text('vehicle_plate')
      ..claimNumber = text('claim_number')
      ..customerInsuranceCompany = text('customer_insurance_company')
      ..insurerReferenceNumber = text('insurer_reference_number')
      ..claimAmount = text('claim_amount_sar')
      ..notes = text('notes');

    final String amount = text('claim_amount_sar');
    if (amount.isNotEmpty &&
        double.tryParse(amount.replaceAll(',', '.')) == null) {
      fail('claim_amount_sar', S.csvErrorAmount);
    }

    final String liability = text('liability_percent').replaceAll('%', '');
    if (liability.isNotEmpty) {
      final double? share = double.tryParse(liability);
      if (share == null || !ClaimFormModel.liabilityOptions.contains(share)) {
        fail('liability_percent', S.csvErrorLiability);
      } else {
        m.liabilityPercent = share;
      }
    }

    final String status = text('status_key').isEmpty
        ? ClaimStatus.defaultKey
        : text('status_key');
    if (ClaimStatus.all.any((ClaimStatusMeta s) => s.key == status)) {
      m.statusKey = status;
    } else {
      fail('status_key', S.csvErrorStatus);
    }

    m.accidentDateUtcMs = _parseDate(text('accident_date'));
    if (text('accident_date').isNotEmpty && m.accidentDateUtcMs == null) {
      fail('accident_date', S.csvErrorDate);
    }
    m.submissionDateUtcMs = _parseDate(text('submission_date'));
    if (text('submission_date').isNotEmpty && m.submissionDateUtcMs == null) {
      fail('submission_date', S.csvErrorDate);
    }
    final String followUp = text('next_follow_up');
    if (followUp.isNotEmpty) {
      m.nextFollowUpUtcMs = _parseDate(followUp, defaultHour: 9);
      if (m.nextFollowUpUtcMs == null) fail('next_follow_up', S.csvErrorDate);
    }

    // The same required-field rules as the claim form.
    final String? nameError = m.validateCustomerName();
    if (nameError != null) fail('customer_name', nameError);
    final String? mobileError = m.validateMobile();
    if (mobileError != null) fail('customer_mobile', mobileError);
    final String? claimError = m.validateClaimNumber();
    if (claimError != null) fail('claim_number', claimError);
    final String? insurerError = m.validateCustomerInsurer();
    if (insurerError != null) fail('customer_insurance_company', insurerError);
    if (m.accidentDateUtcMs == null && text('accident_date').isEmpty) {
      fail('accident_date', S.requiredField);
    }
    if (m.submissionDateUtcMs == null && text('submission_date').isEmpty) {
      fail('submission_date', S.requiredField);
    }

    return CsvRowResult(
      id: id,
      model: errors.isEmpty ? m : null,
      errors: errors,
    );
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  /// Splits [input] into rows of cells (RFC 4180): quoted fields may contain
  /// commas, quotes (doubled) and line breaks. Accepts LF, CRLF and a UTF-8
  /// BOM. Throws [FormatException] on an unterminated quoted field.
  static List<_RawRow> _tokenize(String input) {
    final String text = input.startsWith('﻿') ? input.substring(1) : input;
    final List<_RawRow> rows = <_RawRow>[];
    List<String> cells = <String>[];
    final StringBuffer field = StringBuffer();
    bool quoted = false;
    int row = 1;

    void endField() {
      cells.add(field.toString());
      field.clear();
    }

    void endRow() {
      endField();
      final bool blank = cells.length == 1 && cells.first.trim().isEmpty;
      if (!blank) rows.add(_RawRow(row, cells));
      cells = <String>[];
      row++;
    }

    int i = 0;
    while (i < text.length) {
      final String ch = text[i];
      if (quoted) {
        if (ch == '"') {
          if (i + 1 < text.length && text[i + 1] == '"') {
            field.write('"');
            i++;
          } else {
            quoted = false;
          }
        } else {
          field.write(ch);
        }
      } else if (ch == '"') {
        quoted = true;
      } else if (ch == ',') {
        endField();
      } else if (ch == '\r' || ch == '\n') {
        if (ch == '\r' && i + 1 < text.length && text[i + 1] == '\n') i++;
        endRow();
      } else {
        field.write(ch);
      }
      i++;
    }
    if (quoted) throw const FormatException('unterminated quoted field');
    if (field.isNotEmpty || cells.isNotEmpty) endRow();
    return rows;
  }

  /// Parses `yyyy-MM-dd` (local midnight, or [defaultHour] when no time is
  /// given) or `yyyy-MM-dd HH:mm`. Returns UTC, or null when invalid.
  static DateTime? _parseDate(String raw, {int defaultHour = 0}) {
    final RegExpMatch? m = RegExp(
      r'^(\d{4})-(\d{1,2})-(\d{1,2})(?:[ T](\d{1,2}):(\d{2}))?$',
    ).firstMatch(raw.trim());
    if (m == null) return null;
    final int year = int.parse(m.group(1)!);
    final int month = int.parse(m.group(2)!);
    final int day = int.parse(m.group(3)!);
    final int hour = m.group(4) == null ? defaultHour : int.parse(m.group(4)!);
    final int minute = m.group(5) == null ? 0 : int.parse(m.group(5)!);
    if (hour > 23 || minute > 59) return null;
    final DateTime local = DateTime(year, month, day, hour, minute);
    if (local.year != year || local.month != month || local.day != day) {
      return null; // e.g. 2026-02-31 would silently roll over
    }
    return local.toUtc();
  }

  static String _formatDate(DateTime utc) {
    final DateTime l = utc.toLocal();
    return '${_pad(l.year, 4)}-${_pad(l.month, 2)}-${_pad(l.day, 2)}';
  }

  static String _formatDateTime(DateTime utc) {
    final DateTime l = utc.toLocal();
    return '${_formatDate(utc)} ${_pad(l.hour, 2)}:${_pad(l.minute, 2)}';
  }

  static String _pad(int value, int width) =>
      value.toString().padLeft(width, '0');

  static String _formatNumber(double value) => value == value.roundToDouble()
      ? value.toStringAsFixed(0)
      : value.toString();
}

class _RawRow {
  const _RawRow(this.row, this.cells);

  final int row;
  final List<String> cells;
}
