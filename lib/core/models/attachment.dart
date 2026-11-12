/// Attachment record (spec §12). Physical files live in app-private storage;
/// [relativePath] is relative to the attachments directory.
library;

class Attachment {
  const Attachment({
    required this.id,
    required this.claimId,
    required this.originalName,
    required this.mimeType,
    required this.sizeBytes,
    required this.relativePath,
    required this.createdAtUtcMs,
  });

  final int id;
  final int claimId;
  final String originalName;
  final String mimeType;
  final int sizeBytes;

  /// Path relative to the app's attachments directory (never absolute).
  final String relativePath;
  final DateTime createdAtUtcMs;

  Map<String, Object?> toRow() => <String, Object?>{
    'id': id,
    'claim_id': claimId,
    'original_name': originalName,
    'mime_type': mimeType,
    'size_bytes': sizeBytes,
    'relative_path': relativePath,
    'created_at_utc_ms': createdAtUtcMs.millisecondsSinceEpoch,
  };

  factory Attachment.fromRow(Map<String, Object?> row) => Attachment(
    id: row['id']! as int,
    claimId: row['claim_id']! as int,
    originalName: row['original_name']! as String,
    mimeType: row['mime_type']! as String,
    sizeBytes: row['size_bytes']! as int,
    relativePath: row['relative_path']! as String,
    createdAtUtcMs: DateTime.fromMillisecondsSinceEpoch(
      row['created_at_utc_ms']! as int,
      isUtc: true,
    ),
  );
}
