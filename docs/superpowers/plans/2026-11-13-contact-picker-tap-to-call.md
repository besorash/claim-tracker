# Contact Picker + Tap-to-Call Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let the user fill both claim phone fields (customer mobile, insurance company mobile) from the device contact list — alongside manual typing — and tap a stored number on the details screen to call it via the system dialer. Works on Android now; iOS path implemented for later builds.

**Architecture:** A thin Dart seam (`ContactPhonePicker`) over one MethodChannel `com.claimtracker/contacts` (method `pickContactPhone` → `{phone: String}` or null). Android implements it with an `ACTION_PICK` launcher in `MainActivity.kt`; iOS with `CNContactPickerViewController` in `AppDelegate.swift` — both permission-free pickers, matching the project's existing native-channel seams (`com.claimtracker/permissions`, `com.claimtracker/files`). Tap-to-call reuses `url_launcher` (already a dependency) behind an injectable `callNumber` seam on the details screen.

**Tech Stack:** Flutter 3.47 / Dart 3.13, Kotlin (androidx.activity result API), Swift/Contacts framework, url_launcher, existing gen-l10n pipeline (`lib/l10n/*.arb`, `S` facade).

**Spec:** `docs/superpowers/specs/2026-11-13-contact-picker-tap-to-call-design.md`

## Global Constraints

- No new pub dependencies; channel name is exactly `com.claimtracker/contacts`, method exactly `pickContactPhone`.
- minSdk 23 / compileSdk 37, Java 17 target (android/app/build.gradle.kts).
- Every user-facing string ships in EN **and** AR via `lib/l10n/app_en.arb` + `app_ar.arb`, exposed through the `S` facade (`lib/core/l10n/app_strings.dart`).
- Layout must stay RTL-correct (use `TextAlignDirectional`/`MainAxisAlignment` as existing rows do — see `_row` in claim_details_screen.dart).
- Saudi-number validation is UNCHANGED: a picked number passes through the same validators as typed input.
- Widget tests never touch method channels: screens take injectable seams; fakes are passed by existing test harnesses.

## Review Focus

1. **Contact with no phone number** → picker returns "no number" (null / empty) and the field stays exactly as it was — no crash, no snackbar. Pinned in Task 1 (seam: `{'phone': ''}` → null) + Task 2 (cancel/fake-null test).
2. **Contact with an international-format or spaced number** (`+9665…`, `00966…`) → passes the existing validator and stores cleanly. Pinned in Task 2 ("international picked number saves").
3. **Channel failure vs cancel must be distinguishable**: platform error → UI shows `S.contactPickFailed`; user cancel → silent no-op. Pinned in Task 1 (exception propagates) + Task 2 (failure snackbar test).
4. **Dialer launch fails** (no dial app, exception) → snackbar `S.callFailed`, no crash — even if the injected caller throws. Pinned in Task 3 (false + throwing tests).
5. **Engine recreation / hot restart re-running native setup on Android** → launcher must not be registered twice (IllegalStateException). Not host-testable; pinned by code inspection of Task 4's null-guard (`if (pickLauncher == null)`) during review — reviewer MUST check this line exists before approving.

---

## File Structure

| Path | Change | Responsibility |
|---|---|---|
| `lib/core/contacts/contact_phone_picker.dart` | Create | Seam: abstract `ContactPhonePicker` + `PlatformContactPhonePicker` over the MethodChannel (parsing, null/throw contract) |
| `lib/l10n/app_en.arb`, `lib/l10n/app_ar.arb` | Modify | 3 new strings each (`pickFromContacts`, `contactPickFailed`, `callFailed`) + generated files via `flutter gen-l10n` |
| `lib/core/l10n/app_strings.dart` | Modify | 3 new `S` getters |
| `lib/features/claims/claim_form_screen.dart` | Modify | Constructor seam param, suffix pick buttons on both phone fields, `_pickFromContacts(key)` |
| `lib/features/claims/claim_details_screen.dart` | Modify | Constructor `callNumber` seam, tappable `_phoneRow`, `_dial` default via url_launcher |
| `android/app/src/main/kotlin/com/claimtracker/claim_tracker/MainActivity.kt` | Modify | `com.claimtracker/contacts` channel + ACTION_PICK launcher |
| `ios/Runner/AppDelegate.swift` | Modify | `com.claimtracker/contacts` channel + `CNContactPickerViewController` handler class |
| `test/core/contact_phone_picker_test.dart` | Create | Seam unit tests (mock method channel) |
| `test/features/claim_form_screen_test.dart` | Modify | Pick-button widget tests with a fake picker |
| `test/features/claim_details_screen_test.dart` | Modify | Tap-to-call widget tests with a recording caller |

