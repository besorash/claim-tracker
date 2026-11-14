/// Customers screen: pick a customer, see their claims broken down by status
/// (same look as the dashboard), tap a status to list exactly those claims.
/// Customers are grouped by their trimmed name from the claims table.
library;

import 'package:flutter/material.dart';

import '../../core/database/claims_repository.dart';
import '../../core/l10n/app_strings.dart';
import '../../core/models/claim.dart';
import '../../core/models/claim_status.dart';
import '../../core/theme/app_theme.dart';
import '../../shared/widgets/load_error_view.dart';
import '../../shared/widgets/modern.dart';
import '../claims/claim_card.dart';

class CustomersScreen extends StatefulWidget {
  const CustomersScreen({
    super.key,
    required this.repo,
    this.initialCustomer,
    this.initialStatus,
    this.onSelectionChanged,
    this.onClaimTapped,
  });

  final ClaimsRepository repo;

  /// Selection restored after a remount (the shell remembers it).
  final String? initialCustomer;
  final String? initialStatus;
  final void Function(String? customer, String? status)? onSelectionChanged;
  final void Function(Claim claim)? onClaimTapped;

  @override
  State<CustomersScreen> createState() => _CustomersScreenState();
}

class _CustomersScreenState extends State<CustomersScreen> {
  /// Claims per customer name, customers sorted by claim count (most first).
  Map<String, List<Claim>> _byCustomer = const <String, List<Claim>>{};
  bool _loaded = false;
  bool _loadFailed = false;
  String _query = '';
  String? _customer;
  String? _status;

  @override
  void initState() {
    super.initState();
    _customer = widget.initialCustomer;
    _status = widget.initialStatus;
    _load();
  }

  Future<void> _load() async {
    try {
      final List<Claim> claims = await widget.repo.all();
      final Map<String, List<Claim>> groups = <String, List<Claim>>{};
      for (final Claim c in claims) {
        (groups[c.customerName.trim()] ??= <Claim>[]).add(c);
      }
      final List<String> names = groups.keys.toList()
        ..sort((a, b) {
          final int byCount = groups[b]!.length.compareTo(groups[a]!.length);
          return byCount != 0 ? byCount : a.compareTo(b);
        });
      if (!mounted) return;
      setState(() {
        _byCustomer = <String, List<Claim>>{
          for (final String n in names) n: groups[n]!,
        };
        // A remembered customer whose claims were all deleted → back to list.
        if (_customer != null && !_byCustomer.containsKey(_customer)) {
          _customer = null;
          _status = null;
        }
        _loadFailed = false;
        _loaded = true;
      });
    } on Object catch (_) {
      if (!mounted) return;
      setState(() => _loadFailed = true);
    }
  }

  void _select(String? customer, String? status) {
    setState(() {
      _customer = customer;
      _status = status;
    });
    widget.onSelectionChanged?.call(customer, status);
  }

