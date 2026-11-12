/// Restore-source materialization (spec §15).
///
/// BUG C fix: on Android SAF pickers `FilePicker.pickFile` returns a
/// `content://` URI for which `PlatformFile.path` is null in file_picker 13.x,
/// so the old code path (`picked.path == null → treat as canceled`) made every
/// real-world restore silently "cancel". The only cross-scheme read that works
/// for both `file://` and `content://` results is the byte stream — this seam
/// materializes it into an app-private temp file that [BackupService.restoreFrom]
/// can open. Kept as a pure function of the picked [PlatformFile] so widget
/// tests can drive it with synthetic content-URI files (no method channels).
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';

/// Converts an OS-picked backup file into a readable local [File].
///
/// Returns null when the user canceled ([picked] is null) or selected an empty
/// file. Throws on read/write failure — callers must treat that as a failed
/// pick, never as success (spec §15: "never silently report success").
Future<File?> backupFileFromPicked(PlatformFile? picked) async {
  if (picked == null) return null; // user canceled
  final Uint8List bytes = await picked.readAsBytes();
  if (bytes.isEmpty) return null; // empty selection — nothing to restore

  // Distinct prefix from BackupService's staging dirs ('ct_restore*') so the
  // two temp namespaces never collide in leftover checks.
  final Directory dir = Directory.systemTemp.createTempSync('ct_pick_src');
  try {
    return File('${dir.path}${Platform.pathSeparator}restore.ctbk')
      ..writeAsBytesSync(bytes);
  } catch (_) {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
    rethrow; // caller treats this as a failed pick, not a success
  }
}
