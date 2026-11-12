# PROMPT 5 --- FINAL QA, BUG FIXES, AND RELEASE APK

You are performing the final release-readiness phase for Claim Tracker.

## Mandatory preparation

Read the entire `MASTER_PROJECT_SPEC.md`, `IMPLEMENTATION_PROGRESS.md`,
and `WORK_LOG.md`. Inspect the actual repository. Do not assume earlier
phase reports are accurate; independently verify critical behavior.

## Scope for this phase

Implement Phase 5: - Complete acceptance testing. - Fix bugs and
regressions. - Polish UI consistency across all screens. - Verify Light
and Dark themes. - Verify Arabic RTL and mixed text. - Verify database,
status history, reminders, attachments, backup, and restore. - Run
release analysis and build an installable Android APK. - Prepare final
handoff documentation.

## Required checks

Use Section 17 and Section 20 of the master spec as the acceptance
checklist.

At minimum: 1. Formatter. 2. Static analysis. 3. Unit and widget tests.
4. Integration tests where practical. 5. Android release build. 6.
Verify APK exists and report exact path and file size. 7. Install and
launch on emulator/device if available. 8. Verify no critical runtime
crash in the tested flows. 9. Inspect logs for accidental personal data.
10. Verify no unexpected network dependency for core claim workflows.

Do not change product scope during final QA. If you discover a feature
that is incomplete, implement and test it if feasible. If not feasible,
document it clearly as a known limitation rather than disguising it.

## APK requirements

-   Build Android APK only.
-   Do not configure or build iOS.
-   Use the appropriate Flutter release build command for the project's
    actual configuration.
-   Do not invent signing credentials. If a production signing key is
    not provided, build a valid installable APK using the available
    debug or documented local signing configuration and clearly state
    the signing status.
-   Verify the exact output file exists before reporting its path.
-   Do not provide a guessed sandbox path or guessed project path.

## Final handoff report

Provide: - Exact APK path and file size - Exact build command and
result - Signing status - Tests and static analysis actually run, with
pass/fail counts where available - Device/emulator and Android version
used, if any - Features verified - Known limitations and untested
areas - Installation instructions - Location of README, progress file,
and work log

Never fabricate a test, screenshot, build, install, or runtime result.
If blocked, identify the precise blocker and the smallest user action
needed.
