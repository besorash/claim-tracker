# PROMPT 4 --- ATTACHMENTS, PRIVACY, SECURITY, BACKUP, AND RESTORE

Continue the Claim Tracker project.

## Mandatory preparation

Read `MASTER_PROJECT_SPEC.md`, `IMPLEMENTATION_PROGRESS.md`, and
`WORK_LOG.md`. Inspect and verify previous phases before changing code.

## Scope for this phase

Implement Phase 4: - Claim attachments for images, PDFs, and supported
common files. - Copy selected files into app-private local storage. -
Attachment listing and supported preview/open behavior. - Safe
attachment deletion and cleanup. - Privacy/security hardening. - Local
encrypted backup and restore. - Settings UI for backup/restore and
relevant security information.

## Attachments

Follow Section 12 of the master spec. Use Android system pickers through
maintained plugins. Copy selected content into app-private storage; do
not depend on temporary picker URIs. Store metadata and stable
relationships in SQLite. Handle missing or unsupported files gracefully.

## Security and privacy

Follow Section 14: - No claim data network transmission. - No analytics
or telemetry. - No personal data in logs. - App-private database and
files. - Evaluate and implement a maintained database-encryption
approach where compatible. - Protect keys appropriately; never hardcode
keys. - Do not invent cryptography or claim encryption without verifying
it. - Generic notification content by default. - Optional biometric/PIN
lock is lower priority than secure data handling; do not implement weak
authentication.

## Backup and restore

Follow Section 15: - Include database and attachments. - Use a reviewed
cryptographic library and a documented encryption design. - Require a
user-supplied passphrase or another properly designed secure
mechanism. - Version the backup format. - Verify password, integrity,
and compatibility before restore. - Stage restore safely; never destroy
existing user data before validation succeeds. - Handle corrupt
archives, wrong passwords, missing attachments, and incompatible
versions. - No server upload.

## Verification required

-   Attach and reopen an image and PDF.
-   Verify persistence after app restart.
-   Delete attachment and verify safe cleanup.
-   Export and restore a backup in a clean test state.
-   Verify restored claims, status history, reminders, and attachment
    links.
-   Verify incorrect password/corrupt backup failure does not damage
    existing data.
-   Inspect logs for sensitive values.
-   Verify no network transmission of claim data.
-   Run formatter, static analysis, tests, and Android debug build.

## Handoff

Record encryption design, key handling, backup format, test evidence,
actual commands/results, and known limitations. Update progress and work
log. Do not claim security certification or legal compliance.
