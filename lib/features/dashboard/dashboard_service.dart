/// Dashboard metrics computed from SQLite (spec §5) — no hardcoded values.
library;

import 'package:claim_tracker/core/database/claims_repository.dart';
import 'package:claim_tracker/core/models/claim.dart';
import 'package:claim_tracker/core/utils/time_utils.dart';

class DashboardMetrics {
  const DashboardMetrics({
    required this.total,
    required this.open,
    required this.closed,
    required this.dueToday,
    required this.overdue,
  });

  final int total;
  final int open;
  final int closed;
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
    final List<Claim> all = await _claims.all();
    return DashboardMetrics(
      total: all.length,
      open: (await _claims.open()).length,
      closed: (await _claims.closed()).length,
      dueToday: (await _claims.dueBetween(start, end)).length,
      overdue: (await _claims.overdue(nowUtc)).length,
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

    final List<Claim> recent = await _claims.all();
    recent.sort((a, b) => b.updatedAtUtcMs.compareTo(a.updatedAtUtcMs));
    for (final Claim c in recent) {
      if (items.length >= limit) break;
      if (!items.any((NeedsAttentionItem i) => i.claim.id == c.id)) {
        items.add(NeedsAttentionItem(claim: c, isOverdue: false));
      }
    }

    return items.take(limit).toList();
  }
}
