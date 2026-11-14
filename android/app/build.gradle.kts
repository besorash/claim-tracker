plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.claimtracker.claim_tracker"
    // flutter_local_notifications 23.x (and androidx.core 1.19+) require SDK 37;
    // AGP 9.5.1 supports it (see settings.gradle.kts).
    compileSdk = maxOf(flutter.compileSdkVersion, 37)
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        // Required by flutter_local_notifications (core library desugaring).
        isCoreLibraryDesugaringEnabled = true
    }

    defaultConfig {
        // Neutral reverse-domain identifier (documented in WORK_LOG.md).
        applicationId = "com.claimtracker.pro"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        // minSdk 23 is required by flutter_local_notifications (Android API 23+).
        minSdk = maxOf(flutter.minSdkVersion, 23)
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
            // Phase 1 fix #5: resource shrinking strips drawable/ic_stat_reminder —
            // it is only referenced at runtime by flutter_local_notifications, so
            // AAPT2 sees no static reference and removes it (the app then crashes
            // on startup with PlatformException(invalid_icon)). Keep all resources.
            isShrinkResources = false
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}

flutter {
    source = "../.."
}
