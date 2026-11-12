/// Passphrase-based encryption for backup archives (spec §15).
///
/// Design (documented per spec §14/§18 — no compliance claims):
///  * KDF: PBKDF2-HMAC-SHA256, random 16-byte salt per archive,
///    [kIterations] iterations, 64-byte output split into an AES key and a
///    separate HMAC key.
///  * Cipher: AES-256 in CTR mode (stream cipher — no padding), random
///    16-byte IV per archive.
///  * Integrity/authenticity: encrypt-then-MAC with HMAC-SHA256 over the
///    header and ciphertext; the tag is verified with a constant-time
///    comparison BEFORE any decryption, so wrong passphrases and corrupt
///    archives both fail closed (spec §15).
///  * Nothing about the passphrase is stored. Salt + iteration count travel
///    in the plaintext header (standard for PBKDF2). No key material ever
///    touches disk or secure storage; no keys are hardcoded (spec §14).
library;

import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:pointycastle/api.dart';
import 'package:pointycastle/block/aes.dart';
import 'package:pointycastle/digests/sha256.dart';
import 'package:pointycastle/key_derivators/api.dart';
import 'package:pointycastle/key_derivators/pbkdf2.dart';
import 'package:pointycastle/macs/hmac.dart';
import 'package:pointycastle/stream/ctr.dart';

import '../constants/app_constants.dart';

/// Base type for all backup archive failures. [detail] is a short, safe
/// diagnostic (never contains the passphrase or file contents).
sealed class BackupError implements Exception {
  const BackupError(this.detail);

  final String detail;

  @override
  String toString() => '$runtimeType: $detail';
}

/// The archive is structurally invalid (bad magic, truncated, bad lengths).
final class CorruptArchiveError extends BackupError {
  const CorruptArchiveError([super.detail = 'corrupt or truncated archive']);
}

/// The passphrase did not authenticate the archive. Treated as a failure of
/// authentication, not corruption — existing data must be left untouched.
final class WrongPassphraseError extends BackupError {
  const WrongPassphraseError([
    super.detail = 'wrong passphrase or corrupt archive',
  ]);
}

/// The archive uses a format version this build does not support.
final class IncompatibleVersionError extends BackupError {
  const IncompatibleVersionError([super.detail = 'unsupported backup version']);
}

/// Pure-Dart crypto core for the Claim Tracker backup format v1.
///
/// File layout (big-endian integers):
/// ```
/// offset  size  field
/// 0       4     magic "CTBK" (AppConstants.backupMagic)
/// 4       2     u16 format version (= AppConstants.backupFormatVersion)
/// 6       16    salt
/// 22      4     u32 PBKDF2 iterations
/// 26      8     u64 ciphertext-region length N (IV + encrypted payload)
/// 34      N     IV(16) || AES-CTR(payload)
/// 34+N    32    HMAC-SHA256 over bytes [0 .. 34+N)
/// ```
abstract final class BackupCrypto {
  static const int kSaltLen = 16;
  static const int kIvLen = 16;
  static const int kMacLen = 32;

  /// PBKDF2 iteration count for new archives (spec §15: documented design).
  static const int kIterations = 100000;

  static const int _headerLen =
      34; // magic(4)+version(2)+salt(16)+iter(4)+len(8)

  /// Derives the 64-byte key material (AES key ‖ HMAC key) from a passphrase.
  /// Exposed for independent cross-checking in tests.
  static Uint8List deriveKeys(
    String passphrase,
    List<int> salt,
    int iterations,
  ) {
    final derivator = PBKDF2KeyDerivator(HMac.withDigest(SHA256Digest()));
    derivator.init(Pbkdf2Parameters(Uint8List.fromList(salt), iterations, 64));
    final out = Uint8List(64);
    derivator.deriveKey(Uint8List.fromList(utf8.encode(passphrase)), 0, out, 0);
    return out;
  }

  /// Parses and validates ONLY the header (magic + version). Never touches
  /// the passphrase. Throws [CorruptArchiveError] or
  /// [IncompatibleVersionError].
  static int formatVersionOf(List<int> fileBytes) {
    final bytes = _asUint8(fileBytes);
    if (bytes.length < 6) throw const CorruptArchiveError('truncated header');
    for (var i = 0; i < AppConstants.backupMagic.length; i++) {
      if (bytes[i] != AppConstants.backupMagic[i]) {
        throw const CorruptArchiveError('bad magic');
      }
    }
    final version = _getU16(bytes, 4);
    if (version != AppConstants.backupFormatVersion) {
      throw IncompatibleVersionError('archive v$version');
    }
    return version;
  }

