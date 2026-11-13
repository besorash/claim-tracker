/// Claims list screen (spec §6): search, filter chips and balanced cards.
///
/// One code path for both modes: a non-empty query goes through
/// [ClaimsRepository.search] and the active filter is re-applied in memory;
/// an empty query uses the repository's dedicated filter queries directly.
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/database/claims_repository.dart';
import '../../core/l10n/app_strings.dart';
import '../../core/models/claim.dart';
import '../../core/models/claim_status.dart';
import '../../core/utils/time_utils.dart';
import '../../shared/widgets/load_error_view.dart';
import 'claim_card.dart';
import 'claim_dialogs.dart';
import 'claims_filter.dart';

class ClaimsListScreen extends StatefulWidget {
  const ClaimsListScreen({
    super.key,
    required this.repo,
    this.initialFilter = ClaimsFilter.all,
    this.initialStatus,
    this.onSelectionChanged,
    this.onClaimTapped,
    this.onChangeStatus,
    this.onEdit,
    this.onDelete,
    this.onBulkDelete,
  });

  final ClaimsRepository repo;

  /// Filter selected when the screen opens (e.g. from a dashboard tile).
  final ClaimsFilter initialFilter;

  /// Status-chip selection active when the screen opens (null = the group
  /// filter [initialFilter] applies). Together with [initialFilter] this is
  /// how the shell's remembered choice survives remounts — e.g. returning
  /// from the details screen must NOT reset a user-selected filter.
  final String? initialStatus;

  /// Reports every selection change (group filter or status chip) to the
  /// owner so it can remember the active choice across navigation and
  /// refreshes. Null in standalone use (tests, previews).
  final void Function(ClaimsFilter filter, String? status)? onSelectionChanged;

  /// Optional tap handler — the shell owns navigation to details (spec §4).
  final void Function(Claim claim)? onClaimTapped;

  /// Card actions, run by the shell (it owns persistence and refreshes every
  /// destination afterwards). Null hides that button on the cards.
  final Future<void> Function(Claim claim)? onChangeStatus;
  final Future<void> Function(Claim claim)? onEdit;
  final Future<void> Function(Claim claim)? onDelete;

  /// Bulk delete of the selection-mode selection (already confirmed by this
  /// screen's dialog before it is called). Null hides the bulk-delete control.
  final Future<void> Function(List<Claim> claims)? onBulkDelete;

  @override
  State<ClaimsListScreen> createState() => _ClaimsListScreenState();
}

class _ClaimsListScreenState extends State<ClaimsListScreen> {
  String _query = '';
  ClaimsFilter _filter = ClaimsFilter.all;

  /// A single status chosen from the status chips; when set it replaces
  /// [_filter] (which then stays at [ClaimsFilter.all]).
  String? _status;

  ClaimsSort _sort = ClaimsSort.smart;
  List<Claim> _claims = const [];
  bool _loaded = false;

  /// Selection mode (bulk delete): while active, tapping a card toggles its
  /// selection instead of opening the details screen. Entering it always
  /// starts from an empty selection — no stale checks can survive a remount or
  /// re-entry.
  bool _selectionMode = false;

  /// Claim ids currently checked in selection mode. Pruned on every reload so
  /// a claim is never bulk-deleted while invisible (filtered out, searched
  /// away, ...) — what you see selected is exactly what gets deleted.
  Set<int> _selectedIds = <int>{};

  void _enterSelectionMode() {
    setState(() {
      _selectionMode = true;
      _selectedIds = <int>{};
    });
  }

  void _exitSelectionMode() {
    setState(() {
      _selectionMode = false;
      _selectedIds = <int>{};
    });
  }

  void _toggleSelected(int id) {
    setState(() {
      if (!_selectedIds.remove(id)) _selectedIds.add(id);
    });
  }

  /// Checks exactly the claims visible under the current search/filter
  /// (caller wraps it in its own [setState] when needed).
  void _selectAllVisible() =>
      _selectedIds = <int>{for (final Claim c in _claims) c.id};

  /// Confirms, then delegates the bulk delete to the owner (the shell runs the
  /// same per-claim guarantees as a single delete — alarms cancelled, files
  /// removed best-effort, rows deleted last). Exits selection mode and reloads.
  Future<void> _bulkDeleteSelected() async {
    final List<Claim> selected = <Claim>[
      for (final Claim c in _claims)
        if (_selectedIds.contains(c.id)) c,
    ];
    if (selected.isEmpty || widget.onBulkDelete == null) return;

    final bool confirmed = await confirmDeleteClaims(context, selected.length);
    if (!confirmed || !mounted) return;

    // Persist first (the shell refreshes every destination on success), then
    // exit selection mode and reload this list.
    await widget.onBulkDelete!(selected);
    if (!mounted) return;
    _exitSelectionMode();
    await _load();
  }

