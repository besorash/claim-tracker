# MASTER PROJECT SPECIFICATION --- CLAIM TRACKER

**Status:** Approved product specification\
**Product name:** Claim Tracker\
**Platform:** Android (APK) + iOS (unsigned IPA built by CI; added 2026-11-12)\
**Primary language:** Arabic\
**UI direction:** RTL\
**Architecture:** Flutter + Dart, local-first\
**Release scope:** Personal single-user application

------------------------------------------------------------------------

## 1. Product vision

Build a polished, reliable Android application that helps one
insurance-broker employee track motor-accident insurance claims from
initial intake through submission, insurer review, settlement,
rejection, or closure.

The app is a personal productivity tool. It must make it easy to: -
Register and find claims. - See which claims are open, overdue, or due
for follow-up. - Update claim status and preserve a status-change
history. - Set a custom reminder date and time for each claim. - Receive
local Android notifications. - Store claim-related documents and images
locally.

The app must prioritize correctness, privacy, and dependable reminders
over unnecessary features.

## 2. Non-negotiable scope decisions

  -----------------------------------------------------------------------
  Area                                Approved decision
  ----------------------------------- -----------------------------------
  Platform                            Android + iOS (iOS added
                                      2026-11-12)

  Deliverable                         Installable APK + unsigned IPA

  Framework                           Flutter + Dart

  Storage                             Local device storage only

  Database                            SQLite

  Users                               One personal user; no login or
                                      multi-user support

  Network                             No backend, cloud sync, or remote
                                      data transmission

  Reminders                           Custom date/time per claim

  Contact log                         Do not implement calls, messages,
                                      or communication history

  Language                            Arabic by default

  Layout                              RTL

  Currency                            SAR where monetary values are shown

  Time zone                           Asia/Riyadh for app defaults and
                                      display

  Calendar                            Gregorian

  Themes                              Both Light and Dark

  Claim layout                        Balanced cards

  Visual identity                     Premium Modern Business App
  -----------------------------------------------------------------------

Scope update 2026-11-12 (owner decision): iOS is in scope as a second
target, built as an unsigned IPA by `.github/workflows/ios-build.yml`.
Android-specific requirements below (notification channels, exact alarms,
battery optimization) apply to Android only.

Do not expand scope into web, desktop, teams, user accounts, CRM,
insurer integrations, email sending, WhatsApp, SMS, or cloud services.

## 3. Design system --- mandatory

### 3.1 Approved visual direction

Use a **Premium Modern Business App** visual identity: elegant,
professional, modern, calm, and highly usable. It should feel like a
finished commercial productivity application, not a default Flutter
sample.

Suggested palette: - Deep navy for primary surfaces and navigation:
`#101D35` - Deep blue for supporting emphasis: `#173D5C` - Teal for
primary actions and positive emphasis: `#19A99A` - Soft neutral light
background: `#F3F5F8` - Use accessible neutral text and surface colors
appropriate to each theme.

The palette is a direction, not permission to sacrifice contrast. Define
semantic design tokens rather than scattering raw color values through
widgets.

### 3.2 Themes

-   Implement complete Light and Dark themes.
-   Add a Settings control to choose Light, Dark, or System default if
    practical; at minimum, Light and Dark must both be supported.
-   Persist the chosen preference locally.
-   Check every screen, dialog, input, card, status chip, chart, and
    notification-related screen in both themes.
-   Never use low-contrast text or status colors.

### 3.3 Layout and components

-   Use balanced claim cards: enough information to identify and
    prioritize a claim without overcrowding.
-   Maintain consistent spacing, typography, corner radii, icon style,
    and elevation.
-   Use modern line icons and subtle transitions.
-   Make primary actions visually clear and secondary actions quieter.
-   Provide polished loading, empty, validation, success, and error
    states.
-   Design for common Android phone sizes and safe areas.
-   Avoid excessive gradients, glass effects, decorative animation, and
    visual clutter.
-   Do not leave decorative or non-functional buttons.

### 3.4 Arabic and RTL

-   Arabic is the default application language.
-   Apply RTL consistently to navigation, forms, cards, lists, dialogs,
    and icon placement where direction matters.
-   Use a high-quality Arabic font such as Cairo or IBM Plex Sans Arabic
    if licensing and packaging permit; otherwise select a readable
    bundled/system-supported Arabic font.
-   Test mixed Arabic/English text, claim IDs, phone numbers, dates, and
    numbers.
-   Do not reverse identifiers or phone numbers incorrectly.
-   Use clear Arabic labels and natural phrasing.

## 4. Core navigation and screens

Use a simple navigation structure appropriate for a personal claims
tool. Suggested primary destinations: 1. Dashboard 2. Claims 3.
Reminders / Follow-ups 4. Settings