  /// Encrypts [plaintext] under [passphrase], producing a complete archive.
  static Uint8List encrypt(String passphrase, List<int> plaintext) {
    final rand = Random.secure();
    final salt = _randomBytes(rand, kSaltLen);
    final iv = _randomBytes(rand, kIvLen);
    final keys = deriveKeys(passphrase, salt, kIterations);

    final n = kIvLen + plaintext.length; // ciphertext-region length
    final out = Uint8List(_headerLen + n + kMacLen);
    out.setRange(0, 4, AppConstants.backupMagic);
    _putU16(out, 4, AppConstants.backupFormatVersion);
    out.setRange(6, 22, salt);
    _putU32(out, 22, kIterations);
    _putU64(out, 26, n);

    out.setRange(_headerLen, _headerLen + kIvLen, iv);
    final body = Uint8List.fromList(plaintext);
    _ctrXor(keys.sublist(0, 32), iv, body, out, _headerLen + kIvLen);

    final tag = _hmac(keys.sublist(32, 64), out, 0, _headerLen + n);
    out.setRange(_headerLen + n, out.length, tag);
    return out;
  }

  /// Authenticates then decrypts a complete archive. Throws a [BackupError]
  /// subtype on any failure — never returns partial data.
  static Uint8List decrypt(String passphrase, List<int> fileBytes) {
    final bytes = _asUint8(fileBytes);
    formatVersionOf(bytes); // magic + version (throws Corrupt/Incompatible)

    if (bytes.length < _headerLen + kMacLen) {
      throw const CorruptArchiveError('truncated archive');
    }
    final n = _getU64(bytes, 26);
    if (n < kIvLen || bytes.length != _headerLen + n + kMacLen) {
      throw const CorruptArchiveError('length mismatch');
    }

    final salt = bytes.sublist(6, 22);
    final iterations = _getU32(bytes, 22);
    if (iterations < 1) throw const CorruptArchiveError('bad iteration count');

    final keys = deriveKeys(passphrase, salt, iterations);

    // Encrypt-then-MAC: verify BEFORE decrypting. A mismatch means either a
    // wrong passphrase or corruption — both must fail closed identically.
    final expectedTag = _hmac(keys.sublist(32, 64), bytes, 0, _headerLen + n);
    if (!_constantTimeEquals(expectedTag, bytes.sublist(_headerLen + n))) {
      throw const WrongPassphraseError();
    }

    final iv = bytes.sublist(_headerLen, _headerLen + kIvLen);
    final out = Uint8List(n - kIvLen);
    _ctrXor(
      keys.sublist(0, 32),
      iv,
      bytes.sublist(_headerLen + kIvLen, _headerLen + n),
      out,
      0,
    );
    return out;
  }

  // --- internals -----------------------------------------------------------

  static Uint8List _asUint8(List<int> bytes) =>
      bytes is Uint8List ? bytes : Uint8List.fromList(bytes);

  // Big-endian integer I/O at arbitrary offsets (ByteData.sublistView requires
  // 8-byte alignment, which the header layout does not have).
  static void _putU16(Uint8List b, int off, int v) {
    b[off] = (v >> 8) & 0xff;
    b[off + 1] = v & 0xff;
  }

  static void _putU32(Uint8List b, int off, int v) {
    for (var i = 3; i >= 0; i--) {
      b[off + i] = v & 0xff;
      v >>= 8;
    }
  }

  static void _putU64(Uint8List b, int off, int v) {
    for (var i = 7; i >= 0; i--) {
      b[off + i] = v & 0xff;
      v >>= 8;
    }
  }

  static int _getU16(List<int> b, int off) => (b[off] << 8) | b[off + 1];

  static int _getU32(List<int> b, int off) {
    var v = 0;
    for (var i = 0; i < 4; i++) {
      v = (v << 8) | b[off + i];
    }
    return v;
  }

  static int _getU64(List<int> b, int off) {
    var v = 0;
    for (var i = 0; i < 8; i++) {
      v = (v << 8) | b[off + i];
    }
    return v;
  }

  static Uint8List _randomBytes(Random rand, int len) {
    final out = Uint8List(len);
    for (var i = 0; i < len; i++) {
      out[i] = rand.nextInt(256);
    }
    return out;
  }

  /// XORs [data] with the AES-CTR keystream, writing into [dest][destOff..].
  static void _ctrXor(
    List<int> key,
    List<int> iv,
    Uint8List data,
    Uint8List dest,
    int destOff,
  ) {
    // AESEngine — not the deprecated AESFastEngine (side-channel issues).
    final cipher = CTRStreamCipher(AESEngine());
    cipher.init(
      true,
      ParametersWithIV(
        KeyParameter(Uint8List.fromList(key)),
        Uint8List.fromList(iv),
      ),
    );
    cipher.processBytes(data, 0, data.length, dest, destOff);
  }

  static Uint8List _hmac(List<int> key, List<int> data, int off, int len) {
    final mac = HMac.withDigest(SHA256Digest());
    mac.init(KeyParameter(Uint8List.fromList(key)));
    mac.update(_asUint8(data), off, len);
    final out = Uint8List(kMacLen);
    mac.doFinal(out, 0);
    return out;
  }

  static bool _constantTimeEquals(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a[i] ^ b[i];
    }
    return diff == 0;
  }
}
