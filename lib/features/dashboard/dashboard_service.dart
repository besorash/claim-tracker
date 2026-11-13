/// Dashboard metrics computed from SQLite (spec §5) — no hardcoded values.
library;

import 'package:claim_tracker/core/database/claims_repository.dart';
import 'package:claim_tracker/core/models/claim.dart';
import 'package:claim_tracker/core/models/claim_status.dart';
import 'package:claim_tracker/core/utils/time_utils.dart';

class DashboardMetrics {
  const DashboardMetrics({
    required this.total,
    required this.open,
    required this.closed,
    required this.awaitingApproval,
    required this.dueToday,
    required this.overdue,
  });

  final int total;
  final int open;
  final int closed;

  /// Claims whose status is exactly "Awaiting Approval".
  final int awaitingApproval;
  final int dueToday;
  final int overdue;
}

class NeedsAttentionItem {
  const NeedsAttentionItem({required this.claim, required this.isOverdue});

  final Claim claim;
  final bool isOverdue;
}

class DashboardService {
  const DashboardService(this._claims);

  final ClaimsRepository _claims;

  Future<DashboardMetrics> metrics() async {
    final DateTime nowUtc = DateTime.now().toUtc();
    final (DateTime start, DateTime end) = TimeUtils.riyadhDayRange(nowUtc);
    // Counted in SQL: loading every claim just to count them froze the app
    // once ~1,700 claims were imported.
    return DashboardMetrics(
      total: await _claims.countAll(),
      open: await _claims.countOpen(),
      closed: await _claims.countClosed(),
      awaitingApproval: await _claims.countWithStatus(
        ClaimStatus.awaitingApprovalKey,
      ),
      dueToday: await _claims.countDueBetween(start, end),
      overdue: await _claims.countOverdue(nowUtc),
    );
  }

  /// Overdue first, then due-today, then recently updated — capped at [limit].
  Future<List<NeedsAttentionItem>> needsAttention({int limit = 5}) async {
    final DateTime nowUtc = DateTime.now().toUtc();
    final (DateTime start, DateTime end) = TimeUtils.riyadhDayRange(nowUtc);

    final List<NeedsAttentionItem> items = <NeedsAttentionItem>[];
    for (final Claim c in await _claims.overdue(nowUtc)) {
      items.add(NeedsAttentionItem(claim: c, isOverdue: true));
    }
    for (final Claim c in await _claims.dueBetween(start, end)) {
      if (!items.any((NeedsAttentionItem i) => i.claim.id == c.id)) {
        items.add(NeedsAttentionItem(claim: c, isOverdue: false));
      }
    }

    // Only as many recent claims as could still fit (plus the ones that may
    // already be listed above), not the whole table.
    final List<Claim> recent = await _claims.recentlyUpdated(
      limit + items.length,
    );
    for (final Claim c in recent) {
      if (items.length >= limit) break;
      if (!items.any((NeedsAttentionItem i) => i.claim.id == c.id)) {
        items.add(NeedsAttentionItem(claim: c, isOverdue: false));
      }
    }

    return items.take(limit).toList();
  }
}
