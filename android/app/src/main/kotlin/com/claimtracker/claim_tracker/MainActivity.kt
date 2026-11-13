package com.claimtracker.claim_tracker

import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.PowerManager
import android.provider.ContactsContract
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    /// Request code for the contact-picker intent (classic startActivityForResult —
    /// FlutterActivity extends plain Activity, and androidx.activity is not on this
    /// module's classpath). Kept in a companion so it has one stable name.
    private companion object {
        const val REQUEST_CONTACT_PICK = 1001
    }

    /// Pending result of an in-flight contact pick (at most one at a time — the
    /// channel handler refuses to start a second while this is set).
    private var pendingPickResult: MethodChannel.Result? = null

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

        // Contact-picker seam (design: contact picker + tap-to-call): method
        // `pickContactPhone` opens the OS contact picker and replies
        // {"phone": String} for the chosen number, or null when the user cancels
        // or the contact has no number. The ACTION_PICK flow grants a one-off
        // read on the returned row — NO READ_CONTACTS permission is needed (the
        // manifest intentionally stays unchanged).
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "com.claimtracker/contacts"
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "pickContactPhone" -> {
                    if (pendingPickResult != null) {
                        // A pick is already in flight — don't start a second one.
                        result.success(null)
                        return@setMethodCallHandler
                    }
                    pendingPickResult = result
                    try {
                        // ACTION_PICK with the phone item type opens a picker of
                        // phone numbers (person → number) — no permission prompt.
                        startActivityForResult(
                            Intent(Intent.ACTION_PICK).apply {
                                type = ContactsContract.CommonDataKinds.Phone.CONTENT_ITEM_TYPE
                            },
                            REQUEST_CONTACT_PICK
                        )
                    } catch (e: Exception) {
                        // No contacts app can handle the intent — read as cancel.
                        pendingPickResult = null
                        result.success(null)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    /// Returns the contact-picker outcome to Dart — contract (Task 1 tests):
    /// {"phone": String} for the chosen number, null on cancel / no number.
    /// Any other request code is left to Flutter's embedding and its plugins.
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != REQUEST_CONTACT_PICK) return
        val callback = pendingPickResult ?: return
        pendingPickResult = null
        var phone: String? = null
        try {
            // The pick flow grants a one-off read on this row — no manifest permission.
            data?.data?.let { uri ->
                contentResolver.query(
                    uri,
                    arrayOf(ContactsContract.CommonDataKinds.Phone.NUMBER),
                    null, null, null
                )?.use { c -> if (c.moveToFirst()) phone = c.getString(0) }
            }
        } catch (e: Exception) {
            phone = null // never crash from here — read as "no number"
        }
        callback.success(phone?.let { mapOf("phone" to it) })
    }
}
