/// Backup export and staged restore (spec §15).
///
/// Restore order — validation ALWAYS precedes any mutation of live data:
///  1. Header version check + passphrase authentication (MAC) + decryption.
///     Failures here throw before anything on disk is touched, so a wrong
///     passphrase or corrupt archive can never damage existing data.
///  2. Parse the payload into a fresh staging directory (`ct_restore*` in the
///     system temp dir): `db.sqlite` + attachment files at their relative
///     paths. Every declared length is bounds-checked (else
///     [CorruptArchiveError]).
///  3. Open the staged DB read-only: `PRAGMA integrity_check` must be 'ok',
///     and every `attachments.relative_path` row must have a non-empty file
///     in staging — otherwise the staging dir is deleted and the restore
///     aborts with [CorruptArchiveError].
///  4. Swap (only after all of the above passed): close the live DB, replace
///     its file with the staged one, and replace the attachment store
///     contents via [AttachmentFileService.replaceStoreFrom]. The caller
///     reopens through `AppDatabase.open()`.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:sqflite/sqflite.dart' as sqf;

import '../../features/attachments/attachment_file_service.dart';
import '../database/app_database.dart';
import '../database/attachments_repository.dart';
import '../models/attachment.dart';
import 'backup_crypto.dart';

/// Counts returned after a successful restore (for the UI success dialog).
class RestoreReport {
  const RestoreReport({
    required this.claims,
    required this.attachmentsRestored,
  });

  final int claims;
  final int attachmentsRestored;
}

class BackupService {
  BackupService(this.db, this.files);

  /// The live database handle. [restoreFrom] closes it during the swap —
  /// after a successful restore the caller must reopen via
  /// `AppDatabase.open()` (spec §15).
  final AppDatabase db;

  /// Attachment file store used for export reads and the post-validation
  /// store replacement.
  final AttachmentFileService files;

  // ---------------------------------------------------------------------------
  // Export
  // ---------------------------------------------------------------------------

  /// Builds the encrypted archive bytes for the current live data (DB +
  /// attachments) without writing to disk. The settings screen hands these
  /// bytes to the OS save-file dialog (`FilePicker.saveFile`), which is what
  /// actually places the file where the user chooses — so no shared/public
  /// storage path is ever written by this app (spec §14/§15).
  Future<Uint8List> buildArchive(String passphrase) async {
    // Gather plain data on the main isolate (async reads — no UI blocking),
    // then run serialization + PBKDF2/AES/HMAC off the UI thread. Only
    // sendable plain values cross the boundary — never [db], [files] or File
    // handles.
    final _ExportData data = await _gatherExportData();
    return Isolate.run(() => _encryptInIsolate(passphrase, data));
  }

  /// Encrypts the live database + all attachment files into [destination].
  ///
  /// If a stored row has no backing file (or it is empty), that entry is
  /// serialized with zero length so the archive stays structurally complete;
  /// [restoreFrom] then rejects such archives during staged validation —
  /// spec §15 "missing attachments" fails closed on both ends.
  Future<File> exportTo(File destination, String passphrase) async {
    // sqflite always opens a real on-disk file (never in-memory), so the DB
    // bytes can be read directly from its path — same for FFI host tests.
    final _ExportData data = await _gatherExportData();
    final Uint8List archive = await Isolate.run(
      () => _encryptInIsolate(passphrase, data),
    );

    if (!destination.parent.existsSync()) {
      destination.parent.createSync(recursive: true);
    }
    await destination.writeAsBytes(archive, flush: true);
    return destination;
  }

  /// Reads the live DB bytes and every attachment file with async I/O and
  /// packages them as plain sendable data for the export isolate. A missing
  /// or empty backing file becomes a zero-length entry (restore rejects it).
  Future<_ExportData> _gatherExportData() async {
    final Uint8List dbBytes = await File(db.rawDb.path).readAsBytes();
    final List<Attachment> attachments = await AttachmentsRepository(db)
        .listAll();
    final List<_AttachmentData> atts = <_AttachmentData>[];
    for (final Attachment a in attachments) {
      final File f = files.fileFor(a);
      final Uint8List data = f.existsSync()
          ? await f.readAsBytes()
          : Uint8List(0);
      atts.add(
        _AttachmentData(a.originalName, a.relativePath, a.mimeType, data),
      );
    }
    return _ExportData(dbBytes, atts);
  }

  // ---------------------------------------------------------------------------
  // Restore (staged — see library doc for the order)
  // ---------------------------------------------------------------------------

