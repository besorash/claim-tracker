/// Centralized claim status definitions (spec §8).
///
/// Statuses are stored in the database as [ClaimStatus.key] strings.
/// Localized labels and semantic color roles live here — never scatter literal
/// status strings across the codebase (spec §8). Labels resolve against the
/// current UI language at build time (bilingual EN/AR, spec §3.4).
library;

import '../l10n/app_strings.dart';

/// Semantic role used to map a status onto theme tokens (spec §3.1, §8).
enum StatusTone { neutral, info, progress, warning, success, danger }

class ClaimStatusMeta {
  const ClaimStatusMeta({
    required this.key,
    required this.tone,
    required this.isClosed,
  });

  /// Stable identifier persisted in the database.
  final String key;

  /// Localized display label (spec §8) — English or Arabic depending on the
  /// active UI language ([AppLocale.locale]).
  String get label => switch (key) {
    'new' => S.statusNew,
    'submitted' => S.statusSubmitted,
    'awaiting_review' => S.statusAwaitingReview,
    'awaiting_documents' => S.statusAwaitingDocuments,
    'processing' => S.statusProcessing,
    'awaiting_approval' => S.statusAwaitingApproval,
    'approved' => S.statusApproved,
    'compensated' => S.statusCompensated,
    'rejected' => S.statusRejected,
    'closed' => S.statusClosed,
    _ => key,
  };

  /// Semantic color role — resolved to concrete colors per theme.
  final StatusTone tone;

  /// Whether this status counts as "closed" for lists, dashboard metrics and
  /// follow-ups: Closed, Approved and Rejected are final outcomes.
  /// Compensated stays open until the user closes it.
  final bool isClosed;
}

abstract final class ClaimStatus {
  static const List<ClaimStatusMeta> all = [
    ClaimStatusMeta(key: 'new', tone: StatusTone.neutral, isClosed: false),
    ClaimStatusMeta(key: 'submitted', tone: StatusTone.info, isClosed: false),
    ClaimStatusMeta(
      key: 'awaiting_review',
      tone: StatusTone.progress,
      isClosed: false,
    ),
    ClaimStatusMeta(
      key: 'awaiting_documents',
      tone: StatusTone.warning,
      isClosed: false,
    ),
    ClaimStatusMeta(
      key: 'processing',
      tone: StatusTone.progress,
      isClosed: false,
    ),
    ClaimStatusMeta(
      key: 'awaiting_approval',
      tone: StatusTone.warning,
      isClosed: false,
    ),
    ClaimStatusMeta(key: 'approved', tone: StatusTone.success, isClosed: true),
    ClaimStatusMeta(
      key: 'compensated',
      tone: StatusTone.success,
      isClosed: false,
    ),
    ClaimStatusMeta(key: 'rejected', tone: StatusTone.danger, isClosed: true),
    ClaimStatusMeta(key: 'closed', tone: StatusTone.neutral, isClosed: true),
  ];

  static const String defaultKey = 'new';

  /// The "Awaiting Approval" status key (the dashboard metric tile).
  static const String awaitingApprovalKey = 'awaiting_approval';

  /// The explicit "Closed" status (what closing a claim sets).
  static final ClaimStatusMeta closed = all.last;

  /// Every status key that counts as closed (see [ClaimStatusMeta.isClosed]).
  static final List<String> closedKeys = <String>[
    for (final ClaimStatusMeta m in all)
      if (m.isClosed) m.key,
  ];

  static ClaimStatusMeta byKey(String key) {
    for (final meta in all) {
      if (meta.key == key) return meta;
    }
    throw ArgumentError.value(key, 'key', 'Unknown claim status');
  }

  static bool isClosedKey(String key) => byKey(key).isClosed;
}
