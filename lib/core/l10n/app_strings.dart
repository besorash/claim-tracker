/// Centralized UI strings (spec §3.4 — bilingual EN/AR, English default).
///
/// Widgets and pure-Dart code reference these keys through the [S] facade —
/// no scattered literal text in widget or model code. The actual translations
/// live in `lib/l10n/app_en.arb` (template/default) and `app_ar.arb`, exposed
/// by the generated `AppLocalizations` (`flutter gen-l10n`, see l10n.yaml).
///
/// [S] resolves every key against [AppLocale.locale], so call sites that have
/// no `BuildContext` (validators, TimeUtils, notification text) stay correct
/// after a runtime language switch. Widget code may also use
/// `AppLocalizations.of(context)` directly when it prefers context lookup.
library;

import 'package:flutter/widgets.dart';

import '../../l10n/app_localizations.dart';

/// The app's current UI language (English by default). Set once at startup
/// from the persisted preference and again on every user switch — the whole
/// tree rebuilds around it, flipping layout direction with it (ar → RTL).
class AppLocale {
  AppLocale._();

  static Locale locale = const Locale('en');
}

abstract final class S {
  /// Current-locale table. `lookupAppLocalizations` is synchronous (the
  /// generated delegate wraps a plain lookup in a [SynchronousFuture]), so
  /// this is safe outside of widget builds too.
  static AppLocalizations get _l => lookupAppLocalizations(AppLocale.locale);

  // App / navigation.
  static String get appName => _l.appName;
  static String get navDashboard => _l.navDashboard;
  static String get navClaims => _l.navClaims;
  static String get navReminders => _l.navReminders;
  static String get navSettings => _l.navSettings;

  // Common actions.
  static String get addClaim => _l.addClaim;
  static String get edit => _l.edit;
  static String get noPlate => _l.noPlate;
  static String get vehicleTypeLabel => _l.vehicleTypeLabel;
  static String get sectionCustomerInfo => _l.sectionCustomerInfo;
  static String get sectionAccidentInfo => _l.sectionAccidentInfo;
  static String get sectionClaimInfo => _l.sectionClaimInfo;
  static String get insurerOther => _l.insurerOther;
  static String get insurerOtherLabel => _l.insurerOtherLabel;
  static String get save => _l.save;
  static String get cancel => _l.cancel;
  static String get delete => _l.delete;
  static String get close => _l.close;
  static String get confirm => _l.confirm;
  static String get search => _l.search;
  static String get retry => _l.retry;

  // Dashboard (spec §5).
  static String get dashTotalClaims => _l.dashTotalClaims;
  static String get dashOpenClaims => _l.dashOpenClaims;
  static String get dashClosedClaims => _l.dashClosedClaims;
  static String get dashDueToday => _l.dashDueToday;
  static String get dashOverdue => _l.dashOverdue;
  static String get dashNeedsAttention => _l.dashNeedsAttention;
  static String get dashRecentlyUpdated => _l.dashRecentlyUpdated;
  static String get dashEmpty => _l.dashEmpty;

  // Claims list (spec §6).
  static String get filterAll => _l.filterAll;
  static String get filterOpen => _l.filterOpen;
  static String get filterFollowUp => _l.filterFollowUp;
  static String get filterOverdue => _l.filterOverdue;
  static String get filterClosed => _l.filterClosed;
  static String get searchHint => _l.searchHint;
  static String get claimsEmpty => _l.claimsEmpty;

  /// Shown when a screen's initial load fails (e.g. the database handle was
  /// closed mid-load during a restore swap) — with a retry affordance.
  static String get loadFailed => _l.loadFailed;

