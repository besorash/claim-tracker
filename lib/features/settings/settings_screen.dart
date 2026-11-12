/// Settings screen (spec §16): theme selection persisted in SQLite, live
/// `onThemeChanged` callback for the app shell, read-only notifications
/// status and about/version card. No non-functional controls (spec §3.3).
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';

import 'package:claim_tracker/core/constants/app_constants.dart';
import 'package:claim_tracker/core/database/settings_repository.dart';
import 'package:claim_tracker/core/l10n/app_strings.dart';
import 'package:claim_tracker/core/notifications/notification_service.dart';
import 'package:claim_tracker/core/notifications/reminder_scheduler.dart';
import 'package:claim_tracker/core/security/backup_crypto.dart';
import 'package:claim_tracker/core/security/backup_service.dart';
import 'package:claim_tracker/core/theme/app_theme.dart';
import 'package:claim_tracker/features/settings/restore_source_seam.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({
    super.key,
    required this.settingsRepo,
    required this.currentThemeMode,
    required this.onThemeChanged,
    this.currentLanguageCode = 'en',
    this.onLanguageChanged,
    this.backupService,
    this.saveArchive,
    this.pickRestoreSource,
    this.reconnectAfterRestore,
    this.onDataRestored,
    this.notifications,
  });

  final SettingsRepository settingsRepo;
  final ThemeMode currentThemeMode;

  /// Called after the selection is persisted — the shell uses it to switch
  /// the live theme without a restart.
  final ValueChanged<ThemeMode> onThemeChanged;

  /// Active UI language code (`en` default / `ar`) for the language card's
  /// selected state. Null/absent in tests that don't exercise switching.
  final String currentLanguageCode;

  /// Called after a language is picked — the app persists it and rebuilds
  /// around the new locale (layout direction flips with it).
  final ValueChanged<String>? onLanguageChanged;

  /// Backup engine (spec §15). When null the backup card is hidden entirely —
  /// no dead buttons (spec §3.3). Production always provides one.
  final BackupService? backupService;

  /// OS save-file seam for export: receives the finished encrypted archive
  /// bytes and returns where they were written (null = canceled/failed).
  /// Defaults to `FilePicker.saveFile`; widget tests inject a temp-dir writer.
  final Future<Uri?> Function(Uint8List archive)? saveArchive;

  /// OS file-picker seam for restore: returns the chosen backup file
  /// (null = canceled). Defaults to `FilePicker.pickFile`.
  final Future<File?> Function()? pickRestoreSource;

  /// Reconnects the app to the freshly-restored database. `restoreFrom`
  /// closes the live DB handle during its swap, so production passes a hook
  /// that reopens via `AppDatabase.open()` and rebuilds the shell around it —
  /// without this every repository would keep pointing at a closed file
  /// (spec §15: "the caller reopens through AppDatabase.open()").
  final Future<void> Function()? reconnectAfterRestore;

  /// Fired after a successful restore so the shell can refresh every
  /// destination (IndexedStack staleness rule from Phase 2).
  final VoidCallback? onDataRestored;

  /// Notification permission seam (spec §10). Defaults to the production
  /// [NotificationService] singleton; widget tests inject a recording fake so
  /// no method channels are touched on the host.
  final ReminderScheduler? notifications;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  static const Map<String, ThemeMode> _modes = <String, ThemeMode>{
    'light': ThemeMode.light,
    'dark': ThemeMode.dark,
    'system': ThemeMode.system,
  };

  String _selected = 'system';
  bool _notificationsEnabled = false;

  // Phase 1 fix #1/#4 — exact-alarm + battery-optimization state.
  bool? _exactAlarmsAllowed;
  bool? _batteryExempt;

  /// One-shot result line for the backup card (success/failure, Arabic).
  String? _message;

  /// True while an export/restore is running in a background isolate — both
  /// backup buttons are disabled and a small progress indicator is shown so
  /// the user sees work is happening instead of a frozen UI.
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _selected = switch (widget.currentThemeMode) {
      ThemeMode.light => 'light',
      ThemeMode.dark => 'dark',
      ThemeMode.system => 'system',
    };
    _loadStored();
  }

  Future<void> _loadStored() async {
    // Persisted selection wins over the live mode (spec §16).
    try {
      final String? stored = await widget.settingsRepo.get(
        AppConstants.settingThemeMode,
      );
      if (stored != null && _modes.containsKey(stored) && mounted) {
        setState(() => _selected = stored);
      }
    } catch (_) {
      // Keep the live mode on read failure — never crash settings.
    }

    bool enabled = false;
    try {
      enabled = await _notifications.areNotificationsEnabled();
    } catch (_) {
      enabled = false;
    }

    // Phase 1 fix #1/#4 — load the exact-alarm and battery states (best-effort:
    // a missing channel simply leaves them null → no status row shown).
    // These are Android-only concepts: on iOS both stay null so the rows are
    // hidden instead of showing controls that do nothing.
    final bool androidAlarmControls =
        defaultTargetPlatform != TargetPlatform.iOS;
    bool? exactOk;
    bool? exempt;
    if (androidAlarmControls) {
      try {
        exactOk = await _notifications.canScheduleExactAlarms();
      } catch (_) {}
      try {
        exempt = await _notifications.isIgnoringBatteryOptimizations();
      } catch (_) {}
    }

    if (mounted) {
      setState(() {
        _notificationsEnabled = enabled;
        _exactAlarmsAllowed = exactOk;
        _batteryExempt = exempt;
      });
    }
  }

  /// Phase 1 fix #1 — request the exact-alarm permission, then refresh state.
  Future<void> _requestExactAlarms() async {
    await _notifications.requestExactAlarmsPermission();
    if (!mounted) return;
    bool? ok;
    try {
      ok = await _notifications.canScheduleExactAlarms();
    } catch (_) {}
    setState(() => _exactAlarmsAllowed = ok);
  }

  /// Phase 1 fix #4 — show the system battery-optimization request, then
  /// refresh state (the dialog is modal; re-query on return).
  Future<void> _requestBatteryExemption() async {
    await _notifications.requestIgnoreBatteryOptimizations();
    if (!mounted) return;
    bool? exempt;
    try {
      exempt = await _notifications.isIgnoringBatteryOptimizations();
    } catch (_) {}
    setState(() => _batteryExempt = exempt);
  }

  Future<void> _select(String mode) async {
    if (!_modes.containsKey(mode)) return;
    setState(() => _selected = mode);
    try {
      await widget.settingsRepo.set(AppConstants.settingThemeMode, mode);
    } catch (_) {
      // Persistence failure must not block the live theme switch.
    }
    final ThemeMode? next = _modes[mode];
    if (next != null && mounted) {
      widget.onThemeChanged(next);
    }
  }

  // ---------------------------------------------------------------------------
  // Backup & restore (spec §15). The passphrase is user-supplied per operation
  // and used in memory only — never persisted, never logged.
  // ---------------------------------------------------------------------------

  Future<void> _exportBackup() async {
    final BackupService? svc = widget.backupService;
    if (svc == null) return;

    final String? first = await _passphraseDialog(S.backupPassphraseTitle);
    if (!mounted || first == null) return;
    final String? second = await _passphraseDialog(
      S.backupPassphraseConfirmTitle,
    );
    if (!mounted || second == null) return;
    if (first != second) {
      // Blocked before any archive is built — nothing is written.
      setState(() => _message = S.backupPassphraseMismatch);
      return;
    }

    Uint8List archive;
    try {
      // Heavy crypto + file I/O runs off the UI isolate inside buildArchive —
      // show a busy state so both backup buttons are inert meanwhile.
      if (mounted) setState(() => _busy = true);
      archive = await svc.buildArchive(first);
    } on Object catch (_) {
      // Archive build failed (e.g. DB read error) — report it explicitly and
      // never claim an export that was not produced (spec §15).
      if (!mounted) return;
      setState(() => _message = S.backupExportFailed);
      return;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    Future<Uri?> Function(Uint8List) save =
        widget.saveArchive ?? _defaultSaveArchive;
    Uri? destination;
    try {
      destination = await save(archive);
    } on Object catch (_) {
      destination = null; // picker failure — treat as "not saved"
    }
    if (!mounted) return;
    setState(
      () => _message = destination == null
          ? S.backupExportFailed
          : S.backupExportedOk,
    );
  }

  Future<void> _restoreBackup() async {
    final BackupService? svc = widget.backupService;
    if (svc == null) return;

    Future<File?> Function() pick =
        widget.pickRestoreSource ?? _defaultPickRestoreSource;
    File? source;
    try {
      source = await pick();
    } on Object catch (_) {
      source = null; // picker failure — nothing to restore from
    }
    if (!mounted || source == null) return; // user canceled

    final bool confirmed =
        await showDialog<bool>(
          context: context,
          builder: (BuildContext ctx) => AlertDialog(
            title: Text(S.restoreWarningTitle),
            content: Text(S.restoreWarningBody),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: Text(S.cancel),
              ),
              FilledButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                child: Text(S.confirm),
              ),
            ],
          ),
        ) ??
        false;
    if (!mounted || !confirmed) return;

    final String? passphrase = await _passphraseDialog(S.backupPassphraseTitle);
    if (!mounted || passphrase == null) return;

    RestoreReport report;
    try {
      // restoreFrom validates (MAC + integrity + files) BEFORE any mutation,
      // so every failure path below leaves the current data untouched. The
      // decrypt runs in a background isolate — keep the UI busy meanwhile.
      if (mounted) setState(() => _busy = true);
      report = await svc.restoreFrom(source, passphrase);
    } on WrongPassphraseError {
      if (mounted) setState(() => _message = S.backupFailedWrongPassphrase);
      return;
    } on BackupError {
      if (mounted) setState(() => _message = S.backupFailedCorrupt);
      return;
    } on Object catch (_) {
      if (mounted) setState(() => _message = S.backupRestoreFailed);
      return;
    } finally {
      if (mounted) setState(() => _busy = false);
    }

    // The swap closed the live DB handle — reconnect BEFORE refreshing any
    // destination, or their repositories would read a closed file.
    final Future<void> Function()? reconnect = widget.reconnectAfterRestore;
    if (reconnect != null) {
      try {
        await reconnect();
      } on Object catch (_) {
        // Reopen failed — the data is already swapped in place, so report it
        // as a restore failure rather than claiming success.
        if (mounted) setState(() => _message = S.backupRestoreFailed);
        return;
      }
    }

    widget.onDataRestored?.call(); // shell refreshes all destinations
    if (!mounted) return;
    setState(
      () => _message = S.restoredOk(report.claims, report.attachmentsRestored),
    );
  }

  /// Single obscured passphrase entry dialog. Returns the entered text, or
  /// null when canceled. The value is used in memory only (spec §15: never
  /// invent or store a backup password).
  Future<String?> _passphraseDialog(String title) {
    return showDialog<String>(
      context: context,
      builder: (_) => _PassphraseDialog(title: title),
    );
  }

  /// Production save seam (spec §15): hands the finished archive bytes to the
  /// OS save-file dialog, which writes them where the user chooses — this app
  /// never picks a shared/public path itself.
  static Future<Uri?> _defaultSaveArchive(Uint8List archive) {
    return FilePicker.saveFile(
      fileName: 'claim-tracker-backup.ctbk',
      bytes: archive,
      mimeType: 'application/octet-stream',
      dialogTitle: S.backupExportTitle,
    );
  }

  /// Production restore seam: pick an existing backup file from the OS picker.
  /// BUG C fix lives in [backupFileFromPicked] — it reads via the byte stream
  /// (works for `content://` SAF URIs where `PlatformFile.path` is null) and
  /// materializes a local temp file instead of trusting `picked.path`.
  static Future<File?> _defaultPickRestoreSource() async {
    final PlatformFile? picked = await FilePicker.pickFile(
      dialogTitle: S.backupRestoreTitle,
    );
    return backupFileFromPicked(picked);
  }

  /// Notification seam — production singleton by default (spec §10).
  ReminderScheduler get _notifications =>
      widget.notifications ?? NotificationService.instance;

  /// BUG B fix: explicit permission acquisition path. On Android 13+ the
  /// POST_NOTIFICATIONS permission starts DENIED and there was no way to
  /// request it outside the reminder-save flow — so reminders saved while
  /// denied never produced an OS alarm. This button requests the permission,
  /// then refreshes the status line from the real device state (spec §10).
  Future<void> _requestNotificationPermission() async {
    await _notifications.requestNotificationsPermission();
    if (!mounted) return;
    bool enabled = false;
    try {
      enabled = await _notifications.areNotificationsEnabled();
    } catch (_) {
      enabled = false;
    }
    setState(() => _notificationsEnabled = enabled);
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(S.navSettings)),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            _card(theme, S.settingsTheme, <Widget>[
              for (final MapEntry<String, String> entry in <String, String>{
                'light': S.themeLight,
                'dark': S.themeDark,
                'system': S.themeSystem,
              }.entries)
                _themeRow(theme, entry.key, entry.value),
            ]),
            const SizedBox(height: 12),
            // Language (bilingual EN/AR — English is the default). Switching
            // rebuilds the whole app around the new locale; RTL follows `ar`.
            if (widget.onLanguageChanged != null) ...<Widget>[
              _card(theme, S.settingsLanguage, <Widget>[
                _languageRow(
                  theme,
                  code: 'en',
                  label: S.languageEnglish,
                  selected: widget.currentLanguageCode == 'en',
                ),
                _languageRow(
                  theme,
                  code: 'ar',
                  label: S.languageArabic,
                  selected: widget.currentLanguageCode == 'ar',
                ),
              ]),
              const SizedBox(height: 12),
            ],
            _card(theme, S.settingsNotifications, <Widget>[
              Text(
                _notificationsEnabled
                    ? S.notificationsStatusEnabled
                    : S.notificationsStatusDisabled,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: AppTheme.muted(context),
                ),
              ),
              if (!_notificationsEnabled) ...<Widget>[
                const SizedBox(height: 8),
                FilledButton.icon(
                  key: const Key('request-notifications'),
                  onPressed: _requestNotificationPermission,
                  icon: const Icon(Icons.notifications_active_outlined),
                  label: Text(S.notificationsRequestAction),
                ),
              ],
              // Phase 1 fix #1 — exact-alarm status row + request button.
              if (_exactAlarmsAllowed != null) ...<Widget>[
                const SizedBox(height: 8),
                Text(
                  _exactAlarmsAllowed!
                      ? S.exactAlarmsStatusGranted
                      : S.exactAlarmsStatusDenied,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: AppTheme.muted(context),
                  ),
                ),
                if (!_exactAlarmsAllowed!) ...<Widget>[
                  const SizedBox(height: 8),
                  FilledButton.icon(
                    key: const Key('request-exact-alarms'),
                    onPressed: _requestExactAlarms,
                    icon: const Icon(Icons.access_alarm_outlined),
                    label: Text(S.exactAlarmsRequestAction),
                  ),
                ],
              ],
              // Phase 1 fix #4 — battery-optimization status row + request.
              if (_batteryExempt != null) ...<Widget>[
                const SizedBox(height: 8),
                Text(
                  _batteryExempt!
                      ? S.batteryStatusExempt
                      : S.batteryStatusNotExempt,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: AppTheme.muted(context),
                  ),
                ),
                if (!_batteryExempt!) ...<Widget>[
                  const SizedBox(height: 8),
                  FilledButton.icon(
                    key: const Key('request-battery-exemption'),
                    onPressed: _requestBatteryExemption,
                    icon: const Icon(Icons.battery_charging_full),
                    label: Text(S.batteryRequestAction),
                  ),
                ],
              ],
            ]),
            if (widget.backupService != null) ...<Widget>[
              const SizedBox(height: 12),
              _card(theme, S.settingsBackupRestore, <Widget>[
                FilledButton.icon(
                  key: const Key('backup-export'),
                  onPressed: _busy ? null : _exportBackup,
                  icon: const Icon(Icons.file_download_outlined),
                  label: Text(S.backupExportAction),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  key: const Key('backup-restore'),
                  onPressed: _busy ? null : _restoreBackup,
                  icon: const Icon(Icons.restore_outlined),
                  label: Text(S.backupRestoreAction),
                ),
                if (_busy) ...<Widget>[
                  const SizedBox(height: 10),
                  Row(
                    children: <Widget>[
                      SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        S.backupWorking,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: AppTheme.muted(context),
                        ),
                      ),
                    ],
                  ),
                ],
                if (_message != null) ...<Widget>[
                  const SizedBox(height: 10),
                  Text(
                    _message!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: AppTheme.muted(context),
                    ),
                  ),
                ],
              ]),
            ],
            const SizedBox(height: 12),
            _card(theme, S.securityInfoTitle, <Widget>[
              Text(S.securityInfoBody),
            ], cardKey: const Key('security-info')),
            const SizedBox(height: 12),
            _card(theme, S.settingsAbout, <Widget>[
              Text(S.appName, style: theme.textTheme.titleMedium),
              const SizedBox(height: 4),
              Text(
                S.appVersion(
                  AppConstants.appVersionLabel,
                  AppConstants.appBuildLabel,
                ),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: AppTheme.muted(context),
                ),
              ),
            ]),
          ],
        ),
      ),
    );
  }

  Widget _card(
    ThemeData theme,
    String title,
    List<Widget> children, {
    Key? cardKey,
  }) {
    return Card(
      key: cardKey,
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              title,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            ...children,
          ],
        ),
      ),
    );
  }

  /// Language selection row — same visual contract as [_themeRow].
  Widget _languageRow(
    ThemeData theme, {
    required String code,
    required String label,
    required bool selected,
  }) {
    return InkWell(
      key: Key('lang-$code'),
      onTap: () => widget.onLanguageChanged?.call(code),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
        child: Row(
          children: <Widget>[
            Expanded(child: Text(label)),
            if (selected)
              Icon(
                Icons.check_circle,
                key: Key('lang-$code-selected'),
                color: AppColors.teal,
              ),
          ],
        ),
      ),
    );
  }

  Widget _themeRow(ThemeData theme, String mode, String label) {
    final bool selected = _selected == mode;
    return InkWell(
      key: Key('theme-$mode'),
      onTap: () => _select(mode),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
        child: Row(
          children: <Widget>[
            Expanded(child: Text(label)),
            if (selected)
              Icon(
                Icons.check_circle,
                key: Key('theme-$mode-selected'),
                color: AppColors.teal,
              ),
          ],
        ),
      ),
    );
  }
}

/// Passphrase entry dialog (spec §15). Owns its [TextEditingController] for
/// the lifetime of the widget — created in `initState`, disposed in this
/// widget's own `dispose()`. That is what fixes the "used after being
/// disposed" crash: previously the controller was disposed by the caller as
/// soon as `showDialog` returned, while the dialog's exit animation was still
/// running and the TextField still referenced it.
class _PassphraseDialog extends StatefulWidget {
  const _PassphraseDialog({required this.title});

  final String title;

  @override
  State<_PassphraseDialog> createState() => _PassphraseDialogState();
}

class _PassphraseDialogState extends State<_PassphraseDialog> {
  late final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        controller: _controller,
        obscureText: true,
        decoration: InputDecoration(hintText: S.backupPassphraseHint),
        onSubmitted: (String value) => Navigator.of(context).pop(value),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(S.cancel),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_controller.text),
          child: Text(S.confirm),
        ),
      ],
    );
  }
}
