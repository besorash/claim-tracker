/// Claims list filter (spec §6) — single-sourced so dashboard tiles and the
/// claims list agree on what each filter means.
library;

import '../../core/l10n/app_strings.dart';

enum ClaimsFilter {
  all,
  open,
  followUp,
  overdue,
  closed;

  /// Localized label shown on filter chips (spec §3.4 — strings only via `S.*`,
  /// resolved against the current UI language at build time).
  String get label => switch (this) {
    ClaimsFilter.all => S.filterAll,
    ClaimsFilter.open => S.filterOpen,
    ClaimsFilter.followUp => S.filterFollowUp,
    ClaimsFilter.overdue => S.filterOverdue,
    ClaimsFilter.closed => S.filterClosed,
  };
}