  /// True when a load threw (e.g. DB closed mid-load during a restore swap) —
  /// shown as an honest error state with retry, never a red screen (spec §3.3).
  bool _loadFailed = false;

  /// Pending search after the user stops typing.
  Timer? _debounce;

  /// Bumped on every load; an older load that finishes late is ignored so a
  /// slow query cannot overwrite newer results.
  int _loadGen = 0;

  @override
  void initState() {
    super.initState();
    // Restore the owner's remembered selection: a remount (returning from
    // details, any data refresh) must keep the filter the user chose.
    _filter = widget.initialFilter;
    _status = widget.initialStatus;
    _load();
  }

  @override
  void didUpdateWidget(covariant ClaimsListScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialFilter == oldWidget.initialFilter &&
        widget.initialStatus == oldWidget.initialStatus) {
      return;
    }
    // The selection changed externally (e.g. a dashboard metric tile). Adopt
    // it — unless we already hold exactly this choice, which is the echo of
    // our own onSelectionChanged report and must not reload twice.
    if (_filter == widget.initialFilter && _status == widget.initialStatus) {
      return;
    }
    setState(() {
      _filter = widget.initialFilter;
      _status = widget.initialStatus;
    });
    _load();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  /// Applies a new filter/status selection, reports it to the owner (so it
  /// survives remounts) and reloads. One code path for chip taps and the
  /// clear-filters action.
  void _setSelection(ClaimsFilter filter, String? status) {
    setState(() {
      _filter = filter;
      _status = status;
    });
    widget.onSelectionChanged?.call(filter, status);
    _load();
  }

  /// Clears every active selection — group filter and status chip — back to
  /// "all claims". The clear control is only shown while something is active.
  void _clearFilters() => _setSelection(ClaimsFilter.all, null);

