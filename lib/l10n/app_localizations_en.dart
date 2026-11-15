// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appName => 'Claim Tracker Pro';

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
  String get share => 'Share';

  @override
  String get shareEmailFailed =>
      'Couldn\'t open an email app to share this claim.';

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
  String get dashAwaitingApproval => 'Awaiting Approval Claims';

  @override
  String get dashNeedsAttention => 'Needs Your Attention';

  @override
  String get dashRecentlyUpdated => 'Recently Updated Claims';

  @override
  String get dashRecentlyRegistered => 'Recently Registered';

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
  String get clearFilters => 'Clear filters';

  @override
  String get searchHint => 'Search plate, name, claim number, vehicle…';

  @override
  String get claimsEmpty => 'No matching claims.';

  @override
  String get loadFailed =>
      'Couldn\'t load the data right now. Please try again.';

  @override
  String get selectClaims => 'Select claims';

  @override
  String get selectAll => 'Select all';

  @override
  String get deselectAll => 'Deselect all';

  @override
  String selectedCount(int count) {
    return '$count selected';
  }

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
  String get customerInsurerLabel => 'Insurance Company';

  @override
  String get insuranceMobileLabel => 'Insurance Mobile';

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
  String get csvDatesDayFirst =>
      'Dates were read as day/month/year (5/11/2026 = 5 November 2026).';

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
  String get attachmentAddPhotos => 'Add Photos';

  @override
  String get attachmentAddVideos => 'Add Videos';

  @override
  String get videoPlay => 'Play';

  @override
  String get videoPause => 'Pause';

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
  String get setNextFollowUp => 'Set next follow-up date and time';

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
  String get pickFromContacts => 'Add from contacts';

  @override
  String get contactPickFailed => 'Couldn\'t open the contact picker';

  @override
  String get callFailed => 'Couldn\'t open the dialer';

  @override
  String get deleteClaimTitle => 'Delete claim?';

  @override
  String get deleteClaimBody =>
      'The claim, its status history, reminders and attachments will be permanently deleted.';

  @override
  String deleteClaimsTitle(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Delete # claims?',
      one: 'Delete this claim?',
    );
    return '$_temp0';
  }

  @override
  String get deleteClaimsBody =>
      'These claims and their status histories, reminders and attachments will be permanently deleted.';

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
  String get aboutDeveloper =>
      'This application has been fully developed and designed by Bassam Alrasheed.';

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

  @override
  String get dashGreeting => 'Welcome back 👋';

  @override
  String get dashHeroSubtitle =>
      'Every accident claim, organized in one place.';

  @override
  String get dashProgress => 'Resolution progress';

  @override
  String get dashStatusOverview => 'Status overview';

  @override
  String get navCustomers => 'Customers';

  @override
  String get customersAll => 'All customers';

  @override
  String customersCount(int count) {
    return '$count customers';
  }

  @override
  String get customersEmpty =>
      'No customers yet. They appear here once you add claims.';

  @override
  String get customersSearchHint => 'Search customer name or mobile';

  @override
  String get customerAllClaims => 'All claims';

  @override
  String customerClaimsCount(int count) {
    return '$count claims';
  }

  @override
  String get sheetsCardTitle => 'Google Sheets';

  @override
  String get sheetsSyncAction => 'Sync now';

  @override
  String get sheetsSetupAction => 'Connection settings';

  @override
  String get sheetsUrlLabel => 'Web app URL';

  @override
  String get sheetsTokenLabel => 'Sync key';

  @override
  String get sheetsNotConfigured =>
      'Add the web app URL and the sync key first (Connection settings).';

  @override
  String get sheetsNeverSynced => 'Not synced yet.';

  @override
  String sheetsLastSync(String time) {
    return 'Last sync: $time';
  }

  @override
  String sheetsFromSheet(int created, int updated) {
    return 'From the sheet: $created new, $updated updated.';
  }

  @override
  String sheetsToSheet(int sent, int deleted) {
    return 'To the sheet: $sent sent, $deleted deleted.';
  }

  @override
  String sheetsConflicts(int count) {
    return '$count claims were edited in both places; the newer edit was kept.';
  }

  @override
  String sheetsIdMisses(int count) {
    return '$count new rows moved in the sheet during the sync and did not get their number. Check them for duplicates.';
  }

  @override
  String get sheetsSkipped => 'Rows skipped (fix them in the sheet):';

  @override
  String sheetsFailed(String reason) {
    return 'Sync failed: $reason';
  }

  @override
  String get sheetsWrongKey => 'the sync key is wrong.';

  @override
  String get sheetsNoInternet => 'no internet connection.';

  @override
  String get sheetsBadResponse =>
      'the web app did not answer. Check the URL and that it is deployed for \"Anyone\".';

  @override
  String get navAssistant => 'Assistant';

  @override
  String get assistantTitle => 'Claims Assistant';

  @override
  String get assistantSubtitle =>
      'Tell me what to do with your claims, and I\'ll handle it.';

  @override
  String get assistantPoweredBy => 'Powered by Google Gemini';

  @override
  String get assistantInputHint => 'Ask or tell me what to do…';

  @override
  String get assistantThinking => 'Thinking…';

  @override
  String get assistantSend => 'Send';

  @override
  String get assistantSetupTitle => 'Connect your Gemini key';

  @override
  String get assistantSetupBody =>
      'The assistant runs on Google Gemini. Create a free API key at aistudio.google.com, then add it here. The key is stored encrypted on this device only.';

  @override
  String get assistantAddKey => 'Add API key';

  @override
  String get assistantGetKey => 'Get a free key';

  @override
  String get assistantSettingsTitle => 'Assistant settings';

  @override
  String get assistantKeyLabel => 'Gemini API key';

  @override
  String get assistantModelLabel => 'Model';

  @override
  String get assistantModelHelp =>
      'Leave as is unless you want a specific Gemini model.';

  @override
  String get assistantTestSave => 'Test & save';

  @override
  String get assistantRemoveKey => 'Remove key';

  @override
  String get assistantConnected => 'Connected. The assistant is ready.';

  @override
  String get assistantKeyRemoved => 'Key removed.';

  @override
  String get assistantNewChat => 'New chat';

  @override
  String get assistantTryAsking => 'Try asking';

  @override
  String get assistantSuggestOverdue => 'Which claims are overdue?';

  @override
  String get assistantSuggestSummary => 'Give me a summary of my claims';

  @override
  String get assistantSuggestReminder =>
      'Remind me about plate 3557 ATR tomorrow at 10 AM';

  @override
  String get assistantSuggestCreate => 'Register a new claim';

  @override
  String get assistantReviewAction => 'Review and confirm';

  @override
  String get assistantActionCreate => 'Register new claim';

  @override
  String get assistantActionReminder => 'Set reminder';

  @override
  String get assistantActionClearReminder => 'Remove reminder';

  @override
  String get assistantActionStatus => 'Change status';

  @override
  String get assistantActionNote => 'Add note';

  @override
  String get assistantStateDone => 'Done';

  @override
  String get assistantStateCancelled => 'Cancelled';

  @override
  String get assistantStateFailed => 'Failed';

  @override
  String get assistantStateRunning => 'Saving…';

  @override
  String get assistantOpenClaim => 'Open claim';

  @override
  String get assistantErrInvalidKey =>
      'Gemini rejected the API key. Check it in the assistant settings.';

  @override
  String get assistantErrRateLimit =>
      'Too many requests for the free plan. Wait a minute and try again.';

  @override
  String get assistantErrModel =>
      'That Gemini model was not found. Check the model name in the assistant settings.';

  @override
  String get assistantErrNetwork => 'No internet connection.';

  @override
  String get assistantErrEmpty => 'Gemini returned no answer. Try rephrasing.';

  @override
  String assistantErrOther(String detail) {
    return 'Something went wrong: $detail';
  }

  @override
  String get assistantMicListening => 'Listening… speak now';

  @override
  String get assistantMicUnavailable =>
      'Voice input isn\'t available. Allow microphone access for the app, and make sure speech recognition (Google app on Android) is installed.';

  @override
  String assistantMicLanguage(String language) {
    return 'Voice language: $language';
  }

  @override
  String get assistantMicTooltip => 'Tap to speak · hold to switch language';
}