  // Claim card / details (spec §6, §11).
  static String get claimNumberLabel => _l.claimNumberLabel;
  static String get customerNameLabel => _l.customerNameLabel;
  static String get mobileLabel => _l.mobileLabel;
  static String get nationalIdLabel => _l.nationalIdLabel;
  static String get emailLabel => _l.emailLabel;
  static String get accidentNumberLabel => _l.accidentNumberLabel;
  static String get accidentDateLabel => _l.accidentDateLabel;
  static String get cityLabel => _l.cityLabel;
  static String get accidentTypeLabel => _l.accidentTypeLabel;
  static String get vehiclePlateLabel => _l.vehiclePlateLabel;
  static String get customerInsurerLabel => _l.customerInsurerLabel;
  static String get liabilityPercentLabel => _l.liabilityPercentLabel;
  static String get liabilityNotSet => _l.liabilityNotSet;
  static String get csvCardTitle => _l.csvCardTitle;
  static String get csvExportAction => _l.csvExportAction;
  static String get csvImportAction => _l.csvImportAction;
  static String get csvExportedOk => _l.csvExportedOk;
  static String get csvExportFailed => _l.csvExportFailed;
  static String csvImportedOk(int created, int updated) =>
      _l.csvImportedOk(created, updated);
  static String get csvImportRejected => _l.csvImportRejected;
  static String get csvImportFailed => _l.csvImportFailed;
  static String get csvReminderWarning => _l.csvReminderWarning;
  static String get csvErrorEncoding => _l.csvErrorEncoding;
  static String get csvErrorMalformed => _l.csvErrorMalformed;
  static String get csvErrorMissingColumns => _l.csvErrorMissingColumns;
  static String get csvRowLabel => _l.csvRowLabel;
  static String get csvErrorBadId => _l.csvErrorBadId;
  static String get csvErrorUnknownId => _l.csvErrorUnknownId;
  static String get csvErrorDuplicateId => _l.csvErrorDuplicateId;
  static String get csvErrorAmount => _l.csvErrorAmount;
  static String get csvErrorLiability => _l.csvErrorLiability;
  static String get csvErrorDate => _l.csvErrorDate;
  static String get csvErrorStatus => _l.csvErrorStatus;
  static String csvImportUnchanged(int count) => _l.csvImportUnchanged(count);
  static String get csvNothingChanged => _l.csvNothingChanged;
  static String get csvNoRows => _l.csvNoRows;
  static String csvUnknownIdsAdded(int count) => _l.csvUnknownIdsAdded(count);
  static String get csvDatesMonthFirst => _l.csvDatesMonthFirst;
  static String csvExtraColumnsSaved(String columns) =>
      _l.csvExtraColumnsSaved(columns);
  static String get extraFieldsLabel => _l.extraFieldsLabel;
  static String get submissionDateLabel => _l.submissionDateLabel;
  static String get insurerRefLabel => _l.insurerRefLabel;
  static String get claimAmountLabel => _l.claimAmountLabel;
  static String get notesLabel => _l.notesLabel;
  static String get statusLabel => _l.statusLabel;
  static String get lastStatusUpdateLabel => _l.lastStatusUpdateLabel;
  static String get nextFollowUpLabel => _l.nextFollowUpLabel;
  static String get reminderEnabled => _l.reminderEnabled;
  static String get reminderDisabled => _l.reminderDisabled;
  static String get attachmentsLabel => _l.attachmentsLabel;
  static String get attachmentsEmpty => _l.attachmentsEmpty;
  static String get attachmentAdd => _l.attachmentAdd;
  static String get attachmentOpenFailed => _l.attachmentOpenFailed;
  static String get attachmentMissing => _l.attachmentMissing;
  static String get deleteAttachmentTitle => _l.deleteAttachmentTitle;
  static String get deleteAttachmentBody => _l.deleteAttachmentBody;
  static String get attachmentPickFailed => _l.attachmentPickFailed;
  static String get attachmentStoreError => _l.attachmentStoreError;
  static String get claimNotFound => _l.claimNotFound;
  static String get statusHistoryLabel => _l.statusHistoryLabel;
  static String get historyEmpty => _l.historyEmpty;

  // Status flow (spec §9).
  static String get changeStatus => _l.changeStatus;
  static String get changeStatusTitle => _l.changeStatusTitle;
  static String get statusNoteHint => _l.statusNoteHint;
  static String get setNextFollowUp => _l.setNextFollowUp;
  static String get keepExistingFollowUp => _l.keepExistingFollowUp;
  static String get clearFollowUp => _l.clearFollowUp;

  // Reminders (spec §10).
  static String get reminderTitle => _l.reminderTitle;
  static String get reminderWhenLabel => _l.reminderWhenLabel;
  static String get reminderSet => _l.reminderSet;
  static String get reminderDisable => _l.reminderDisable;
  static String get reminderRepeatLabel => _l.reminderRepeatLabel;
  static String get repeatNone => _l.repeatNone;
  static String repeatEveryHours(int n) => _l.repeatEveryHours(n);
  static String repeatEveryDays(int n) => _l.repeatEveryDays(n);
  static String get notificationsPermissionTitle =>
      _l.notificationsPermissionTitle;
  static String get notificationsPermissionBody =>
      _l.notificationsPermissionBody;
  static String get notificationsDeniedTitle => _l.notificationsDeniedTitle;
  static String get notificationsDeniedBody => _l.notificationsDeniedBody;

  // Validation (spec §7).
  static String get requiredField => _l.requiredField;
  static String get invalidNumber => _l.invalidNumber;
  static String get invalidDate => _l.invalidDate;
  static String get futureFollowUpRequired => _l.futureFollowUpRequired;

  // Delete / close confirmations (spec §11).
  static String get deleteClaimTitle => _l.deleteClaimTitle;
  static String get deleteClaimBody => _l.deleteClaimBody;
  static String get closeClaimTitle => _l.closeClaimTitle;
  static String get closeClaimBody => _l.closeClaimBody;

