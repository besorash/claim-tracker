# Contact picker + tap-to-call — design (short)

Date: 2026-11-13 · Status: approved by user (approach delegated to builder; constraints below are the user's)

## Intent & why

The claim form has two phone fields — **customer mobile** and **insurance company
mobile**. Typing Saudi numbers is slow and error-prone. The user wants to fill
either field from the device contact list, keep manual typing available, and be
able to tap a stored number later to call it directly from the app.

## User constraints (verbatim intent)

1. Must work on **iOS** when built later — not just Android.
2. Each phone field must support **both**: manual entry **and** pick-from-contacts.

## Goals

- "Pick from contacts" affordance on both phone fields in add/edit claim form;
  selection fills that field with the chosen number (editable afterwards).
- Tap-to-call for both stored numbers on the claim details screen → system dialer.
- EN + AR strings for all new UI text (existing l10n pipeline, `S` facade).
- Full existing test suite green + new tests; no regressions or conflicts.
- APK built and installed on emulator `emulator-5554`; app launches clean.

## Non-goals

- No contacts browsing/search UI in the app (system picker only).
- No saving of the contact's name — only the number enters the claim.
- No SMS/messenger actions; dialer (`tel:`) only.
- No iOS build/verification here (no macOS host); iOS code path implemented and
  consistent, verified by review + shared Dart tests.

## Constraints

- Existing architecture: native MethodChannel seams with injectable Dart fakes in
  widget tests (`com.claimtracker/permissions`, `com.claimtracker/files` precedent;
  `openExternal` seam pattern). New code follows the same shape.
- Saudi-number validation unchanged: a picked number goes through the same
  validator as typed input (invalid → existing inline error on save).
- minSdk 23 / compileSdk 37, Java 17, no new pub dependencies.

## Approaches considered

| Option | Trade-off | Verdict |
|---|---|---|
| **A) Native contact-picker channel** (Android `ACTION_PICK`, iOS `CNContactPickerViewController`) | Small native code per platform; zero deps; **no contacts permission prompt**; hands back exactly one number | **Chosen** — best fits both user constraints and the project's existing channel seams |
| B) Contacts plugin (e.g. `contacts_service`) | Extra dependency; requires READ_CONTACTS runtime permission (system dialog); list-oriented API, not picker-first | Rejected for this scenario |

## Decisions (builder's calls unless noted)

- **Channel**: `com.claimtracker/contacts`, one method `pickContactPhone` →
  returns `{ "phone": String }` or null on cancel. Number only — keeps both
  platforms minimal and identical in shape.
- **Android** (`MainActivity.kt`): ActivityResultLauncher with
  `ACTION_PICK` + `Phone.CONTENT_ITEM_TYPE`; query the returned URI for
  `PHONE_NUMBER`. The pick flow grants temporary read access — no manifest
  permission needed (verified against existing manifest: none added).
- **iOS** (`AppDelegate.swift`): `CNContactPickerViewController`; picker-only use
  needs no `NSContactsUsageDescription` and no authorization request. Returns the
  selected contact's preferred phone number.
- **Dart seam**: `ContactPhonePicker` abstract in `lib/core/contacts/`,
  default implementation over the MethodChannel; both screens accept an injected
  instance so widget tests use a fake (same pattern as `openExternal`).
- **Form UI**: suffix icon (`person_add`) on each phone field with tooltip + l10n
  label; tapping opens the picker; result is written into the field's controller
  and model, clearing any prior validation error for that field.
- **Details UI**: both phone rows become tappable (phone icon affordance); launch
  `tel:<normalized>` via url_launcher; failure shows an Arabic/English snackbar.
- **New strings** (EN+AR): picker tooltip/hint, "call" label, call-failed message.

## Test plan

- Unit: channel-result parsing in the Dart seam (valid / null / malformed).
- Widget (form): pick buttons present on both fields; fake picker fills customer
  and insurer fields independently; manual entry still works; validation applies to
  picked values.
- Widget (details): phone rows tappable, `tel:` launch recorded via injected
  seam; failure path shows snackbar.
- Full suite (`flutter analyze` + `flutter test`) must pass — this is the
  "no conflicts with other features" proof.

## Build & install

`flutter build apk --release` → `adb -s emulator-5554 install` → launch smoke:
app starts, form opens, no crashes (logcat clean). The system picker/dialer are
OS surfaces; verified by code review + emulator presence of the contacts app.