  Future<RestoreReport> restoreFrom(File source, String passphrase) async {
    final File src = File(source.path);
    if (!src.existsSync()) {
      throw const CorruptArchiveError('backup file not found');
    }

    // --- Step 1: authenticate + decrypt. Throws BEFORE any filesystem
    // mutation of live data (spec §15). The PBKDF2/AES/HMAC work runs in a
    // background isolate so the UI stays responsive; [BackupError] subtypes
    // are plain sendable objects, so they cross back to this isolate and the
    // caller's `on WrongPassphraseError` / `on BackupError` handlers still
    // see the exact same types.
    final Uint8List fileBytes = await src.readAsBytes();
    final Uint8List payload = await Isolate.run(
      () => BackupCrypto.decrypt(passphrase, fileBytes),
    );

    // --- Step 2: parse into a fresh staging directory.
    final Directory staging = Directory.systemTemp.createTempSync('ct_restore');
    try {
      _parsePayload(
        payload,
        staging,
      ); // structural failure → CorruptArchiveError

      // --- Step 3: validate the staged database before touching live data.
      int claims;
      List<Attachment> restoredAttachments;
      final sqf.Database stagedDb = await sqf.openDatabase(
        '${staging.path}/db.sqlite',
        readOnly: true,
      );
      try {
        final List<Map<String, Object?>> integrity = await stagedDb.rawQuery(
          'PRAGMA integrity_check',
        );
        if (integrity.isEmpty || integrity.first['integrity_check'] != 'ok') {
          throw const CorruptArchiveError(
            'staged database failed integrity check',
          );
        }

        claims = (await stagedDb.rawQuery('SELECT id FROM claims')).length;

        final List<Map<String, Object?>> attRows = await stagedDb.rawQuery(
          'SELECT * FROM attachments ORDER BY id',
        );
        restoredAttachments = attRows
            .map(Attachment.fromRow)
            .toList(growable: false);

        for (final Attachment a in restoredAttachments) {
          final File f = File('${staging.path}/files/${a.relativePath}');
          if (!f.existsSync() || f.lengthSync() == 0) {
            throw const CorruptArchiveError(
              'attachment file missing from archive',
            );
          }
        }
      } finally {
        await stagedDb.close();
      }

      // --- Step 4: swap. Reached only after every validation above passed,
      // so destroying the old data here is safe (spec §15).
      final String livePath = db.rawDb.path;
      await db.close(); // sqflite no-ops if already closed — safe either way
      File(livePath).deleteSync();
      await _moveFile(File('${staging.path}/db.sqlite'), livePath);
      await files.replaceStoreFrom(Directory('${staging.path}/files'));

      return RestoreReport(
        claims: claims,
        attachmentsRestored: restoredAttachments.length,
      );
    } finally {
      // Every path — success or failure — leaves no staging leftovers.
      if (staging.existsSync()) staging.deleteSync(recursive: true);
    }
  }

  // ---------------------------------------------------------------------------
  // Payload serialization (format v1, big-endian)
  //   u64 dbBytesLength || dbBytes
  //   u32 attachmentCount
  //   per attachment:
  //     u32 originalNameLen || UTF-8 name
  //     u32 relativePathLen || path (relative, slash-separated)
  //     u32 mimeTypeLen    || MIME type
  //     u64 dataLength     || file bytes
  // ---------------------------------------------------------------------------

  // ---------------------------------------------------------------------------
  // Isolate-side export (runs off the UI thread — see [buildArchive])
  // ---------------------------------------------------------------------------

  /// Serializes plain export data and encrypts it. Runs inside `Isolate.run`
  /// with only sendable values ([String] passphrase + [_ExportData]).
  static Uint8List _encryptInIsolate(String passphrase, _ExportData data) {
    return BackupCrypto.encrypt(passphrase, _serializePayload(data));
  }

  /// Serializes already-gathered plain data (format v1, big-endian). No file
  /// or database access happens here — the bytes were read on the caller's
  /// isolate before crossing into this one.
  static Uint8List _serializePayload(_ExportData data) {
    final BytesBuilder b = BytesBuilder(copy: false);
    _putU64(b, data.dbBytes.length);
    b.add(data.dbBytes);
    _putU32(b, data.attachments.length);
    for (final _AttachmentData a in data.attachments) {
      _putString(b, a.originalName);
      _putString(b, a.relativePath);
      _putString(b, a.mimeType);
      _putU64(b, a.data.length);
      b.add(a.data);
    }
    return b.toBytes();
  }

