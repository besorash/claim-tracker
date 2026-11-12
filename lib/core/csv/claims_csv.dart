/// Claims spreadsheet (CSV) format — pure Dart, no database and no Flutter.
///
/// Export writes one row per claim using [kClaimsCsvColumns], followed by one
/// column per user-defined extra field. The `id` column is the claim's
/// identity on import: a row with an id updates that claim, a row without one
/// creates a new claim.
///
/// Import is forgiving about what spreadsheet apps (Excel, WPS, Google Sheets)
/// do to a file when it is edited and saved again:
///  * the separator may be `,`, `;` or a tab;
///  * headers may be the column keys or the field names shown in the app, in
///    English or Arabic, in any order;
///  * dates may be `2026-11-04`, `2026/11/04`, `11/4/2026` or `4/11/2026`
///    (the day/month order is worked out for the whole file);
///  * columns the app does not know become extra fields of the claim;
///  * optional columns may be left out.
///
/// Every data row is mapped into a [ClaimFormModel] and checked with the same
/// validators as the claim form, so a file can never store a claim the form
/// would reject. Nothing is written here — [ClaimsCsvService] does the
/// database work once the whole file has been accepted.
library;

import '../../features/claims/claim_form_model.dart';
import '../../l10n/app_localizations.dart';
import '../../l10n/app_localizations_ar.dart';
import '../../l10n/app_localizations_en.dart';
import '../l10n/app_strings.dart';
import '../models/claim.dart';
import '../models/claim_status.dart';

/// Column order of the exported file.
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

/// Columns an import must contain. The others are optional: when one is left
/// out, new claims get it empty and existing claims keep their stored value.
const List<String> kRequiredCsvColumns = <String>[
  'customer_name',
  'customer_mobile',
  'accident_date',
  'claim_number',
  'customer_insurance_company',
  'submission_date',
];

const List<String> _dateColumns = <String>[
  'accident_date',
  'submission_date',
  'next_follow_up',
];

/// One data row of a parsed file.
class CsvRecord {
  const CsvRecord(
    this.line,
    this.values, {
    this.extras = const <String, String>{},
  });

  /// 1-based row number in the file (the header is row 1).
  final int line;

  /// Cell values of the known columns present in the file, keyed by
  /// [kClaimsCsvColumns] name.
  final Map<String, String> values;

  /// Cell values of the extra (user-defined) columns, keyed by the header as
  /// written in the file. Empty cells are included as empty strings.
  final Map<String, String> extras;
}

/// Day/month order of slash dates such as `11/4/2026` in one file.
enum CsvDateOrder {
  /// `11/4/2026` is 4 November (Excel/WPS in English).
  monthFirst,

  /// `11/4/2026` is 11 April (Excel in Arabic or British English).
  dayFirst,
}

/// A parsed file: either a header problem (nothing else is read) or records.
class CsvDocument {
  const CsvDocument({
    this.headerError,
    this.records = const <CsvRecord>[],
    this.presentColumns = const <String>{},
    this.extraColumns = const <String>[],
    this.dateOrder = CsvDateOrder.monthFirst,
    this.dateOrderAssumed = false,
  });

  /// Non-null when the file cannot be used at all (bad encoding, malformed
  /// quotes, or missing required columns). Shown to the user as-is.
  final String? headerError;

  final List<CsvRecord> records;

  /// Known columns that appear in the header.
  final Set<String> presentColumns;

  /// Extra column headers, in file order.
  final List<String> extraColumns;

  /// How slash dates in this file are read.
  final CsvDateOrder dateOrder;

  /// True when the file has slash dates that fit both orders (every day and
  /// month is 12 or less), so [dateOrder] is the month-first default.
  final bool dateOrderAssumed;
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
  /// Extra fields become extra columns after the standard ones.
  static String encode(List<Claim> claims) {
    final List<String> extraColumns = <String>[];
    for (final Claim claim in claims) {
      for (final String key in claim.extraFields.keys) {
        if (!extraColumns.contains(key)) extraColumns.add(key);
      }
    }
    final StringBuffer out = StringBuffer()
      ..write(
        <String>[...kClaimsCsvColumns, ...extraColumns].map(_cell).join(','),
      )
      ..write('\r\n');
    for (final Claim claim in claims) {
      final Map<String, String> v = valuesOf(claim);
      final List<String> cells = <String>[
        for (final String column in kClaimsCsvColumns) v[column]!,
        for (final String column in extraColumns)
          claim.extraFields[column] ?? '',
      ];
      out
        ..write(cells.map(_cell).join(','))
        ..write('\r\n');
    }
    return out.toString();
  }

