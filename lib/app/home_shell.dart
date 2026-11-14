/// App shell (spec §4): bottom navigation with the primary destinations,
/// an Add-Claim FAB on the dashboard and claims-list destinations, and
/// ownership of all cross-screen navigation + persistence so feature screens
/// stay router-free and testable in isolation.
library;

import 'package:flutter/material.dart';

import '../core/csv/claims_csv_service.dart';
import '../core/database/app_database.dart';
import '../core/database/claims_repository.dart';
import '../core/security/backup_service.dart';
import '../core/database/settings_repository.dart';
import '../core/l10n/app_strings.dart';
import '../core/models/claim.dart';
import '../core/notifications/notification_service.dart';
import '../core/notifications/reminder_scheduler.dart';
import '../features/attachments/attachment_file_service.dart';
import '../features/claims/claim_actions.dart';
import '../features/claims/claim_dialogs.dart';
import '../features/claims/claim_details_screen.dart';
import '../features/claims/claim_form_screen.dart';
import '../features/claims/claims_filter.dart';
import '../features/claims/claims_list_screen.dart';
import '../features/claims/reminder_save_flow.dart';
import '../features/dashboard/dashboard_screen.dart';
import '../features/customers/customers_screen.dart';
import '../features/dashboard/dashboard_service.dart';
import '../features/settings/settings_screen.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({
    super.key,
    required this.db,
    required this.settingsRepo,
    required this.currentThemeMode,
    required this.onThemeChanged,
    this.currentLanguageCode = 'en',
    this.onLanguageChanged,
    this.backupService,
    this.csvService,
    this.reconnectAfterRestore,
    this.scheduler,
  });

  /// Notification-tap routing hook (spec §10): set by the shell's State while
  /// mounted and cleared on dispose. `main.dart` points
  /// `NotificationService.onClaimTapped` at it so a tap on a reminder — even
  /// after a cold start — opens the right claim in the live shell.
  static void Function(int claimId)? openClaimFromNotification;

  final AppDatabase db;
  final SettingsRepository settingsRepo;
  final ThemeMode currentThemeMode;

  /// Called after the user picks a theme in settings — the app switches live.
  final ValueChanged<ThemeMode> onThemeChanged;

  /// Active UI language code (`en` default / `ar`) for the settings card.
  final String currentLanguageCode;

  /// Called after the user picks a language in settings — the app persists it
  /// and rebuilds around the new locale (RTL follows Arabic).
  final ValueChanged<String>? onLanguageChanged;

  /// Backup engine for the settings card (spec §15). Null hides the card —
  /// widget tests that don't exercise backup simply omit it.
  final BackupService? backupService;

  /// Spreadsheet (CSV) import/export engine handed to the settings screen.
  final ClaimsCsvService? csvService;

  /// Reopens the database after a successful restore swap (the live handle is
  /// closed during the swap) and rebuilds the app around the new instance.
  /// Provided by `main.dart`; null in tests that don't restore.
  final Future<void> Function()? reconnectAfterRestore;

  /// OS-side reminder scheduler seam (spec §10). Defaults to the production
  /// [NotificationService] singleton; widget tests inject a recording fake so
  /// no method channels are touched when add/edit flows schedule reminders.
  final ReminderScheduler? scheduler;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;
  ClaimsFilter _listFilter = ClaimsFilter.all;

  /// Status-chip selection active in the claims list (null = the group filter
  /// [_listFilter] applies). Remembered here alongside the group filter so a
  /// remount — returning from details, any data refresh — restores exactly
  /// what the user had selected instead of resetting to "all".
  String? _listStatus;

  /// Customers tab selection, kept across remounts like the list filter.
  String? _customer;
  String? _customerStatus;

  /// Bumped after every data mutation. IndexedStack keeps all destinations
  /// alive, so without a remount they would keep showing stale SQLite data —
  /// baking [gen] into each destination's key forces a fresh load (spec §5–§6).
  int _gen = 0;

  // Not `final`: re-pointed in [didUpdateWidget] when the live database is
  // swapped after a restore (see there).
  late ClaimsRepository _claims;
  late DashboardService _dashboard;

  /// Reminder scheduling seam (spec §10) — production default, fake-injectable.
  ReminderScheduler get _scheduler =>
      widget.scheduler ?? NotificationService.instance;

  @override
  void initState() {
    super.initState();
    _claims = ClaimsRepository(widget.db);
    _dashboard = DashboardService(_claims);
    HomeShell.openClaimFromNotification = _openClaim;
  }

  /// The live database handle is swapped after a successful restore: the old
  /// one was closed during `BackupService.restoreFrom`'s swap and [widget.db]
  /// now points at a fresh instance (spec §15). Without this, every cached
  /// repository would keep querying the CLOSED pre-restore database — observed
  /// on device as unhandled `DatabaseException(error database_closed)` in the
  /// dashboard/claims-list loads right after a restore. Re-pointing here keeps
  /// all destinations (and the FAB's `_claims.create`) on the live handle; the
  /// shell's own key-bump refresh then remounts them against fresh data.
  @override
  void didUpdateWidget(covariant HomeShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(widget.db, oldWidget.db)) {
      _claims = ClaimsRepository(widget.db);
      _dashboard = DashboardService(_claims);
    }
  }

  @override
  void dispose() {
    // Clear only if still ours — a newer shell may have replaced it.
    if (identical(HomeShell.openClaimFromNotification, _openClaim)) {
      HomeShell.openClaimFromNotification = null;
    }
    super.dispose();
  }

  void _bump() => setState(() => _gen++);

  /// Opens the claim details screen and refreshes every destination on return
  /// (an edit or delete may have happened — spec §11).
  Future<void> _openClaim(int claimId) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ClaimDetailsScreen(db: widget.db, claimId: claimId),
      ),
    );
    if (!mounted) return;
    _bump();
  }

  /// Dashboard metric tile → claims list pre-filtered to that metric (spec §5):
  /// group tiles pass their [ClaimsFilter]; the "Awaiting Approval" status
  /// tile passes its status key as a selected status chip.
  void _onMetricTapped(ClaimsFilter filter, String? status) {
    setState(() {
      _listFilter = filter;
      _listStatus = status;
      _index = 1;
    });
  }

  /// The claims list reports its active selection (group chip or status chip)
  /// so the shell can restore it on every remount. Without this, returning
  /// from the details screen — which bumps [_gen] and remounts the list —
  /// silently reset a user-selected filter back to "all".
  void _onListSelectionChanged(ClaimsFilter filter, String? status) {
    if (_listFilter == filter && _listStatus == status) return;
    setState(() {
      _listFilter = filter;
      _listStatus = status;
    });
  }

  Future<void> _addClaim() async {
    final Map<String, String> customers = await _claims.customers();
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ClaimFormScreen(
          customers: customers,
          // A follow-up picked on the form is a REAL reminder (spec §10):
          // after the claim row exists, persist its enabled reminder and
          // schedule the OS alarm — same permission-aware flow as the details
          // screen. The in-app state persists regardless of OS permission;
          // only the scheduling depends on it (failures are surfaced).
          onSaved: (Claim c) async {
            final DateTime? when = c.nextFollowUpUtcMs;
            final int id = await _claims.create(c);
            if (when != null && mounted) {
              await scheduleFollowUpOnCreate(
                context,
                widget.db,
                _scheduler,
                id,
                when,
              );
            }
          },
        ),
      ),
    );
    if (!mounted) return;
    // The form only closes after its onSaved persist completed — refresh all.
    _bump();
  }

  /// Claims-list card actions: the same flows as the details screen, without
  /// opening the claim. Each one refreshes every destination afterwards.
  Future<void> _cardChangeStatus(Claim claim) => showChangeStatusDialog(
    context,
    claim: claim,
    onSave: (StatusChangeRequest request) async {
      await ClaimActions(widget.db, NotificationService.instance).changeStatus(
        claim.id,
        request.statusKey,
        note: request.note,
        followUp: request.followUp,
      );
      if (mounted) _bump();
    },
  );

  Future<void> _cardEdit(Claim claim) async {
    final Map<String, String> customers = await _claims.customers();
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ClaimFormScreen(
          claim: claim,
          customers: customers,
          onSaved: (Claim saved) async {
            await _claims.update(saved);
            if (!mounted) return;
            // Keep the reminder in sync with the saved follow-up (spec §10):
            // reschedule when it changed, cancel + clear when removed —
            // otherwise an edit would leave a stale alarm at the old time.
            await syncFollowUpAfterEdit(
              context,
              widget.db,
              _scheduler,
              before: claim,
              saved: saved,
            );
          },
        ),
      ),
    );
    if (mounted) _bump();
  }

  /// Bulk delete of the claims list's selection-mode selection: the list
  /// screen already showed its count-aware confirmation, so this only runs the
  /// deletion (same per-claim guarantees as [_cardDelete] — alarms cancelled,
  /// attachment files removed best-effort, rows deleted last) and refreshes.
  Future<void> _bulkDelete(List<Claim> claims) async {
    if (claims.isEmpty) return;
    AttachmentFileService? files;
    try {
      files = AttachmentFileService(
        baseDir: await const AttachmentFileService().storeDir(),
      );
    } on Object catch (_) {
      files = null;
    }
    final List<int> ids = <int>[for (final Claim c in claims) c.id];
    await ClaimActions(
      widget.db,
      NotificationService.instance,
      files: files,
    ).deleteClaims(ids);
    if (mounted) _bump();
  }

  Future<void> _cardDelete(Claim claim) async {
    if (!await confirmDeleteClaim(context)) return;
    // Resolve the attachment store so the claim's files are removed too; if
    // it cannot be resolved the claim is still deleted (spec §12).
    AttachmentFileService? files;
    try {
      files = AttachmentFileService(
        baseDir: await const AttachmentFileService().storeDir(),
      );
    } on Object catch (_) {
      files = null;
    }
    await ClaimActions(
      widget.db,
      NotificationService.instance,
      files: files,
    ).deleteClaim(claim.id);
    if (mounted) _bump();
  }

  @override
  Widget build(BuildContext context) {
    final bool showFab = _index == 0 || _index == 1;
    return Scaffold(
      body: SafeArea(
        child: IndexedStack(
          index: _index,
          children: <Widget>[
            DashboardScreen(
              key: ValueKey('dash-$_gen'),
              service: _dashboard,
              onMetricTapped: _onMetricTapped,
              onClaimTapped: _openClaim,
            ),
            ClaimsListScreen(
              // Key carries only the generation counter: a data refresh (bump)
              // remounts this screen for a fresh load, and initState restores
              // the selection below. Chip taps must NOT change the key — that
              // would remount and drop local state like the search box;
              // external changes instead arrive through didUpdateWidget.
              key: ValueKey('claims-$_gen'),
              repo: _claims,
              initialFilter: _listFilter,
              initialStatus: _listStatus,
              onSelectionChanged: _onListSelectionChanged,
              onClaimTapped: (Claim c) => _openClaim(c.id),
              onChangeStatus: _cardChangeStatus,
              onEdit: _cardEdit,
              onDelete: _cardDelete,
              onBulkDelete: _bulkDelete,
            ),
            CustomersScreen(
              key: ValueKey('customers-$_gen'),
              repo: _claims,
              initialCustomer: _customer,
              initialStatus: _customerStatus,
              onSelectionChanged: (String? customer, String? status) {
                _customer = customer;
                _customerStatus = status;
              },
              onClaimTapped: (Claim c) => _openClaim(c.id),
            ),
            SettingsScreen(
              settingsRepo: widget.settingsRepo,
              currentThemeMode: widget.currentThemeMode,
              onThemeChanged: widget.onThemeChanged,
              currentLanguageCode: widget.currentLanguageCode,
              onLanguageChanged: widget.onLanguageChanged,
              backupService: widget.backupService,
              csvService: widget.csvService,
              reconnectAfterRestore: widget.reconnectAfterRestore,
              // Refresh every destination after a restore (IndexedStack keeps
              // them alive — the _gen bump forces fresh loads).
              onDataRestored: _bump,
            ),
          ],
        ),
      ),
      floatingActionButton: showFab
          ? FloatingActionButton.extended(
              onPressed: _addClaim,
              icon: const Icon(Icons.add_rounded, size: 26),
              label: Text(S.addClaim),
            )
          : null,
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (int i) => setState(() => _index = i),
        destinations: <NavigationDestination>[
          NavigationDestination(
            icon: const Icon(Icons.space_dashboard_outlined),
            selectedIcon: const Icon(Icons.space_dashboard_rounded),
            label: S.navDashboard,
          ),
          NavigationDestination(
            icon: const Icon(Icons.car_crash_outlined),
            selectedIcon: const Icon(Icons.car_crash_rounded),
            label: S.navClaims,
          ),
          NavigationDestination(
            icon: const Icon(Icons.groups_outlined),
            selectedIcon: const Icon(Icons.groups_rounded),
            label: S.navCustomers,
          ),
          NavigationDestination(
            icon: const Icon(Icons.tune_outlined),
            selectedIcon: const Icon(Icons.tune_rounded),
            label: S.navSettings,
          ),
        ],
      ),
    );
  }
}
