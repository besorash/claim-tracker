/// Attachment metadata persistence (spec §12). Physical file handling is done
/// by `AttachmentFileService` in the attachments feature; this repository only
/// stores rows.
library;

import '../models/attachment.dart';
import 'app_database.dart';

class AttachmentsRepository {
  const AttachmentsRepository(this._db);

  final AppDatabase _db;

  /// Inserts a new row. Callers pass `id == 0` as "unsaved" — the explicit id
  /// is stripped so SQLite assigns the next auto-increment value (same
  /// convention as [ClaimsRepository.create]).
  Future<int> create(Attachment attachment) async {
    final Map<String, Object?> row = Map.of(attachment.toRow())..remove('id');
    return _db.rawDb.insert('attachments', row);
  }

  Future<List<Attachment>> listForClaim(int claimId) =>
      _db.attachmentsForClaim(claimId);

  /// Every attachment row, ordered by id (used by backup export/restore).
  Future<List<Attachment>> listAll() async {
    final List<Map<String, Object?>> rows = await _db.rawDb.query(
      'attachments',
      orderBy: 'id',
    );
    return rows.map(Attachment.fromRow).toList(growable: false);
  }

  /// Deletes the row (spec §12). The caller is responsible for deleting the
  /// physical file using [Attachment.relativePath].
  Future<void> delete(int id) =>
      _db.rawDb.delete('attachments', where: 'id = ?', whereArgs: [id]);
}