  void _parsePayload(Uint8List payload, Directory staging) {
    final _Reader r = _Reader(payload);

    final int dbLen = r.u64('database length');
    final Uint8List dbBytes = r.bytes(dbLen, 'database bytes');
    File('${staging.path}/db.sqlite').writeAsBytesSync(dbBytes, flush: true);

    final int count = r.u32('attachment count');
    for (var i = 0; i < count; i++) {
      r.str('original_name', i); // parsed + validated UTF-8 (discarded here)
      final String rel = _validatedRelativePath(r.str('relative_path', i));
      r.str('mime_type', i);
      final int dataLen = r.u64('attachment data length');
      final Uint8List data = r.bytes(dataLen, 'attachment data');

      final File f = File('${staging.path}/files/$rel');
      f.parent.createSync(recursive: true);
      f.writeAsBytesSync(data, flush: true);
    }

    if (r.pos != payload.length) {
      throw const CorruptArchiveError('trailing bytes after payload');
    }
  }

  /// Rejects absolute paths and any `..`/`.` segment — an archive must never
  /// be able to stage files outside its own staging dir.
  String _validatedRelativePath(String rel) {
    if (rel.isEmpty || rel.startsWith('/')) {
      throw const CorruptArchiveError('unsafe attachment path in archive');
    }
    final List<String> parts = rel.replaceAll('\\', '/').split('/');
    if (parts.any((String p) => p == '..' || p == '.')) {
      throw const CorruptArchiveError('unsafe attachment path in archive');
    }
    return rel;
  }

  /// Moves [src] to [destPath], falling back to copy+delete when a direct
  /// rename is not possible (e.g. cross-device on some platforms).
  Future<void> _moveFile(File src, String destPath) async {
    final File dest = File(destPath);
    if (!dest.parent.existsSync()) dest.parent.createSync(recursive: true);
    try {
      await src.rename(dest.path);
    } on FileSystemException {
      await src.copy(dest.path);
      await src.delete();
    }
  }

  // --- big-endian writers ----------------------------------------------------

  static void _putU32(BytesBuilder b, int v) {
    b.addByte((v >> 24) & 0xff);
    b.addByte((v >> 16) & 0xff);
    b.addByte((v >> 8) & 0xff);
    b.addByte(v & 0xff);
  }

  static void _putU64(BytesBuilder b, int v) {
    for (var i = 56; i >= 0; i -= 8) {
      b.addByte((v >> i) & 0xff);
    }
  }

  static void _putString(BytesBuilder b, String s) {
    final List<int> utf8 = const Utf8Encoder().convert(s);
    _putU32(b, utf8.length);
    b.add(utf8);
  }
}

/// Plain, sendable snapshot of everything an export needs (DB bytes + one
/// record per attachment). Only simple values live here, so it can cross an
/// isolate boundary into [_encryptInIsolate] without dragging the database
/// handle or [AttachmentFileService] along.
class _ExportData {
  const _ExportData(this.dbBytes, this.attachments);

  final Uint8List dbBytes;
  final List<_AttachmentData> attachments;
}

/// One attachment's metadata + bytes as plain values (no [Attachment] model,
/// no [File]).
class _AttachmentData {
  const _AttachmentData(
    this.originalName,
    this.relativePath,
    this.mimeType,
    this.data,
  );

  final String originalName;
  final String relativePath;
  final String mimeType;
  final Uint8List data;
}

/// Bounds-checked big-endian reader over a payload. Every read that would run
/// past the end throws [CorruptArchiveError] — never returns partial data.
class _Reader {
  _Reader(this._b);

  final Uint8List _b;
  int pos = 0;

  void _check(int n, String what) {
    if (n < 0 || pos + n > _b.length) {
      throw CorruptArchiveError('truncated $what');
    }
  }

  int u32(String what) {
    _check(4, what);
    final int v =
        (_b[pos] << 24) |
        (_b[pos + 1] << 16) |
        (_b[pos + 2] << 8) |
        _b[pos + 3];
    pos += 4;
    return v;
  }

  int u64(String what) {
    _check(8, what);
    var v = 0;
    for (var i = 0; i < 8; i++) {
      v = (v << 8) | _b[pos + i];
    }
    pos += 8;
    return v;
  }

  Uint8List bytes(int n, String what) {
    _check(n, what);
    final Uint8List out = _b.sublist(pos, pos + n);
    pos += n;
    return out;
  }

  /// Reads a u32-length-prefixed UTF-8 string; invalid UTF-8 is corruption.
  String str(String what, int index) {
    final int n = u32('$what length');
    final Uint8List raw = bytes(n, what);
    try {
      return utf8.decode(raw);
    } on FormatException {
      throw CorruptArchiveError('invalid UTF-8 in $what #$index');
    }
  }
}