A prominent Add Claim action should be easy to reach.

Required screens: - Dashboard - Claims list with filters and search -
Add claim - Edit claim - Claim details - Status update flow - Reminder
create/edit flow - Attachments picker/list/preview - Settings - Backup
and restore flow

Avoid creating extra screens unless they materially improve usability.

## 5. Dashboard

Show useful live summaries: - Total claims - Open claims - Closed
claims - Due for follow-up today - Overdue claims

Also show a concise "needs attention" section: - Overdue follow-ups
first - Follow-ups due today - Recently updated claims where useful

Every dashboard metric must be derived from the database, not hardcoded.
Tapping a metric should navigate to a correctly filtered claims list.

Define statuses consistently so that open/closed counts are accurate. A
claim is closed when its status is `مغلقة`; do not count `تم التعويض` as
closed unless the user explicitly closes it.

## 6. Claims list, search, and filters

Provide filters: - All - Open - Needs follow-up - Overdue - Closed

Search across: - Claim number - Customer name - Customer mobile number -
Accident number - Insured's insurance company - Claim-submitted-to
insurance company - Insurer reference number, if present

Search should be forgiving of leading/trailing spaces and should not
crash on Arabic/English mixed input.

Sort sensibly. Recommended default: overdue and due-soon claims first,
then most recently updated. Provide a clear way to change sort order if
useful.

Balanced claim card should show a useful subset: - Claim number -
Customer name - Insurer receiving the claim - Current status - Next
follow-up date/time, if any - A visible overdue/due-today indicator when
applicable

Do not put every field on the card.

## 7. Claim data model and forms

### 7.1 Customer information

-   Customer name --- required
-   Mobile number --- required
-   National ID --- optional
-   Email --- optional

### 7.2 Accident information

-   Accident number --- optional
-   Accident date --- required
-   City --- optional
-   Accident type --- optional
-   Vehicle plate number --- optional

### 7.3 Claim information

-   Claim number --- required
-   Customer's insurance company --- required
-   Insurance company to which the claim was submitted --- required
-   Claim submission date --- required
-   Insurer reference number --- optional
-   Claim amount --- optional, numeric, display SAR
-   Notes --- optional

### 7.4 Follow-up information

-   Current status
-   Date/time of last status update
-   Next follow-up date/time
-   Reminder enabled/disabled

Use clear validation messages in Arabic. Validate required fields and
numeric/date values. Preserve user input when validation fails.

Do not assume claim number is globally unique unless the product
implementation explicitly establishes and validates that rule. Prefer a
stable internal ID and allow business identifiers to be duplicated if
needed.

## 8. Default claim statuses

Implement these statuses: 1. جديدة 2. تم تقديم المطالبة 3. بانتظار
المراجعة 4. بانتظار مستندات 5. تحت المعالجة 6. بانتظار الموافقة 7. تمت
الموافقة 8. تم التعويض 9. مرفوضة 10. مغلقة

Use a consistent semantic color mapping with adequate contrast in Light
and Dark themes. Do not rely on color alone; always show the status
label.

Keep status definitions centralized. Do not scatter literal status
strings across the codebase.

A custom-status feature is not required for the first release.

## 9. Status history

Every status change must create a persistent history record
containing: - Claim ID - Previous status - New status - Timestamp -
Optional note

The claim's current status and its history record must be saved
atomically in a database transaction. If either write fails, roll back
both.

Display status history chronologically in claim details, newest or
oldest first consistently. The UI must clearly distinguish the current
status.

Changing a status should offer the user the option to set or adjust the
next follow-up date/time. Do not silently erase existing history.

## 10. Reminders and Android notifications

Reminders are a core feature and must work reliably.

Required capabilities: - Set a custom reminder date and time for each
claim. - Enable or disable a reminder. - Edit, reschedule, or dismiss a
reminder. - Support one-time reminders. - Support recurring reminders
with a user-selected interval in hours or days if technically reliable
within Android limits. - Display upcoming, due-today, and overdue
follow-ups inside the app. - Tapping a notification should open the
relevant claim details. - Closing a claim must cancel its future
scheduled reminders. - Deleting a claim must cancel its reminders and
remove related scheduled notification records. - When the status
changes, allow the user to schedule a new follow-up without deleting
prior status history.

### Android implementation requirements

-   Request notification permission appropriately on Android versions
    that require it.
-   Explain the permission in user-friendly Arabic before or alongside
    the system prompt.
-   Handle denied permission gracefully and show the user how to enable
    it in Android settings.
-   Use a maintained local-notifications package compatible with the
    selected Flutter/Android toolchain.
-   Account for Android notification channel requirements.
-   Persist reminder definitions in SQLite; do not rely only on
    in-memory scheduled jobs.
