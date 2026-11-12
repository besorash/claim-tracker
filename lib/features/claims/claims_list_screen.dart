/// Claims list screen (spec §6): search, filter chips and balanced cards.
///
/// One code path for both modes: a non-empty query goes through
/// [ClaimsRepository.search] and the active filter is re-applied in memory;
/// an empty query uses the repository's dedicated filter queries directly.
library;

import 'package:flutter/material.dart';

import '../../core/database/claims_repository.dart';
import '../../core/l10n/app_strings.dart';
import '../../core/models/claim.dart';
import '../../core/models/claim_status.dart';
import '../../shared/widgets/load_error_view.dart';
import 'claim_card.dart';
import 'claims_filter.dart';

class ClaimsListScreen extends StatefulWidget {
  const ClaimsListScreen({
    super.key,
    required this.repo,
    this.initialFilter = ClaimsFilter.all,
    this.onClaimTapped,
    this.onChangeStatus,
    this.onEdit,
    this.onDelete,
  });

  final ClaimsRepository repo;

  /// Filter selected when the screen opens (e.g. from a dashboard tile).
  final ClaimsFilter initialFilter;

  /// Optional tap handler — the shell owns navigation to details (spec §4).
  final void Function(Claim claim)? onClaimTapped;

  /// Card actions, run by the shell (it owns persistence and refreshes every
  /// destination afterwards). Null hides that button on the cards.
  final Future<void> Function(Claim claim)? onChangeStatus;
  final Future<void> Function(Claim claim)? onEdit;
  final Future<void> Function(Claim claim)? onDelete;

  @override
  State<ClaimsListScreen> createState() => _ClaimsListScreenState();
}

class _ClaimsListScreenState extends State<ClaimsListScreen> {
  String _query = '';
  ClaimsFilter _filter = ClaimsFilter.all;
  List<Claim> _claims = const [];
  bool _loaded = false;

  /// True when a load threw (e.g. DB closed mid-load during a restore swap) —
  /// shown as an honest error state with retry, never a red screen (spec §3.3).
  bool _loadFailed = false;

  @override
  void initState() {
    super.initState();
    _filter = widget.initialFilter;
    _load();
  }

  Future<void> _load() async {
    try {
      final DateTime nowUtc = DateTime.now().toUtc();
      final String query = _query.trim();

      List<Claim> claims;
      if (query.isNotEmpty) {
        // Search first, then re-apply the active filter in memory so search and
        // filters compose on a single code path.
        claims = await widget.repo.search(query);
        claims = claims.where((c) => _matches(c, nowUtc)).toList();
      } else {
        switch (_filter) {
          case ClaimsFilter.all:
            claims = await widget.repo.all();
          case ClaimsFilter.open:
            claims = await widget.repo.open();
          case ClaimsFilter.closed:
            claims = await widget.repo.closed();
          case ClaimsFilter.followUp:
            claims = await widget.repo.needsFollowUp();
          case ClaimsFilter.overdue:
            claims = await widget.repo.overdue(nowUtc);
        }
      }

      if (!mounted) return;
      setState(() {
        _claims = claims;
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

  /// In-memory mirror of the repository filter semantics (spec §5–§6):
  /// closed means status key `closed` only — compensated stays open.
  bool _matches(Claim claim, DateTime nowUtc) {
    final bool closed = ClaimStatus.isClosedKey(claim.statusKey);
    final DateTime? followUp = claim.nextFollowUpUtcMs;
    switch (_filter) {
      case ClaimsFilter.all:
        return true;
      case ClaimsFilter.open:
        return !closed;
      case ClaimsFilter.closed:
        return closed;
      case ClaimsFilter.followUp:
        return followUp != null && !closed;
      case ClaimsFilter.overdue:
        return followUp != null && followUp.isBefore(nowUtc) && !closed;
    }
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: Text(S.navClaims)),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: TextField(
              decoration: InputDecoration(
                hintText: S.searchHint,
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onChanged: (String value) {
                setState(() => _query = value);
                _load();
              },
            ),
          ),
          SizedBox(
            height: 48,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                children: [
                  for (final ClaimsFilter f in ClaimsFilter.values) ...[
                    if (f != ClaimsFilter.all) const SizedBox(width: 8),
                    ChoiceChip(
                      label: Text(f.label),
                      selected: _filter == f,
                      onSelected: (bool selected) {
                        if (!selected) return;
                        setState(() => _filter = f);
                        _load();
                      },
                    ),
                  ],
                ],
              ),
            ),
          ),
          Expanded(child: _buildList(theme)),
        ],
      ),
    );
  }

  /// Wraps a card action so the list reloads once it finished.
  VoidCallback? _action(Future<void> Function(Claim)? run, Claim claim) {
    if (run == null) return null;
    return () async {
      await run(claim);
      if (mounted) await _load();
    };
  }

  Widget _buildList(ThemeData theme) {
    if (_loadFailed) {
      return LoadErrorView(onRetry: _load);
    }
    if (!_loaded) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_claims.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.inbox_outlined,
              size: 48,
              color: theme.colorScheme.outline,
            ),
            const SizedBox(height: 12),
            Text(S.claimsEmpty, style: theme.textTheme.bodyLarge),
          ],
        ),
      );
    }

    // Eager (non-lazy) list: this is a small single-user dataset and every
    // card must be present in the tree at once — deterministic for tests and
    // simple to reason about.
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      child: Column(
        children: [
          for (final Claim c in _claims) ...[
            if (c != _claims.first) const SizedBox(height: 10),
            InkWell(
              key: Key('card-${c.id}'),
              borderRadius: BorderRadius.circular(12),
              onTap: widget.onClaimTapped == null
                  ? null
                  : () => widget.onClaimTapped!(c),
              child: ClaimCard(
                claim: c,
                onChangeStatus: _action(widget.onChangeStatus, c),
                onEdit: _action(widget.onEdit, c),
                onDelete: _action(widget.onDelete, c),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
