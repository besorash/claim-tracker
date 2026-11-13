/// OS contact-picker seam — one MethodChannel shared by both phone fields of
/// the claim form (design: docs/superpowers/specs/2026-11-13-contact-picker-tap-to-call-design.md).
library;

import 'package:flutter/services.dart';

/// Opens the system contact picker and returns the chosen contact's number.
///
/// Contract — a cancel is NOT an error:
/// - Returns `null` when the user cancels, or when the chosen contact has no
///   phone number: the caller leaves its field exactly as it was (no UI noise).
/// - **Throws** on platform failure (picker unavailable, channel error) so the
///   UI can tell it apart from a cancel and surface an error message.
abstract class ContactPhonePicker {
  /// Opens the picker; see the class contract for null vs throw semantics.
  Future<String?> pickContactPhone();
}

/// Production implementation over MethodChannel `com.claimtracker/contacts`.
/// The native side (MainActivity.kt on Android, AppDelegate.swift on iOS) opens
/// a permission-free system picker and replies `{phone: String}` or null — the
/// Dart widget tests never touch this channel; they inject their own fakes.
class PlatformContactPhonePicker implements ContactPhonePicker {
  const PlatformContactPhonePicker({MethodChannel? channel})
      : _channel = channel ?? const MethodChannel('com.claimtracker/contacts');

  final MethodChannel _channel;

  @override
  Future<String?> pickContactPhone() async {
    // A platform failure propagates (PlatformException & co) — by contract it
    // is distinct from a cancel. Parsing is lenient: any malformed reply reads
    // as "no number" instead of crashing into the form with a type error.
    final Object? result = await _channel.invokeMethod<Object>(
      'pickContactPhone',
    );
    if (result is! Map) return null; // malformed reply → "no number"
    final String phone = ((result['phone']?.toString() ?? '').trim());
    return phone.isEmpty ? null : phone;
  }
}