Task dependency: 1 → 2, 1 → 3 (seam + strings first); 4 and 5 implement the channel contract pinned by Task 1's tests; 6 is the full gate.

---

### Task 1: Dart contact-picker seam + l10n strings

**Files:**
- Create: `lib/core/contacts/contact_phone_picker.dart`
- Create: `test/core/contact_phone_picker_test.dart`
- Modify: `lib/l10n/app_en.arb`, `lib/l10n/app_ar.arb` (plain `"key": "value",` entries, matching neighbors)
- Modify: `lib/core/l10n/app_strings.dart` (3 getters in a new `// Contacts / calls.` section after the Validation block)

**Interfaces:**
- Consumes: nothing (foundation task).
- Produces:
  - `abstract class ContactPhonePicker { Future<String?> pickContactPhone(); }` — null = user cancelled or chosen contact has no phone; **throws** on platform failure.
  - `class PlatformContactPhonePicker implements ContactPhonePicker` with `const PlatformContactPhonePicker({MethodChannel? channel})`; default channel `com.claimtracker/contacts`, method `pickContactPhone`. Result map `{phone: String}`; non-map or empty phone → null.
  - Strings: `S.pickFromContacts`, `S.contactPickFailed`, `S.callFailed` (EN: "Add from contacts" / "Couldn't open the contact picker" / "Couldn't open the dialer"; AR: "إضافة من جهات الاتصال" / "تعذّر فتح جهات الاتصال" / "تعذّر فتح الهاتف").

- [ ] **Step 1: Write the failing seam tests** in `test/core/contact_phone_picker_test.dart`.

