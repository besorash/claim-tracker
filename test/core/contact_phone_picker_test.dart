/// ContactPhonePicker seam tests (design doc: contact picker + tap-to-call):
/// the Dart side of channel `com.claimtracker/contacts`, method
/// `pickContactPhone`. Contract under test:
/// null = user cancelled or chosen contact has no phone; a platform error
/// PROPAGATES so the UI can surface it (distinct from a cancel).
library;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:claim_tracker/core/contacts/contact_phone_picker.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const MethodChannel channel = MethodChannel('com.claimtracker/contacts');
  final List<MethodCall> log = <MethodCall>[];

  /// Installs a mock handler that records the call and replies [reply].
  void mockReply(Object? reply) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall call) async {
      log.add(call);
      return reply;
    });
  }

  test('returns the picked phone number and calls pickContactPhone', () async {
    log.clear();
    mockReply(<String, Object?>{'phone': '0551234567'});

    final PlatformContactPhonePicker picker = const PlatformContactPhonePicker();

    expect(await picker.pickContactPhone(), '0551234567');
    expect(log, hasLength(1)); // exactly one channel round-trip
    expect(log.single.method, 'pickContactPhone');
  });

  test('a null reply (user cancelled) is reported as null', () async {
    mockReply(null);

    final PlatformContactPhonePicker picker = const PlatformContactPhonePicker();

    expect(await picker.pickContactPhone(), isNull);
  });

  // Review Focus #1: a contact with no phone number must read as "no number",
  // not crash and not fill the field.
  test('an empty phone number reads as null (contact without a number)', () async {
    mockReply(<String, Object?>{'phone': ''});

    final PlatformContactPhonePicker picker = const PlatformContactPhonePicker();

    expect(await picker.pickContactPhone(), isNull);
  });

  // Lenient parse: a malformed platform reply degrades to "no number" instead
  // of throwing a type error into the form.
  test('a malformed platform reply (wrong shape) reads as null', () async {
    mockReply('oops');

    final PlatformContactPhonePicker picker = const PlatformContactPhonePicker();

    expect(await picker.pickContactPhone(), isNull);
  });

  // Review Focus #3: a genuine platform failure must be distinguishable from a
  // cancel — it propagates so the form can show S.contactPickFailed.
  test('a platform failure propagates (cancel and error are distinct)', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall call) async {
      throw PlatformException(code: 'picker_unavailable');
    });

    final PlatformContactPhonePicker picker = const PlatformContactPhonePicker();

    await expectLater(
      () => picker.pickContactPhone(),
      throwsA(isA<Object>()),
    );
  });
}
