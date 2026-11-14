# Reusable prompt: build an iOS IPA from a Flutter project and push it to GitHub

> Copy everything below the line and give it to the AI agent while it is opened inside the project folder.

---

You are working inside a Flutter project folder (an Android app). Your goal: produce an **unsigned iOS IPA** built by GitHub Actions from the **current** state of the project, and make sure it is error-free. Follow the steps in order and do not move to the next step until the current one succeeds.

## 1) Inspect the project
- Confirm it is a Flutter project (`pubspec.yaml` exists) and that an `ios/` folder exists. If `ios/` is missing, create it with `flutter create --platforms=ios .` and touch nothing else.
- Show `git status`, `git remote -v` and the current branch. Never discard existing changes: no `reset`, no `checkout --`, no force push.

## 2) Sync Android-only changes into iOS
Code in `lib/` and `pubspec.yaml` is shared, so it reaches iOS automatically. Settings that live only in `android/` do not. Compare Android with iOS and bring iOS up to date.
- **App name**: copy `android:label` from `AndroidManifest.xml`, plus any localized `strings.xml`, such as `values-ar`, into `CFBundleDisplayName` in `ios/Runner/Info.plist`. For localized names, use `ios/Runner/<lang>.lproj/InfoPlist.strings`.
- **Version and bundle ID**: confirm the version in `pubspec.yaml` is the one being used. Confirm the iOS bundle ID matches the Android `applicationId` (from `android/app/build.gradle*`) or is a sensible equivalent of it.
- **App icon**: if the Android launcher icon (`android/app/src/main/res/mipmap-*`, adaptive icon, or a `flutter_launcher_icons` config) changed, regenerate the iOS icons in `ios/Runner/Assets.xcassets/AppIcon.appiconset` from the same source. iOS icons must have no transparency, and the 1024×1024 icon is required.
- **Launch / splash screen**: if the Android splash changed (`launch_background.xml`, `flutter_native_splash` config, dark-mode variant), update `ios/Runner/Base.lproj/LaunchScreen.storyboard` and its assets to match.
- **Permissions**: for every permission in `AndroidManifest.xml`, and for every plugin in `pubspec.yaml` that needs one (notifications, camera, photos, files, location, microphone, contacts, ...), add the matching `NS...UsageDescription` key to `Info.plist` with a clear description. Without these keys, the app crashes the moment it requests the permission.
- **Plugins**: for every plugin, follow its README's iOS setup. This includes `Info.plist` keys, `AppDelegate` changes, and background modes. Make sure the minimum iOS version in `ios/Podfile` and the Xcode project meets every plugin's requirement.
- Use `git log` and `git diff` on `android/`, `pubspec.yaml` and `assets/` to see what changed since the last iOS build. List what you synced.

## 3) Verify the code locally
- Run `flutter pub get`, then `flutter analyze`, then `flutter test`.
- Fix any errors and re-run until analysis is clean and all tests pass. Never delete or skip a test to make it pass.
- If Flutter is not installed on this machine, say so clearly and continue. GitHub will run the same checks anyway.

## 4) Set up the GitHub Actions workflow
- If `.github/workflows/ios-build.yml` exists, review it and fix anything wrong. Otherwise, create it with the content below. Set `APP_NAME` to the app's name, and set `FLUTTER_VERSION` to the version the project requires (check `pubspec.yaml` and `flutter --version`):

```yaml
name: iOS build

on:
  push:
    branches: ['**']
  workflow_dispatch:

concurrency:
  group: ios-build-${{ github.ref }}
  cancel-in-progress: true

env:
  FLUTTER_VERSION: "3.x.x"   # ← the project's Flutter version
  APP_NAME: "MyApp"          # ← IPA file name

jobs:
  test:
    name: Analyze and test
    runs-on: ubuntu-latest
    timeout-minutes: 20
    steps:
      - uses: actions/checkout@v4
      - uses: subosito/flutter-action@v2
        with:
          channel: stable
          flutter-version: ${{ env.FLUTTER_VERSION }}
          cache: true
      # Remove this step if the tests don't use sqflite_common_ffi
      - name: Install SQLite
        run: sudo apt-get update && sudo apt-get install -y libsqlite3-dev
      - run: flutter pub get
      - run: flutter analyze
      - run: flutter test

  build-ios:
    name: Build unsigned IPA
    needs: test
    runs-on: macos-latest
    timeout-minutes: 45
    steps:
      - uses: actions/checkout@v4
      - uses: subosito/flutter-action@v2
        with:
          channel: stable
          flutter-version: ${{ env.FLUTTER_VERSION }}
          cache: true
      - run: flutter pub get
      - name: Build iOS app (no code signing)
        run: flutter build ios --release --no-codesign --build-number=${{ github.run_number }}
      - name: Package Runner.app into an .ipa
        run: |
          set -euo pipefail
          rm -rf Payload && mkdir Payload
          cp -R build/ios/iphoneos/Runner.app Payload/
          zip -qry "${APP_NAME}-unsigned.ipa" Payload
          ls -lh "${APP_NAME}-unsigned.ipa"
      - name: Verify the .ipa contents
        run: |
          set -euo pipefail
          APP=Payload/Runner.app
          test -x "$APP/Runner"
          test -f "$APP/Info.plist"
          test -d "$APP/Frameworks/Flutter.framework"
          test -d "$APP/Frameworks/App.framework"
          lipo -info "$APP/Runner" | grep -q arm64
          /usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP/Info.plist"
          /usr/libexec/PlistBuddy -c 'Print :CFBundleDisplayName' "$APP/Info.plist"
          /usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Info.plist"
      - uses: actions/upload-artifact@v4
        with:
          name: ${{ env.APP_NAME }}-unsigned-ipa
          path: ${{ env.APP_NAME }}-unsigned.ipa
          if-no-files-found: error
          retention-days: 30
```

## 5) Push to GitHub (try this first)
- If you are on `main`, create a new branch before committing. Otherwise, stay on the current branch.
- Commit all changes with a message that describes what changed, then run `git push origin <branch>`.
- The push triggers the workflow. Watch it with whatever you have: `gh run watch`, the GitHub API (`curl https://api.github.com/repos/<owner>/<repo>/actions/runs?head_sha=<sha>`), or a browser. Never report success unless you have seen the result yourself.
- If the run fails, read the failing step's log, fix the root cause, and push again. Repeat until it succeeds, with a maximum of 5 attempts. If it still fails after that, stop and explain exactly what is wrong.
- On success, give me the run URL, the artifact name and size, and where to download it (Actions → the run → Artifacts).

## 6) Fallback: if you cannot push
If you cannot push (no remote, no permission, push rejected, etc.):
- Do not work around it: don't change credentials, don't force push, and don't create a new repository without asking me.
- Commit everything locally so the project is ready to push with a single command.
- Make sure `.github/workflows/ios-build.yml` exists and is correct in the project.
- Write clear steps for me to push it myself:
  1. Create a repository on GitHub, or use the existing one.
  2. The exact commands: `git remote add origin ...` if there is no remote, then `git push -u origin <branch>`.
  3. After pushing: open Actions → "iOS build" → wait for ✅ → download the file from Artifacts.
- Tell me clearly what stopped you from pushing.

## General rules
- Reply to me in Arabic, briefly.
- Don't delete files or change anything unrelated to this task.
- The IPA is **unsigned**. Remind me that installing it on an iPhone requires re-signing it with a tool such as AltStore or Sideloadly.
- Finish with a summary: what you synced from Android, what you fixed, the analyze/test results, whether the push succeeded, and either the run URL or the manual push steps.
