/// ClaimFormModel tests (spec §7): pure-Dart validation, mobile normalization,
/// and buildNew/applyTo semantics. No Flutter widget involvement.
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:claim_tracker/core/l10n/app_strings.dart';
import 'package:claim_tracker/features/claims/claim_form_model.dart';

/// A typical filled-in claim (only plate and accident date are required).
ClaimFormModel _validModel() => ClaimFormModel()
  ..vehiclePlate = '4051 VJD'
  ..accidentDateUtcMs = DateTime.utc(2026, 10, 1)
  ..vehicleType = 'Camry 2022'
  ..customerName = 'خالد'
  ..customerInsuranceCompany = 'GIG'
  ..liabilityPercent = 50;

void main() {
  group('required-field validation', () {
    test('only plate and accident date are required', () {
      final ClaimFormModel m = ClaimFormModel();
      expect(m.validateVehiclePlate(), S.requiredField);
      expect(m.isValid, isFalse);

      // Plate + accident date alone: valid, with no name, type or insurer.
      final ClaimFormModel minimal = ClaimFormModel()
        ..vehiclePlate = '4051 VJD'
        ..accidentDateUtcMs = DateTime.utc(2026, 10, 1);
      expect(minimal.isValid, isTrue);
      final claim = minimal.buildNew(DateTime.utc(2026, 10, 2));
      expect(claim.customerName, isEmpty);
      expect(claim.customerInsuranceCompany, isEmpty);
      expect(claim.vehicleType, isNull);
    });

    test('whitespace-only plate is still required', () {
      final ClaimFormModel m = ClaimFormModel()..vehiclePlate = '   ';
      expect(m.validateVehiclePlate(), S.requiredField);
    });

    test('all fields filled → valid', () {
      final ClaimFormModel m = _validModel();
      expect(m.validateVehiclePlate(), isNull);
      expect(m.isValid, isTrue);
    });

    test('loss type round-trips through the claim', () {
      final ClaimFormModel m = _validModel()..lossType = 'total';
      final claim = m.toClaim(id: 1, createdAtUtcMs: DateTime.utc(2026));
      expect(claim.lossType, 'total');
      expect((ClaimFormModel()..loadFrom(claim)).lossType, 'total');
    });

    test('mobile, claim number and submission date are optional', () {
      final ClaimFormModel m = _validModel();
      expect(m.customerMobile, isEmpty);
      expect(m.claimNumber, isEmpty);
      expect(m.submissionDateUtcMs, isNull);
      expect(m.isValid, isTrue);
      final claim = m.toClaim(id: 1, createdAtUtcMs: DateTime.utc(2026));
      expect(claim.submissionDateUtcMs, isNull);
      expect(claim.claimNumberDisplay, '—');
    });

    test('missing the accident date keeps isValid false', () {
      final ClaimFormModel m = _validModel()..accidentDateUtcMs = null;
      expect(m.isValid, isFalse);
    });

    test('plate blocks saving; name, vehicle type and insurer do not', () {
      expect((_validModel()..vehiclePlate = '').isValid, isFalse);
      expect((_validModel()..vehicleType = ' ').isValid, isTrue);
      expect((_validModel()..customerName = '').isValid, isTrue);
      expect((_validModel()..customerInsuranceCompany = '').isValid, isTrue);
    });
  });

  group('mobile normalization (spec §7.1)', () {
    test('"abc" → S.invalidNumber', () {
      final ClaimFormModel m = ClaimFormModel()..customerMobile = 'abc';
      expect(m.validateMobile(), S.invalidNumber);
    });

    test('"0559876543" (leading 0) is valid', () {
      final ClaimFormModel m = ClaimFormModel()..customerMobile = '0559876543';
      expect(m.validateMobile(), isNull);
    });

    test('"+966 55 987 6543" normalizes to a valid 9-digit number', () {
      final ClaimFormModel m = ClaimFormModel()
        ..customerMobile = '+966 55 987 6543';
      expect(m.validateMobile(), isNull);
    });

    test(
      '"0551234" (fewer than 9 digits after normalization) → S.invalidNumber',
      () {
        final ClaimFormModel m = ClaimFormModel()..customerMobile = '0551234';
        expect(m.validateMobile(), S.invalidNumber);
      },
    );

    test('blank mobile is allowed (optional)', () {
      final ClaimFormModel m = ClaimFormModel();
      expect(m.validateMobile(), isNull);
    });
  });

  group('insurance company mobile (spec §7.3)', () {
    test('blank is allowed (optional) and does not block saving', () {
      final ClaimFormModel m = _validModel();
      expect(m.validateInsuranceMobile(), isNull);
      expect(m.isValid, isTrue);
    });

    test('"abc" → S.invalidNumber and blocks saving', () {
      final ClaimFormModel m = _validModel()..insuranceMobile = 'abc';
      expect(m.validateInsuranceMobile(), S.invalidNumber);
      expect(m.isValid, isFalse);
    });

    test('"0559876543" (leading 0) and "+966 55 987 6543" are valid', () {
      final ClaimFormModel a = _validModel()..insuranceMobile = '0559876543';
      expect(a.validateInsuranceMobile(), isNull);
      final ClaimFormModel b = _validModel()
        ..insuranceMobile = '+966 55 987 6543';
      expect(b.validateInsuranceMobile(), isNull);
    });

    test('toClaim trims the value; an empty one stays null', () {
      final DateTime t0 = DateTime.utc(2026, 1, 1);
      final ClaimFormModel m = _validModel()..insuranceMobile = ' 0559876543 ';
      expect(
        m.toClaim(id: 1, createdAtUtcMs: t0).insuranceMobile,
        '0559876543',
      );
      final ClaimFormModel empty = _validModel();
      expect(empty.toClaim(id: 1, createdAtUtcMs: t0).insuranceMobile, isNull);
    });
  });

  group('buildNew / applyTo (spec §7)', () {
    test(
      'toClaim receives the provided id and createdAt; fields are trimmed',
      () {
        final ClaimFormModel m = _validModel()..customerName = '  خالد  ';
        final DateTime t0 = DateTime.utc(2026, 1, 1);

        final claim = m.toClaim(id: 42, createdAtUtcMs: t0);

        expect(claim.id, 42);
        expect(claim.createdAtUtcMs, t0);
        expect(claim.customerName, 'خالد');
        expect(claim.statusKey, isNotEmpty);
      },
    );

    test('liability percent is optional and carried into the claim', () {
      final ClaimFormModel unset = _validModel()..liabilityPercent = null;
      final DateTime t0 = DateTime.utc(2026, 1, 1);
      expect(unset.toClaim(id: 1, createdAtUtcMs: t0).liabilityPercent, isNull);

      final ClaimFormModel full = _validModel()..liabilityPercent = 100;
      expect(full.toClaim(id: 1, createdAtUtcMs: t0).liabilityPercent, 100);
    });

    test('applyTo preserves id and createdAt but bumps updatedAt', () {
      final ClaimFormModel m = _validModel();
      final DateTime created = DateTime.utc(2026, 1, 1);
      final DateTime later = DateTime.utc(2026, 6, 15);

      final existing = m.toClaim(id: 7, createdAtUtcMs: created);
      final updated = m.applyTo(existing, later);

      expect(updated.id, 7);
      expect(updated.createdAtUtcMs, created);
      expect(updated.updatedAtUtcMs, later);
    });

    test('applyTo keeps the existing reminder flag (Phase 3 groundwork)', () {
      final ClaimFormModel m = _validModel();
      final DateTime created = DateTime.utc(2026, 1, 1);
      final DateTime later = DateTime.utc(2026, 6, 15);

      final existing = m
          .toClaim(id: 7, createdAtUtcMs: created)
          .copyWith(reminderEnabled: true);
      final updated = m.applyTo(existing, later);

      expect(updated.reminderEnabled, isTrue);
    });
  });
}
