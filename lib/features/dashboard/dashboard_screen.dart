/// Dashboard screen: gradient hero with the accident illustration, colorful
/// metric tiles, a status overview bar and the needs-attention list. Every
/// number is computed from SQLite via [DashboardService] — nothing hardcoded.
library;

import 'package:flutter/material.dart';

import '../../core/l10n/app_strings.dart';
import '../../core/models/claim.dart';
import '../../core/models/claim_status.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/time_utils.dart';
import '../../shared/widgets/load_error_view.dart';
import '../../shared/widgets/modern.dart';
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

  /// Called when a metric tile is tapped with the selection it represents:
  /// a group [ClaimsFilter] and, for status-based tiles, a single status key.
  final void Function(ClaimsFilter filter, String? status) onMetricTapped;

  /// Called when a needs-attention row is tapped.
  final void Function(int claimId)? onClaimTapped;

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  DashboardMetrics? _metrics;
  List<NeedsAttentionItem> _attention = const <NeedsAttentionItem>[];
  List<Claim> _registered = const <Claim>[];
  Map<String, int> _statusCounts = const <String, int>{};
  bool _loaded = false;

  /// True when the load threw (e.g. DB closed mid-restore) — shown as a
  /// retryable error state, never a red screen.
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
      final Future<Map<String, int>> countsF = widget.service.statusCounts();
      final Future<List<Claim>> registeredF = widget.service.recentlyRegistered(
        limit: 5,
      );
      final DashboardMetrics m = await metricsF;
      final List<NeedsAttentionItem> items = await attentionF;
      final Map<String, int> counts = await countsF;
      final List<Claim> registered = await registeredF;
      if (!mounted) return;
      setState(() {
        _metrics = m;
        _attention = items;
        _registered = registered;
        _statusCounts = counts;
        _loadFailed = false;
        _loaded = true;
      });
    } on Object catch (_) {
      if (!mounted) return;
      setState(() => _loadFailed = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final DashboardMetrics? metrics = _metrics;
    final ThemeData theme = Theme.of(context);
    return SafeArea(
      child: RefreshIndicator(
        onRefresh: _load,
        child: SingleChildScrollView(
          // The shell remounts the dashboard after every data change (e.g.
          // back from a claim); the scroll position survives in the route's
          // PageStorage. Keyed only once loaded: restored onto the short
          // loading view, the offset would be clamped to the top.
          key: _loaded
              ? const PageStorageKey<String>('dashboard-scroll')
              : null,
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(18, 12, 18, 110),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          S.dashGreeting,
                          style: theme.textTheme.bodyLarge?.copyWith(
                            color: AppTheme.muted(context),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          S.appName,
                          style: theme.textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const IconBubble(
                    icon: Icons.car_crash_rounded,
                    color: AppColors.violet,
                    size: 50,
                    solid: true,
                  ),
                ],
              ),
              const SizedBox(height: 18),
              _Hero(metrics: metrics),
              const SizedBox(height: 22),
              if (_loadFailed)
                LoadErrorView(onRetry: _load)
              else if (!_loaded || metrics == null)
                const Padding(
                  padding: EdgeInsets.all(32),
                  child: Center(child: CircularProgressIndicator()),
                )
              else ...<Widget>[
                _MetricGrid(
                  metrics: metrics,
                  onTileTapped: widget.onMetricTapped,
                ),
                const SizedBox(height: 24),
                if (metrics.total == 0)
                  const _EmptyState()
                else ...<Widget>[
                  _StatusOverview(counts: _statusCounts),
                  const SizedBox(height: 24),
                  // Overdue / due-today follow-ups jump above the new claims.
                  ...(metrics.overdue > 0 || metrics.dueToday > 0
                      ? <Widget>[
                          _attentionColumn(),
                          const SizedBox(height: 24),
                          _registeredColumn(),
                        ]
                      : <Widget>[
                          _registeredColumn(),
                          const SizedBox(height: 24),
                          _attentionColumn(),
                        ]),
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _registeredColumn() => _ClaimColumn(
    icon: Icons.fiber_new_rounded,
    title: S.dashRecentlyRegistered,
    color: AppColors.mint,
    claims: _registered,
    pill: (Claim c) => null,
    onTapClaim: widget.onClaimTapped,
  );

  Widget _attentionColumn() {
    final DateTime nowUtc = DateTime.now().toUtc();
    final Set<int> overdue = <int>{
      for (final NeedsAttentionItem i in _attention)
        if (i.isOverdue) i.claim.id,
    };
    return _ClaimColumn(
      icon: Icons.notifications_active_rounded,
      title: S.dashNeedsAttention,
      color: AppColors.rose,
      claims: <Claim>[for (final NeedsAttentionItem i in _attention) i.claim],
      pill: (Claim c) {
        if (c.nextFollowUpUtcMs == null) return null;
        final bool late = overdue.contains(c.id);
        return (
          icon: late ? Icons.alarm_rounded : Icons.schedule_rounded,
          text: TimeUtils.followUpLabel(c.nextFollowUpUtcMs, nowUtc: nowUtc),
          color: late ? AppColors.rose : AppColors.indigo,
        );
      },
      onTapClaim: widget.onClaimTapped,
    );
  }
}

class _Hero extends StatelessWidget {
  const _Hero({required this.metrics});

  final DashboardMetrics? metrics;

  @override
  Widget build(BuildContext context) {
    final DashboardMetrics? m = metrics;
    final double progress = m == null || m.total == 0 ? 0 : m.closed / m.total;
    final TextTheme text = Theme.of(context).textTheme;
    return GradientHero(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const Center(child: Illustration('hero_crash', height: 150)),
          const SizedBox(height: 10),
          Text(
            S.dashHeroSubtitle,
            style: text.titleMedium?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w800,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: <Widget>[
              Text(
                S.dashProgress,
                style: text.bodyMedium?.copyWith(
                  color: Colors.white.withValues(alpha: 0.88),
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              Text(
                '${(progress * 100).round()}%',
                style: text.titleMedium?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: TweenAnimationBuilder<double>(
              tween: Tween<double>(begin: 0, end: progress),
              duration: const Duration(milliseconds: 900),
              curve: Curves.easeOutCubic,
              builder: (_, double v, _) => LinearProgressIndicator(
                value: v,
                minHeight: 10,
                backgroundColor: Colors.white.withValues(alpha: 0.22),
                valueColor: const AlwaysStoppedAnimation<Color>(
                  Color(0xFF6EE7B7),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MetricGrid extends StatelessWidget {
  const _MetricGrid({required this.metrics, required this.onTileTapped});

  final DashboardMetrics metrics;
  final void Function(ClaimsFilter filter, String? status) onTileTapped;

  @override
  Widget build(BuildContext context) {
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 12,
      crossAxisSpacing: 12,
      childAspectRatio: 2.1,
      children: <Widget>[
        _MetricTile(
          key: const Key('metric-all'),
          icon: Icons.layers_rounded,
          color: AppColors.indigo,
          value: metrics.total,
          label: S.dashTotalClaims,
          onTap: () => onTileTapped(ClaimsFilter.all, null),
        ),
        _MetricTile(
          key: const Key('metric-open'),
          icon: Icons.folder_open_rounded,
          color: AppColors.sky,
          value: metrics.open,
          label: S.dashOpenClaims,
          onTap: () => onTileTapped(ClaimsFilter.open, null),
        ),
        _MetricTile(
          key: const Key('metric-closed'),
          icon: Icons.task_alt_rounded,
          color: AppColors.mint,
          value: metrics.closed,
          label: S.dashClosedClaims,
          onTap: () => onTileTapped(ClaimsFilter.closed, null),
        ),
        _MetricTile(
          key: const Key('metric-awaitingApproval'),
          icon: Icons.gavel_rounded,
          color: AppColors.amber,
          value: metrics.awaitingApproval,
          label: S.dashAwaitingApproval,
          onTap: () =>
              onTileTapped(ClaimsFilter.all, ClaimStatus.awaitingApprovalKey),
        ),
        _MetricTile(
          key: const Key('metric-followUp'),
          icon: Icons.event_available_rounded,
          color: AppColors.violet,
          value: metrics.dueToday,
          label: S.dashDueToday,
          onTap: () => onTileTapped(ClaimsFilter.followUp, null),
        ),
        _MetricTile(
          key: const Key('metric-overdue'),
          icon: Icons.alarm_rounded,
          color: AppColors.rose,
          value: metrics.overdue,
          label: S.dashOverdue,
          onTap: () => onTileTapped(ClaimsFilter.overdue, null),
        ),
      ],
    );
  }
}

class _MetricTile extends StatelessWidget {
  const _MetricTile({
    super.key,
    required this.icon,
    required this.color,
    required this.value,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final Color color;
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
        child: Stack(
          children: <Widget>[
            PositionedDirectional(
              end: -14,
              bottom: -14,
              child: Icon(icon, size: 64, color: color.withValues(alpha: 0.07)),
            ),
            Padding(
              padding: const EdgeInsets.all(10),
              child: Row(
                children: <Widget>[
                  IconBubble(icon: icon, color: color, size: 38, solid: true),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          '$value',
                          style: theme.textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.w900,
                            height: 1.1,
                          ),
                        ),
                        Text(
                          label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: AppTheme.muted(context),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Stacked bar of claims per status with a labelled legend (never color
/// alone).
class _StatusOverview extends StatelessWidget {
  const _StatusOverview({required this.counts});

  final Map<String, int> counts;

  @override
  Widget build(BuildContext context) {
    final List<MapEntry<String, int>> entries = counts.entries.toList();
    Color accent(String key) =>
        StatusPalette.accent(ClaimStatus.byKey(key).tone);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            SectionTitle(
              icon: Icons.donut_large_rounded,
              title: S.dashStatusOverview,
              color: AppColors.violet,
            ),
            const SizedBox(height: 14),
            ClipRRect(
              borderRadius: BorderRadius.circular(99),
              child: SizedBox(
                height: 14,
                child: Row(
                  children: <Widget>[
                    for (final MapEntry<String, int> e in entries)
                      Expanded(
                        flex: e.value,
                        child: Container(
                          margin: const EdgeInsetsDirectional.only(end: 2),
                          color: accent(e.key),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 14,
              runSpacing: 8,
              children: <Widget>[
                for (final MapEntry<String, int> e in entries)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                          color: accent(e.key),
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '${ClaimStatus.byKey(e.key).label} · ${e.value}',
                        style: Theme.of(context).textTheme.bodySmall
                            ?.copyWith(fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        children: <Widget>[
          const Illustration('empty_claims', height: 170),
          const SizedBox(height: 12),
          Text(
            S.dashEmpty,
            style: Theme.of(context).textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.w700),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

/// One pill shown under a claim in a dashboard column.
typedef _Pill = ({IconData icon, String text, Color color});

/// Titled column of compact claim cards (half the screen width).
class _ClaimColumn extends StatelessWidget {
  const _ClaimColumn({
    required this.icon,
    required this.title,
    required this.color,
    required this.claims,
    required this.pill,
    required this.onTapClaim,
  });

  final IconData icon;
  final String title;
  final Color color;
  final List<Claim> claims;
  final _Pill? Function(Claim) pill;
  final void Function(int claimId)? onTapClaim;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool dark = theme.brightness == Brightness.dark;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        SectionTitle(icon: icon, title: title, color: color),
        const SizedBox(height: 12),
        if (claims.isEmpty)
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
          ...claims.map((Claim claim) {
            final _Pill? p = pill(claim);
            // Darken (light theme) / lighten (dark theme) for text contrast.
            final Color? fg = p == null
                ? null
                : Color.lerp(
                    p.color,
                    dark ? Colors.white : Colors.black,
                    dark ? 0.35 : 0.2,
                  );
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Card(
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: onTapClaim == null
                      ? null
                      : () => onTapClaim!(claim.id),
                  child: Padding(
                    padding: const EdgeInsets.all(10),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        IconBubble(
                          icon: AccidentVisual.icon(claim.accidentType),
                          color: AccidentVisual.color(claim.accidentType),
                          size: 34,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              // Plate always renders LTR (both EN and AR UIs).
                              Directionality(
                                textDirection: TextDirection.ltr,
                                child: Text(
                                  claim.vehiclePlate ?? S.noPlate,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  textAlign: TextAlign.left,
                                  style: theme.textTheme.titleSmall?.copyWith(
                                    fontWeight: FontWeight.w900,
                                    color: claim.vehiclePlate == null
                                        ? AppTheme.muted(context)
                                        : null,
                                  ),
                                ),
                              ),
                              Text(
                                claim.customerName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              Text(
                                claim.claimNumberDisplay,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: AppTheme.muted(context),
                                ),
                              ),
                              if (p != null) ...<Widget>[
                                const SizedBox(height: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: p.color.withValues(alpha: 0.13),
                                    borderRadius: BorderRadius.circular(999),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: <Widget>[
                                      Icon(p.icon, size: 13, color: fg),
                                      const SizedBox(width: 4),
                                      Flexible(
                                        child: Text(
                                          p.text,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: theme.textTheme.labelSmall
                                              ?.copyWith(
                                                fontWeight: FontWeight.w700,
                                                color: fg,
                                              ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          }),
      ],
    );
  }
}
