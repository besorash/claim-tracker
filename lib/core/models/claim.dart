/// Claim entity — customer, accident, claim and follow-up information
/// (spec §7). Timestamps are stored as UTC milliseconds since epoch.
library;

import 'dart:convert';

class Claim {
  const Claim({
    required this.id,
    required this.customerName,
    required this.customerMobile,
    this.customerNationalId,
    this.customerEmail,
    this.accidentNumber,
    required this.accidentDateUtcMs,
    this.accidentCity,
    this.accidentType,
    this.vehiclePlate,
    this.vehicleType,
    required this.claimNumber,
    required this.customerInsuranceCompany,
    this.liabilityPercent,
    required this.submissionDateUtcMs,
    this.insurerReferenceNumber,
    this.claimAmountSar,
    this.notes,
    this.extraFields = const <String, String>{},
    required this.statusKey,
    required this.lastStatusUpdateUtcMs,
    this.nextFollowUpUtcMs,
    this.reminderEnabled = false,
    required this.createdAtUtcMs,
    required this.updatedAtUtcMs,
  });

  final int id;

  // Customer (spec §7.1).
  final String customerName;
  final String customerMobile;
  final String? customerNationalId;
  final String? customerEmail;

  // Accident (spec §7.2).
  final String? accidentNumber;
  final DateTime accidentDateUtcMs;
  final String? accidentCity;
  final String? accidentType;
  final String? vehiclePlate;

  /// Vehicle make/model as typed, e.g. "Camry 2022".
  final String? vehicleType;

  // Claim (spec §7.3).
  final String claimNumber;
  final String customerInsuranceCompany;

  /// Liability share of the claim: 0, 50 or 100 (percent). Null = not set.
  final double? liabilityPercent;
  final DateTime submissionDateUtcMs;
  final String? insurerReferenceNumber;
  final double? claimAmountSar;
  final String? notes;

  /// User-defined fields that came in as extra spreadsheet columns, keyed by
  /// the column header. Stored as JSON; never null (empty = none).
  final Map<String, String> extraFields;

  // Follow-up (spec §7.4).
  /// One of [ClaimStatus.all] keys — see `claim_status.dart`.
  final String statusKey;
  final DateTime lastStatusUpdateUtcMs;
  final DateTime? nextFollowUpUtcMs;
  final bool reminderEnabled;

  final DateTime createdAtUtcMs;
  final DateTime updatedAtUtcMs;

  Claim copyWith({
    int? id,
    String? customerName,
    String? customerMobile,
    String? customerNationalId,
    String? customerEmail,
    String? accidentNumber,
    DateTime? accidentDateUtcMs,
    String? accidentCity,
    String? accidentType,
    String? vehiclePlate,
    String? vehicleType,
    String? claimNumber,
    String? customerInsuranceCompany,
    double? liabilityPercent,
    DateTime? submissionDateUtcMs,
    String? insurerReferenceNumber,
    double? claimAmountSar,
    String? notes,
    Map<String, String>? extraFields,
    String? statusKey,
    DateTime? lastStatusUpdateUtcMs,
    DateTime? nextFollowUpUtcMs,
    bool? reminderEnabled,
    DateTime? createdAtUtcMs,
    DateTime? updatedAtUtcMs,
  }) {
    return Claim(
      id: id ?? this.id,
      customerName: customerName ?? this.customerName,
      customerMobile: customerMobile ?? this.customerMobile,
      customerNationalId: customerNationalId ?? this.customerNationalId,
      customerEmail: customerEmail ?? this.customerEmail,
      accidentNumber: accidentNumber ?? this.accidentNumber,
      accidentDateUtcMs: accidentDateUtcMs ?? this.accidentDateUtcMs,
      accidentCity: accidentCity ?? this.accidentCity,
      accidentType: accidentType ?? this.accidentType,
      vehiclePlate: vehiclePlate ?? this.vehiclePlate,
      vehicleType: vehicleType ?? this.vehicleType,
      claimNumber: claimNumber ?? this.claimNumber,
      customerInsuranceCompany:
          customerInsuranceCompany ?? this.customerInsuranceCompany,
      liabilityPercent: liabilityPercent ?? this.liabilityPercent,
      submissionDateUtcMs: submissionDateUtcMs ?? this.submissionDateUtcMs,
      insurerReferenceNumber:
          insurerReferenceNumber ?? this.insurerReferenceNumber,
      claimAmountSar: claimAmountSar ?? this.claimAmountSar,
      notes: notes ?? this.notes,
      extraFields: extraFields ?? this.extraFields,
      statusKey: statusKey ?? this.statusKey,
      lastStatusUpdateUtcMs:
          lastStatusUpdateUtcMs ?? this.lastStatusUpdateUtcMs,
      nextFollowUpUtcMs: nextFollowUpUtcMs ?? this.nextFollowUpUtcMs,
      reminderEnabled: reminderEnabled ?? this.reminderEnabled,
      createdAtUtcMs: createdAtUtcMs ?? this.createdAtUtcMs,
      updatedAtUtcMs: updatedAtUtcMs ?? this.updatedAtUtcMs,
    );
  }