  /// The exported cell value of every known column for [c].
  static Map<String, String> valuesOf(Claim c) => <String, String>{
    'id': c.id.toString(),
    'customer_name': c.customerName,
    'customer_mobile': c.customerMobile,
    'customer_national_id': c.customerNationalId ?? '',
    'customer_email': c.customerEmail ?? '',
    'accident_number': c.accidentNumber ?? '',
    'accident_date': _formatDate(c.accidentDateUtcMs),
    'accident_city': c.accidentCity ?? '',
    'accident_type': c.accidentType ?? '',
    'vehicle_plate': c.vehiclePlate ?? '',
    'claim_number': c.claimNumber,
    'customer_insurance_company': c.customerInsuranceCompany,
    'submission_date': _formatDate(c.submissionDateUtcMs),
    'insurer_reference_number': c.insurerReferenceNumber ?? '',
    'claim_amount_sar': c.claimAmountSar == null
        ? ''
        : _formatNumber(c.claimAmountSar!),
    'liability_percent': c.liabilityPercent == null
        ? ''
        : c.liabilityPercent!.toStringAsFixed(0),
    'notes': c.notes ?? '',
    'status_key': c.statusKey,
    'next_follow_up': c.nextFollowUpUtcMs == null
        ? ''
        : _formatDateTime(c.nextFollowUpUtcMs!),
  };

  static String _cell(String value) {
    final bool needsQuotes =
        value.contains(',') ||
        value.contains(';') ||
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
    final String body = text.startsWith('\uFEFF') ? text.substring(1) : text;
    final List<_RawRow> rows;
    try {
      rows = _tokenize(body, _detectDelimiter(body));
    } on FormatException {
      return CsvDocument(headerError: S.csvErrorMalformed);
    }
    if (rows.isEmpty) {
      return CsvDocument(headerError: S.csvErrorMalformed);
    }

    // Map each header cell to a known column, an extra column, or nothing
    // (blank headers — spreadsheet apps often leave trailing empty columns).
    final Map<String, String> aliases = _headerAliases();
    final Map<String, int> known = <String, int>{};
    final Map<String, int> extra = <String, int>{};
    final List<String> header = rows.first.cells;
    for (int i = 0; i < header.length; i++) {
      final String name = _cleanHeader(header[i]);
      if (name.isEmpty) continue;
      final String? column = aliases[_normalize(name)];
      if (column != null && !known.containsKey(column)) {
        known[column] = i;
      } else if (!extra.containsKey(name)) {
        extra[name] = i;
      }
    }
    final List<String> missing = kRequiredCsvColumns
        .where((String c) => !known.containsKey(c))
        .toList(growable: false);
    if (missing.isNotEmpty) {
      return CsvDocument(
        headerError: '${S.csvErrorMissingColumns} ${missing.join(', ')}',
      );
    }

    String cellAt(_RawRow row, int index) =>
        index < row.cells.length ? row.cells[index] : '';

    final List<CsvRecord> records = <CsvRecord>[];
    for (final _RawRow row in rows.skip(1)) {
      final Map<String, String> values = <String, String>{
        for (final MapEntry<String, int> e in known.entries)
          e.key: cellAt(row, e.value),
      };
      final Map<String, String> extras = <String, String>{
        for (final MapEntry<String, int> e in extra.entries)
          e.key: cellAt(row, e.value).trim(),
      };
      // A row where every cell is empty is treated as blank.
      if (values.values.every((String v) => v.trim().isEmpty) &&
          extras.values.every((String v) => v.isEmpty)) {
        continue;
      }
      records.add(CsvRecord(row.row, values, extras: extras));
    }

    final (CsvDateOrder order, bool assumed) = _detectDateOrder(records);
    return CsvDocument(
      records: records,
      presentColumns: known.keys.toSet(),
      extraColumns: extra.keys.toList(growable: false),
      dateOrder: order,
      dateOrderAssumed: assumed,
    );
  }

  /// The claim id of [record], or null when the cell is empty or invalid
  /// ([toForm] reports the invalid case).
  static int? idOf(CsvRecord record) {
    final String raw = _western((record.values['id'] ?? '').trim());
    final int? id = int.tryParse(raw);
    return id == null || id <= 0 ? null : id;
  }