-   Reconcile/reschedule reminders after device reboot and app restart
    using supported Android mechanisms.
-   Handle timezone and daylight-saving/time changes safely. Use
    Asia/Riyadh as the default app timezone, but store timestamps in a
    consistent format (prefer UTC internally with local display).
-   Respect Android exact-alarm restrictions. Do not promise exact
    delivery if the OS does not grant exact-alarm capability. Use the
    best supported scheduling mode and explain any limitation in
    Settings.
-   Avoid duplicate notifications after rescheduling or reboot.
-   Test notification payload routing to the correct claim.

If recurring reminders are not dependable under the selected Android
APIs, implement a robust one-time reminder foundation first and document
the recurrence limitation rather than shipping a misleading or broken
control.

## 11. Claim details screen

Display: - All customer, accident, and claim information - Current
status - Last status update - Next follow-up date/time - Attachments -
Status history

Actions: - Edit claim - Change status - Set/edit/reschedule reminder -
Enable/disable reminder - Close claim - Delete claim with explicit
confirmation

No call, SMS, email, WhatsApp, or contact-history features are required.

## 12. Attachments

Allow attaching relevant files such as: - Images - PDF documents - Other
common document types where supported

Requirements: - Use Android's system file picker / photo picker through
maintained Flutter plugins. - Copy selected files into the app's private
local storage; do not rely on temporary picker URIs remaining valid. -
Associate each attachment with a claim using a stable ID. - Display
filename, type, and useful metadata. - Support opening/previewing
supported file types. - Handle missing, corrupt, or unsupported files
gracefully. - Delete physical files when an attachment is deleted, while
avoiding accidental deletion of unrelated files. - Do not upload
attachments.

## 13. Local database and architecture

Use Flutter + Dart and SQLite. Select a maintained database library (for
example, Drift or sqflite) based on compatibility, migration support,
and project simplicity. State the choice and rationale in the work log.

Suggested entities/tables: - `claims` - `status_history` - `reminders` -
`attachments` - `insurance_companies` - `app_settings`

Use stable primary keys, foreign keys where appropriate, indexes for
frequently searched fields, and database migrations.

Suggested indexes: - Claim number - Customer name - Customer mobile -
Accident number - Insurer reference number - Status - Next follow-up
timestamp

Use transactions for multi-table operations. Define deletion behavior
explicitly (cascade or controlled cleanup) and ensure attachment files
are cleaned safely.

Use a maintainable separation of concerns, such as: - `core/` ---
database, notifications, security, constants, utilities -
`features/dashboard/` - `features/claims/` - `features/reminders/` -
`features/attachments/` - `features/status_history/` -
`features/settings/` - `shared/` --- reusable widgets and common models

A pragmatic Clean Architecture approach is encouraged. Do not
over-engineer with unnecessary abstractions or packages.

## 14. Privacy and security

Claims contain sensitive personal and insurance information. Treat all
records as confidential.

Mandatory: - No backend, cloud sync, analytics, telemetry, or external
transmission of claim data. - Never log customer names, national IDs,
phone numbers, claim details, notes, or attachment contents. - Keep
database and attachments inside app-private storage. - Evaluate database
encryption using a maintained, compatible solution. If full database
encryption is implemented, securely manage the encryption key using
Android Keystore-backed secure storage where practical. - Do not
hardcode encryption keys in source code. - Use Android app sandbox
protections. - Consider an optional app lock using biometric
authentication or PIN if it can be implemented securely without
jeopardizing data access. It is not a blocker for the core release; do
not implement weak home-made cryptography. - Provide a local encrypted
backup and restore mechanism. - Validate backup integrity before
replacing existing data. - Do not overwrite current user data until
restore validation succeeds. - Use generic notification text by default
to avoid exposing sensitive customer data on the lock screen. A user may
opt into more detailed notification text if implemented safely.

Before real customer information is entered, the user must confirm that
local storage on the device and the app's handling of personal data
comply with their employer's policies and applicable Saudi privacy
requirements, including PDPL where relevant. Do not claim legal
compliance merely because the app is offline or encrypted.

## 15. Backup and restore

Provide a user-initiated local backup export and restore flow.

Requirements: - Backup should include database content and associated
attachments. - Encrypt the backup using a well-reviewed cryptographic
library and a user-provided passphrase or another secure design
documented by the agent. - Never invent or silently store a backup
password. - Verify backup integrity and version before restore. -
Provide clear warnings before restore replaces current local data. -
Make restore atomic or use a safe staging-and-swap strategy. - Handle
incorrect password, corrupt archive, missing files, and incompatible
versions. - Document the backup format and version it for future
migrations. - Do not send backup files to any server.

## 16. Settings

At minimum: - Theme selection (Light / Dark; System optional) -
Notification permission/status information - Reminder behavior
information, including Android exact-alarm limitations where relevant -
Backup and restore - App version/build information