  // Settings (spec §16).
  static String get settingsTheme => _l.settingsTheme;
  static String get themeLight => _l.themeLight;
  static String get themeDark => _l.themeDark;
  static String get themeSystem => _l.themeSystem;
  static String get settingsLanguage => _l.settingsLanguage;
  static String get languageEnglish => _l.languageEnglish;
  static String get languageArabic => _l.languageArabic;
  static String get settingsNotifications => _l.settingsNotifications;
  static String get notificationsStatusEnabled => _l.notificationsStatusEnabled;
  static String get notificationsStatusDisabled =>
      _l.notificationsStatusDisabled;
  static String get exactAlarmHint => _l.exactAlarmHint;
  static String get notificationsRequestAction => _l.notificationsRequestAction;
  static String get notificationsOpenSettingsAction =>
      _l.notificationsOpenSettingsAction;

  // Exact alarms (Phase 1 fix #1).
  static String get exactAlarmsStatusGranted => _l.exactAlarmsStatusGranted;
  static String get exactAlarmsStatusDenied => _l.exactAlarmsStatusDenied;
  static String get exactAlarmsRequestAction => _l.exactAlarmsRequestAction;
  static String get exactAlarmExplainTitle => _l.exactAlarmExplainTitle;
  static String get exactAlarmExplainBody => _l.exactAlarmExplainBody;

  // Battery optimization (Phase 1 fix #4).
  static String get batteryStatusExempt => _l.batteryStatusExempt;
  static String get batteryStatusNotExempt => _l.batteryStatusNotExempt;
  static String get batteryRequestAction => _l.batteryRequestAction;
  static String get batteryExplainBody => _l.batteryExplainBody;

  // Scheduling failure / inexact warning (Phase 1 fix #3).
  static String get reminderScheduleFailed => _l.reminderScheduleFailed;
  static String get reminderInexactWarning => _l.reminderInexactWarning;
  static String get settingsBackupRestore => _l.settingsBackupRestore;
  static String get settingsAbout => _l.settingsAbout;
  static String appVersion(String version, String build) =>
      _l.appVersion(version, build);

  // Backup (spec §15).
  static String get backupExportTitle => _l.backupExportTitle;
  static String get backupRestoreTitle => _l.backupRestoreTitle;
  static String get backupPassphraseHint => _l.backupPassphraseHint;
  static String get backupExportAction => _l.backupExportAction;
  static String get backupRestoreAction => _l.backupRestoreAction;
  static String get backupPassphraseTitle => _l.backupPassphraseTitle;
  static String get backupPassphraseConfirmTitle =>
      _l.backupPassphraseConfirmTitle;
  static String get backupPassphraseMismatch => _l.backupPassphraseMismatch;
  static String get backupExportedOk => _l.backupExportedOk;

  /// Short busy label shown while an export/restore is running in the
  /// background isolate (spec §15 — UI must stay responsive).
  static String get backupWorking => _l.backupWorking;
  static String get restoreWarningTitle => _l.restoreWarningTitle;
  static String get restoreWarningBody => _l.restoreWarningBody;
  static String restoredOk(int claims, int attachments) =>
      _l.restoredOk(claims, attachments);
  static String get backupFailedWrongPassphrase =>
      _l.backupFailedWrongPassphrase;
  static String get backupFailedCorrupt => _l.backupFailedCorrupt;
  static String get backupExportFailed => _l.backupExportFailed;
  static String get backupRestoreFailed => _l.backupRestoreFailed;
  static String get securityInfoTitle => _l.securityInfoTitle;
  static String get securityInfoBody => _l.securityInfoBody;

  // Claim statuses (spec §8) — resolved by [ClaimStatusMeta.label].
  static String get statusNew => _l.statusNew;
  static String get statusSubmitted => _l.statusSubmitted;
  static String get statusAwaitingReview => _l.statusAwaitingReview;
  static String get statusAwaitingDocuments => _l.statusAwaitingDocuments;
  static String get statusProcessing => _l.statusProcessing;
  static String get statusAwaitingApproval => _l.statusAwaitingApproval;
  static String get statusApproved => _l.statusApproved;
  static String get statusCompensated => _l.statusCompensated;
  static String get statusRejected => _l.statusRejected;
  static String get statusClosed => _l.statusClosed;

  // Time / currency display (spec §2, §6).
  static String get followUpOverdue => _l.followUpOverdue;
  static String get followUpToday => _l.followUpToday;
  static String get currencySar => _l.currencySar;

  // OS notifications (spec §10) — resolved by [NotificationService].
  static String get reminderChannelName => _l.reminderChannelName;
  static String get reminderChannelDescription => _l.reminderChannelDescription;
  static String get genericReminderTitle => _l.genericReminderTitle;
  static String get genericReminderBody => _l.genericReminderBody;
}