  Future<void> _load() async {
    final int gen = ++_loadGen;
    try {
      final DateTime nowUtc = DateTime.now().toUtc();
      final String query = _query.trim();

      List<Claim> claims;
      final String? status = _status;
      if (query.isNotEmpty) {
        // Search first, then re-apply the active filter in memory so search and
        // filters compose on a single code path.
        claims = await widget.repo.search(query);
        claims = claims.where((c) => _matches(c, nowUtc)).toList();
      } else if (status != null) {
        claims = await widget.repo.withStatus(status);
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

      if (!mounted || gen != _loadGen) return;
      final Set<int> visibleIds = claims.map((Claim c) => c.id).toSet();
      setState(() {
        _claims = _sort.apply(claims);
        // Selection mode: drop any checked claim that is no longer visible, so
        // the bulk delete can never reach a filtered-out or searched-away row.
        if (_selectionMode) {
          _selectedIds.removeWhere((int id) => !visibleIds.contains(id));
        }
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
  /// finished means Closed, Approved or Rejected — compensated stays open.
  bool _matches(Claim claim, DateTime nowUtc) {
    if (_status != null) return claim.statusKey == _status;
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

    // Selection mode (bulk delete) owns the app bar while active: close it on
    // the leading edge, live count in the title, select/deselect-all + the
    // bulk-delete action on the trailing edge. Normal mode keeps sort and adds
    // the entry point to selection mode.
    final bool selecting = _selectionMode;
    final int selectedCount = _selectedIds.length;
    final bool allVisibleSelected =
        _claims.isNotEmpty && selectedCount == _claims.length;

    return Scaffold(
      appBar: AppBar(
        leading: selecting
            ? IconButton(
                key: const Key('exit-selection'),
                tooltip: S.cancel,
                icon: const Icon(Icons.close),
                onPressed: _exitSelectionMode,
              )
            : null,
        title: selecting && selectedCount > 0
            ? Text(S.selectedCount(selectedCount))
            : Text(S.navClaims),
        actions: <Widget>[
          if (selecting) ...<Widget>[
            IconButton(
              key: const Key('selection-all'),
              tooltip: allVisibleSelected ? S.deselectAll : S.selectAll,
              icon: Icon(
                allVisibleSelected ? Icons.deselect : Icons.select_all,
              ),
              onPressed: _claims.isEmpty
                  ? null
                  : () => setState(() {
                      if (allVisibleSelected) {
                        _selectedIds = <int>{};
                      } else {
                        _selectAllVisible();
                      }
                    }),
            ),
            IconButton(
              key: const Key('bulk-delete'),
              tooltip: S.delete,
              icon: const Icon(Icons.delete_outline),
              style: IconButton.styleFrom(
                foregroundColor: theme.colorScheme.error,
              ),
              onPressed: selectedCount == 0 ? null : _bulkDeleteSelected,
            ),
          ] else ...<Widget>[
            PopupMenuButton<ClaimsSort>(
              key: const Key('claims-sort'),
              tooltip: S.sortTooltip,
              icon: Icon(
                Icons.sort,
                color: _sort == ClaimsSort.smart
                    ? null
                    : theme.colorScheme.primary,
              ),
              initialValue: _sort,
              onSelected: (ClaimsSort s) {
                setState(() {
                  _sort = s;
                  _claims = s.apply(_claims);
                });
                // Smart order comes from the repository; reload to restore it.
                if (s == ClaimsSort.smart) _load();
              },
              itemBuilder: (BuildContext context) =>
                  <PopupMenuEntry<ClaimsSort>>[
                    for (final ClaimsSort s in ClaimsSort.values)
                      CheckedPopupMenuItem<ClaimsSort>(
                        value: s,
                        checked: s == _sort,
                        child: Text(s.label),
                      ),
                  ],
            ),
            IconButton(
              key: const Key('enter-selection'),
              tooltip: S.selectClaims,
              icon: const Icon(Icons.checklist),
              onPressed: _claims.isEmpty ? null : _enterSelectionMode,
            ),
          ],
        ],
      ),
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
                _query = value;
                // Wait for a short pause in typing before searching, so a
                // word does not trigger one full reload per letter.
                _debounce?.cancel();
                _debounce = Timer(const Duration(milliseconds: 250), _load);
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
                  // Groups first, then one chip per status.
                  for (final ClaimsFilter f in ClaimsFilter.values) ...[
                    if (f != ClaimsFilter.all) const SizedBox(width: 8),
                    ChoiceChip(
                      key: Key('filter-${f.name}'),
                      label: Text(f.label),
                      selected: _status == null && _filter == f,
                      onSelected: (bool selected) {
                        if (!selected) return;
                        _setSelection(f, null);
                      },
                    ),
                  ],
                  for (final ClaimStatusMeta m in ClaimStatus.all) ...[
                    const SizedBox(width: 8),
                    ChoiceChip(
                      key: Key('filter-status-${m.key}'),
                      label: Text(m.label),
                      selected: _status == m.key,
                      onSelected: (bool selected) {
                        if (!selected) return;
                        _setSelection(ClaimsFilter.all, m.key);
                      },
                    ),
                  ],
                ],
              ),
            ),
          ),
          // Clear control, shown only while a selection is active: it resets
          // the group filter and status chip back to "all claims" in one tap.
          if (_filter != ClaimsFilter.all || _status != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 0, 4, 2),
              child: Align(
                alignment: AlignmentDirectional.centerEnd,
                child: TextButton.icon(
                  key: const Key('clear-filters'),
                  onPressed: _clearFilters,
                  icon: Icon(Icons.filter_alt_off, size: 18),
                  label: Text(S.clearFilters),
                ),
              ),
            ),
          if (_sort != ClaimsSort.smart)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 2, 16, 0),
              child: Row(
                children: [
                  Icon(Icons.sort, size: 16, color: theme.colorScheme.primary),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      _sort.label,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.primary,
                      ),
                    ),
                  ),
                ],
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

  /// With a date order, each card shows the date it is sorted by.
  String? _dateNote(Claim c) {
    final DateTime? d = _sort.dateOf(c);
    if (d == null) return null;
    final bool submission =
        _sort == ClaimsSort.submissionNewest ||
        _sort == ClaimsSort.submissionOldest;
    return '${submission ? S.submissionDateLabel : S.lastUpdateLabel}: '
        '${TimeUtils.formatDate(d)}';
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

    // Lazy list: only the cards on screen are built. Building every card up
    // front froze the app (ANR) with ~1,700 imported claims.
    final bool selecting = _selectionMode;
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      itemCount: _claims.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (BuildContext context, int index) {
        final Claim c = _claims[index];
        return InkWell(
          key: Key('card-${c.id}'),
          borderRadius: BorderRadius.circular(12),
          // In selection mode a card tap toggles the check instead of opening
          // details — no accidental navigation out of bulk delete.
          onTap: selecting
              ? () => _toggleSelected(c.id)
              : (widget.onClaimTapped == null
                    ? null
                    : () => widget.onClaimTapped!(c)),
          child: ClaimCard(
            claim: c,
            dateNote: _dateNote(c),
            selection: selecting ? _selectedIds.contains(c.id) : null,
            onSelectionChanged: selecting ? () => _toggleSelected(c.id) : null,
            onChangeStatus: _action(widget.onChangeStatus, c),
            onEdit: _action(widget.onEdit, c),
            onDelete: _action(widget.onDelete, c),
          ),
        );
      },
    );
  }
}
