# Claim Tracker --- AI Agent Implementation Package

This package is for building **Claim Tracker**, an Android-first,
offline personal claims-management app.

## Package contents

-   `MASTER_PROJECT_SPEC.md` --- authoritative product, technical, UX,
    security, and acceptance specification.
-   `PROMPT_1_INITIALIZE.md` --- inspect the environment and establish
    the project foundation.
-   `PROMPT_2_CORE_UI_AND_CLAIMS.md` --- dashboard, claims list, CRUD,
    search, and details.
-   `PROMPT_3_STATUSES_AND_REMINDERS.md` --- status workflow, history,
    and local notifications.
-   `PROMPT_4_ATTACHMENTS_SECURITY_BACKUP.md` --- attachments,
    privacy/security, and encrypted backup/restore.
-   `PROMPT_5_FINAL_QA_AND_APK.md` --- final verification, fixes, and
    APK build.

## How to use

1.  Give the agent `MASTER_PROJECT_SPEC.md` first, or place it in the
    project root.
2.  Start with Prompt 1.
3.  Do not skip phases. Give the next prompt only after the previous
    phase has passed its checks.
4.  Keep the spec and progress files in the project repository.
5.  If the agent session ends, resume by asking it to read
    `MASTER_PROJECT_SPEC.md`, `IMPLEMENTATION_PROGRESS.md`, and
    `WORK_LOG.md` before continuing.

## Important boundaries

-   Android only for this release. Do not configure or build iOS.
-   Single user, local-only storage. No backend, account system, cloud
    sync, analytics, or telemetry.
-   Per-claim custom reminders.
-   No contact/call communication log.
-   Arabic-first RTL interface.
-   Design system: Premium Modern, Light + Dark themes, Balanced claim
    cards.
-   The agent must not claim that a test or build succeeded unless it
    actually ran and verified it.
