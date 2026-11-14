/// AttachmentPicker seam defaults — pickImages()/pickVideos() must delegate to
/// pick(type:) with the right FileType, so fakes that implement only pick() work.
library;

import 'dart:typed_data';

import 'package:cross_file/cross_file.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:claim_tracker/features/attachments/attachment_picker_seam.dart';

/// Minimal concrete [PlatformFile] — the class is an `abstract base class` with
/// no public constructor, so it must be extended (same pattern as
/// `_FakePlatformFile` in claim_details_screen_test.dart).
final class _PF extends PlatformFile {
  _PF();

  @override
  String get name => 'x.jpg';

  @override
  Uri get uri => Uri.file('/tmp/x.jpg');

  @override
  XFile get xFile => XFile('/tmp/x.jpg');

  @override
  int? lengthSync() => null;

  @override
  Future<int?> length() async => null;

  @override
  Future<Uint8List> readAsBytes() async => Uint8List(0);

  @override
  Stream<Uint8List> readAsByteStream() async* {}
}

class _Recording implements AttachmentPicker {
  final List<FileType> types = [];

  @override
  Future<List<PlatformFile>> pick({required FileType type}) async {
    types.add(type);
    return [_PF()];
  }
}

void main() {
  test('pickImages delegates to pick(FileType.image)', () async {
    final _Recording p = _Recording();
    await p.pickImages();
    expect(p.types, <FileType>[FileType.image]);
  });

  test('pickVideos delegates to pick(FileType.video)', () async {
    final _Recording p = _Recording();
    await p.pickVideos();
    expect(p.types, <FileType>[FileType.video]);
  });
}