  /// Maps one record into form data and validates it with the form's rules.
  static CsvRowResult toForm(
    CsvRecord record, {
    CsvDateOrder dateOrder = CsvDateOrder.monthFirst,
  }) {
    final Map<String, String> v = record.values;
    final List<String> errors = <String>[];

    String text(String column) => (v[column] ?? '').trim();
    String number(String column) => _western(text(column));
    void fail(String column, String message) =>
        errors.add('${S.csvRowLabel} ${record.line} ($column): $message');

    int? id;
    final String rawId = number('id');
    if (rawId.isNotEmpty) {
      id = int.tryParse(rawId);
      if (id == null || id <= 0) fail('id', S.csvErrorBadId);
    }

    final ClaimFormModel m = ClaimFormModel()
      ..customerName = text('customer_name')
      ..customerMobile = _mobile(number('customer_mobile'))
      ..customerNationalId = number('customer_national_id')
      ..customerEmail = text('customer_email')
      ..accidentNumber = text('accident_number')
      ..accidentCity = text('accident_city')
      ..accidentType = text('accident_type')
      ..vehiclePlate = text('vehicle_plate')
      ..claimNumber = text('claim_number')
      ..customerInsuranceCompany = text('customer_insurance_company')
      ..insurerReferenceNumber = text('insurer_reference_number')
      ..notes = text('notes');

    final String amount = _amount(number('claim_amount_sar'));
    if (amount.isNotEmpty && double.tryParse(amount) == null) {
      fail('claim_amount_sar', S.csvErrorAmount);
    } else {
      m.claimAmount = amount;
    }

    final String liability = number('liability_percent').replaceAll('%', '');
    if (liability.trim().isNotEmpty) {
      final double? share = double.tryParse(liability.trim());
      if (share == null || !ClaimFormModel.liabilityOptions.contains(share)) {
        fail('liability_percent', S.csvErrorLiability);
      } else {
        m.liabilityPercent = share;
      }
    }

    final String? status = text('status_key').isEmpty
        ? ClaimStatus.defaultKey
        : _statusKey(text('status_key'));
    if (status != null) {
      m.statusKey = status;
    } else {
      fail('status_key', S.csvErrorStatus);
    }

    DateTime? date(String column, {int defaultHour = 0}) {
      final String raw = number(column);
      if (raw.isEmpty) return null;
      final DateTime? parsed = _parseDate(
        raw,
        order: dateOrder,
        defaultHour: defaultHour,
      );
      if (parsed == null) fail(column, S.csvErrorDate);
      return parsed;
    }

    m.accidentDateUtcMs = date('accident_date');
    m.submissionDateUtcMs = date('submission_date');
    m.nextFollowUpUtcMs = date('next_follow_up', defaultHour: 9);

    // The same required-field rules as the claim form.
    final String? nameError = m.validateCustomerName();
    if (nameError != null) fail('customer_name', nameError);
    final String? mobileError = m.validateMobile();
    if (mobileError != null) fail('customer_mobile', mobileError);
    final String? claimError = m.validateClaimNumber();
    if (claimError != null) fail('claim_number', claimError);
    final String? insurerError = m.validateCustomerInsurer();
    if (insurerError != null) fail('customer_insurance_company', insurerError);
    if (text('accident_date').isEmpty) {
      fail('accident_date', S.requiredField);
    }
    if (text('submission_date').isEmpty) {
      fail('submission_date', S.requiredField);
    }

    return CsvRowResult(
      id: id,
      model: errors.isEmpty ? m : null,
      errors: errors,
    );
  }

  // ---------------------------------------------------------------------------
  // Headers and values
  // ---------------------------------------------------------------------------

  /// Normalized header text → column key: the keys themselves plus the field
  /// names the app shows in English and Arabic.
  static Map<String, String> _headerAliases() {
    final Map<String, String> map = <String, String>{};
    void add(String alias, String column) =>
        map.putIfAbsent(_normalize(alias), () => column);

    for (final String column in kClaimsCsvColumns) {
      add(column, column);
    }
    for (final AppLocalizations l in <AppLocalizations>[
      AppLocalizationsEn(),
      AppLocalizationsAr(),
    ]) {
      add(l.customerNameLabel, 'customer_name');
      add(l.mobileLabel, 'customer_mobile');
      add(l.nationalIdLabel, 'customer_national_id');
      add(l.emailLabel, 'customer_email');
      add(l.accidentNumberLabel, 'accident_number');
      add(l.accidentDateLabel, 'accident_date');
      add(l.cityLabel, 'accident_city');
      add(l.accidentTypeLabel, 'accident_type');
      add(l.vehiclePlateLabel, 'vehicle_plate');
      add(l.claimNumberLabel, 'claim_number');
      add(l.customerInsurerLabel, 'customer_insurance_company');
      add(l.submissionDateLabel, 'submission_date');
      add(l.insurerRefLabel, 'insurer_reference_number');
      add(l.claimAmountLabel, 'claim_amount_sar');
      add(l.liabilityPercentLabel, 'liability_percent');
      add(l.notesLabel, 'notes');
      add(l.statusLabel, 'status_key');
      add(l.nextFollowUpLabel, 'next_follow_up');
    }
    add('status', 'status_key');
    add('الحالة', 'status_key');
    add('amount', 'claim_amount_sar');
    return map;
  }

