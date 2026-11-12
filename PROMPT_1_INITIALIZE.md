# PROMPT 1 --- INITIALIZE PROJECT AND FOUNDATION

You are the implementation agent for **Claim Tracker**.

## First: read the source of truth

Read `MASTER_PROJECT_SPEC.md` completely. It is authoritative. Inspect
the current workspace/repository before changing anything. If
`IMPLEMENTATION_PROGRESS.md` or `WORK_LOG.md` exists, read them too.

## Scope for this phase

Implement Phase 1 only: - Inspect available Flutter, Dart, Android SDK,
Java, Gradle, and build tooling. - Report versions and any blockers. -
Create or initialize the Flutter Android project in the current intended
project directory. - Do not configure iOS, web, or desktop targets. -
Select compatible maintained dependencies for SQLite, notifications
(foundation only in this phase), file picking (later use), secure
storage, and testing as appropriate. - Establish a pragmatic,
maintainable folder structure aligned with the master spec. - Create the
database layer and initial schema/migrations for the core entities. -
Establish theme tokens and Arabic RTL app foundation without attempting
all screens yet. - Create README, `IMPLEMENTATION_PROGRESS.md`, and
`WORK_LOG.md`.

## Technical expectations

-   Choose a compatible SQLite library and document why.
-   Define stable IDs, timestamps, foreign keys, indexes, and migration
    strategy.
-   Keep database access out of UI widgets.
-   Define centralized status constants and semantic theme colors.
-   Configure Arabic localization/RTL as the default.
-   Configure Android app metadata with a sensible app name and package
    ID. If a package ID is not already specified by the repository,
    choose a neutral reverse-domain identifier and document it; do not
    ask the user for routine naming decisions.
-   Do not add unnecessary dependencies.

## Verification required before finishing

-   Run `flutter doctor -v` or the available equivalent.
-   Run dependency resolution.
-   Run formatter.
-   Run static analysis.
-   Run an Android debug build.
-   Run database schema/migration tests or a minimal smoke test.
-   Fix all errors introduced by this phase.

If the environment lacks a required tool, do not pretend it exists.
Record the exact missing tool and what remains blocked.

## Boundaries

-   Do not build the complete application in this phase.
-   Do not add backend, authentication, cloud sync, telemetry, or
    contact logging.
-   Do not start Phase 2 until Phase 1 checks have been executed and
    recorded.
-   Do not delete or overwrite existing project files without inspecting
    them first.

## Handoff

Update `IMPLEMENTATION_PROGRESS.md` and append to `WORK_LOG.md`: -
Environment/tool versions - Architecture and dependency decisions -
Files created/changed - Commands executed - Actual test/build outcomes -
Known issues - Exact next step for Prompt 2

Finish with a concise factual report. Never say "passed" unless the
command actually passed.
