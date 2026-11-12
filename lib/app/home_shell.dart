/// App shell (spec §4): bottom navigation with the four primary destinations,
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
import '../features/attachments/attachment_file_service.dart';
import '../features/claims/claim_actions.dart';
import '../features/claims/claim_dialogs.dart';
import '../features/claims/claim_details_screen.dart';
import '../features/claims/claim_form_screen.dart';
import '../features/claims/claims_filter.dart';
import '../features/claims/claims_list_screen.dart';
import '../features/dashboard/dashboard_screen.dart';
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

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;
  ClaimsFilter _listFilter = ClaimsFilter.all;

  /// Bumped after every data mutation. IndexedStack keeps all destinations
  /// alive, so without a remount they would keep showing stale SQLite data —
  /// baking [gen] into each destination's key forces a fresh load (spec §5–§6).
  int _gen = 0;

  // Not `final`: re-pointed in [didUpdateWidget] when the live database is
  // swapped after a restore (see there).
  late ClaimsRepository _claims;
  late DashboardService _dashboard;

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

  /// Dashboard metric tile → claims list pre-filtered to that metric (spec §5).
  void _onMetricTapped(ClaimsFilter filter) {
    setState(() {
      _listFilter = filter;
      _index = 1;
    });
  }

  Future<void> _addClaim() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            ClaimFormScreen(onSaved: (Claim c) => _claims.create(c)),
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
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ClaimFormScreen(
          claim: claim,
          onSaved: (Claim saved) => _claims.update(saved),
        ),
      ),
    );
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
              // Key includes the filter so a metric-tap re-inits this screen
              // with the new initialFilter (IndexedStack would otherwise keep
              // the old instance and its old filter).
              key: ValueKey('claims-$_listFilter-$_gen'),
              repo: _claims,
              initialFilter: _listFilter,
              onClaimTapped: (Claim c) => _openClaim(c.id),
              onChangeStatus: _cardChangeStatus,
              onEdit: _cardEdit,
              onDelete: _cardDelete,
            ),
            // Reminders destination = the follow-up-filtered claims list — a
            // real, honest view of scheduled follow-ups (spec §3.3: no stubs).
            ClaimsListScreen(
              key: ValueKey('reminders-$_gen'),
              repo: _claims,
              initialFilter: ClaimsFilter.followUp,
              onClaimTapped: (Claim c) => _openClaim(c.id),
              onChangeStatus: _cardChangeStatus,
              onEdit: _cardEdit,
              onDelete: _cardDelete,
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
              icon: const Icon(Icons.add),
              label: Text(S.addClaim),
            )
          : null,
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (int i) => setState(() => _index = i),
        destinations: <NavigationDestination>[
          NavigationDestination(
            icon: Icon(Icons.dashboard_outlined),
            label: S.navDashboard,
          ),
          NavigationDestination(
            icon: Icon(Icons.folder_open_outlined),
            label: S.navClaims,
          ),
          NavigationDestination(
            icon: Icon(Icons.notifications_none_rounded),
            label: S.navReminders,
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            label: S.navSettings,
          ),
        ],
      ),
    );
  }
}