Keep settings simple. Do not add account management, cloud sync, or
irrelevant preferences.

## 17. Quality, testing, and acceptance criteria

The app is not complete merely because it compiles. Verify behavior.

### Claims

-   Create a claim with required fields.
-   Validation blocks invalid submissions and preserves entered values.
-   Edit a claim and verify persistence.
-   Delete a claim after confirmation.
-   Search by each supported search field.
-   Verify all filters and dashboard counts.
-   Confirm data remains after force-close/reopen and device restart.

### Status history

-   Change status and verify current status updates.
-   Verify exactly one corresponding history entry is created.
-   Verify timestamps and optional notes.
-   Simulate a database write failure if feasible and verify
    transactional consistency.

### Reminders

-   Schedule a reminder and verify it is persisted.
-   Reschedule and ensure the old notification is cancelled.
-   Disable and verify cancellation.
-   Close a claim and verify future reminders are cancelled.
-   Reboot/restart and verify pending reminders are reconciled.
-   Tap a notification and verify the correct claim opens.
-   Verify permission-denied behavior.
-   Check timezone and date-boundary behavior.
-   Verify recurring behavior if included; otherwise document the
    limitation.

### Attachments and backup

-   Attach and open an image and PDF.
-   Verify attachments remain available after app restart.
-   Delete an attachment and verify safe file cleanup.
-   Export backup, restore it into a clean test state, and verify
    claims/history/reminders/attachments.
-   Verify incorrect password and corrupt backup fail safely.

### Privacy

-   Inspect logs for personal data leakage.
-   Confirm there are no network calls for claim data.
-   Confirm files are in app-private storage.
-   Verify backup encryption and restore validation.

### UI

-   Verify all screens in Light and Dark.
-   Verify Arabic RTL alignment and mixed Arabic/English identifiers.
-   Test small and large Android phone layouts.
-   Verify empty, error, loading, and validation states.
-   Ensure every visible control works.

### Build

-   Run formatter and static analysis.
-   Run unit/widget/integration tests that are practical.
-   Build a release APK.
-   Verify the APK file exists and report its exact path and size.
-   Install and launch it on an emulator or device if available.
-   Do not claim installation or runtime verification unless actually
    performed.

## 18. Development workflow and agent conduct

The implementation must be phased. Use the five prompts supplied with
this specification.

At the start of each phase: 1. Read this entire specification. 2. Read
`IMPLEMENTATION_PROGRESS.md` and `WORK_LOG.md` if present. 3. Inspect
the actual repository and environment. 4. Identify the current phase and
completed acceptance criteria.

At the end of each phase: 1. Run relevant formatting, analysis, tests,
and build checks. 2. Fix issues introduced by the phase. 3. Update
`IMPLEMENTATION_PROGRESS.md`. 4. Append decisions, commands, results,
known issues, and exact file paths to `WORK_LOG.md`. 5. Report what was
actually completed and what remains.

Agent rules: - Do not ask the user to choose ordinary technical
implementation details. Make a sensible, maintainable choice and
document it. - Ask only when a genuinely essential user decision,
permission, credential, or unavailable input blocks progress. - Do not
silently change approved product scope. - Do not create fake buttons,
placeholder workflows, hardcoded dashboard metrics, or pretend
functionality. - Do not skip tests to claim completion. - Do not claim a
test passed unless it ran and passed. - Do not claim a build succeeded
unless the build command completed successfully. - Never fabricate
screenshots, logs, APK paths, test results, or device verification. - If
blocked, explain the exact blocker, evidence, and smallest required user
action. - Preserve existing user work; inspect before modifying or
deleting files. - Keep the code simple, modular, and maintainable. - Do
not put secrets or personal customer data in source control or logs.

## 19. Required project handoff files

Maintain these files in the project root: - `MASTER_PROJECT_SPEC.md` ---
this specification. - `IMPLEMENTATION_PROGRESS.md` --- phase, completed
work, acceptance checklist, next action. - `WORK_LOG.md` --- dated
technical decisions, commands, outputs, test/build results, blockers. -
`README.md` --- setup, run, test, build, backup/restore notes, and known
limitations.

## 20. Definition of done

The first release is done only when: - All required core claim workflows
work. - Status history is correct and persistent. - Per-claim local
reminders work within documented Android OS limits. - Attachments and
backup/restore work safely. - Arabic RTL and both themes are polished. -
Acceptance checks have been run and results recorded. - No critical
known issue remains undisclosed. - A release APK has been built and its
exact verified path reported.

The final handoff must include: - APK path and file size - Build command
and result - Tests/analysis actually run and their outcomes - Features
completed - Known limitations - Installation instructions - Location of
progress and work-log files