  /// A status cell: the key, or the status name in English or Arabic.
  static String? _statusKey(String raw) {
    final String wanted = _normalize(raw);
    for (final ClaimStatusMeta s in ClaimStatus.all) {
      if (_normalize(s.key) == wanted) return s.key;
      for (final AppLocalizations l in <AppLocalizations>[
        AppLocalizationsEn(),
        AppLocalizationsAr(),
      ]) {
        if (_normalize(_statusLabel(l, s.key)) == wanted) return s.key;
      }
    }
    return null;
  }

  static String _statusLabel(AppLocalizations l, String key) => switch (key) {
    'new' => l.statusNew,
    'submitted' => l.statusSubmitted,
    'awaiting_review' => l.statusAwaitingReview,
    'awaiting_documents' => l.statusAwaitingDocuments,
    'processing' => l.statusProcessing,
    'awaiting_approval' => l.statusAwaitingApproval,
    'approved' => l.statusApproved,
    'compensated' => l.statusCompensated,
    'rejected' => l.statusRejected,
    'closed' => l.statusClosed,
    _ => key,
  };

  /// Header as written, without invisible marks spreadsheet apps add.
  static String _cleanHeader(String raw) =>
      raw.replaceAll(RegExp('[\uFEFF\u200B-\u200F\u202A-\u202E]'), '').trim();

  /// Case-, space- and punctuation-insensitive form used to match headers and
  /// status names (`Customer Name`, `customer_name`, `CUSTOMER-NAME`).
  static String _normalize(String raw) =>
      _cleanHeader(raw)
          .toLowerCase()
          .replaceAll(RegExp(r'[\s_\-:*()]+'), ' ')
          .trim();

  /// Arabic-Indic and Persian digits → ASCII digits; Arabic decimal and
  /// thousands separators → `.` and `,`.
  static String _western(String raw) {
    final StringBuffer out = StringBuffer();
    for (final int c in raw.runes) {
      if (c >= 0x0660 && c <= 0x0669) {
        out.writeCharCode(0x30 + c - 0x0660);
      } else if (c >= 0x06F0 && c <= 0x06F9) {
        out.writeCharCode(0x30 + c - 0x06F0);
      } else if (c == 0x066B) {
        out.write('.');
      } else if (c == 0x066C) {
        out.write(',');
      } else {
        out.writeCharCode(c);
      }
    }
    return out.toString();
  }

  /// Puts back what a spreadsheet strips from a number cell: the leading `0`
  /// (`569896589` → `0569896589`) or the `+` (`966569896589`).
  static String _mobile(String raw) {
    if (RegExp(r'^5\d{8}$').hasMatch(raw)) return '0$raw';
    if (RegExp(r'^966\d{9}$').hasMatch(raw)) return '+$raw';
    return raw;
  }

  /// Amount cell → plain decimal text. Drops currency marks and spaces and
  /// tells a thousands comma (`1,500`) from a decimal comma (`1500,5`).
  static String _amount(String raw) {
    String s = raw
        .replaceAll(RegExp(r'SAR|ر\.س|ريال|﷼', caseSensitive: false), '')
        .replaceAll(RegExp(r'[\s\u00A0]'), '');
    if (s.contains(',') && s.contains('.')) {
      s = s.replaceAll(',', '');
    } else if (RegExp(r'^-?\d{1,3}(,\d{3})+$').hasMatch(s)) {
      s = s.replaceAll(',', '');
    } else {
      s = s.replaceAll(',', '.');
    }
    return s;
  }

  // ---------------------------------------------------------------------------
  // Dates
  // ---------------------------------------------------------------------------

  static final RegExp _yearFirst = RegExp(
    r'^(\d{4})[-/.](\d{1,2})[-/.](\d{1,2})(?:[ T]+(.+))?$',
  );
  static final RegExp _yearLast = RegExp(
    r'^(\d{1,2})[-/.](\d{1,2})[-/.](\d{4})(?:[ T]+(.+))?$',
  );
  static final RegExp _time = RegExp(
    r'^(\d{1,2}):(\d{2})(?::\d{2}(?:\.\d+)?)?\s*(am|pm|a\.m\.|p\.m\.|ص|م)?$',
    caseSensitive: false,
  );

