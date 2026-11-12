/// OS file-picker seam (spec §12): screens depend on [AttachmentPicker] so
/// widget tests can inject a fake that returns synthetic `PlatformFile`s backed
/// by real temp files — no method channels are touched in tests.
library;

import 'package:file_picker/file_picker.dart';

abstract class AttachmentPicker {
  /// Opens the OS picker for [type] and returns the chosen files (empty list
  /// when the user cancels). Implementations must not read file bytes inline —
  /// callers copy from `PlatformFile.path` into the app-private store.
  Future<List<PlatformFile>> pick({required FileType type});
}

/// Production implementation wrapping file_picker (spec §12: images, PDFs and
/// common document types). Note: file_picker 13.x exposes a static API with no
/// `withData` parameter — bytes are read on demand from the returned path,
/// which is all we need.
class FilePickerAttachmentPicker implements AttachmentPicker {
  const FilePickerAttachmentPicker();

  @override
  Future<List<PlatformFile>> pick({required FileType type}) =>
      FilePicker.pickFiles(type: type);
}
