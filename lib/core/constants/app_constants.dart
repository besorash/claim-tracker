/// Application-wide constants (MASTER_PROJECT_SPEC.md §2, §10, §15).
library;

abstract final class AppConstants {
  /// Default UI language — English is the main/default language (bilingual
  /// EN/AR per spec §3.4 update); Arabic remains fully supported and can be
  /// selected at runtime from Settings.
  static const String defaultLanguage = 'en';

  /// Default app time zone (spec §2: Asia/Riyadh).
  static const String timeZoneId = 'Asia/Riyadh';

  /// Currency used for monetary display (spec §2: SAR).
  static const String currencyCode = 'SAR';

  /// Backup file format version — bump on incompatible changes (spec §15).
  static const int backupFormatVersion = 1;

  /// Magic header identifying a Claim Tracker backup archive.
  static const List<int> backupMagic = [0x43, 0x54, 0x42, 0x4B]; // "CTBK"

  /// Notification channel id for claim reminders (spec §10). Channel name and
  /// description are localized at runtime via `S.reminderChannelName` /
  /// `S.reminderChannelDescription` (lib/l10n ARB files).
  static const String reminderChannelId = 'claim_reminders';

  /// Notification payload prefix used to route taps to a claim (spec §10).
  static const String payloadClaimPrefix = 'claim:';

  /// Version/build labels shown in the settings "about" card (spec §16).
  static const String appVersionLabel = '1.0.0';
  static const String appBuildLabel = '1';

  // app_settings keys.
  static const String settingThemeMode = 'theme_mode'; // light|dark|system
  static const String settingLanguage = 'language'; // en|ar (default: en)
}
