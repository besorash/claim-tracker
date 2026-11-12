/// Security & privacy audit (spec §14, prompt 4 "Security and privacy"):
/// pins the hardening rules as executable checks so a future refactor cannot
/// silently regress them:
///  * notification text stays generic — no claim/customer fields on lock screens;
///  * the Android manifest declares NO INTERNET permission (no network at all);
///  * no logging call in lib/ references sensitive model fields or passphrases;
///  * no hardcoded key material (long hex literals bound to key-like names).
library;

import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:claim_tracker/core/l10n/app_strings.dart';

void main() {
  /// Sample PII values — stand-ins for a real claim's fields. The generic
  /// notification text must never contain any of these (spec §14 lock-screen
  /// rule). Seeded values mirror the shape of real data (Arabic name, Saudi
  /// mobile, alphanumeric claim number).
  const String customerName = 'سعد العميل';
  const String customerMobile = '0501234567';
  const String claimNumber = 'CLM-100';

  test('notification text is generic (no claim fields)', () {
    // Generic reminder text now lives in the ARB tables — check both locales.
    final List<String> texts = <String>[];
    for (final Locale l in const <Locale>[Locale('en'), Locale('ar')]) {
      AppLocale.locale = l;
      texts.add(S.genericReminderTitle);
      texts.add(S.genericReminderBody);
    }
    AppLocale.locale = const Locale('en'); // restore default
    for (final String t in texts) {
      expect(t.contains(customerName), isFalse);
      expect(t.contains(customerMobile), isFalse);
      expect(t.contains(claimNumber), isFalse);
      // No digits at all — a generic reminder never needs one.
      expect(RegExp(r'\d').hasMatch(t), isFalse, reason: t);
    }

    // The scheduler must actually use the generic constants (not inline text).
    final String service = File(
      'lib/core/notifications/notification_service.dart',
    ).readAsStringSync();
    expect(service.contains('genericReminderTitle'), isTrue);
    expect(service.contains('genericReminderBody'), isTrue);
  });

  test('production manifest declares no INTERNET permission', () {
    // The MAIN manifest governs release builds — it must never grant network
    // access (spec §14). The debug/profile variants keep the stock Flutter
    // template permission, which exists only for hot-reload tooling and is
    // not part of any shipped build.
    final String xml = File('android/app/src/main/AndroidManifest.xml')
        .readAsStringSync();
    expect(xml.contains('android.permission.INTERNET'), isFalse);
  });

  test('production manifest declares exact-alarm + battery-optimization permissions', () {
    // Phase 1 fix #1/#4: reminders must be schedulable exactly (Android 14+
    // denies SCHEDULE_EXACT_ALARM by default; USE_EXACT_ALARM is auto-granted
    // on API 33+ for sideloaded reminder apps) and must survive OEM battery
    // killers. Both are required in the production manifest.
    final String xml = File('android/app/src/main/AndroidManifest.xml')
        .readAsStringSync();
    expect(
      xml.contains('android.permission.SCHEDULE_EXACT_ALARM'),
      isTrue,
      reason: 'exact-alarm scheduling must be declared',
    );
    expect(
      xml.contains('android.permission.USE_EXACT_ALARM'),
      isTrue,
      reason: 'USE_EXACT_ALARM auto-grants exact alarms on API 33+',
    );
    expect(
      xml.contains('android.permission.REQUEST_IGNORE_BATTERY_OPTIMIZATIONS'),
      isTrue,
      reason: 'battery-optimization exemption must be requestable',
    );
  });

  test('no sensitive logging in lib/', () {
    final List<String> offenders = <String>[];
    final RegExp callRe = RegExp(r'\b(print|debugPrint|log)\s*\(');
    final RegExp denyRe = RegExp(
      r'customerName|customerMobile|nationalId|claimNumber|\bnotes\b|passphrase',
      caseSensitive: false,
    );

    for (final FileSystemEntity e in Directory(
      'lib',
    ).listSync(recursive: true)) {
      if (e is! File || !e.path.endsWith('.dart')) continue;
      final List<String> lines = e.readAsLinesSync();
      for (int i = 0; i < lines.length; i++) {
        final String line = lines[i];
        if (!callRe.hasMatch(line)) continue;
        // Skip the call's own name matching its argument on the same line.
        if (denyRe.hasMatch(line)) {
          offenders.add('${e.path}:${i + 1}: ${line.trim()}');
        }
      }
    }

    expect(
      offenders,
      isEmpty,
      reason: "sensitive logging found:\n${offenders.join('\n')}",
    );
  });

  test('no hardcoded key material', () {
    final List<String> offenders = <String>[];
    // A long hex literal (>=33 chars) bound to a key-like identifier.
    final RegExp re = RegExp(
      r"""\b\w*(key|secret|iv|salt)\w*\s*[:=]\s*['"][0-9a-fA-F]{33,}['"]""",
      caseSensitive: false,
    );

    for (final FileSystemEntity e in Directory(
      'lib',
    ).listSync(recursive: true)) {
      if (e is! File || !e.path.endsWith('.dart')) continue;
      final List<String> lines = e.readAsLinesSync();
      for (int i = 0; i < lines.length; i++) {
        if (re.hasMatch(lines[i])) {
          offenders.add('${e.path}:${i + 1}: ${lines[i].trim()}');
        }
      }
    }

    expect(
      offenders,
      isEmpty,
      reason: "hardcoded key material found:\n${offenders.join('\n')}",
    );
  });
}
