import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pointycastle/api.dart';
import 'package:pointycastle/digests/sha256.dart';
import 'package:pointycastle/macs/hmac.dart';

import 'package:claim_tracker/core/security/backup_crypto.dart';

/// Deterministic pseudo-random payload (seeded LCG) so tests are reproducible.
Uint8List _lcgPayload(int length, int seed) {
  final out = Uint8List(length);
  var state = seed;
  for (var i = 0; i < length; i++) {
    state = (state * 1103515245 + 12345) & 0x7fffffff;
    out[i] = state & 0xff;
  }
  return out;
}

/// Independent reference PBKDF2-HMAC-SHA256 (RFC 2898), written directly with
/// pointycastle's HMac so it shares no code with [BackupCrypto.deriveKeys].
Uint8List _refPbkdf2(
  Uint8List password,
  Uint8List salt,
  int iterations,
  int dkLen,
) {
  const hLen = 32;
  Uint8List prf(List<int> msg) {
    final mac = HMac.withDigest(SHA256Digest());
    mac.init(KeyParameter(password));
    return mac.process(Uint8List.fromList(msg));
  }

  final l = (dkLen + hLen - 1) ~/ hLen;
  final out = BytesBuilder();
  for (var i = 1; i <= l; i++) {
    final ibuf = ByteData(4)..setUint32(0, i); // big-endian block index
    var u = prf([...salt, ...ibuf.buffer.asUint8List()]);
    final t = Uint8List.fromList(u);
    for (var c = 1; c < iterations; c++) {
      u = prf(u);
      for (var j = 0; j < hLen; j++) {
        t[j] ^= u[j];
      }
    }
    out.add(t);
  }
  return Uint8List.fromList(out.takeBytes().sublist(0, dkLen));
}

void main() {
  group('BackupCrypto', () {
    test('round-trips arbitrary bytes', () {
      final plaintext = _lcgPayload(1 << 20, 42); // 1 MiB deterministic payload
      const passphrase = 'correct horse battery staple';
      final fileBytes = BackupCrypto.encrypt(passphrase, plaintext);
      expect(fileBytes.length, greaterThan(plaintext.length));
      final restored = BackupCrypto.decrypt(passphrase, fileBytes);
      expect(restored, equals(plaintext));
    });

    test('rejects wrong passphrase', () {
      final fileBytes = BackupCrypto.encrypt('pass-one', _lcgPayload(4096, 7));
      expect(
        () => BackupCrypto.decrypt('pass-two', fileBytes),
        throwsA(isA<WrongPassphraseError>()),
      );
    });

    test('rejects corrupted ciphertext', () {
      final fileBytes = Uint8List.fromList(
        BackupCrypto.encrypt('p', _lcgPayload(4096, 7)),
      );
      // Flip one byte in the middle of the ciphertext region (after header+IV).
      final mid = 34 + 16 + 2048;
      fileBytes[mid] ^= 0xff;
      expect(
        () => BackupCrypto.decrypt('p', fileBytes),
        throwsA(isA<BackupError>()),
      );
    });

    test('detects truncated file', () {
      final fileBytes = Uint8List.fromList(
        BackupCrypto.encrypt('p', _lcgPayload(4096, 7)),
      );
      expect(
        () => BackupCrypto.decrypt(
          'p',
          fileBytes.sublist(0, fileBytes.length - 10),
        ),
        throwsA(isA<BackupError>()),
      );
    });

    test('rejects unknown version before decryption', () {
      final fileBytes = Uint8List.fromList(
        BackupCrypto.encrypt('p', _lcgPayload(4096, 7)),
      );
      // Overwrite the u16 format version at offset 4 with an unsupported value.
      fileBytes[4] = (99 >> 8) & 0xff;
      fileBytes[5] = 99 & 0xff;
      expect(
        () => BackupCrypto.formatVersionOf(fileBytes),
        throwsA(isA<IncompatibleVersionError>()),
      );
      expect(
        () => BackupCrypto.decrypt('p', fileBytes),
        throwsA(isA<IncompatibleVersionError>()),
      );
    });

    test('KDF matches an independent reference implementation', () {
      const passphrase = 'kdf-cross-check';
      final salt = Uint8List.fromList(List.generate(16, (i) => i * 3 + 1));
      // Small iteration count for speed; production uses BackupCrypto.kIterations.
      const iterations = 500;
      final derived = BackupCrypto.deriveKeys(passphrase, salt, iterations);
      expect(derived.length, 64);
      final reference = _refPbkdf2(
        Uint8List.fromList(utf8.encode(passphrase)),
        salt,
        iterations,
        64,
      );
      expect(derived, equals(reference));
    });

    test('different salts produce different keys for same passphrase', () {
      const passphrase = 'same-pass';
      final k1 = BackupCrypto.deriveKeys(
        passphrase,
        List.generate(16, (i) => i),
        500,
      );
      final k2 = BackupCrypto.deriveKeys(
        passphrase,
        List.generate(16, (i) => 255 - i),
        500,
      );
      expect(k1, isNot(equals(k2)));
    });
  });
}