  @override
  Widget build(BuildContext context) {
    final String? customer = _customer;
    return PopScope(
      // System back closes the customer view before leaving the app.
      canPop: customer == null,
      onPopInvokedWithResult: (bool didPop, _) {
        if (!didPop) _select(null, null);
      },
      child: RefreshIndicator(
        onRefresh: _load,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: <Widget>[
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(18, 12, 18, 0),
              sliver: SliverToBoxAdapter(child: _header(context)),
            ),
            if (_loadFailed)
              SliverToBoxAdapter(child: LoadErrorView(onRetry: _load))
            else if (!_loaded)
              const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.all(32),
                  child: Center(child: CircularProgressIndicator()),
                ),
              )
            else if (customer == null)
              ..._customerList(context)
            else
              ..._customerDetails(context, customer, _byCustomer[customer]!),
            const SliverToBoxAdapter(child: SizedBox(height: 110)),
          ],
        ),
      ),
    );
  }

  Widget _header(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Row(
      children: <Widget>[
        if (_customer != null) ...<Widget>[
          IconButton.filledTonal(
            key: const Key('customers-back'),
            tooltip: S.customersAll,
            onPressed: () => _select(null, null),
            icon: const BackButtonIcon(),
          ),
          const SizedBox(width: 8),
        ],
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                S.navCustomers,
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w900,
                ),
              ),
              if (_loaded)
                Text(
                  S.customersCount(_byCustomer.length),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: AppTheme.muted(context),
                    fontWeight: FontWeight.w600,
                  ),
                ),
            ],
          ),
        ),
        const IconBubble(
          icon: Icons.groups_rounded,
          color: AppColors.sky,
          size: 50,
          solid: true,
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Customer picker
  // ---------------------------------------------------------------------------

  List<Widget> _customerList(BuildContext context) {
    if (_byCustomer.isEmpty) {
      return <Widget>[
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: <Widget>[
                const Illustration('empty_claims', height: 170),
                const SizedBox(height: 12),
                Text(
                  S.customersEmpty,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
              ],
            ),
          ),
        ),
      ];
    }
    final String q = _query.trim().toLowerCase();
    final List<String> names = <String>[
      for (final String n in _byCustomer.keys)
        if (q.isEmpty ||
            n.toLowerCase().contains(q) ||
            _byCustomer[n]!.first.customerMobile.contains(q))
          n,
    ];
    return <Widget>[
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 12),
        sliver: SliverToBoxAdapter(
          child: TextField(
            key: const Key('customers-search'),
            decoration: InputDecoration(
              hintText: S.customersSearchHint,
              prefixIcon: const Icon(Icons.search_rounded),
            ),
            onChanged: (String v) => setState(() => _query = v),
          ),
        ),
      ),
      SliverPadding(
        padding: const EdgeInsets.symmetric(horizontal: 18),
        sliver: SliverList.separated(
          itemCount: names.length,
          separatorBuilder: (_, _) => const SizedBox(height: 10),
          itemBuilder: (BuildContext context, int i) => _CustomerTile(
            name: names[i],
            claims: _byCustomer[names[i]]!,
            onTap: () => _select(names[i], null),
          ),
        ),
      ),
    ];
  }

  // ---------------------------------------------------------------------------
  // One customer's breakdown
  // ---------------------------------------------------------------------------

  List<Widget> _customerDetails(
    BuildContext context,
    String name,
    List<Claim> claims,
  ) {
    // Status counts in the canonical status order (only statuses present).
    final List<(ClaimStatusMeta, int)> counts = <(ClaimStatusMeta, int)>[
      for (final ClaimStatusMeta m in ClaimStatus.all)
        if (claims.any((Claim c) => c.statusKey == m.key))
          (m, claims.where((Claim c) => c.statusKey == m.key).length),
    ];
    final int closed = claims
        .where((Claim c) => ClaimStatus.isClosedKey(c.statusKey))
        .length;
    final List<Claim> shown = _status == null
        ? claims
        : claims.where((Claim c) => c.statusKey == _status).toList();
    final String listTitle = _status == null
        ? S.customerAllClaims
        : ClaimStatus.byKey(_status!).label;

    return <Widget>[
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 0),
        sliver: SliverToBoxAdapter(
          child: _CustomerHero(
            name: name,
            mobile: claims.first.customerMobile,
            total: claims.length,
            open: claims.length - closed,
            closed: closed,
          ),
        ),
      ),
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(18, 22, 18, 12),
        sliver: SliverToBoxAdapter(
          child: SectionTitle(
            icon: Icons.donut_large_rounded,
            title: S.dashStatusOverview,
            color: AppColors.violet,
          ),
        ),
      ),
      SliverPadding(
        padding: const EdgeInsets.symmetric(horizontal: 18),
        sliver: SliverGrid.count(
          crossAxisCount: 2,
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          childAspectRatio: 2.3,
          children: <Widget>[
            _StatusTile(
              key: const Key('customer-status-all'),
              icon: Icons.layers_rounded,
              color: AppColors.indigo,
              count: claims.length,
              label: S.filterAll,
              selected: _status == null,
              onTap: () => _select(name, null),
            ),
            for (final (ClaimStatusMeta m, int n) in counts)
              _StatusTile(
                key: Key('customer-status-${m.key}'),
                icon: _toneIcon(m.tone),
                color: StatusPalette.accent(m.tone),
                count: n,
                label: m.label,
                selected: _status == m.key,
                onTap: () => _select(name, _status == m.key ? null : m.key),
              ),
          ],
        ),
      ),
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(18, 24, 18, 12),
        sliver: SliverToBoxAdapter(
          child: SectionTitle(
            icon: Icons.car_crash_rounded,
            title: '$listTitle · ${shown.length}',
            color: AppColors.rose,
          ),
        ),
      ),
      SliverPadding(
        padding: const EdgeInsets.symmetric(horizontal: 18),
        sliver: SliverList.separated(
          itemCount: shown.length,
          separatorBuilder: (_, _) => const SizedBox(height: 12),
          itemBuilder: (BuildContext context, int i) {
            final Claim c = shown[i];
            return InkWell(
              key: Key('customer-claim-${c.id}'),
              borderRadius: BorderRadius.circular(22),
              onTap: widget.onClaimTapped == null
                  ? null
                  : () => widget.onClaimTapped!(c),
              child: ClaimCard(claim: c),
            );
          },
        ),
      ),
    ];
  }

  static IconData _toneIcon(StatusTone tone) => switch (tone) {
    StatusTone.neutral => Icons.radio_button_unchecked_rounded,
    StatusTone.info => Icons.send_rounded,
    StatusTone.progress => Icons.autorenew_rounded,
    StatusTone.warning => Icons.hourglass_top_rounded,
    StatusTone.success => Icons.task_alt_rounded,
    StatusTone.danger => Icons.block_rounded,
  };
}

