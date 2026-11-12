// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appName => 'Claim Tracker';

  @override
  String get navDashboard => 'Dashboard';

  @override
  String get navClaims => 'Claims';

  @override
  String get navReminders => 'Follow-ups';

  @override
  String get navSettings => 'Settings';

  @override
  String get addClaim => 'Add Claim';

  @override
  String get edit => 'Edit';

  @override
  String get save => 'Save';

  @override
  String get cancel => 'Cancel';

  @override
  String get delete => 'Delete';

  @override
  String get close => 'Close';

  @override
  String get confirm => 'Confirm';

  @override
  String get search => 'Search';

  @override
  String get retry => 'Retry';

  @override
  String get dashTotalClaims => 'Total Claims';

  @override
  String get dashOpenClaims => 'Open Claims';

  @override
  String get dashClosedClaims => 'Finished Claims';

  @override
  String get dashDueToday => 'Follow-up Due Today';

  @override
  String get dashOverdue => 'Overdue Follow-ups';

  @override
  String get dashNeedsAttention => 'Needs Your Attention';

  @override
  String get dashRecentlyUpdated => 'Recently Updated Claims';

  @override
  String get dashEmpty => 'No claims yet. Start by adding your first claim.';

  @override
  String get filterAll => 'All';

  @override
  String get filterOpen => 'Open';

  @override
  String get filterFollowUp => 'Needs Follow-up';

  @override
  String get filterOverdue => 'Overdue';

  @override
  String get sortTooltip => 'Sort';

  @override
  String get sortDefault => 'Default order';

  @override
  String get sortSubmissionNewest => 'Submission date: newest first';

  @override
  String get sortSubmissionOldest => 'Submission date: oldest first';

  @override
  String get sortUpdatedNewest => 'Last update: newest first';

  @override
  String get sortUpdatedOldest => 'Last update: oldest first';

  @override
  String get lastUpdateLabel => 'Last update';

  @override
  String get filterClosed => 'Finished';

  @override
  String get searchHint => 'Search plate, name, claim number, vehicle…';

  @override
  String get claimsEmpty => 'No matching claims.';

  @override
  String get loadFailed =>
      'Couldn\'t load the data right now. Please try again.';

  @override
  String get claimNumberLabel => 'Claim Number';

  @override
  String get customerNameLabel => 'Customer Name';

  @override
  String get mobileLabel => 'Mobile Number';

  @override
  String get nationalIdLabel => 'National ID';

  @override
  String get emailLabel => 'Email Address';

  @override
  String get accidentNumberLabel => 'Accident Number';

  @override
  String get accidentDateLabel => 'Accident Date';

  @override
  String get cityLabel => 'City';

  @override
  String get accidentTypeLabel => 'Accident Type';

  @override
  String get noPlate => 'No plate';

  @override
  String get vehicleTypeLabel => 'Vehicle Type';

  @override
  String get sectionCustomerInfo => 'Customer Information';

  @override
  String get sectionAccidentInfo => 'Accident & Vehicle Information';

  @override
  String get sectionClaimInfo => 'Claim & Insurance Information';

  @override
  String get insurerOther => 'Other';

  @override
  String get insurerOtherLabel => 'Insurance company name';

  @override
  String get vehiclePlateLabel => 'Vehicle Plate';

  @override
  String get customerInsurerLabel => 'Customer\'s Insurance Company';

  @override
  String get liabilityPercentLabel => 'Liability %';

  @override
  String get liabilityNotSet => 'Not set';

  @override
  String get csvCardTitle => 'Spreadsheet (CSV)';

  @override
  String get csvExportAction => 'Export to spreadsheet (CSV)';

  @override
  String get csvImportAction => 'Import from spreadsheet (CSV)';

  @override
  String get csvExportedOk => 'Spreadsheet exported.';

  @override
  String get csvExportFailed => 'Could not export the spreadsheet.';

  @override
  String csvImportedOk(int created, int updated) {
    return 'Imported: $created new, $updated updated.';
  }

  @override
  String get csvImportRejected =>
      'Nothing was saved. Fix these rows in the file and import again:';

  @override
  String get csvImportFailed =>
      'The import stopped because of a database error. Some rows may have been saved.';

  @override
  String get csvReminderWarning =>
      'Some reminders could not be scheduled on this device.';

  @override
  String get csvErrorEncoding => 'Save the file as CSV UTF-8 and try again.';

  @override
  String get csvErrorMalformed =>
      'The file could not be read. Check the quotation marks.';

  @override
  String get csvErrorMissingColumns => 'Missing columns:';

  @override
  String get csvRowLabel => 'Row';

  @override
  String get csvErrorBadId => 'The id must be a whole number from the export.';

  @override
  String get csvErrorUnknownId => 'No claim with this id exists in the app.';

  @override
  String get csvErrorDuplicateId =>
      'This id appears more than once in the file.';

  @override
  String get csvErrorAmount => 'The amount must be a number.';

  @override
  String get csvErrorLiability =>
      'Liability % must be empty, 0, 25, 50, 75 or 100.';

  @override
  String get csvErrorDate =>
      'Unrecognized date. Use e.g. 2026-03-31 or 31/03/2026 (add 14:30 for a follow-up time).';

  @override
  String get csvErrorStatus =>
      'Unknown status. Use the status name shown in the app or its key.';

  @override
  String csvImportUnchanged(int count) {
    return '$count unchanged.';
  }

  @override
  String get csvNothingChanged =>
      'Nothing changed: the file matches what is already in the app. If you edited it in WPS or Excel, make sure you saved the file before importing it.';

  @override
  String csvUnknownIdsAdded(int count) {
    return '$count row(s) had an id not found in the app and were added as new claims.';
  }

  @override
  String get csvNoRows => 'The file has no claims in it.';

  @override
  String get csvDatesMonthFirst =>
      'Dates were read as month/day/year (11/4/2026 = 4 November 2026).';

  @override
  String csvExtraColumnsSaved(String columns) {
    return 'Extra columns saved with the claims: $columns';
  }

  @override
  String get extraFieldsLabel => 'Additional Fields';

  @override
  String get submissionDateLabel => 'Submission Date';

  @override
  String get insurerRefLabel => 'Insurer Reference Number';

  @override
  String get claimAmountLabel => 'Claim Amount (SAR)';

  @override
  String get notesLabel => 'Notes';

  @override
  String get statusLabel => 'Current Status';

  @override
  String get lastStatusUpdateLabel => 'Last Status Update';

  @override
  String get nextFollowUpLabel => 'Next Follow-up';

  @override
  String get reminderEnabled => 'Reminder Enabled';

  @override
  String get reminderDisabled => 'Reminder Disabled';

  @override
  String get attachmentsLabel => 'Attachments';

  @override
  String get attachmentsEmpty => 'No attachments yet.';

  @override
  String get attachmentAdd => 'Add Attachment';

  @override
  String get attachmentOpenFailed =>
      'Could not open the file. Your device may have no app that opens this type.';

  @override
  String get attachmentMissing => 'The file is missing on this device.';

  @override
  String get deleteAttachmentTitle => 'Delete attachment?';

  @override
  String get deleteAttachmentBody =>
      'The file will be permanently removed from the app\'s storage.';

  @override
  String get attachmentPickFailed => 'Could not open the file picker.';

  @override
  String get attachmentStoreError =>
      'Could not access the attachments storage.';

  @override
  String get claimNotFound =>
      'Claim not found. It may have been deleted elsewhere.';

  @override
  String get statusHistoryLabel => 'Status Change History';

  @override
  String get historyEmpty => 'No changes recorded yet.';

  @override
  String get changeStatus => 'Change Status';

  @override
  String get changeStatusTitle => 'Change Claim Status';

  @override
  String get statusNoteHint => 'Optional note about the change';

  @override
  String get setNextFollowUp => 'Set next follow-up date';

  @override
  String get keepExistingFollowUp => 'Keep current date';

  @override
  String get clearFollowUp => 'Clear date';

  @override
  String get reminderTitle => 'Claim Reminder';

  @override
  String get reminderWhenLabel => 'Reminder Time';

  @override
  String get reminderSet => 'Set reminder time';

  @override
  String get reminderDisable => 'Cancel reminder';

  @override
  String get reminderRepeatLabel => 'Repeat';

  @override
  String get repeatNone => 'Once';

  @override
  String repeatEveryHours(int n) {
    return 'Every $n hours';
  }

  @override
  String repeatEveryDays(int n) {
    return 'Every $n days';
  }

  @override
  String get notificationsPermissionTitle => 'Allow Notifications';

  @override
  String get notificationsPermissionBody =>
      'We need notification permission to remind you of claim follow-up times on schedule.';

  @override
  String get notificationsDeniedTitle => 'Notifications Off';

  @override
  String get notificationsDeniedBody =>
      'Enable app notifications in your device settings so follow-up reminders arrive on time.';

  @override
  String get requiredField => 'This field is required';

  @override
  String get invalidNumber => 'Enter a valid number';

  @override
  String get invalidDate => 'Enter a valid date';

  @override
  String get futureFollowUpRequired =>
      'The follow-up date must be in the future';

  @override
  String get deleteClaimTitle => 'Delete claim?';

  @override
  String get deleteClaimBody =>
      'The claim, its status history, reminders and attachments will be permanently deleted.';

  @override
  String get closeClaimTitle => 'Close claim?';

  @override
  String get closeClaimBody =>
      'Status will change to “Closed” and upcoming scheduled reminders will be cancelled.';

  @override
  String get settingsTheme => 'Appearance';

  @override
  String get themeLight => 'Light';

  @override
  String get themeDark => 'Dark';

  @override
  String get themeSystem => 'Follow System';

  @override
  String get settingsLanguage => 'Language';

  @override
  String get languageEnglish => 'English';

  @override
  String get languageArabic => 'العربية (Arabic)';

  @override
  String get settingsNotifications => 'Notifications & Reminders';

  @override
  String get notificationsStatusEnabled => 'Notifications enabled';

  @override
  String get notificationsStatusDisabled =>
      'Notifications disabled on this device';

  @override
  String get exactAlarmHint =>
      'Reminders may not arrive at the exact time if Exact Alarms are restricted on your device.';

  @override
  String get notificationsRequestAction => 'Request notification permission';

  @override
  String get notificationsOpenSettingsAction => 'Open notification settings';

  @override
  String get exactAlarmsStatusGranted =>
      'Exact alarms allowed — reminders arrive on time.';

  @override
  String get exactAlarmsStatusDenied =>
      'Exact alarms not allowed — reminders may be delayed.';

  @override
  String get exactAlarmsRequestAction => 'Allow exact alarms';

  @override
  String get exactAlarmExplainTitle => 'Exact Alarms';

  @override
  String get exactAlarmExplainBody =>
      'We need the exact-alarm permission so follow-up reminders arrive at their scheduled time, especially while the app is closed.';

  @override
  String get batteryStatusExempt =>
      'App exempt from battery optimization — reminders work even when the app is closed.';

  @override
  String get batteryStatusNotExempt =>
      'App not exempt from battery optimization — the battery policy may block reminders when the app is closed.';

  @override
  String get batteryRequestAction => 'Request exemption';

  @override
  String get batteryExplainBody =>
      'Some Android devices stop background apps to save battery, which blocks on-time reminders. Granting the exemption guarantees your reminder arrives even while the app is closed.';

  @override
  String get reminderScheduleFailed =>
      'The time was saved, but scheduling the system reminder failed. Try again or check notification permissions.';

  @override
  String get reminderInexactWarning =>
      'Exact alarms are not allowed — this reminder may arrive late. Enable the permission in settings so it arrives on time.';

  @override
  String get settingsBackupRestore => 'Backup & Restore';

  @override
  String get settingsAbout => 'About the App';

  @override
  String appVersion(String version, String build) {
    return 'Version $version (build $build)';
  }

  @override
  String get backupExportTitle => 'Backup';

  @override
  String get backupRestoreTitle => 'Restore Backup';

  @override
  String get backupPassphraseHint => 'Encryption passphrase for the backup';

  @override
  String get backupExportAction => 'Export encrypted backup';

  @override
  String get backupRestoreAction => 'Restore from backup';

  @override
  String get backupPassphraseTitle => 'Encryption Passphrase';

  @override
  String get backupPassphraseConfirmTitle => 'Confirm Passphrase';

  @override
  String get backupPassphraseMismatch => 'The passphrases do not match';

  @override
  String get backupExportedOk => 'Backup created successfully.';

  @override
  String get backupWorking => 'Working…';

  @override
  String get restoreWarningTitle => 'Replace current data?';

  @override
  String get restoreWarningBody =>
      'This replaces all current claims and attachments with the backup\'s contents. This cannot be undone after confirming.';

  @override
  String restoredOk(int claims, int attachments) {
    return 'Restored: $claims claim(s) and $attachments attachment(s).';
  }

  @override
  String get backupFailedWrongPassphrase =>
      'The passphrase is wrong or the backup is corrupt. Your current data was not modified.';

  @override
  String get backupFailedCorrupt =>
      'The backup is corrupt or incompatible with this version. Your current data was not modified.';

  @override
  String get backupExportFailed => 'Could not create the backup.';

  @override
  String get backupRestoreFailed =>
      'Restore failed. Your current data was not modified.';

  @override
  String get securityInfoTitle => 'Privacy & Security';

  @override
  String get securityInfoBody =>
      'All data is stored locally on your device only — nothing is sent over a network or used for analytics. Backups are encrypted with your passphrase (PBKDF2 + AES-256). Before entering real data, make sure local storage complies with your employer\'s policies and Saudi PDPL privacy requirements where applicable.';

  @override
  String get statusNew => 'New';

  @override
  String get statusSubmitted => 'Claim Submitted';

  @override
  String get statusAwaitingReview => 'Awaiting Review';

  @override
  String get statusAwaitingDocuments => 'Awaiting Documents';

  @override
  String get statusProcessing => 'In Processing';

  @override
  String get statusAwaitingApproval => 'Awaiting Approval';

  @override
  String get statusApproved => 'Approved';

  @override
  String get statusCompensated => 'Compensated';

  @override
  String get statusRejected => 'Rejected';

  @override
  String get statusClosed => 'Closed';

  @override
  String get followUpOverdue => 'Overdue';

  @override
  String get followUpToday => 'Today';

  @override
  String get currencySar => 'SAR';

  @override
  String get reminderChannelName => 'Claim Reminders';

  @override
  String get reminderChannelDescription =>
      'Follow-up alerts for motor-accident insurance claims';

  @override
  String get genericReminderTitle => 'Claim Follow-up Reminder';

  @override
  String get genericReminderBody =>
      'You have a claim that is due for follow-up now.';
}