Use `TestWidgetsFlutterBinding.ensureInitialized()` + `tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, ...)` with `const MethodChannel channel = MethodChannel('com.claimtracker/contacts');` (or plain `test(...)` after binding init). Five cases:
  - handler returns `<String, Object?>{'phone': '0551234567'}` → `pickContactPhone()` == `'0551234567'`; also assert the call log shows method name `pickContactPhone`.
  - handler returns null → result isNull.
  - handler returns `<String, Object?>{'phone': ''}` → result isNull (Review Focus #1).
  - handler returns a bare string `'oops'` (wrong shape) → result isNull (lenient parse).
  - handler throws `PlatformException(code: 'picker_unavailable')` → `expect(() => picker.pickContactPhone(), throwsA(isA<Object>()))` — failure must propagate so the form can surface it (Review Focus #3).

- [ ] **Step 2: Run to verify they fail**

Run: `flutter test test/core/contact_phone_picker_test.dart`
Expected: FAIL — `contact_phone_picker.dart` doesn't exist yet.

- [ ] **Step 3: Implement the seam + strings**

Create `lib/core/contacts/contact_phone_picker.dart`: doc comment referencing the design spec; abstract class with one method and a contract comment (null = cancel/no number, throw = platform failure); `PlatformContactPhonePicker` doing `await _channel.invokeMethod<Object>('pickContactPhone')`, lenient map parse (`(result as Map?)?['phone']?.toString()`), empty → null. No other logic — parsing stays in the seam so both screens share it.

Add the 3 EN + AR arb entries (exact strings above) next to `invalidNumber`; add the 3 getters to `app_strings.dart`.

- [ ] **Step 4: Regenerate l10n and run tests**

Run: `flutter gen-l10n` then `flutter test test/core/contact_phone_picker_test.dart` and `flutter analyze`
Expected: PASS (5/5); analysis clean, with all three new `S.*` getters resolving.

- [ ] **Step 5: Commit**

```bash
git add lib/core/contacts/contact_phone_picker.dart test/core/contact_phone_picker_test.dart lib/l10n/app_en.arb lib/l10n/app_ar.arb lib/l10n/app_localizations*.dart lib/core/l10n/app_strings.dart
git commit -m "feat: contact-picker seam, call strings (EN/AR)"
```

---

### Task 2: Form screen — pick-from-contacts on both phone fields

**Files:**
- Modify: `lib/features/claims/claim_form_screen.dart`
- Test: `test/features/claim_form_screen_test.dart`

**Interfaces:**
- Consumes: `ContactPhonePicker`, `PlatformContactPhonePicker`, `S.pickFromContacts`, `S.contactPickFailed` (Task 1).
- Produces:
  - New optional constructor param on `ClaimFormScreen`: `final ContactPhonePicker? picker;` — when null the screen uses `const PlatformContactPhonePicker()`. Existing callers/tests unaffected.
  - Suffix `IconButton`s with keys `Key('pick-mobile')` and `Key('pick-insMobile')`, tooltip `S.pickFromContacts`, icon `Icons.person_add_outlined`.

- [ ] **Step 1: Write the failing widget tests** in `claim_form_screen_test.dart`.

First extend the existing harness: add a `ContactPhonePicker? picker` named param to `_harness({Claim? claim, List<Claim>? saved})` and pass it through to `ClaimFormScreen(...)`. Add a fake next to the other helpers:

```dart
/// Recording [ContactPhonePicker] for widget tests (no method channels).
class FakeContacts implements ContactPhonePicker {
  String? returnValue = '0559876543'; // null simulates cancel / no number
  bool shouldThrow = false;
  int calls = 0;

  @override
  Future<String?> pickContactPhone() async {
    calls++;
    if (shouldThrow) throw PlatformException(code: 'picker_unavailable');
    return returnValue;
  }
}
```

New tests (follow the file's existing style — `tappable()` helper before tapping, Arabic locale harness as-is):
  - **'picking from contacts fills the customer mobile field'**: fake returns `'0559876543'`; tap `Key('pick-mobile')`; expect `tester.widget<TextField>(field('mobile')).controller!.text` == `'0559876543'` and `fake.calls == 1`.
  - **'picking fills customer and insurer mobiles independently'**: pick `'0559876543'` into mobile, then change fake to `'0561234567'` and tap `Key('pick-insMobile')`; expect both fields hold their own values (proves the write goes through `_onChanged(key, …)` — i.e. `find.text('0561234567'), findsOneWidget`).
  - **'cancelling the picker leaves the field untouched'**: fake returns null (start with an empty field); tap pick; expect text stays `''` and no snackbar appears (`find.byType(SnackBar)`, `findsNothing`).
  - **'a failed picker shows contactPickFailed and keeps the field'** (Review Focus #3): fake.shouldThrow = true, pre-type `'abc'` into mobile via enterText; tap pick; expect `find.text(S.contactPickFailed), findsOneWidget`; field text still `'abc'`.
  - **'an international picked number passes validation and saves'** (Review Focus #2): fake returns `'+966551234567'` into mobile; fill the other required fields like the existing "valid add" test does (`customerName`, `plate`, `vehicleType`, insurer via `chooseInsurer`, dates via `pickDate`); tap save; expect saved list has one claim with `customerMobile == '+966551234567'` and no `S.invalidNumber` text anywhere.

- [ ] **Step 2: Run to verify they fail**

Run: `flutter test test/features/claim_form_screen_test.dart --plain-name "picking from contacts fills the customer mobile field"`
Expected: FAIL — widget with key `pick-mobile` not found (or constructor error).

- [ ] **Step 3: Implement in `claim_form_screen.dart`**

Add imports for Task 1's seam. Add the `picker` param to the constructor + a field doc comment ("OS contact-picker seam; defaults to the production channel — widget tests inject a fake"). Extend `_field(…)` with an optional `VoidCallback? onPickSuffix`: when non-null, set `decoration.suffixIcon = IconButton(key: Key('pick-$key'), tooltip: S.pickFromContacts, icon: Icon(Icons.person_add_outlined), onPressed: onPickSuffix)`. Wire the two phone fields: `_field('mobile', label: S.mobileLabel, number: true, onPickSuffix: () => _pickFromContacts('mobile'))` and same for `'insMobile'`. Add:

```dart
Future<void> _pickFromContacts(String key) async {
  final ContactPhonePicker picker = widget.picker ?? const PlatformContactPhonePicker();
  String? phone;
  try {
    phone = await picker.pickContactPhone();
  } on Object catch (_) {
    // Platform failure — distinct from a cancel (null): surface it.
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(S.contactPickFailed)),
    );
    return;
  }
  if (phone == null || !mounted) return; // user cancelled — field untouched
  setState(() {
    _controllers[key]!.text = phone;
    _onChanged(key, phone);
    _errors[key] = null; // a fresh valid-looking value clears any prior error
  });
}
```

- [ ] **Step 4: Run the whole form test file**

Run: `flutter test test/features/claim_form_screen_test.dart`
Expected: PASS — new tests AND all pre-existing ones (input preservation, validation counts like `findsNWidgets(5)` for required errors must stay green).

- [ ] **Step 5: Commit**

```bash
git add lib/features/claims/claim_form_screen.dart test/features/claim_form_screen_test.dart
git commit -m "feat: pick phone from contacts on both claim-form fields"
```

---

### Task 3: Details screen — tap-to-call rows for both numbers

**Files:**
- Modify: `lib/features/claims/claim_details_screen.dart`
- Test: `test/features/claim_details_screen_test.dart`

**Interfaces:**
- Consumes: `S.callFailed` (Task 1); existing `url_launcher`.
- Produces:
  - New optional constructor param on `ClaimDetailsScreen`: `final Future<bool> Function(String phoneNumber)? callNumber;` — default implementation launches `tel:<number>` via url_launcher and returns success.
  - Tappable phone rows with stable keys `Key('call-customerMobile')` and `Key('call-insuranceMobile')`, each showing the existing label + value plus a trailing `Icons.call` affordance (existing text layout preserved so current `find.text(…)` assertions keep passing).

- [ ] **Step 1: Write the failing widget tests** in `claim_details_screen_test.dart`.

Extend `_harness(db, id, {scheduler, picker, files, openExternal})` with a `Future<bool> Function(String)? callNumber` param passed through to `ClaimDetailsScreen(...)`. Add a recorder next to `FakeScheduler`:

```dart
/// Recording dialer for widget tests — no url_launcher channel touched.
class FakeDialer {
  final List<String> called = [];
  bool result = true; // false → snackbar path
  bool shouldThrow = false;

  Future<bool> call(String phone) async {
    if (shouldThrow) throw StateError('dialer unavailable');
    called.add(phone);
    return result;
  }
}
```

New tests (inside `tester.runAsync` like their neighbors, using existing `seedFull()` / `seedInsurer(...)` + `openDetails` + `settle`):
  - **'tapping the customer mobile row dials it'**: seedFull (mobile `'0559876543'`); inject recorder; settle on `find.text('0559876543')`; tap `Key('call-customerMobile')`; expect `recorder.called == ['0559876543']`.
  - **'both phone rows dial their own number'**: seedInsurer `'0561234567'` (customer `'0501234567'`); tap `Key('call-insuranceMobile')`, then `Key('call-customerMobile')`; expect order `['0561234567', '0501234567']`.
  - **'a failed dial shows callFailed'** (Review Focus #4): recorder.result = false; tap customer row; expect `find.text(S.callFailed), findsOneWidget`; no crash (`tester.takeException()` isNull).
  - **'a throwing dialer is caught and reported'**: recorder.shouldThrow = true; tap; same expectations as above.

- [ ] **Step 2: Run to verify they fail**

Run: `flutter test test/features/claim_details_screen_test.dart --plain-name "tapping the customer mobile row dials it"`
Expected: FAIL — key `call-customerMobile` not found (or constructor error).

- [ ] **Step 3: Implement in `claim_details_screen.dart`**

Add the `callNumber` param with a doc comment mirroring `openExternal`. Replace the two phone `_row(…)` calls (customer section + claim section) with a new `_phoneRow(theme, label, value, id)`: same visual layout as `_row` (label start / value end, RTL-safe) wrapped in an `InkWell(key: Key('call-$id'), borderRadius 8, onTap: () => _tapCall(value))` with a trailing `Icon(Icons.call, size: 18)` colored via `AppTheme.muted(context)`. Add:

```dart
Future<void> _tapCall(String number) async {
  final Future<bool> Function(String) call = widget.callNumber ?? _dial;
  bool ok;
  try {
    ok = await call(number);
  } on Object catch (_) {
    ok = false; // a throwing dialer must never crash the screen
  }
  if (!mounted) return;
  if (!ok) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(S.callFailed)),
    );
  }
}

/// Default dialer: hand the number to the OS via `tel:` (url_launcher,
/// already a dependency — same channel family as attachment opens).
Future<bool> _dial(String number) async {
  try {
    return await launchUrl(Uri(scheme: 'tel', path: number.trim()));
  } on Object catch (_) {
    return false;
  }
}
```

- [ ] **Step 4: Run the whole details test file**

Run: `flutter test test/features/claim_details_screen_test.dart`
Expected: PASS — new tests AND all pre-existing ones (including "insurer mobile is shown" `findsOneWidget('0561234567')`, which must still hold with the tappable row).

- [ ] **Step 5: Commit**

```bash
git add lib/features/claims/claim_details_screen.dart test/features/claim_details_screen_test.dart
git commit -m "feat: tap-to-call rows for customer and insurer mobiles"
```

---

### Task 4: Android native channel (ACTION_PICK)

**Files:**
- Modify: `android/app/src/main/kotlin/com/claimtracker/claim_tracker/MainActivity.kt`

**Interfaces:**
- Consumes: the contract pinned by Task 1's tests — channel `com.claimtracker/contacts`, method `pickContactPhone`, reply `{phone: String}` or null.
- Produces: working Android-side implementation; no new manifest permission (the pick flow grants a one-off read on the returned row).

- [ ] **Step 1: Implement in MainActivity.kt**

Keep the existing battery channel untouched. Add fields + setup inside `configureFlutterEngine` after it:

```kotlin
/// Pending result of an in-flight contact pick (at most one at a time) and its launcher,
/// registered once — re-registration on engine recreation would throw IllegalStateException.
private var pendingPickResult: MethodChannel.Result? = null
private var pickLauncher: ActivityResultLauncher<Intent>? = null
```

Inside `configureFlutterEngine` (after the existing channel setup): guard `if (pickLauncher == null)` → register via `registerForActivityResult(ActivityResultContracts.StartActivityForResult()) { result -> … }`. In the callback: take `pendingPickResult`, clear it, then best-effort query — on any exception reply null (never crash into a red screen from here):

```kotlin
result.resultData?.data?.let { uri ->
    contentResolver.query(
        uri, arrayOf(ContactsContract.PhoneColumns.NUMBER), null, null, null
    )?.use { c -> if (c.moveToFirst()) phone = c.getString(0) }
}
callback.success(phone?.let { mapOf("phone" to it) })
```

Channel handler for `pickContactPhone`: reject a second concurrent pick (`pendingPickResult != null` → reply null); otherwise store the result, then `launch(Intent(ContactsContract.Intents.PICK).apply { type = ContactsContract.Phone.CONTENT_ITEM_TYPE })`; catch `Exception` (e.g. no contacts app) → clear pending and reply null. Imports: `android.content.Intent`, `android.net.Uri` (only if needed), `android.provider.ContactsContract`, `androidx.activity.result.ActivityResultLauncher`, `androidx.activity.result.contract.ActivityResultContracts`.

- [ ] **Step 2: Verify the Kotlin compiles**

Run: `cd android && .\gradlew.bat :app:compileReleaseKotlin --console=plain -q`
Expected: BUILD SUCCESSFUL (no Kotlin errors). If `registerForActivityResult` is unresolved on this toolchain, fall back to classic `startActivityForResult(intent, 1001)` + an `onActivityResult` override in the same class — same contract, and re-run until green.

- [ ] **Step 3: Commit**

```bash
git add android/app/src/main/kotlin/com/claimtracker/claim_tracker/MainActivity.kt
git commit -m "feat(android): contact-picker channel (ACTION_PICK, no permission)"
```

---

### Task 5: iOS native channel (CNContactPickerViewController)

**Files:**
- Modify: `ios/Runner/AppDelegate.swift`

**Interfaces:**
- Consumes: same contract as Task 4 (channel `com.claimtracker/contacts`, method `pickContactPhone`).
- Produces: working iOS-side implementation. Picker-only use needs **no** `NSContactsUsageDescription` and no authorization request — do NOT add one.

- [ ] **Step 1: Implement in AppDelegate.swift**

Add `import Contacts`. In `didInitializeImplicitFlutterEngine`, after the existing attachment-preview block, register (mirror its shape exactly): retain the handler on a new stored property `private var contactPickerHandler: ContactPickerHandler?` (same lifetime concern as `attachmentPreviewer`), registrar key `"ClaimTrackerContactPicker"`, channel name `"com.claimtracker/contacts"`. Add the class after `AttachmentPreviewer`:

```swift
/// Contact-picker channel (spec §7): method `pickContactPhone` opens the system
/// picker; replies ["phone": String] for the chosen number, or nil on cancel /
/// no phone. Picker-only — presenting CNContactPickerViewController does not
/// require NSContactsUsageDescription or contact-access authorization.
final class ContactPickerHandler: NSObject, CNContactPickerDelegate {
    private var pendingResult: FlutterResult?

    func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard call.method == "pickContactPhone" else {
            result(FlutterMethodNotImplemented); return
        }
        pendingResult = result
        let picker = CNContactPickerViewController()
        picker.delegate = self
        Self.topViewController()?.present(picker, animated: true, completion: nil)
    }

    func contactPickerDidCancel(_ picker: CNContactPickerViewController) {
        pendingResult?(nil); pendingResult = nil
    }

    @objc func contactPicker(_ picker: CNContactPickerViewController, didSelect contact: CNContact) {
        let phone = (contact.phoneNumbers.first?.value as String?) ?? ""
        pendingResult?(phone.isEmpty ? nil : ["phone": phone])
        pendingResult = nil
    }

    private static func topViewController() -> UIViewController? { /* same 6-line walk as AttachmentPreviewer.topViewController */ }
}
```

- [ ] **Step 2: Verify by inspection (no Xcode on this host)**

Re-read the diff against `AttachmentPreviewer`'s pattern: handler retained, channel name identical to Task 1/4 (`com.claimtracker/contacts`), delegate methods match the Contacts framework signatures, no permission strings added. Also confirm `ios/Runner.xcodeproj/project.pbxproj` already links the Contacts framework implicitly (system frameworks need no explicit link — verify by grep that no `FRAMEWORK_SEARCH_PATHS`-style manual entry is expected for other system frameworks like UserNotifications, which is already imported without a project entry).

- [ ] **Step 3: Commit**

```bash
git add ios/Runner/AppDelegate.swift
git commit -m "feat(ios): contact-picker channel (CNContactPickerViewController)"
```

---

### Task 6: Full verification gate + release APK on emulator

**Files:** none new — this is the proof task.

- [ ] **Step 1: Static analysis clean**

Run: `flutter analyze`
Expected: no errors, no warnings (infos acceptable).

- [ ] **Step 2: FULL test suite green (the "no conflicts" proof)**

Run: `flutter test`
Expected: every pre-existing file PLUS the new one passes. Any failure → fix root cause (do not weaken existing assertions), re-run until fully green, then commit any fixes.

- [ ] **Step 3: Build the release APK**

Run: `flutter build apk --release`
Expected: BUILD SUCCEEDED; artifact at `build/app/outputs/flutter-apk/app-release.apk`.

- [ ] **Step 4: Install on the emulator and smoke-test launch**

```bash
adb -s emulator-5554 install -r build\app\outputs\flutter-apk\app-release.apk
adb -s emulator-5554 shell am start -n com.claimtracker.claim_tracker/.MainActivity
Start-Sleep -Seconds 8
adb -s emulator-5554 logcat -d | Select-String -Pattern "FATAL|AndroidRuntime" 
```

Expected: `Success` from install; app process alive (`adb shell pidof com.claimtracker.claim_tracker` returns a PID); **no** FATAL/AndroidRuntime lines mentioning the app. If any crash → diagnose, fix, rebuild, reinstall (loop until clean).

- [ ] **Step 5: Final commit + report**

```bash
git add -A; git status --short   # must be empty or only intentional files
```

Report to the user: what was added (picker on both fields, tap-to-call), test totals, APK installed where, and the two OS surfaces (system picker / dialer) that are verified by code review + channel contract tests rather than headless automation.
