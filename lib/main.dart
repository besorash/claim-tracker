/// Claim Tracker — entry point.
///
/// Bilingual EN/AR with English as the default language (spec §3.4 update):
/// the UI language is a persisted preference, switchable at runtime from
/// Settings; Arabic automatically flips the layout to RTL. Light/Dark themes
/// with persisted preference (spec §3.2), local SQLite database, and the
/// notification foundation initialized at startup so reminders survive app
/// restarts (spec §10).
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:path_provider/path_provider.dart';

import 'app/home_shell.dart';
import 'core/l10n/app_strings.dart';
import 'l10n/app_localizations.dart';
import 'core/constants/app_constants.dart';
import 'core/database/app_database.dart';
import 'core/database/reminders_repository.dart';
import 'core/database/settings_repository.dart';
import 'core/models/reminder.dart';
import 'core/notifications/notification_service.dart';
import 'core/notifications/reminder_scheduler.dart';
import 'core/security/backup_service.dart';
import 'core/theme/app_theme.dart';
import 'features/attachments/attachment_file_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Time zone foundation (Asia/Riyadh) — spec §2, §10.
  final AppDatabase db = await AppDatabase.open();
  final SettingsRepository settings = SettingsRepository(db);
  final RemindersRepository reminders = RemindersRepository(db);

  // Attachment store + backup engine (spec §12/§15): the documents dir is
  // resolved once at startup so every screen and the BackupService share one
  // explicit baseDir (`<documents>/attachments`) — app-private storage only.
  final Directory documents = await getApplicationDocumentsDirectory();
  final AttachmentFileService files = AttachmentFileService(
    baseDir: Directory('${documents.path}/attachments'),
  );
  final BackupService backup = BackupService(db, files);

  // Notification foundation + reconcile pending reminders after restart
  // (spec §10: reconcile/reschedule after app restart). Reconciliation must
  // never block startup, so failures are swallowed.
  await NotificationService.instance.init();
  try {
    final List<Reminder> enabled = await reminders.allEnabled();
    await NotificationService.instance.reconcile(enabled);
  } catch (_) {
    // Non-critical: the app remains usable without rescheduled alarms.
  }

  // Route notification taps into the live shell (spec §10). The hook is null
  // until HomeShell mounts, so a tap before that simply no-ops safely.
  NotificationService.onClaimTapped = (int claimId) =>
      HomeShell.openClaimFromNotification?.call(claimId);

  // UI language (bilingual EN/AR — English default): load the persisted
  // preference BEFORE building so the very first frame is in the right
  // locale and direction. Failure falls back to the default (en).
  String language = AppConstants.defaultLanguage;
  try {
    final String? stored = await settings.get(AppConstants.settingLanguage);
    if (stored == 'ar' || stored == 'en') language = stored!;
  } catch (_) {}
  AppLocale.locale = Locale(language);

  runApp(
    ClaimTrackerApp(db: db, settings: settings, files: files, backup: backup),
  );
}

/// Reconciles the OS alarm set with [freshDb]'s enabled reminders after a
/// successful restore (spec §10/§15): stale alarms from deleted claims are
/// cancelled and restored future reminders rescheduled. Best-effort — a
/// failing scheduler must never break the post-restore flow, so errors are
/// swallowed (mirrors the startup reconciliation in [main]).
Future<void> reconcileRemindersAfterRestore(
  AppDatabase freshDb,
  ReminderScheduler scheduler,
) async {
  try {
    final List<Reminder> enabled = await RemindersRepository(freshDb)
        .allEnabled();
    await scheduler.reconcile(enabled);
  } catch (_) {
    // Non-critical: the app remains usable without rescheduled alarms.
  }
}

class ClaimTrackerApp extends StatefulWidget {
  const ClaimTrackerApp({
    super.key,
    required this.db,
    required this.settings,
    required this.files,
    required this.backup,
    this.scheduler,
  });

  final AppDatabase db;
  final SettingsRepository settings;
  final AttachmentFileService files;
  final BackupService backup;

  /// OS-side reminder scheduler used for post-restore reconciliation. Defaults
  /// to the production [NotificationService] singleton (spec §10).
  final ReminderScheduler? scheduler;

  @override
  State<ClaimTrackerApp> createState() => _ClaimTrackerAppState();
}

class _ClaimTrackerAppState extends State<ClaimTrackerApp> {
  ThemeMode _themeMode = ThemeMode.system;

  /// Active UI language (English default). Mirrors [AppLocale.locale] — the
  /// static is what context-free code (validators, TimeUtils, notifications)
  /// reads; this field drives the MaterialApp rebuild.
  Locale _locale = AppLocale.locale;

  /// Live database handle. A successful restore closes it during the swap, so
  /// [reconnectAfterRestore] reopens it and swaps these fields — every screen
  /// then rebuilds around the fresh instance (spec §15: "the caller reopens
  /// through AppDatabase.open()").
  late AppDatabase _db = widget.db;
  late SettingsRepository _settings = widget.settings;
  late AttachmentFileService _files = widget.files;
  late BackupService _backup = widget.backup;

  Future<void> reconnectAfterRestore() async {
    final AppDatabase fresh = await AppDatabase.open();
    if (!mounted) return;
    setState(() {
      _db = fresh;
      // The old settings repository wrapped the closed pre-restore handle —
      // swap it too, or theme persistence would silently fail after a restore.
      _settings = SettingsRepository(fresh);
      _files = AttachmentFileService(baseDir: _files.baseDir);
      _backup = BackupService(fresh, _files);
    });

    // Reconcile the OS alarm set with the restored database (spec §10/§15):
    // stale alarms from deleted claims are cancelled and restored future
    // reminders rescheduled — without this they would persist until the next
    // app start. Best-effort: a failure never breaks the post-restore flow.
    await reconcileRemindersAfterRestore(
      fresh,
      widget.scheduler ?? NotificationService.instance,
    );
  }

  @override
  void initState() {
    super.initState();
    _loadThemePreference();
  }

  Future<void> _loadThemePreference() async {
    final String? stored = await _settings.get(AppConstants.settingThemeMode);
    if (!mounted) return;
    setState(() {
      switch (stored) {
        case 'light':
          _themeMode = ThemeMode.light;
          break;
        case 'dark':
          _themeMode = ThemeMode.dark;
          break;
        default:
          _themeMode = ThemeMode.system;
      }
    });
  }

  /// Runtime language switch (bilingual EN/AR): persist the choice, update
  /// [AppLocale.locale] so context-free strings follow immediately, and
  /// rebuild the MaterialApp — layout direction flips with Arabic (RTL).
  Future<void> _onLanguageChanged(String code) async {
    if (code != 'en' && code != 'ar') return;
    try {
      await _settings.set(AppConstants.settingLanguage, code);
    } catch (_) {
      // Persistence failure must not block the live switch.
    }
    if (!mounted) return;
    setState(() {
      AppLocale.locale = Locale(code);
      _locale = Locale(code);
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Claim Tracker',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: _themeMode,
      // Bilingual EN/AR — English is the default; Arabic (when selected)
      // automatically drives RTL layout via its locale direction.
      locale: _locale,
      supportedLocales: const [Locale('en'), Locale('ar')],
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: HomeShell(
        db: _db,
        settingsRepo: _settings,
        currentThemeMode: _themeMode,
        onThemeChanged: (ThemeMode mode) {
          if (mode != _themeMode) setState(() => _themeMode = mode);
        },
        currentLanguageCode: _locale.languageCode,
        onLanguageChanged: _onLanguageChanged,
        backupService: _backup,
        reconnectAfterRestore: reconnectAfterRestore,
      ),
    );
  }
}
