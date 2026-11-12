/// Claim form model (spec §7) — pure Dart, no Flutter imports.
///
/// Editable strings + `DateTime?` for dates; per-field validators return the
/// Arabic message to show (`S.*`) or null when valid. The screen keeps all
/// input intact on a failed save and re-runs these same validators (Review
/// Focus #1: never lose typed data).
library;

import '../../core/l10n/app_strings.dart';
import '../../core/models/claim.dart';
import '../../core/models/claim_status.dart';

class ClaimFormModel {
  // Customer (spec §7.1) — name and mobile are required.
  String customerName = '';
  String customerMobile = '';
  String customerNationalId = '';
  String customerEmail = '';

  // Accident (spec §7.2) — date is required, the rest optional.
  DateTime? accidentDateUtcMs;
  String accidentNumber = '';
  String accidentCity = '';
  String accidentType = '';
  String vehiclePlate = '';

  // Claim (spec §7.3) — number, both insurers and submission date are required.
  String claimNumber = '';
  String customerInsuranceCompany = '';
  double? liabilityPercent; // null = not set; otherwise 0, 50 or 100
  DateTime? submissionDateUtcMs;
  String insurerReferenceNumber = '';
  String claimAmount = ''; // editable string; parsed to SAR double on save
  String notes = '';

  /// Extra spreadsheet columns (see [Claim.extraFields]). Not shown in the
  /// form; carried through edits so saving the form never drops them.
  Map<String, String> extraFields = <String, String>{};

  // Follow-up (spec §7.4) — status defaults to `new`; follow-up optional.
  String statusKey = ClaimStatus.defaultKey;
  DateTime? nextFollowUpUtcMs;

  /// Populates every field from an existing claim (edit mode).
  void loadFrom(Claim claim) {
    customerName = claim.customerName;
    customerMobile = claim.customerMobile;
    customerNationalId = claim.customerNationalId ?? '';
    customerEmail = claim.customerEmail ?? '';
    accidentDateUtcMs = claim.accidentDateUtcMs;
    accidentNumber = claim.accidentNumber ?? '';
    accidentCity = claim.accidentCity ?? '';
    accidentType = claim.accidentType ?? '';
    vehiclePlate = claim.vehiclePlate ?? '';
    claimNumber = claim.claimNumber;
    customerInsuranceCompany = claim.customerInsuranceCompany;
    liabilityPercent = claim.liabilityPercent;
    submissionDateUtcMs = claim.submissionDateUtcMs;
    insurerReferenceNumber = claim.insurerReferenceNumber ?? '';
    claimAmount = claim.claimAmountSar?.toString() ?? '';
    notes = claim.notes ?? '';
    extraFields = Map<String, String>.of(claim.extraFields);
    statusKey = claim.statusKey;
    nextFollowUpUtcMs = claim.nextFollowUpUtcMs;
  }

  // ---------------------------------------------------------------------------
  // Validation (spec §7) — separate methods so the UI can show per-field errors.
  // ---------------------------------------------------------------------------

  String? _required(String value) =>
      value.trim().isEmpty ? S.requiredField : null;

  String? validateCustomerName() => _required(customerName);

  String? validateClaimNumber() => _required(claimNumber);

  String? validateCustomerInsurer() => _required(customerInsuranceCompany);

  /// Liability percentage is optional; when set it must be one of the
  /// allowed shares.
  static const List<double> liabilityOptions = <double>[0, 50, 100];

  /// Canonical Saudi mobile: strip spaces/dashes/parens, a leading `+966` or
  /// `00966`, then one leading `0`; the result must be exactly 9 digits.
  static String normalizeMobile(String raw) {
    var s = raw.replaceAll(RegExp(r'[\s\-()]'), '');
    if (s.startsWith('+966')) {
      s = s.substring(4);
    } else if (s.startsWith('00966')) {
      s = s.substring(5);
    }
    if (s.startsWith('0')) {
      s = s.substring(1);
    }
    return s;
  }

  String? validateMobile() {
    final String raw = customerMobile.trim();
    if (raw.isEmpty) return S.requiredField;
    if (!RegExp(r'^\d{9}$').hasMatch(normalizeMobile(raw))) {
      return S.invalidNumber;
    }
    return null;
  }

  /// All required validators pass AND both dates are set.
  bool get isValid =>
      validateCustomerName() == null &&
      validateMobile() == null &&
      validateClaimNumber() == null &&
      validateCustomerInsurer() == null &&
      accidentDateUtcMs != null &&
      submissionDateUtcMs != null;

  // ---------------------------------------------------------------------------
  // Claim construction (spec §7) — the screen never touches the repository.
  // ---------------------------------------------------------------------------

  /// Builds a [Claim] from the current field values with the given identity.
  /// Only call when [isValid] is true (dates are then guaranteed non-null).
  Claim toClaim({required int id, required DateTime createdAtUtcMs}) {
    return Claim(
      id: id,
      customerName: customerName.trim(),
      customerMobile: customerMobile.trim(),
      customerNationalId: _opt(customerNationalId),
      customerEmail: _opt(customerEmail),
      accidentNumber: _opt(accidentNumber),
      accidentDateUtcMs: accidentDateUtcMs!,
      accidentCity: _opt(accidentCity),
      accidentType: _opt(accidentType),
      vehiclePlate: _opt(vehiclePlate),
      claimNumber: claimNumber.trim(),
      customerInsuranceCompany: customerInsuranceCompany.trim(),
      liabilityPercent: liabilityPercent,
      submissionDateUtcMs: submissionDateUtcMs!,
      insurerReferenceNumber: _opt(insurerReferenceNumber),
      claimAmountSar: _parseAmount(claimAmount),
      notes: _opt(notes),
      extraFields: Map<String, String>.unmodifiable(extraFields),
      statusKey: statusKey,
      lastStatusUpdateUtcMs: createdAtUtcMs,
      nextFollowUpUtcMs: nextFollowUpUtcMs,
      reminderEnabled: false, // reminders are Phase 3 — never faked here
      createdAtUtcMs: createdAtUtcMs,
      updatedAtUtcMs: createdAtUtcMs,
    );
  }

  /// Add mode: a brand-new claim (id assigned by the repository on create).
  Claim buildNew(DateTime nowUtc) => toClaim(id: 0, createdAtUtcMs: nowUtc);

  /// Edit mode: preserves [existing]'s id/createdAt and reminder flag; bumps
  /// `updatedAtUtcMs` to [nowUtc]; refreshes `lastStatusUpdateUtcMs` only when
  /// the status actually changed (no history writes — that is Phase 3).
  Claim applyTo(Claim existing, DateTime nowUtc) {
    final Claim base = toClaim(
      id: existing.id,
      createdAtUtcMs: existing.createdAtUtcMs,
    );
    return base.copyWith(
      updatedAtUtcMs: nowUtc,
      lastStatusUpdateUtcMs: statusKey == existing.statusKey
          ? existing.lastStatusUpdateUtcMs
          : nowUtc,
      reminderEnabled: existing.reminderEnabled,
    );
  }

  String? _opt(String value) {
    final String trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  double? _parseAmount(String raw) {
    final String cleaned = raw.trim().replaceAll(',', '.');
    if (cleaned.isEmpty) return null;
    return double.tryParse(cleaned);
  }
}