  Map<String, Object?> toRow() => <String, Object?>{
    'id': id,
    'customer_name': customerName,
    'customer_mobile': customerMobile,
    'customer_national_id': customerNationalId,
    'customer_email': customerEmail,
    'accident_number': accidentNumber,
    'accident_date_utc_ms': accidentDateUtcMs.millisecondsSinceEpoch,
    'accident_city': accidentCity,
    'accident_type': accidentType,
    'vehicle_plate': vehiclePlate,
    'vehicle_type': vehicleType,
    'claim_number': claimNumber,
    'customer_insurance_company': customerInsuranceCompany,
    'liability_percent': liabilityPercent,
    'submission_date_utc_ms': submissionDateUtcMs.millisecondsSinceEpoch,
    'insurer_reference_number': insurerReferenceNumber,
    'claim_amount_sar': claimAmountSar,
    'notes': notes,
    'extra_fields': encodeExtraFields(extraFields),
    'status_key': statusKey,
    'last_status_update_utc_ms': lastStatusUpdateUtcMs.millisecondsSinceEpoch,
    'next_follow_up_utc_ms': nextFollowUpUtcMs?.millisecondsSinceEpoch,
    'reminder_enabled': reminderEnabled ? 1 : 0,
    'created_at_utc_ms': createdAtUtcMs.millisecondsSinceEpoch,
    'updated_at_utc_ms': updatedAtUtcMs.millisecondsSinceEpoch,
  };

  factory Claim.fromRow(Map<String, Object?> row) => Claim(
    id: row['id']! as int,
    customerName: row['customer_name']! as String,
    customerMobile: row['customer_mobile']! as String,
    customerNationalId: row['customer_national_id'] as String?,
    customerEmail: row['customer_email'] as String?,
    accidentNumber: row['accident_number'] as String?,
    accidentDateUtcMs: DateTime.fromMillisecondsSinceEpoch(
      row['accident_date_utc_ms']! as int,
      isUtc: true,
    ),
    accidentCity: row['accident_city'] as String?,
    accidentType: row['accident_type'] as String?,
    vehiclePlate: row['vehicle_plate'] as String?,
    vehicleType: row['vehicle_type'] as String?,
    claimNumber: row['claim_number']! as String,
    customerInsuranceCompany: row['customer_insurance_company']! as String,
    liabilityPercent: (row['liability_percent'] as num?)?.toDouble(),
    submissionDateUtcMs: DateTime.fromMillisecondsSinceEpoch(
      row['submission_date_utc_ms']! as int,
      isUtc: true,
    ),
    insurerReferenceNumber: row['insurer_reference_number'] as String?,
    claimAmountSar: (row['claim_amount_sar'] as num?)?.toDouble(),
    notes: row['notes'] as String?,
    extraFields: decodeExtraFields(row['extra_fields'] as String?),
    statusKey: row['status_key']! as String,
    lastStatusUpdateUtcMs: DateTime.fromMillisecondsSinceEpoch(
      row['last_status_update_utc_ms']! as int,
      isUtc: true,
    ),
    nextFollowUpUtcMs: (row['next_follow_up_utc_ms'] as int?) == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(
            row['next_follow_up_utc_ms']! as int,
            isUtc: true,
          ),
    reminderEnabled: (row['reminder_enabled'] as int) == 1,
    createdAtUtcMs: DateTime.fromMillisecondsSinceEpoch(
      row['created_at_utc_ms']! as int,
      isUtc: true,
    ),
    updatedAtUtcMs: DateTime.fromMillisecondsSinceEpoch(
      row['updated_at_utc_ms']! as int,
      isUtc: true,
    ),
  );

  /// JSON for the `extra_fields` column; null when there are none.
  static String? encodeExtraFields(Map<String, String> fields) =>
      fields.isEmpty ? null : jsonEncode(fields);

  /// Reads the `extra_fields` column. A missing or unreadable value is
  /// treated as "no extra fields" rather than failing the whole claim.
  static Map<String, String> decodeExtraFields(String? raw) {
    if (raw == null || raw.isEmpty) return const <String, String>{};
    try {
      final Object? decoded = jsonDecode(raw);
      if (decoded is! Map) return const <String, String>{};
      return <String, String>{
        for (final MapEntry<dynamic, dynamic> e in decoded.entries)
          e.key.toString(): e.value?.toString() ?? '',
      };
    } on FormatException {
      return const <String, String>{};
    }
  }
}
