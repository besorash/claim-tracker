# PROMPT 2 --- CORE UI, DASHBOARD, AND CLAIM MANAGEMENT

You are continuing the Claim Tracker implementation.

## Mandatory preparation

Read `MASTER_PROJECT_SPEC.md`, `IMPLEMENTATION_PROGRESS.md`, and
`WORK_LOG.md` completely. Inspect the repository and verify Phase 1
artifacts exist. Do not assume prior work is correct; run relevant
checks if necessary.

## Scope for this phase

Implement Phase 2 only: - Premium Modern design system. - Complete Light
and Dark themes with persisted selection. - Arabic-first RTL navigation
and reusable components. - Dashboard with database-backed metrics. -
Claims list with Balanced Cards. - Search and filters. - Add claim
form. - Edit claim form. - Claim details screen. - Claim CRUD and
persistence. - Basic Settings screen including theme selection.

## Design is mandatory

Follow the approved design: - Premium Modern Business App. -
Navy/deep-blue/teal accents with accessible semantic tokens. - Light +
Dark modes. - Balanced claim cards: clear, useful, not overcrowded. -
Polished typography, spacing, cards, buttons, icons, dialogs, and
transitions. - Arabic default and correct RTL. - Do not use
default-looking Flutter scaffolding as the finished design. - Check
every implemented screen in both themes.

## Functional requirements

Follow Sections 5--8, 11, and 16 of `MASTER_PROJECT_SPEC.md`. All
dashboard values must come from SQLite. Search must cover every
specified field. Filters must work. Required form fields must validate
in Arabic. Claim data must persist after app restart.

Do not implement contact history, calls, SMS, email, WhatsApp, cloud, or
insurer integrations.

## Verification required

-   Run formatter and static analysis.
-   Run unit/widget tests for CRUD, validation, search, filters, and
    dashboard calculations.
-   Build the Android debug APK.
-   Manually inspect or run the app on an emulator/device if available.
-   Verify RTL, mixed Arabic/English identifiers, and both themes.
-   Fix all issues introduced by this phase.

## Handoff

Update progress and work log with: - Screens/features completed - Design
and architecture decisions - Database behavior - Commands and actual
test outcomes - Screens/device sizes/themes checked - Known issues -
Exact next step for Prompt 3

Do not proceed to reminders/status history beyond any minimal model
groundwork needed. Do not claim visual verification if you did not run
the app.
