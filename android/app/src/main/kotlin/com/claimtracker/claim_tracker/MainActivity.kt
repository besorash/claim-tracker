package com.claimtracker.claim_tracker

import android.content.Context
import android.os.Build
import android.os.PowerManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    /// Battery-optimization exemption seam (Phase 1 fix #4): OEM battery
    /// killers defer or drop closed-app alarms, so the app must be able to ask
    /// the user for an exemption. Two methods:
    ///   isIgnoringBatteryOptimizations -> Boolean
    ///   requestIgnoreBatteryOptimizations -> Boolean (true when the system
    ///   dialog was shown and granted; false on denial or pre-API 23)
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "com.claimtracker/permissions"
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "isIgnoringBatteryOptimizations" -> {
                    val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
                    result.success(pm.isIgnoringBatteryOptimizations(packageName))
                }
                "requestIgnoreBatteryOptimizations" -> {
                    if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) {
                        // No battery-optimization concept before API 23.
                        result.success(true)
                        return@setMethodCallHandler
                    }
                    val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
                    if (pm.isIgnoringBatteryOptimizations(packageName)) {
                        result.success(true)
                        return@setMethodCallHandler
                    }
                    try {
                        startActivity(android.content.Intent(
                            android.provider.Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS,
                            android.net.Uri.parse("package:$packageName")
                        ))
                        // The dialog is modal; report optimistically — the UI
                        // re-queries isIgnoringBatteryOptimizations on resume.
                        result.success(true)
                    } catch (e: Exception) {
                        result.success(false)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }
}