  /// Works out the day/month order of `a/b/yyyy` dates from the whole file:
  /// a first part above 12 means day first, a second part above 12 means
  /// month first. With no such hint, month first is assumed (what Excel and
  /// WPS write in English) and the caller tells the user.
  static (CsvDateOrder, bool) _detectDateOrder(List<CsvRecord> records) {
    bool dayFirst = false;
    bool monthFirst = false;
    bool any = false;
    for (final CsvRecord r in records) {
      for (final String column in _dateColumns) {
        final RegExpMatch? m = _yearLast.firstMatch(
          _western((r.values[column] ?? '').trim()),
        );
        if (m == null) continue;
        any = true;
        if (int.parse(m.group(1)!) > 12) dayFirst = true;
        if (int.parse(m.group(2)!) > 12) monthFirst = true;
      }
    }
    if (dayFirst && !monthFirst) return (CsvDateOrder.dayFirst, false);
    return (CsvDateOrder.monthFirst, any && !monthFirst && !dayFirst);
  }

  /// Parses a date with an optional time (`14:30`, `2:30 PM`). Without a
  /// time, [defaultHour] local time is used. Returns UTC, or null when the
  /// text is not a real date.
  static DateTime? _parseDate(
    String raw, {
    required CsvDateOrder order,
    int defaultHour = 0,
  }) {
    final String s = raw.trim();
    int year;
    int month;
    int day;
    String? timeText;
    RegExpMatch? m = _yearFirst.firstMatch(s);
    if (m != null) {
      year = int.parse(m.group(1)!);
      month = int.parse(m.group(2)!);
      day = int.parse(m.group(3)!);
      timeText = m.group(4);
    } else {
      m = _yearLast.firstMatch(s);
      if (m == null) return null;
      final int a = int.parse(m.group(1)!);
      final int b = int.parse(m.group(2)!);
      year = int.parse(m.group(3)!);
      (month, day) = order == CsvDateOrder.dayFirst ? (b, a) : (a, b);
      timeText = m.group(4);
    }

    int hour = defaultHour;
    int minute = 0;
    if (timeText != null) {
      final RegExpMatch? t = _time.firstMatch(timeText.trim());
      if (t == null) return null;
      hour = int.parse(t.group(1)!);
      minute = int.parse(t.group(2)!);
      final String? half = t.group(3)?.toLowerCase();
      if (half != null) {
        if (hour < 1 || hour > 12) return null;
        final bool pm = half.startsWith('p') || half == 'م';
        hour = hour % 12 + (pm ? 12 : 0);
      }
    }
    if (month < 1 || month > 12 || day < 1 || hour > 23 || minute > 59) {
      return null;
    }
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

  // ---------------------------------------------------------------------------
  // Tokenizer
  // ---------------------------------------------------------------------------

  /// Picks the separator used in the header line: `,`, `;` (Excel with an
  /// Arabic or European list separator) or a tab.
  static String _detectDelimiter(String text) {
    final Map<String, int> counts = <String, int>{',': 0, ';': 0, '\t': 0};
    bool quoted = false;
    for (int i = 0; i < text.length; i++) {
      final String ch = text[i];
      if (ch == '"') {
        quoted = !quoted;
      } else if (!quoted && (ch == '\n' || ch == '\r')) {
        break;
      } else if (!quoted && counts.containsKey(ch)) {
        counts[ch] = counts[ch]! + 1;
      }
    }
    String best = ',';
    for (final String d in <String>[';', '\t']) {
      if (counts[d]! > counts[best]!) best = d;
    }
    return best;
  }

  /// Splits [text] into rows of cells (RFC 4180): quoted fields may contain
  /// the separator, quotes (doubled) and line breaks. Accepts LF and CRLF.
  /// Throws [FormatException] on an unterminated quoted field.
  static List<_RawRow> _tokenize(String text, String delimiter) {
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
      // Rows of empty cells (`,,,,`) are what spreadsheets leave below data.
      if (cells.any((String c) => c.trim().isNotEmpty)) {
        rows.add(_RawRow(row, cells));
      }
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
      } else if (ch == delimiter) {
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
}

class _RawRow {
  const _RawRow(this.row, this.cells);

  final int row;
  final List<String> cells;
}
