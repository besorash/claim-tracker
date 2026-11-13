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
  String? insuranceMobile,
}) {
  final DateTime t = DateTime.utc(2026, 9, 1, 8);
  return Claim(
    id: id,
    customerName: name,
    customerMobile: '0559876543',
    insuranceMobile: insuranceMobile,
    vehiclePlate: '4051 VJD',
    vehicleType: 'Camry 2022',
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

    test('the insurer mobile survives export → import', () {
      final String csv = ClaimsCsv.encode(
        <Claim>[_claim(insuranceMobile: '0561234567')],
      );
      expect(csv.split('\r\n').first, contains('insurance_mobile'));
      final CsvRowResult row = ClaimsCsv.toForm(_firstRecord(csv));
      expect(row.errors, isEmpty);
      expect(row.model!.insuranceMobile, '0561234567');
    });

    test('an empty insurer mobile stays absent on import', () {
      final String csv = ClaimsCsv.encode(<Claim>[_claim()]);
      final CsvRowResult row = ClaimsCsv.toForm(_firstRecord(csv));
      expect(row.errors, isEmpty);
      expect(row.model!.insuranceMobile, isEmpty);
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

    test('a missing required column is a header error that names it', () {
      final String csv = ClaimsCsv.encode(<Claim>[_claim()])
          .replaceFirst(',vehicle_type', '');
      final CsvDocument doc = ClaimsCsv.parse(csv);
      expect(doc.headerError, contains('vehicle_type'));
      expect(doc.records, isEmpty);
    });

    test('a missing optional column is allowed', () {
      final String csv = ClaimsCsv.encode(<Claim>[_claim()])
          .replaceFirst(',liability_percent', '');
      final CsvDocument doc = ClaimsCsv.parse(csv);
      expect(doc.headerError, isNull);
      expect(doc.presentColumns, isNot(contains('liability_percent')));
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

    test('liability must be one of 0, 25, 50, 75 or 100', () {
      final CsvRowResult row = ClaimsCsv.toForm(
        _firstRecord(rowWith(<String, String>{'liability_percent': '30'})),
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

    test('plate and vehicle type are required; claim number is not', () {
      final CsvRowResult noPlate = ClaimsCsv.toForm(
        _firstRecord(rowWith(<String, String>{'vehicle_plate': ''})),
      );
      expect(noPlate.errors.single, contains('vehicle_plate'));
      final CsvRowResult noType = ClaimsCsv.toForm(
        _firstRecord(rowWith(<String, String>{'vehicle_type': ''})),
      );
      expect(noType.errors.single, contains('vehicle_type'));
      final CsvRowResult optional = ClaimsCsv.toForm(
        _firstRecord(
          rowWith(<String, String>{
            'claim_number': '',
            'customer_mobile': '',
            'submission_date': '',
          }),
        ),
      );
      expect(optional.errors, isEmpty);
      expect(optional.model!.submissionDateUtcMs, isNull);
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

    test('an invalid insurer mobile is a row error', () {
      final CsvRowResult row = ClaimsCsv.toForm(
        _firstRecord(rowWith(<String, String>{'insurance_mobile': 'abc'})),
      );
      expect(row.errors.single, contains('insurance_mobile'));
    });

    test('a valid insurer mobile passes the same Saudi rules', () {
      final CsvRowResult row = ClaimsCsv.toForm(
        _firstRecord(
          rowWith(<String, String>{'insurance_mobile': '0561234567'}),
        ),
      );
      expect(row.errors, isEmpty);
      expect(row.model!.insuranceMobile, '0561234567');
    });
  });

  group('files edited in Excel / WPS', () {
    const String required =
        'vehicle_plate,vehicle_type,customer_name,customer_mobile,'
        'accident_date,claim_number,customer_insurance_company,'
        'submission_date';

    CsvDocument parseOk(String csv) {
      final CsvDocument doc = ClaimsCsv.parse(csv);
      expect(doc.headerError, isNull);
      return doc;
    }

    test('semicolon-separated files are read', () {
      final CsvDocument doc = parseOk(
        '${required.replaceAll(',', ';')}\r\n'
        '1234 ABC;Camry;سعد;0567897654;2026-11-05;CLM-1;GIG;2026-11-13\r\n',
      );
      final CsvRowResult row = ClaimsCsv.toForm(doc.records.single);
      expect(row.errors, isEmpty);
      expect(row.model!.claimNumber, 'CLM-1');
    });

    test('headers may be the Arabic field names, in any order', () {
      final CsvDocument doc = parseOk(
        'رقم اللوحة,نوع المركبة,رقم المطالبة,اسم العميل,رقم الجوال,'
        'شركة تأمين العميل,تاريخ الحادث,تاريخ تقديم المطالبة,الحالة\r\n'
        '1234 ABC,Camry,CLM-2,سعد,0567897654,GIG,2026-11-05,2026-11-13,'
        'approved\r\n',
      );
      final CsvRowResult row = ClaimsCsv.toForm(doc.records.single);
      expect(row.errors, isEmpty);
      expect(row.model!.customerName, 'سعد');
      expect(row.model!.statusKey, 'approved');
    });

    test('status may be written as its English or Arabic name', () {
      for (final String name in <String>['Approved', 'APPROVED']) {
        final CsvDocument doc = parseOk(
          '$required,status_key\r\n'
          '1234 ABC,Camry,سعد,0567897654,2026-11-05,CLM-1,GIG,2026-11-13,$name\r\n',
        );
        expect(
          ClaimsCsv.toForm(doc.records.single).model!.statusKey,
          'approved',
        );
      }
    });

    test('common status wordings map to app statuses', () {
      const Map<String, String> cases = <String, String>{
        'missing docs.': 'awaiting_documents',
        'Missing Documents': 'awaiting_documents',
        'invoice payment': 'processing',
      };
      cases.forEach((String cell, String key) {
        final CsvDocument doc = parseOk(
          '$required,status_key\r\n'
          '1234 ABC,Camry,سعد,0567897654,2026-11-05,CLM-1,GIG,2026-11-13,$cell\r\n',
        );
        expect(
          ClaimsCsv.toForm(doc.records.single).model?.statusKey,
          key,
          reason: cell,
        );
      });
    });

    test('an unknown status error names the value', () {
      final CsvDocument doc = parseOk(
        '$required,status_key\r\n'
        '1234 ABC,Camry,سعد,0567897654,2026-11-05,CLM-1,GIG,2026-11-13,on hold\r\n',
      );
      expect(
        ClaimsCsv.toForm(doc.records.single).errors.single,
        contains('"on hold"'),
      );
    });

    test('month-first slash dates (WPS) are read, and flagged as assumed', () {
      final CsvDocument doc = parseOk(
        '$required\r\n'
        '1234 ABC,Camry,سعد,567897654,11/5/2026,CLM-1,GIG,11/12/2026\r\n',
      );
      expect(doc.dateOrder, CsvDateOrder.monthFirst);
      expect(doc.dateOrderAssumed, isTrue);
      final CsvRowResult row = ClaimsCsv.toForm(
        doc.records.single,
        dateOrder: doc.dateOrder,
      );
      expect(row.errors, isEmpty);
      expect(row.model!.accidentDateUtcMs, DateTime(2026, 11, 5).toUtc());
      // The spreadsheet dropped the leading zero; it is put back.
      expect(row.model!.customerMobile, '0567897654');
    });

    test('a day above 12 anywhere in the file switches to day-first', () {
      final CsvDocument doc = parseOk(
        '$required\r\n'
        '1234 ABC,Camry,سعد,0567897654,4/11/2026,CLM-1,GIG,31/10/2026\r\n',
      );
      expect(doc.dateOrder, CsvDateOrder.dayFirst);
      expect(doc.dateOrderAssumed, isFalse);
      final CsvRowResult row = ClaimsCsv.toForm(
        doc.records.single,
        dateOrder: doc.dateOrder,
      );
      expect(row.model!.accidentDateUtcMs, DateTime(2026, 11, 4).toUtc());
    });

    test('Arabic digits, thousands commas and 12-hour times are read', () {
      final CsvDocument doc = parseOk(
        '$required,claim_amount_sar,next_follow_up\r\n'
        '1234 ABC,Camry,سعد,٠٥٦٧٨٩٧٦٥٤,2026/11/05,CLM-1,GIG,2026-11-13,"1,500",'
        '2026-11-20 2:30 PM\r\n',
      );
      final CsvRowResult row = ClaimsCsv.toForm(doc.records.single);
      expect(row.errors, isEmpty);
      expect(row.model!.customerMobile, '0567897654');
      expect(row.model!.claimAmount, '1500');
      expect(
        row.model!.nextFollowUpUtcMs,
        DateTime(2026, 11, 20, 14, 30).toUtc(),
      );
    });

    test('unknown columns become extra fields; blank headers are ignored', () {
      final CsvDocument doc = parseOk(
        '$required,اسم المندوب,,Car Model\r\n'
        '1234 ABC,Camry,سعد,0567897654,2026-11-05,CLM-1,GIG,2026-11-13,فهد,,Camry\r\n',
      );
      expect(doc.extraColumns, <String>['اسم المندوب', 'Car Model']);
      expect(doc.records.single.extras, <String, String>{
        'اسم المندوب': 'فهد',
        'Car Model': 'Camry',
      });
    });

    test('extra fields are exported as extra columns', () {
      final Claim c = _claim().copyWith(
        extraFields: <String, String>{'اسم المندوب': 'فهد'},
      );
      final List<String> lines = ClaimsCsv.encode(<Claim>[c]).split('\r\n');
      expect(lines.first, endsWith(',اسم المندوب'));
      expect(lines[1], endsWith(',فهد'));
    });
  });
}
