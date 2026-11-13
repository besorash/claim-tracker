import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_ar.dart';
import 'app_localizations_en.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('ar'),
  ];

  /// No description provided for @appName.
  ///
  /// In en, this message translates to:
  /// **'Claim Tracker'**
  String get appName;

  /// No description provided for @navDashboard.
  ///
  /// In en, this message translates to:
  /// **'Dashboard'**
  String get navDashboard;

  /// No description provided for @navClaims.
  ///
  /// In en, this message translates to:
  /// **'Claims'**
  String get navClaims;

  /// No description provided for @navReminders.
  ///
  /// In en, this message translates to:
  /// **'Follow-ups'**
  String get navReminders;

  /// No description provided for @navSettings.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get navSettings;

  /// No description provided for @addClaim.
  ///
  /// In en, this message translates to:
  /// **'Add Claim'**
  String get addClaim;

  /// No description provided for @edit.
  ///
  /// In en, this message translates to:
  /// **'Edit'**
  String get edit;

  /// No description provided for @save.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get save;

  /// No description provided for @cancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancel;

  /// No description provided for @delete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get delete;

  /// No description provided for @close.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get close;

  /// No description provided for @confirm.
  ///
  /// In en, this message translates to:
  /// **'Confirm'**
  String get confirm;

  /// No description provided for @search.
  ///
  /// In en, this message translates to:
  /// **'Search'**
  String get search;

  /// No description provided for @retry.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get retry;

  /// No description provided for @dashTotalClaims.
  ///
  /// In en, this message translates to:
  /// **'Total Claims'**
  String get dashTotalClaims;

  /// No description provided for @dashOpenClaims.
  ///
  /// In en, this message translates to:
  /// **'Open Claims'**
  String get dashOpenClaims;

  /// No description provided for @dashClosedClaims.
  ///
  /// In en, this message translates to:
  /// **'Finished Claims'**
  String get dashClosedClaims;

  /// No description provided for @dashDueToday.
  ///
  /// In en, this message translates to:
  /// **'Follow-up Due Today'**
  String get dashDueToday;

  /// No description provided for @dashOverdue.
  ///
  /// In en, this message translates to:
  /// **'Overdue Follow-ups'**
  String get dashOverdue;

  /// No description provided for @dashAwaitingApproval.
  ///
  /// In en, this message translates to:
  /// **'Awaiting Approval Claims'**
  String get dashAwaitingApproval;

  /// No description provided for @dashNeedsAttention.
  ///
  /// In en, this message translates to:
  /// **'Needs Your Attention'**
  String get dashNeedsAttention;

  /// No description provided for @dashRecentlyUpdated.
  ///
  /// In en, this message translates to:
  /// **'Recently Updated Claims'**
  String get dashRecentlyUpdated;

  /// No description provided for @dashEmpty.
  ///
  /// In en, this message translates to:
  /// **'No claims yet. Start by adding your first claim.'**
  String get dashEmpty;

  /// No description provided for @filterAll.
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get filterAll;

  /// No description provided for @filterOpen.
  ///
  /// In en, this message translates to:
  /// **'Open'**
  String get filterOpen;

  /// No description provided for @filterFollowUp.
  ///
  /// In en, this message translates to:
  /// **'Needs Follow-up'**
  String get filterFollowUp;

  /// No description provided for @filterOverdue.
  ///
  /// In en, this message translates to:
  /// **'Overdue'**
  String get filterOverdue;

  /// No description provided for @sortTooltip.
  ///
  /// In en, this message translates to:
  /// **'Sort'**
  String get sortTooltip;

  /// No description provided for @sortDefault.
  ///
  /// In en, this message translates to:
  /// **'Default order'**
  String get sortDefault;

  /// No description provided for @sortSubmissionNewest.
  ///
  /// In en, this message translates to:
  /// **'Submission date: newest first'**
  String get sortSubmissionNewest;

  /// No description provided for @sortSubmissionOldest.
  ///
  /// In en, this message translates to:
  /// **'Submission date: oldest first'**
  String get sortSubmissionOldest;

  /// No description provided for @sortUpdatedNewest.
  ///
  /// In en, this message translates to:
  /// **'Last update: newest first'**
  String get sortUpdatedNewest;

  /// No description provided for @sortUpdatedOldest.
  ///
  /// In en, this message translates to:
  /// **'Last update: oldest first'**
  String get sortUpdatedOldest;

  /// No description provided for @lastUpdateLabel.
  ///
  /// In en, this message translates to:
  /// **'Last update'**
  String get lastUpdateLabel;

  /// No description provided for @filterClosed.
  ///
  /// In en, this message translates to:
  /// **'Finished'**
  String get filterClosed;

  /// No description provided for @clearFilters.
  ///
  /// In en, this message translates to:
  /// **'Clear filters'**
  String get clearFilters;

  /// No description provided for @searchHint.
  ///
  /// In en, this message translates to:
  /// **'Search plate, name, claim number, vehicle…'**
  String get searchHint;

  /// No description provided for @claimsEmpty.
  ///
  /// In en, this message translates to:
  /// **'No matching claims.'**
  String get claimsEmpty;

  /// No description provided for @loadFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t load the data right now. Please try again.'**
  String get loadFailed;

  /// No description provided for @selectClaims.
  ///
  /// In en, this message translates to:
  /// **'Select claims'**
  String get selectClaims;

  /// No description provided for @selectAll.
  ///
  /// In en, this message translates to:
  /// **'Select all'**
  String get selectAll;

  /// No description provided for @deselectAll.
  ///
  /// In en, this message translates to:
  /// **'Deselect all'**
  String get deselectAll;

  /// No description provided for @selectedCount.
  ///
  /// In en, this message translates to:
  /// **'{count} selected'**
  String selectedCount(int count);

  /// No description provided for @claimNumberLabel.
  ///
  /// In en, this message translates to:
  /// **'Claim Number'**
  String get claimNumberLabel;

  /// No description provided for @customerNameLabel.
  ///
  /// In en, this message translates to:
  /// **'Customer Name'**
  String get customerNameLabel;

  /// No description provided for @mobileLabel.
  ///
  /// In en, this message translates to:
  /// **'Mobile Number'**
  String get mobileLabel;

  /// No description provided for @nationalIdLabel.
  ///
  /// In en, this message translates to:
  /// **'National ID'**
  String get nationalIdLabel;

  /// No description provided for @emailLabel.
  ///
  /// In en, this message translates to:
  /// **'Email Address'**
  String get emailLabel;

  /// No description provided for @accidentNumberLabel.
  ///
  /// In en, this message translates to:
  /// **'Accident Number'**
  String get accidentNumberLabel;

  /// No description provided for @accidentDateLabel.
  ///
  /// In en, this message translates to:
  /// **'Accident Date'**
  String get accidentDateLabel;

  /// No description provided for @cityLabel.
  ///
  /// In en, this message translates to:
  /// **'City'**
  String get cityLabel;

  /// No description provided for @accidentTypeLabel.
  ///
  /// In en, this message translates to:
  /// **'Accident Type'**
  String get accidentTypeLabel;

  /// No description provided for @noPlate.
  ///
  /// In en, this message translates to:
  /// **'No plate'**
  String get noPlate;

  /// No description provided for @vehicleTypeLabel.
  ///
  /// In en, this message translates to:
  /// **'Vehicle Type'**
  String get vehicleTypeLabel;

  /// No description provided for @sectionCustomerInfo.
  ///
  /// In en, this message translates to:
  /// **'Customer Information'**
  String get sectionCustomerInfo;

  /// No description provided for @sectionAccidentInfo.
  ///
  /// In en, this message translates to:
  /// **'Accident & Vehicle Information'**
  String get sectionAccidentInfo;

  /// No description provided for @sectionClaimInfo.
  ///
  /// In en, this message translates to:
  /// **'Claim & Insurance Information'**
  String get sectionClaimInfo;

  /// No description provided for @insurerOther.
  ///
  /// In en, this message translates to:
  /// **'Other'**
  String get insurerOther;

  /// No description provided for @insurerOtherLabel.
  ///
  /// In en, this message translates to:
  /// **'Insurance company name'**
  String get insurerOtherLabel;

  /// No description provided for @vehiclePlateLabel.
  ///
  /// In en, this message translates to:
  /// **'Vehicle Plate'**
  String get vehiclePlateLabel;

  /// No description provided for @customerInsurerLabel.
  ///
  /// In en, this message translates to:
  /// **'Customer\'s Insurance Company'**
  String get customerInsurerLabel;

  /// No description provided for @insuranceMobileLabel.
  ///
  /// In en, this message translates to:
  /// **'Insurance Company Mobile'**
  String get insuranceMobileLabel;

  /// No description provided for @liabilityPercentLabel.
  ///
  /// In en, this message translates to:
  /// **'Liability %'**
  String get liabilityPercentLabel;

  /// No description provided for @liabilityNotSet.
  ///
  /// In en, this message translates to:
  /// **'Not set'**
  String get liabilityNotSet;

  /// No description provided for @csvCardTitle.
  ///
  /// In en, this message translates to:
  /// **'Spreadsheet (CSV)'**
  String get csvCardTitle;

  /// No description provided for @csvExportAction.
  ///
  /// In en, this message translates to:
  /// **'Export to spreadsheet (CSV)'**
  String get csvExportAction;

  /// No description provided for @csvImportAction.
  ///
  /// In en, this message translates to:
  /// **'Import from spreadsheet (CSV)'**
  String get csvImportAction;

  /// No description provided for @csvExportedOk.
  ///
  /// In en, this message translates to:
  /// **'Spreadsheet exported.'**
  String get csvExportedOk;

  /// No description provided for @csvExportFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not export the spreadsheet.'**
  String get csvExportFailed;

  /// No description provided for @csvImportedOk.
  ///
  /// In en, this message translates to:
  /// **'Imported: {created} new, {updated} updated.'**
  String csvImportedOk(int created, int updated);

  /// No description provided for @csvImportRejected.
  ///
  /// In en, this message translates to:
  /// **'Nothing was saved. Fix these rows in the file and import again:'**
  String get csvImportRejected;

  /// No description provided for @csvImportFailed.
  ///
  /// In en, this message translates to:
  /// **'The import stopped because of a database error. Some rows may have been saved.'**
  String get csvImportFailed;

  /// No description provided for @csvReminderWarning.
  ///
  /// In en, this message translates to:
  /// **'Some reminders could not be scheduled on this device.'**
  String get csvReminderWarning;

  /// No description provided for @csvErrorEncoding.
  ///
  /// In en, this message translates to:
  /// **'Save the file as CSV UTF-8 and try again.'**
  String get csvErrorEncoding;

  /// No description provided for @csvErrorMalformed.
  ///
  /// In en, this message translates to:
  /// **'The file could not be read. Check the quotation marks.'**
  String get csvErrorMalformed;

  /// No description provided for @csvErrorMissingColumns.
  ///
  /// In en, this message translates to:
  /// **'Missing columns:'**
  String get csvErrorMissingColumns;

  /// No description provided for @csvRowLabel.
  ///
  /// In en, this message translates to:
  /// **'Row'**
  String get csvRowLabel;

  /// No description provided for @csvErrorBadId.
  ///
  /// In en, this message translates to:
  /// **'The id must be a whole number from the export.'**
  String get csvErrorBadId;

  /// No description provided for @csvErrorUnknownId.
  ///
  /// In en, this message translates to:
  /// **'No claim with this id exists in the app.'**
  String get csvErrorUnknownId;

  /// No description provided for @csvErrorDuplicateId.
  ///
  /// In en, this message translates to:
  /// **'This id appears more than once in the file.'**
  String get csvErrorDuplicateId;

  /// No description provided for @csvErrorAmount.
  ///
  /// In en, this message translates to:
  /// **'The amount must be a number.'**
  String get csvErrorAmount;

  /// No description provided for @csvErrorLiability.
  ///
  /// In en, this message translates to:
  /// **'Liability % must be empty, 0, 25, 50, 75 or 100.'**
  String get csvErrorLiability;

  /// No description provided for @csvErrorDate.
  ///
  /// In en, this message translates to:
  /// **'Unrecognized date. Use e.g. 2026-03-31 or 31/03/2026 (add 14:30 for a follow-up time).'**
  String get csvErrorDate;

  /// No description provided for @csvErrorStatus.
  ///
  /// In en, this message translates to:
  /// **'Unknown status. Use the status name shown in the app or its key.'**
  String get csvErrorStatus;

  /// No description provided for @csvImportUnchanged.
  ///
  /// In en, this message translates to:
  /// **'{count} unchanged.'**
  String csvImportUnchanged(int count);

  /// No description provided for @csvNothingChanged.
  ///
  /// In en, this message translates to:
  /// **'Nothing changed: the file matches what is already in the app. If you edited it in WPS or Excel, make sure you saved the file before importing it.'**
  String get csvNothingChanged;

  /// No description provided for @csvUnknownIdsAdded.
  ///
  /// In en, this message translates to:
  /// **'{count} row(s) had an id not found in the app and were added as new claims.'**
  String csvUnknownIdsAdded(int count);

  /// No description provided for @csvNoRows.
  ///
  /// In en, this message translates to:
  /// **'The file has no claims in it.'**
  String get csvNoRows;

  /// No description provided for @csvDatesMonthFirst.
  ///
  /// In en, this message translates to:
  /// **'Dates were read as month/day/year (11/4/2026 = 4 November 2026).'**
  String get csvDatesMonthFirst;

  /// No description provided for @csvExtraColumnsSaved.
  ///
  /// In en, this message translates to:
  /// **'Extra columns saved with the claims: {columns}'**
  String csvExtraColumnsSaved(String columns);

  /// No description provided for @extraFieldsLabel.
  ///
  /// In en, this message translates to:
  /// **'Additional Fields'**
  String get extraFieldsLabel;

  /// No description provided for @submissionDateLabel.
  ///
  /// In en, this message translates to:
  /// **'Submission Date'**
  String get submissionDateLabel;

  /// No description provided for @insurerRefLabel.
  ///
  /// In en, this message translates to:
  /// **'Insurer Reference Number'**
  String get insurerRefLabel;

  /// No description provided for @claimAmountLabel.
  ///
  /// In en, this message translates to:
  /// **'Claim Amount (SAR)'**
  String get claimAmountLabel;

  /// No description provided for @notesLabel.
  ///
  /// In en, this message translates to:
  /// **'Notes'**
  String get notesLabel;

  /// No description provided for @statusLabel.
  ///
  /// In en, this message translates to:
  /// **'Current Status'**
  String get statusLabel;

  /// No description provided for @lastStatusUpdateLabel.
  ///
  /// In en, this message translates to:
  /// **'Last Status Update'**
  String get lastStatusUpdateLabel;

  /// No description provided for @nextFollowUpLabel.
  ///
  /// In en, this message translates to:
  /// **'Next Follow-up'**
  String get nextFollowUpLabel;

  /// No description provided for @reminderEnabled.
  ///
  /// In en, this message translates to:
  /// **'Reminder Enabled'**
  String get reminderEnabled;

  /// No description provided for @reminderDisabled.
  ///
  /// In en, this message translates to:
  /// **'Reminder Disabled'**
  String get reminderDisabled;

  /// No description provided for @attachmentsLabel.
  ///
  /// In en, this message translates to:
  /// **'Attachments'**
  String get attachmentsLabel;

  /// No description provided for @attachmentsEmpty.
  ///
  /// In en, this message translates to:
  /// **'No attachments yet.'**
  String get attachmentsEmpty;

  /// No description provided for @attachmentAdd.
  ///
  /// In en, this message translates to:
  /// **'Add Attachment'**
  String get attachmentAdd;

  /// No description provided for @attachmentOpenFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not open the file. Your device may have no app that opens this type.'**
  String get attachmentOpenFailed;

  /// No description provided for @attachmentMissing.
  ///
  /// In en, this message translates to:
  /// **'The file is missing on this device.'**
  String get attachmentMissing;

  /// No description provided for @deleteAttachmentTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete attachment?'**
  String get deleteAttachmentTitle;

  /// No description provided for @deleteAttachmentBody.
  ///
  /// In en, this message translates to:
  /// **'The file will be permanently removed from the app\'s storage.'**
  String get deleteAttachmentBody;

  /// No description provided for @attachmentPickFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not open the file picker.'**
  String get attachmentPickFailed;

  /// No description provided for @attachmentStoreError.
  ///
  /// In en, this message translates to:
  /// **'Could not access the attachments storage.'**
  String get attachmentStoreError;

  /// No description provided for @claimNotFound.
  ///
  /// In en, this message translates to:
  /// **'Claim not found. It may have been deleted elsewhere.'**
  String get claimNotFound;

  /// No description provided for @statusHistoryLabel.
  ///
  /// In en, this message translates to:
  /// **'Status Change History'**
  String get statusHistoryLabel;

  /// No description provided for @historyEmpty.
  ///
  /// In en, this message translates to:
  /// **'No changes recorded yet.'**
  String get historyEmpty;

  /// No description provided for @changeStatus.
  ///
  /// In en, this message translates to:
  /// **'Change Status'**
  String get changeStatus;

  /// No description provided for @changeStatusTitle.
  ///
  /// In en, this message translates to:
  /// **'Change Claim Status'**
  String get changeStatusTitle;

  /// No description provided for @statusNoteHint.
  ///
  /// In en, this message translates to:
  /// **'Optional note about the change'**
  String get statusNoteHint;

  /// No description provided for @setNextFollowUp.
  ///
  /// In en, this message translates to:
  /// **'Set next follow-up date'**
  String get setNextFollowUp;

  /// No description provided for @keepExistingFollowUp.
  ///
  /// In en, this message translates to:
  /// **'Keep current date'**
  String get keepExistingFollowUp;

  /// No description provided for @clearFollowUp.
  ///
  /// In en, this message translates to:
  /// **'Clear date'**
  String get clearFollowUp;

  /// No description provided for @reminderTitle.
  ///
  /// In en, this message translates to:
  /// **'Claim Reminder'**
  String get reminderTitle;

  /// No description provided for @reminderWhenLabel.
  ///
  /// In en, this message translates to:
  /// **'Reminder Time'**
  String get reminderWhenLabel;

  /// No description provided for @reminderSet.
  ///
  /// In en, this message translates to:
  /// **'Set reminder time'**
  String get reminderSet;

  /// No description provided for @reminderDisable.
  ///
  /// In en, this message translates to:
  /// **'Cancel reminder'**
  String get reminderDisable;

  /// No description provided for @reminderRepeatLabel.
  ///
  /// In en, this message translates to:
  /// **'Repeat'**
  String get reminderRepeatLabel;

  /// No description provided for @repeatNone.
  ///
  /// In en, this message translates to:
  /// **'Once'**
  String get repeatNone;

  /// No description provided for @repeatEveryHours.
  ///
  /// In en, this message translates to:
  /// **'Every {n} hours'**
  String repeatEveryHours(int n);

  /// No description provided for @repeatEveryDays.
  ///
  /// In en, this message translates to:
  /// **'Every {n} days'**
  String repeatEveryDays(int n);

  /// No description provided for @notificationsPermissionTitle.
  ///
  /// In en, this message translates to:
  /// **'Allow Notifications'**
  String get notificationsPermissionTitle;

  /// No description provided for @notificationsPermissionBody.
  ///
  /// In en, this message translates to:
  /// **'We need notification permission to remind you of claim follow-up times on schedule.'**
  String get notificationsPermissionBody;

  /// No description provided for @notificationsDeniedTitle.
  ///
  /// In en, this message translates to:
  /// **'Notifications Off'**
  String get notificationsDeniedTitle;

  /// No description provided for @notificationsDeniedBody.
  ///
  /// In en, this message translates to:
  /// **'Enable app notifications in your device settings so follow-up reminders arrive on time.'**
  String get notificationsDeniedBody;

  /// No description provided for @requiredField.
  ///
  /// In en, this message translates to:
  /// **'This field is required'**
  String get requiredField;

  /// No description provided for @invalidNumber.
  ///
  /// In en, this message translates to:
  /// **'Enter a valid number'**
  String get invalidNumber;

  /// No description provided for @invalidDate.
  ///
  /// In en, this message translates to:
  /// **'Enter a valid date'**
  String get invalidDate;

  /// No description provided for @futureFollowUpRequired.
  ///
  /// In en, this message translates to:
  /// **'The follow-up date must be in the future'**
  String get futureFollowUpRequired;

  /// No description provided for @deleteClaimTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete claim?'**
  String get deleteClaimTitle;

  /// No description provided for @deleteClaimBody.
  ///
  /// In en, this message translates to:
  /// **'The claim, its status history, reminders and attachments will be permanently deleted.'**
  String get deleteClaimBody;

  /// No description provided for @deleteClaimsTitle.
  ///
  /// In en, this message translates to:
  /// **'{count,plural, =1{Delete this claim?} other{Delete # claims?}}'**
  String deleteClaimsTitle(num count);

  /// No description provided for @deleteClaimsBody.
  ///
  /// In en, this message translates to:
  /// **'These claims and their status histories, reminders and attachments will be permanently deleted.'**
  String get deleteClaimsBody;

  /// No description provided for @closeClaimTitle.
  ///
  /// In en, this message translates to:
  /// **'Close claim?'**
  String get closeClaimTitle;

  /// No description provided for @closeClaimBody.
  ///
  /// In en, this message translates to:
  /// **'Status will change to “Closed” and upcoming scheduled reminders will be cancelled.'**
  String get closeClaimBody;

  /// No description provided for @settingsTheme.
  ///
  /// In en, this message translates to:
  /// **'Appearance'**
  String get settingsTheme;

  /// No description provided for @themeLight.
  ///
  /// In en, this message translates to:
  /// **'Light'**
  String get themeLight;

  /// No description provided for @themeDark.
  ///
  /// In en, this message translates to:
  /// **'Dark'**
  String get themeDark;

  /// No description provided for @themeSystem.
  ///
  /// In en, this message translates to:
  /// **'Follow System'**
  String get themeSystem;

  /// No description provided for @settingsLanguage.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get settingsLanguage;

  /// No description provided for @languageEnglish.
  ///
  /// In en, this message translates to:
  /// **'English'**
  String get languageEnglish;

  /// No description provided for @languageArabic.
  ///
  /// In en, this message translates to:
  /// **'العربية (Arabic)'**
  String get languageArabic;

  /// No description provided for @settingsNotifications.
  ///
  /// In en, this message translates to:
  /// **'Notifications & Reminders'**
  String get settingsNotifications;

  /// No description provided for @notificationsStatusEnabled.
  ///
  /// In en, this message translates to:
  /// **'Notifications enabled'**
  String get notificationsStatusEnabled;

  /// No description provided for @notificationsStatusDisabled.
  ///
  /// In en, this message translates to:
  /// **'Notifications disabled on this device'**
  String get notificationsStatusDisabled;

  /// No description provided for @exactAlarmHint.
  ///
  /// In en, this message translates to:
  /// **'Reminders may not arrive at the exact time if Exact Alarms are restricted on your device.'**
  String get exactAlarmHint;

  /// No description provided for @notificationsRequestAction.
  ///
  /// In en, this message translates to:
  /// **'Request notification permission'**
  String get notificationsRequestAction;

  /// No description provided for @notificationsOpenSettingsAction.
  ///
  /// In en, this message translates to:
  /// **'Open notification settings'**
  String get notificationsOpenSettingsAction;

  /// No description provided for @exactAlarmsStatusGranted.
  ///
  /// In en, this message translates to:
  /// **'Exact alarms allowed — reminders arrive on time.'**
  String get exactAlarmsStatusGranted;

  /// No description provided for @exactAlarmsStatusDenied.
  ///
  /// In en, this message translates to:
  /// **'Exact alarms not allowed — reminders may be delayed.'**
  String get exactAlarmsStatusDenied;

  /// No description provided for @exactAlarmsRequestAction.
  ///
  /// In en, this message translates to:
  /// **'Allow exact alarms'**
  String get exactAlarmsRequestAction;

  /// No description provided for @exactAlarmExplainTitle.
  ///
  /// In en, this message translates to:
  /// **'Exact Alarms'**
  String get exactAlarmExplainTitle;

  /// No description provided for @exactAlarmExplainBody.
  ///
  /// In en, this message translates to:
  /// **'We need the exact-alarm permission so follow-up reminders arrive at their scheduled time, especially while the app is closed.'**
  String get exactAlarmExplainBody;

  /// No description provided for @batteryStatusExempt.
  ///
  /// In en, this message translates to:
  /// **'App exempt from battery optimization — reminders work even when the app is closed.'**
  String get batteryStatusExempt;

  /// No description provided for @batteryStatusNotExempt.
  ///
  /// In en, this message translates to:
  /// **'App not exempt from battery optimization — the battery policy may block reminders when the app is closed.'**
  String get batteryStatusNotExempt;

  /// No description provided for @batteryRequestAction.
  ///
  /// In en, this message translates to:
  /// **'Request exemption'**
  String get batteryRequestAction;

  /// No description provided for @batteryExplainBody.
  ///
  /// In en, this message translates to:
  /// **'Some Android devices stop background apps to save battery, which blocks on-time reminders. Granting the exemption guarantees your reminder arrives even while the app is closed.'**
  String get batteryExplainBody;

  /// No description provided for @reminderScheduleFailed.
  ///
  /// In en, this message translates to:
  /// **'The time was saved, but scheduling the system reminder failed. Try again or check notification permissions.'**
  String get reminderScheduleFailed;

  /// No description provided for @reminderInexactWarning.
  ///
  /// In en, this message translates to:
  /// **'Exact alarms are not allowed — this reminder may arrive late. Enable the permission in settings so it arrives on time.'**
  String get reminderInexactWarning;

  /// No description provided for @settingsBackupRestore.
  ///
  /// In en, this message translates to:
  /// **'Backup & Restore'**
  String get settingsBackupRestore;

  /// No description provided for @settingsAbout.
  ///
  /// In en, this message translates to:
  /// **'About the App'**
  String get settingsAbout;

  /// No description provided for @appVersion.
  ///
  /// In en, this message translates to:
  /// **'Version {version} (build {build})'**
  String appVersion(String version, String build);

  /// No description provided for @backupExportTitle.
  ///
  /// In en, this message translates to:
  /// **'Backup'**
  String get backupExportTitle;

  /// No description provided for @backupRestoreTitle.
  ///
  /// In en, this message translates to:
  /// **'Restore Backup'**
  String get backupRestoreTitle;

  /// No description provided for @backupPassphraseHint.
  ///
  /// In en, this message translates to:
  /// **'Encryption passphrase for the backup'**
  String get backupPassphraseHint;

  /// No description provided for @backupExportAction.
  ///
  /// In en, this message translates to:
  /// **'Export encrypted backup'**
  String get backupExportAction;

  /// No description provided for @backupRestoreAction.
  ///
  /// In en, this message translates to:
  /// **'Restore from backup'**
  String get backupRestoreAction;

  /// No description provided for @backupPassphraseTitle.
  ///
  /// In en, this message translates to:
  /// **'Encryption Passphrase'**
  String get backupPassphraseTitle;

  /// No description provided for @backupPassphraseConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Confirm Passphrase'**
  String get backupPassphraseConfirmTitle;

  /// No description provided for @backupPassphraseMismatch.
  ///
  /// In en, this message translates to:
  /// **'The passphrases do not match'**
  String get backupPassphraseMismatch;

  /// No description provided for @backupExportedOk.
  ///
  /// In en, this message translates to:
  /// **'Backup created successfully.'**
  String get backupExportedOk;

  /// No description provided for @backupWorking.
  ///
  /// In en, this message translates to:
  /// **'Working…'**
  String get backupWorking;

  /// No description provided for @restoreWarningTitle.
  ///
  /// In en, this message translates to:
  /// **'Replace current data?'**
  String get restoreWarningTitle;

  /// No description provided for @restoreWarningBody.
  ///
  /// In en, this message translates to:
  /// **'This replaces all current claims and attachments with the backup\'s contents. This cannot be undone after confirming.'**
  String get restoreWarningBody;

  /// No description provided for @restoredOk.
  ///
  /// In en, this message translates to:
  /// **'Restored: {claims} claim(s) and {attachments} attachment(s).'**
  String restoredOk(int claims, int attachments);

  /// No description provided for @backupFailedWrongPassphrase.
  ///
  /// In en, this message translates to:
  /// **'The passphrase is wrong or the backup is corrupt. Your current data was not modified.'**
  String get backupFailedWrongPassphrase;

  /// No description provided for @backupFailedCorrupt.
  ///
  /// In en, this message translates to:
  /// **'The backup is corrupt or incompatible with this version. Your current data was not modified.'**
  String get backupFailedCorrupt;

  /// No description provided for @backupExportFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not create the backup.'**
  String get backupExportFailed;

  /// No description provided for @backupRestoreFailed.
  ///
  /// In en, this message translates to:
  /// **'Restore failed. Your current data was not modified.'**
  String get backupRestoreFailed;

  /// No description provided for @securityInfoTitle.
  ///
  /// In en, this message translates to:
  /// **'Privacy & Security'**
  String get securityInfoTitle;

  /// No description provided for @securityInfoBody.
  ///
  /// In en, this message translates to:
  /// **'All data is stored locally on your device only — nothing is sent over a network or used for analytics. Backups are encrypted with your passphrase (PBKDF2 + AES-256). Before entering real data, make sure local storage complies with your employer\'s policies and Saudi PDPL privacy requirements where applicable.'**
  String get securityInfoBody;

  /// No description provided for @statusNew.
  ///
  /// In en, this message translates to:
  /// **'New'**
  String get statusNew;

  /// No description provided for @statusSubmitted.
  ///
  /// In en, this message translates to:
  /// **'Claim Submitted'**
  String get statusSubmitted;

  /// No description provided for @statusAwaitingReview.
  ///
  /// In en, this message translates to:
  /// **'Awaiting Review'**
  String get statusAwaitingReview;

  /// No description provided for @statusAwaitingDocuments.
  ///
  /// In en, this message translates to:
  /// **'Awaiting Documents'**
  String get statusAwaitingDocuments;

  /// No description provided for @statusProcessing.
  ///
  /// In en, this message translates to:
  /// **'In Processing'**
  String get statusProcessing;

  /// No description provided for @statusAwaitingApproval.
  ///
  /// In en, this message translates to:
  /// **'Awaiting Approval'**
  String get statusAwaitingApproval;

  /// No description provided for @statusApproved.
  ///
  /// In en, this message translates to:
  /// **'Approved'**
  String get statusApproved;

  /// No description provided for @statusCompensated.
  ///
  /// In en, this message translates to:
  /// **'Compensated'**
  String get statusCompensated;

  /// No description provided for @statusRejected.
  ///
  /// In en, this message translates to:
  /// **'Rejected'**
  String get statusRejected;

  /// No description provided for @statusClosed.
  ///
  /// In en, this message translates to:
  /// **'Closed'**
  String get statusClosed;

  /// No description provided for @followUpOverdue.
  ///
  /// In en, this message translates to:
  /// **'Overdue'**
  String get followUpOverdue;

  /// No description provided for @followUpToday.
  ///
  /// In en, this message translates to:
  /// **'Today'**
  String get followUpToday;

  /// No description provided for @currencySar.
  ///
  /// In en, this message translates to:
  /// **'SAR'**
  String get currencySar;

  /// No description provided for @reminderChannelName.
  ///
  /// In en, this message translates to:
  /// **'Claim Reminders'**
  String get reminderChannelName;

  /// No description provided for @reminderChannelDescription.
  ///
  /// In en, this message translates to:
  /// **'Follow-up alerts for motor-accident insurance claims'**
  String get reminderChannelDescription;

  /// No description provided for @genericReminderTitle.
  ///
  /// In en, this message translates to:
  /// **'Claim Follow-up Reminder'**
  String get genericReminderTitle;

  /// No description provided for @genericReminderBody.
  ///
  /// In en, this message translates to:
  /// **'You have a claim that is due for follow-up now.'**
  String get genericReminderBody;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['ar', 'en'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'ar':
      return AppLocalizationsAr();
    case 'en':
      return AppLocalizationsEn();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
