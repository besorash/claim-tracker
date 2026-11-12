/// Claims CSV codec tests (spreadsheet format): export → parse round trip,
/// quoting, the header contract, and row-level validation. Pure Dart.
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:claim_tracker/core/csv/claims_csv.dart';
import 'package:claim_tracker/core/l10n/app_strings.dart';
import 'package:claim_tracker/core/models/claim.dart';

Claim _claim({
  int id = 7,
  String name = 'خالد',
  String? notes,
  double? liability = 50,
  String status = 'submitted',
  DateTime? followUp,
}) {
  final DateTime t = DateTime.utc(2026, 9, 1, 8);
  return Claim(
    id: id,
    customerName: name,
    customerMobile: '0559876543',
    accidentDateUtcMs: DateTime(2026, 10, 1).toUtc(),
    claimNumber: 'CLM-7',
    customerInsuranceCompany: 'تعاونية',
    submissionDateUtcMs: DateTime(2026, 10, 5).toUtc(),
    claimAmountSar: 1500.5,
    liabilityPercent: liability,
    notes: notes,
    statusKey: status,
    lastStatusUpdateUtcMs: t,
    nextFollowUpUtcMs: followUp,
    createdAtUtcMs: t,
    updatedAtUtcMs: t,
  );
}

CsvRecord _firstRecord(String csv) {
  final CsvDocument doc = ClaimsCsv.parse(csv);
  expect(doc.headerError, isNull);
  expect(doc.records, isNotEmpty);
  return doc.records.first;
}

void main() {
  group('export → parse round trip', () {
    test('every field survives, including commas, quotes and new lines', () {
      final DateTime followUp = DateTime(2026, 11, 20, 14, 30).toUtc();
      final Claim original = _claim(
        name: 'خالد، "الأول"',
        notes: 'سطر أول\nسطر ثاني',
        followUp: followUp,
      );

      final String csv = ClaimsCsv.encode(<Claim>[original]);
      final CsvRowResult row = ClaimsCsv.toForm(_firstRecord(csv));

      expect(row.errors, isEmpty);
      expect(row.id, 7);
      final model = row.model!;
      expect(model.customerName, 'خالد، "الأول"');
      expect(model.notes, 'سطر أول\nسطر ثاني');
      expect(model.accidentDateUtcMs, original.accidentDateUtcMs);
      expect(model.submissionDateUtcMs, original.submissionDateUtcMs);
      expect(model.claimAmount, '1500.5');
      expect(model.liabilityPercent, 50);
      expect(model.statusKey, 'submitted');
      expect(model.nextFollowUpUtcMs, followUp);
    });

    test('an empty liability share stays empty, not zero', () {
      final String csv = ClaimsCsv.encode(<Claim>[_claim(liability: null)]);
      final CsvRowResult row = ClaimsCsv.toForm(_firstRecord(csv));
      expect(row.errors, isEmpty);
      expect(row.model!.liabilityPercent, isNull);
    });

    test('the file starts with the header in the documented order', () {
      final String csv = ClaimsCsv.encode(<Claim>[_claim()]);
      expect(csv.split('\r\n').first, kClaimsCsvColumns.join(','));
    });
  });

  group('parsing', () {
    test('a UTF-8 BOM is accepted', () {
      final String csv = '﻿${ClaimsCsv.encode(<Claim>[_claim()])}';
      expect(ClaimsCsv.parse(csv).headerError, isNull);
    });

    test('blank lines are skipped', () {
      final String csv =
          '${ClaimsCsv.encode(<Claim>[_claim()])}\r\n\r\n,,,,\r\n';
      expect(ClaimsCsv.parse(csv).records, hasLength(1));
    });

    test('a missing column is a header error that names it', () {
      final String csv = ClaimsCsv.encode(<Claim>[_claim()])
          .replaceFirst(',liability_percent', '');
      final CsvDocument doc = ClaimsCsv.parse(csv);
      expect(doc.headerError, contains('liability_percent'));
      expect(doc.records, isEmpty);
    });

    test('an unterminated quote is reported as a readable header error', () {
      final CsvDocument doc = ClaimsCsv.parse('id,customer_name\n"abc');
      expect(doc.headerError, S.csvErrorMalformed);
    });

    test('an empty file is reported as a readable header error', () {
      expect(ClaimsCsv.parse('').headerError, S.csvErrorMalformed);
    });
  });

  group('row validation (same rules as the claim form)', () {
    String rowWith(Map<String, String> overrides) {
      final String base = ClaimsCsv.encode(<Claim>[_claim()]);
      final List<String> lines = base.split('\r\n');
      final List<String> header = lines.first.split(',');
      final List<String> cells = lines[1].split(',');
      overrides.forEach((String key, String value) {
        cells[header.indexOf(key)] = value;
      });
      return '${lines.first}\r\n${cells.join(',')}\r\n';
    }

    test('a valid row produces no errors and no id error', () {
      final CsvRowResult row = ClaimsCsv.toForm(
        _firstRecord(rowWith(<String, String>{})),
      );
      expect(row.errors, isEmpty);
      expect(row.model, isNotNull);
    });

    test('liability must be one of 0, 50 or 100', () {
      final CsvRowResult row = ClaimsCsv.toForm(
        _firstRecord(rowWith(<String, String>{'liability_percent': '75'})),
      );
      expect(row.model, isNull);
      expect(row.errors.single, contains(S.csvErrorLiability));
      expect(row.errors.single, contains('liability_percent'));
    });

    test('0 is a valid liability share', () {
      final CsvRowResult row = ClaimsCsv.toForm(
        _firstRecord(rowWith(<String, String>{'liability_percent': '0'})),
      );
      expect(row.errors, isEmpty);
      expect(row.model!.liabilityPercent, 0);
    });

    test('an impossible date such as 2026-02-31 is rejected', () {
      final CsvRowResult row = ClaimsCsv.toForm(
        _firstRecord(rowWith(<String, String>{'accident_date': '2026-02-31'})),
      );
      expect(row.errors.single, contains(S.csvErrorDate));
    });

    test('an unknown status key is rejected', () {
      final CsvRowResult row = ClaimsCsv.toForm(
        _firstRecord(rowWith(<String, String>{'status_key': 'nope'})),
      );
      expect(row.errors.single, contains(S.csvErrorStatus));
    });

    test('a required field left empty is rejected', () {
      final CsvRowResult row = ClaimsCsv.toForm(
        _firstRecord(rowWith(<String, String>{'customer_name': ''})),
      );
      expect(row.model, isNull);
      expect(row.errors.single, contains('customer_name'));
    });

    test('a non-numeric id is rejected', () {
      final CsvRowResult row = ClaimsCsv.toForm(
        _firstRecord(rowWith(<String, String>{'id': 'abc'})),
      );
      expect(row.errors.single, contains(S.csvErrorBadId));
    });

    test('an empty id means a new claim', () {
      final CsvRowResult row = ClaimsCsv.toForm(
        _firstRecord(rowWith(<String, String>{'id': ''})),
      );
      expect(row.errors, isEmpty);
      expect(row.id, isNull);
    });
  });
}
