/// Physical attachment file handling (spec §12): copies picked files into the
/// app's private storage, resolves stored rows back to [File]s, and deletes
/// them safely.
///
/// Security rules enforced here (spec §14/§15):
///  * Files live under `<documents>/attachments` — never in shared/temp
///    locations that other apps can read or that the OS may clean up.
///  * [Attachment.relativePath] is always a relative, slash-separated path;
///    every accessor goes through [_resolveGuarded], which rejects absolute
///    paths and any `..`/`.` segment (path traversal), so a tampered row can
///    never point at a foreign file for read or delete.
library;

import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../../core/models/attachment.dart';

/// Per-process uniqueness counter for import subdirectories (top-level so it
/// is not a class field — the value mutates on every import).
int _importCounter = 0;

class AttachmentFileService {
  const AttachmentFileService({this.baseDir});

  /// Store root override (tests inject a temp dir). When null, the default
  /// app-private location is used: `<documents>/attachments`.
  final Directory? baseDir;

  /// The attachments directory, created if missing.
  Future<Directory> storeDir() async {
    final Directory? injected = baseDir;
    if (injected != null) return injected;
    final Directory documents = await getApplicationDocumentsDirectory();
    final Directory root = Directory('${documents.path}/attachments');
    if (!root.existsSync()) root.createSync(recursive: true);
    return root;
  }

  /// Copies [sourcePath] (e.g. a file_picker result) into the store under a
  /// unique subdirectory and returns the relative path to persist in
  /// [Attachment.relativePath]. The source is left untouched so the picker's
  /// temp copy can be cleaned up independently.
  Future<String> importFile(
    String sourcePath, {
    String originalName = '',
  }) async {
    final Directory root = await storeDir();
    final File src = File(sourcePath);
    if (!src.existsSync()) {
      throw ArgumentError.value(
        sourcePath,
        'sourcePath',
        'source file not found',
      );
    }

    // Unique per-import directory: '<epoch-ms>-<counter>' — avoids any
    // collision with existing rows (relative_path is UNIQUE in the schema).
    final String sub =
        '${DateTime.now().millisecondsSinceEpoch}-$_importCounter++';
    final Directory dir = Directory('${root.path}/$sub')
      ..createSync(recursive: true);

    final String name = originalName.isNotEmpty
        ? _sanitizeFileName(originalName)
        : _sanitizeFileName(src.uri.pathSegments.last);
    final File dest = File('${dir.path}/$name');
    await src.copy(dest.path);
    return '$sub/$name';
  }

  /// Null-safe resolution of a stored relative path to its [File]. Unlike
  /// [fileFor], this resolves through [storeDir()] so it works even when the
  /// service was constructed without an explicit [baseDir] (spec §12). Throws
  /// [ArgumentError] if the relative path escapes the store root.
  Future<File> storedFileFor(String relativePath) async {
    final Directory root = await storeDir();
    return File(_resolveGuarded(root, relativePath));
  }

  /// Resolves a stored row to its [File] (does not check existence). Throws
  /// [ArgumentError] if the relative path escapes the store root.
  File fileFor(Attachment attachment) {
    final Directory? injected = baseDir;
    if (injected == null) {
      throw StateError(
        'storeDir() must be resolved first (no default on host)',
      );
    }
    return File(_resolveGuarded(injected, attachment.relativePath));
  }

  /// True when [absolutePath] is inside the store root. Pure check — never
  /// throws; used by tests and UI to reason about paths safely.
  bool isInsideStore(String absolutePath) {
    final Directory? injected = baseDir;
    if (injected == null) return false;
    final String rootAbs = injected.absolute.path.replaceAll('\\', '/');
    final String p = absolutePath.replaceAll('\\', '/');
    return p.startsWith('$rootAbs/');
  }

  /// Deletes the physical file for [attachment]. Refuses paths that escape
  /// the store (path traversal) with [ArgumentError]; tolerates an
  /// already-missing file.
  Future<void> deleteFile(Attachment attachment) async {
    final Directory? injected = baseDir;
    if (injected == null) {
      throw StateError(
        'storeDir() must be resolved first (no default on host)',
      );
    }
    final String absolute = _resolveGuarded(injected, attachment.relativePath);
    final File f = File(absolute);
    if (f.existsSync()) await f.delete();
  }

  /// Replaces the entire store contents with [source] (used by backup restore
  /// after validation succeeded — spec §15: never destroy live data before
  /// validation). Existing files are removed first, then staged files moved in.
  Future<void> replaceStoreFrom(Directory source) async {
    final Directory root = await storeDir();

    // Remove current contents (files and subdirectories), keep the root dir.
    // Materialize the list first — a recursive lazy iterator would try to
    // descend into directories that were already removed with their parent.
    if (root.existsSync()) {
      final List<FileSystemEntity> entries = root
          .listSync(recursive: true)
          .toList();
      for (final FileSystemEntity e in entries) {
        if (e.existsSync()) e.deleteSync(recursive: true);
      }
    } else {
      root.createSync(recursive: true);
    }

    // Move staged files into the store, preserving relative layout.
    if (!source.existsSync()) return;
    final List<FileSystemEntity> staged = source
        .listSync(recursive: true)
        .toList();
    for (final FileSystemEntity e in staged) {
      final String rel = _relativeTo(source.path, e.path);
      if (e is File) {
        final File destFile = File('${root.path}/$rel');
        destFile.parent.createSync(recursive: true);
        await e
            .rename(destFile.path)
            .catchError((Object _) => e.copy(destFile.path));
      } else if (e is Directory) {
        final Directory d = Directory('${root.path}/$rel');
        if (!d.existsSync()) d.createSync(recursive: true);
      }
    }
  }

  // ---------------------------------------------------------------------------
  // Path safety helpers
  // ---------------------------------------------------------------------------

  /// Joins [relativePath] under [root] and verifies the result is still
  /// inside the root. Throws [ArgumentError] on traversal attempts (spec §12:
  /// "avoiding accidental deletion of unrelated files").
  String _resolveGuarded(Directory root, String relativePath) {
    if (relativePath.isEmpty || relativePath.startsWith('/')) {
      throw ArgumentError.value(
        relativePath,
        'relativePath',
        'escapes attachment store',
      );
    }
    final List<String> parts = relativePath.replaceAll('\\', '/').split('/');
    if (parts.any((String p) => p == '..' || p == '.')) {
      throw ArgumentError.value(
        relativePath,
        'relativePath',
        'escapes attachment store',
      );
    }
    // Normalize to forward slashes for the prefix check — File() accepts both.
    final String rootAbs = root.absolute.path.replaceAll('\\', '/');
    final String joined = '$rootAbs/${parts.join('/')}';
    if (!joined.startsWith('$rootAbs/')) {
      throw ArgumentError.value(
        relativePath,
        'relativePath',
        'escapes attachment store',
      );
    }
    return joined;
  }

  /// Strips the [parent] prefix from [child], normalizing separators so the
  /// comparison works on both Windows and POSIX.
  String _relativeTo(String parent, String child) {
    final String p = parent.replaceAll('\\', '/');
    final String c = child.replaceAll('\\', '/');
    if (c.startsWith('$p/')) {
      return c.substring(p.length + 1);
    }
    return c;
  }

  /// Removes path separators and drive letters from a user-supplied file name.
  String _sanitizeFileName(String name) {
    final String cleaned = name.replaceAll(RegExp(r'[\\/]'), '_');
    return cleaned.isEmpty ? 'file' : cleaned;
  }
}
