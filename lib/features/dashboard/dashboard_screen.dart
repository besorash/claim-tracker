/// Dashboard screen (spec §5): metric tiles and needs-attention list, all
/// numbers computed from SQLite via [DashboardService] — nothing hardcoded.
library;

import 'package:flutter/material.dart';

import '../../core/l10n/app_strings.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/time_utils.dart';
import '../../shared/widgets/load_error_view.dart';
import '../claims/claims_filter.dart';
import 'dashboard_service.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({
    super.key,
    required this.service,
    required this.onMetricTapped,
    this.onClaimTapped,
  });

  final DashboardService service;

  /// Called when a metric tile is tapped with the filter it represents.
  /// The shell wires this to `ClaimsListScreen(initialFilter: …)` (Task 7).
  final ValueChanged<ClaimsFilter> onMetricTapped;

  /// Optional: called when a needs-attention row is tapped (details screen,
  /// Task 5). No-op if not provided.
  final void Function(int claimId)? onClaimTapped;

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  DashboardMetrics? _metrics;
  List<NeedsAttentionItem> _attention = const <NeedsAttentionItem>[];
  bool _loaded = false;

  /// True when the initial load threw (e.g. DB closed mid-load during a
  /// restore swap) — shown as an honest error state with retry, never a red
  /// screen (spec §3.3).
  bool _loadFailed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final Future<DashboardMetrics> metricsF = widget.service.metrics();
      final Future<List<NeedsAttentionItem>> attentionF = widget.service
          .needsAttention(limit: 5);
      final DashboardMetrics m = await metricsF;
      final List<NeedsAttentionItem> items = await attentionF;
      if (!mounted) return;
      setState(() {
        _metrics = m;
        _attention = items;
        _loadFailed = false;
        _loaded = true;
      });
    } on Object catch (_) {
      // A failed load must never crash the app (red screen). Surface it as a
      // retryable error state instead.
      if (!mounted) return;
      setState(() => _loadFailed = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final DashboardMetrics? metrics = _metrics;
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text(S.appName, style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 16),
            if (_loadFailed)
              LoadErrorView(onRetry: _load)
            else if (!_loaded || metrics == null)
              const Center(child: CircularProgressIndicator())
            else ...<Widget>[
              _MetricGrid(
                metrics: metrics,
                onTileTapped: widget.onMetricTapped,
              ),
              const SizedBox(height: 20),
              if (metrics.total == 0)
                const _EmptyState()
              else
                _AttentionSection(
                  items: _attention,
                  onTapClaim: widget.onClaimTapped,
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class _MetricGrid extends StatelessWidget {
  const _MetricGrid({required this.metrics, required this.onTileTapped});

  final DashboardMetrics metrics;
  final ValueChanged<ClaimsFilter> onTileTapped;

  @override
  Widget build(BuildContext context) {
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 12,
      crossAxisSpacing: 12,
      childAspectRatio: 1.6,
      children: <Widget>[
        _MetricTile(
          key: const Key('metric-all'),
          icon: Icons.dashboard_outlined,
          value: metrics.total,
          label: S.dashTotalClaims,
          onTap: () => onTileTapped(ClaimsFilter.all),
        ),
        _MetricTile(
          key: const Key('metric-open'),
          icon: Icons.folder_open_outlined,
          value: metrics.open,
          label: S.dashOpenClaims,
          onTap: () => onTileTapped(ClaimsFilter.open),
        ),
        _MetricTile(
          key: const Key('metric-closed'),
          icon: Icons.check_circle_outline,
          value: metrics.closed,
          label: S.dashClosedClaims,
          onTap: () => onTileTapped(ClaimsFilter.closed),
        ),
        _MetricTile(
          key: const Key('metric-followUp'),
          icon: Icons.event_available,
          value: metrics.dueToday,
          label: S.dashDueToday,
          onTap: () => onTileTapped(ClaimsFilter.followUp),
        ),
        _MetricTile(
          key: const Key('metric-overdue'),
          icon: Icons.warning_amber,
          value: metrics.overdue,
          label: S.dashOverdue,
          onTap: () => onTileTapped(ClaimsFilter.overdue),
        ),
      ],
    );
  }
}

class _MetricTile extends StatelessWidget {
  const _MetricTile({
    super.key,
    required this.icon,
    required this.value,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final int value;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Icon(icon, size: 20, color: theme.colorScheme.primary),
              const SizedBox(height: 6),
              Text(
                '$value',
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                label,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: AppTheme.muted(context),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 32),
      child: Column(
        children: <Widget>[
          Icon(
            Icons.folder_open_outlined,
            size: 48,
            color: AppTheme.muted(context),
          ),
          const SizedBox(height: 12),
          Text(
            S.dashEmpty,
            style: theme.textTheme.bodyLarge,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _AttentionSection extends StatelessWidget {
  const _AttentionSection({required this.items, required this.onTapClaim});

  final List<NeedsAttentionItem> items;
  final void Function(int claimId)? onTapClaim;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text(S.dashNeedsAttention, style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        if (items.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text(
              '—',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyLarge?.copyWith(
                color: AppTheme.muted(context),
              ),
            ),
          )
        else
          ...items.map((NeedsAttentionItem item) {
            final DateTime nowUtc = DateTime.now().toUtc();
            return Card(
              margin: const EdgeInsets.only(bottom: 8),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: onTapClaim == null
                    ? null
                    : () => onTapClaim!(item.claim.id),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  child: Row(
                    children: <Widget>[
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Text(
                              item.claim.vehiclePlate ?? S.noPlate,
                              style: theme.textTheme.titleLarge?.copyWith(
                                fontWeight: FontWeight.w800,
                                color: item.claim.vehiclePlate == null
                                    ? AppTheme.muted(context)
                                    : null,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              item.claim.customerName,
                              style: theme.textTheme.titleSmall,
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '${S.claimNumberLabel}: '
                              '${item.claim.claimNumberDisplay}',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: AppTheme.muted(context),
                              ),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: item.isOverdue
                              ? theme.colorScheme.errorContainer
                              : theme.colorScheme.secondaryContainer,
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          TimeUtils.followUpLabel(
                            item.claim.nextFollowUpUtcMs,
                            nowUtc: nowUtc,
                          ),
                          style: theme.textTheme.bodySmall?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }),
      ],
    );
  }
}
