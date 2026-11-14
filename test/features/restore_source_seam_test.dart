/// BUG C regression tests (spec §15): the restore-source seam must work for
/// BOTH `file://` and Android SAF `content://` pick results. In file_picker
/// 13.x, `PlatformFile.path` is null for content URIs — so any code path that
/// relied on it silently "canceled" every real-world restore. The seam reads
/// via the byte stream instead; these tests prove both schemes materialize a
/// readable local file with identical bytes, and that empty/canceled picks are
/// handled without throwing.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:cross_file/cross_file.dart' show XFile;
import 'package:file_picker/file_picker.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:claim_tracker/features/settings/restore_source_seam.dart';

/// A [PlatformFile] whose URI scheme is configurable — `content://` mirrors
/// what the Android SAF picker returns (where `path` is null), `file://`
/// mirrors a plain file pick. Backed by a real temp file so no method
/// channels are touched on the host.
final class _SchemePlatformFile extends PlatformFile {
  _SchemePlatformFile(this._scheme, this._bytes);

  final String _scheme; // 'content' or 'file'
  final Uint8List _bytes;
  late final File _backing = File(
    '${Directory.systemTemp.path}${Platform.pathSeparator}ct_seam_test_${DateTime.now().microsecondsSinceEpoch}.bin',
  );

  @override
  String get name => 'claim-tracker-backup.ctbk';

  @override
  Uri get uri => _scheme == 'content'
      ? Uri.parse('content://com.android.providers.documents/dm/123')
      : (Uri.file(_backing.path));

  @override
  XFile get xFile => throw UnimplementedError();

  @override
  int? lengthSync() => _bytes.length;

  @override
  Future<int?> length() async => _bytes.length;

  @override
  Future<Uint8List> readAsBytes() async {
    // content:// reads go through the provider (simulated: return bytes);
    // file:// reads hit disk — write first so both paths are exercised.
    if (_scheme == 'file') {
      _backing.writeAsBytesSync(_bytes, flush: true);
    }
    return Uint8List.fromList(_bytes);
  }

  @override
  Stream<Uint8List> readAsByteStream() async* {
    yield await readAsBytes();
  }
}

void main() {
  /// Materialized temp files — their whole per-pick directories are removed
  /// after each test so no leftovers leak into other suites' system-temp
  /// hygiene checks.
  final List<File> created = [];

  tearDown(() {
    for (final File f in created) {
      try {
        // Each file lives in its own unique temp dir — remove the directory.
        final Directory parent = f.parent;
        if (parent.existsSync()) parent.deleteSync(recursive: true);
      } catch (_) {}
    }
    created.clear();
  });

  final List<int> archiveBytes = <int>[
    0x43, 0x54, 0x42, 0x4B, // "CTBK" magic — a plausible v1 archive head
    ...List<int>.generate(64, (int i) => i & 0xFF),
  ];

  test(
    'content:// pick (path == null) materializes a readable local file',
    () async {
      final PlatformFile picked = _SchemePlatformFile(
        'content',
        Uint8List.fromList(archiveBytes),
      );
      expect(picked.path, isNull); // the exact BUG C precondition

      final File? out = await backupFileFromPicked(picked);
      if (out != null) created.add(out);

      expect(out, isNotNull);
      expect(out!.existsSync(), isTrue);
      expect(out.readAsBytesSync().toList(), archiveBytes);
    },
  );

  test(
    'file:// pick materializes the same bytes (regression: old path)',
    () async {
      final PlatformFile picked = _SchemePlatformFile(
        'file',
        Uint8List.fromList(archiveBytes),
      );
      expect(picked.path, isNotNull); // file scheme exposes a real path

      final File? out = await backupFileFromPicked(picked);
      if (out != null) created.add(out);

      expect(out, isNotNull);
      expect(out!.readAsBytesSync().toList(), archiveBytes);
    },
  );

  test('canceled pick (null) returns null without throwing', () async {
    expect(await backupFileFromPicked(null), isNull);
  });

  test(
    'empty selection returns null instead of a zero-byte "success"',
    () async {
      final PlatformFile picked = _SchemePlatformFile('content', Uint8List(0));
      expect(await backupFileFromPicked(picked), isNull);
    },
  );

  test(
    'read failure propagates — never silently reported as success',
    () async {
      // A PlatformFile whose byte read blows up must surface the error so the
      // caller can report a failed pick (spec §15: fail loudly).
      final PlatformFile broken = _BrokenPlatformFile();
      await expectLater(backupFileFromPicked(broken), throwsA(isA<Object>()));
    },
  );
}

/// Simulates an unreadable provider result.
final class _BrokenPlatformFile extends PlatformFile {
  @override
  String get name => 'broken.ctbk';

  @override
  Uri get uri => Uri.parse('content://broken/1');

  @override
  XFile get xFile => throw UnimplementedError();

  @override
  int? lengthSync() => null;

  @override
  Future<int?> length() async => null;

  @override
  Future<Uint8List> readAsBytes() async =>
      throw StateError('provider read failed');

  @override
  Stream<Uint8List> readAsByteStream() async* {
    yield await readAsBytes();
  }
}