class _CustomerTile extends StatelessWidget {
  const _CustomerTile({
    required this.name,
    required this.claims,
    required this.onTap,
  });

  final String name;
  final List<Claim> claims;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final int open = claims
        .where((Claim c) => !ClaimStatus.isClosedKey(c.statusKey))
        .length;
    final String initial = name.isEmpty ? '?' : name.characters.first;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        key: Key('customer-$name'),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: <Widget>[
              Container(
                width: 46,
                height: 46,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  gradient: AppGradients.tile(AppColors.sky),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Text(
                  initial.toUpperCase(),
                  style: theme.textTheme.titleLarge?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      '${S.dashOpenClaims}: $open',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: AppTheme.muted(context),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: AppColors.indigo.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  S.customerClaimsCount(claims.length),
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: theme.brightness == Brightness.dark
                        ? const Color(0xFFC7C4FF)
                        : AppColors.indigo,
                  ),
                ),
              ),
              const SizedBox(width: 4),
              Icon(
                Icons.chevron_right_rounded,
                color: AppTheme.muted(context),
                textDirection: Directionality.of(context),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CustomerHero extends StatelessWidget {
  const _CustomerHero({
    required this.name,
    required this.mobile,
    required this.total,
    required this.open,
    required this.closed,
  });

  final String name;
  final String mobile;
  final int total;
  final int open;
  final int closed;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final Color soft = Colors.white.withValues(alpha: 0.88);
    final double progress = total == 0 ? 0 : closed / total;
    Widget stat(String label, int value) => Expanded(
      child: Column(
        children: <Widget>[
          Text(
            '$value',
            style: text.headlineSmall?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w900,
            ),
          ),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: text.bodySmall?.copyWith(
              color: soft,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
    return GradientHero(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: const Icon(
                  Icons.person_rounded,
                  color: Colors.white,
                  size: 30,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      name,
                      style: text.titleLarge?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    // Phone numbers always render LTR.
                    Directionality(
                      textDirection: TextDirection.ltr,
                      child: Text(
                        mobile,
                        style: text.bodyMedium?.copyWith(
                          color: soft,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Row(
            children: <Widget>[
              stat(S.dashTotalClaims, total),
              stat(S.dashOpenClaims, open),
              stat(S.dashClosedClaims, closed),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: <Widget>[
              Text(
                S.dashProgress,
                style: text.bodyMedium?.copyWith(
                  color: soft,
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
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 10,
              backgroundColor: Colors.white.withValues(alpha: 0.22),
              valueColor: const AlwaysStoppedAnimation<Color>(
                Color(0xFF6EE7B7),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Status count tile; tapping filters the claim list below to that status.
class _StatusTile extends StatelessWidget {
  const _StatusTile({
    super.key,
    required this.icon,
    required this.color,
    required this.count,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final Color color;
  final int count;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Semantics(
      selected: selected,
      button: true,
      child: Card(
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(
            color: selected ? color : Colors.transparent,
            width: 2,
          ),
        ),
        color: selected
            ? Color.alphaBlend(color.withValues(alpha: 0.10), theme.cardColor)
            : null,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
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
                        '$count',
                        style: theme.textTheme.titleLarge?.copyWith(
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
        ),
      ),
    );
  }
}
