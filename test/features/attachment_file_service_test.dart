/// AttachmentFileService behavior (spec §12): private store, safe import,
/// traversal refusal on every disk-touching path, and clean store replacement.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:claim_tracker/core/models/attachment.dart';
import 'package:claim_tracker/features/attachments/attachment_file_service.dart';

void main() {
  late Directory tmp; // parent of the store + any "outside" files
  late Directory baseDir;
  late AttachmentFileService svc;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('ct_files_test');
    baseDir = Directory('${tmp.path}/store')..createSync();
    svc = AttachmentFileService(baseDir: baseDir);
  });

  tearDown(() {
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  Attachment att(String rel) => Attachment(
    id: 1,
    claimId: 1,
    originalName: 'x',
    mimeType: 'application/octet-stream',
    sizeBytes: 0,
    relativePath: rel,
    createdAtUtcMs: DateTime.utc(2026),
  );

  test('importFile copies bytes and returns a relative path', () async {
    final File src = File('${tmp.path}/source.png')
      ..writeAsBytesSync(utf8.encode('img-bytes'));

    final String rel = await svc.importFile(
      src.path,
      originalName: 'photo.png',
    );

    expect(rel.startsWith('/'), isFalse);
    expect(rel.split('/').any((String p) => p == '..'), isFalse);
    final File stored = svc.fileFor(att(rel));
    expect(stored.existsSync(), isTrue);
    expect(utf8.decode(stored.readAsBytesSync()), equals('img-bytes'));

    // The source (picker temp copy) must be left untouched.
    expect(src.existsSync(), isTrue);
    expect(utf8.decode(src.readAsBytesSync()), equals('img-bytes'));
  });

  test('importFile sanitizes hostile names', () async {
    final File src = File('${tmp.path}/evil.png')..writeAsBytesSync([1, 2, 3]);

    final String rel = await svc.importFile(
      src.path,
      originalName: '../../evil.png',
    );

    expect(rel.split('/').any((String p) => p == '..'), isFalse);
    final File stored = svc.fileFor(att(rel));
    expect(svc.isInsideStore(stored.path), isTrue);
  });

  test(
    'deleteFile refuses traversal paths and leaves foreign files intact',
    () async {
      // A real file OUTSIDE the store, addressable as '../outside.txt' from it.
      final File outside = File('${tmp.path}/outside.txt')
        ..writeAsBytesSync(utf8.encode('keep me'));

      expect(
        () => svc.deleteFile(att('../outside.txt')),
        throwsA(isA<ArgumentError>()),
      );
      // The foreign file must still exist, byte-identical.
      expect(outside.existsSync(), isTrue);
      expect(utf8.decode(outside.readAsBytesSync()), equals('keep me'));
    },
  );

  test('deleteFile removes exactly the stored file', () async {
    final File srcA = File('${tmp.path}/a.bin')..writeAsBytesSync([9]);
    final String relA = await svc.importFile(srcA.path, originalName: 'a.bin');
    final File srcB = File('${tmp.path}/b.bin')..writeAsBytesSync([8]);
    final String relB = await svc.importFile(srcB.path, originalName: 'b.bin');

    await svc.deleteFile(att(relA));

    expect(svc.fileFor(att(relA)).existsSync(), isFalse);
    // The sibling file is untouched.
    final File b = svc.fileFor(att(relB));
    expect(b.existsSync(), isTrue);
    expect(b.readAsBytesSync().single, equals(8));
  });

  test('fileFor resolves inside the store only', () async {
    // A valid import stays inside the store.
    final File src = File('${tmp.path}/ok.bin')..writeAsBytesSync([1]);
    final String rel = await svc.importFile(src.path);
    expect(svc.isInsideStore(svc.fileFor(att(rel)).path), isTrue);

    // Traversal paths are refused by the guard (spec §12: no accidental
    // access to unrelated files) — and isInsideStore reports them as outside.
    expect(
      () => svc.fileFor(att('../outside.txt')),
      throwsA(isA<ArgumentError>()),
    );
    expect(svc.isInsideStore('${tmp.path}/outside.txt'), isFalse);
  });

  test('replaceStoreFrom swaps contents without leaking old files', () async {
    // Two old files in the store.
    final File src1 = File('${tmp.path}/old1.bin')..writeAsBytesSync([1]);
    await svc.importFile(src1.path, originalName: 'old1.bin');
    final File src2 = File('${tmp.path}/old2.bin')..writeAsBytesSync([2]);
    await svc.importFile(src2.path, originalName: 'old2.bin');

    // Staged source with one new file (nested dir to exercise layout).
    final Directory source = Directory('${tmp.path}/staged/files')
      ..createSync(recursive: true);
    File('${source.path}/new1.bin').writeAsBytesSync(utf8.encode('fresh'));

    await svc.replaceStoreFrom(source);

    // Old files gone, exactly the new set present with correct bytes.
    final List<File> now = baseDir
        .listSync(recursive: true)
        .whereType<File>()
        .toList();
    expect(now.length, equals(1));
    expect(now.single.path.endsWith('new1.bin'), isTrue);
    expect(utf8.decode(now.single.readAsBytesSync()), equals('fresh'));
  });

  test(
    'storedFileFor resolves a stored row without force-unwrapping baseDir',
    () async {
      // Regression (Phase 5): attachFile used to read the size via
      // `svc.baseDir!.path`, which crashes whenever the service was constructed
      // without an explicit baseDir. The null-safe resolver must work with an
      // injected store and refuse traversal paths like every other accessor.
      final File src = File('${tmp.path}/size.bin')
        ..writeAsBytesSync([1, 2, 3]);
      final String rel = await svc.importFile(
        src.path,
        originalName: 'size.bin',
      );

      final File stored = await svc.storedFileFor(rel);
      expect(stored.existsSync(), isTrue);
      expect(stored.readAsBytesSync().length, equals(3));
      expect(svc.isInsideStore(stored.path), isTrue);

      // Traversal paths are refused by the guard (spec §12).
      expect(
        () => svc.storedFileFor('../outside.txt'),
        throwsA(isA<ArgumentError>()),
      );
    },
  );
}
