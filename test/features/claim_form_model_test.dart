/// ClaimFormModel tests (spec §7): pure-Dart validation, mobile normalization,
/// and buildNew/applyTo semantics. No Flutter widget involvement.
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:claim_tracker/core/l10n/app_strings.dart';
import 'package:claim_tracker/features/claims/claim_form_model.dart';

ClaimFormModel _validModel() => ClaimFormModel()
  ..customerName = 'خالد'
  ..customerMobile = '0559876543'
  ..claimNumber = 'CLM-1'
  ..customerInsuranceCompany = 'تعاونية'
  ..liabilityPercent = 50
  ..accidentDateUtcMs = DateTime.utc(2026, 10, 1)
  ..submissionDateUtcMs = DateTime.utc(2026, 10, 5);

void main() {
  group('required-field validation', () {
    test('all required fields blank → each validator returns S.requiredField; '
        'isValid is false', () {
      final ClaimFormModel m = ClaimFormModel();
      expect(m.validateCustomerName(), S.requiredField);
      expect(m.validateMobile(), S.requiredField);
      expect(m.validateClaimNumber(), S.requiredField);
      expect(m.validateCustomerInsurer(), S.requiredField);
      expect(m.isValid, isFalse);
    });

    test('whitespace-only name is still required', () {
      final ClaimFormModel m = ClaimFormModel()..customerName = '   ';
      expect(m.validateCustomerName(), S.requiredField);
    });

    test('all required fields filled → every validator null; isValid true', () {
      final ClaimFormModel m = _validModel();
      expect(m.validateCustomerName(), isNull);
      expect(m.validateMobile(), isNull);
      expect(m.validateClaimNumber(), isNull);
      expect(m.validateCustomerInsurer(), isNull);
      expect(m.isValid, isTrue);
    });

    test('missing a date keeps isValid false even when text fields pass', () {
      final ClaimFormModel m = _validModel()..submissionDateUtcMs = null;
      expect(m.isValid, isFalse);
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

    test('blank mobile is required, not invalid-number', () {
      final ClaimFormModel m = ClaimFormModel();
      expect(m.validateMobile(), S.requiredField);
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
