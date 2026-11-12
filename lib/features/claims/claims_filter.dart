/// Claims list filter and sort (spec §6) — single-sourced so dashboard tiles
/// and the claims list agree on what each filter means.
library;

import '../../core/l10n/app_strings.dart';
import '../../core/models/claim.dart';

enum ClaimsFilter {
  all,
  open,
  followUp,
  overdue,

  /// Finished claims: Closed, Approved and Rejected.
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

/// Order of the claims list. [smart] is the default (needs attention first);
/// the others order by a date, newest or oldest first.
enum ClaimsSort {
  smart,
  submissionNewest,
  submissionOldest,
  updatedNewest,
  updatedOldest;

  String get label => switch (this) {
    ClaimsSort.smart => S.sortDefault,
    ClaimsSort.submissionNewest => S.sortSubmissionNewest,
    ClaimsSort.submissionOldest => S.sortSubmissionOldest,
    ClaimsSort.updatedNewest => S.sortUpdatedNewest,
    ClaimsSort.updatedOldest => S.sortUpdatedOldest,
  };

  /// The date this order uses, or null for [smart].
  DateTime? dateOf(Claim c) => switch (this) {
    ClaimsSort.smart => null,
    ClaimsSort.submissionNewest ||
    ClaimsSort.submissionOldest => c.submissionDateUtcMs,
    ClaimsSort.updatedNewest || ClaimsSort.updatedOldest => c.lastActivityUtcMs,
  };

  /// [claims] in this order; [smart] keeps the given order. Claims without
  /// the date go last; equal dates keep the newest claim (highest id) first.
  List<Claim> apply(List<Claim> claims) {
    if (this == ClaimsSort.smart) return claims;
    final bool newest =
        this == ClaimsSort.submissionNewest || this == ClaimsSort.updatedNewest;
    final List<Claim> sorted = List<Claim>.of(claims);
    sorted.sort((Claim a, Claim b) {
      final DateTime? da = dateOf(a);
      final DateTime? db = dateOf(b);
      if (da == null || db == null) {
        if (da != db) return da == null ? 1 : -1;
        return b.id.compareTo(a.id);
      }
      final int byDate = newest ? db.compareTo(da) : da.compareTo(db);
      return byDate != 0 ? byDate : b.id.compareTo(a.id);
    });
    return sorted;
  }
}
