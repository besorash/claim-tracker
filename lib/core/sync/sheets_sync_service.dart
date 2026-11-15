/// Two-way, manual sync between the claims and one Google Sheet, through the
/// Apps Script in `tools/google_sheets_sync/Code.gs`.
///
/// How a sync decides (per claim id):
///  * `sheet_sync_state` holds a fingerprint of each claim's content at the
///    end of the last sync. A side whose content no longer matches it changed.
///  * Only the sheet changed → the app takes the sheet row.
///  * Only the app changed → the row is sent to the sheet.
///  * Both changed → the newer edit wins: the sheet's `updated_at` stamp (set
///    by the script on every hand edit) against the claim's last update.
///  * A sheet row without an id (or a repeated id) becomes a new claim, and
///    its new id is written back into that row.
///  * A claim deleted in the app is deleted from the sheet. A row deleted in
///    the sheet is NOT deleted from the app; the claim is sent back instead.
///  * First sync (no fingerprints yet): the sheet wins wherever they differ.
library;

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

import '../../features/claims/claim_actions.dart';
import '../csv/claims_csv.dart';
import '../csv/claims_csv_service.dart';
import '../database/app_database.dart';
import '../models/claim.dart';

/// Sends one JSON request to the script and returns its decoded answer.
typedef SheetsTransport =
    Future<Map<String, Object?>> Function(Uri url, Map<String, Object?> body);

/// A sync that could not run. [message] is shown to the user as-is.
class SheetsSyncException implements Exception {
  const SheetsSyncException(this.message);
  final String message;
  @override
  String toString() => message;
}

class SheetsSyncReport {
  int created = 0; // new claims from sheet rows
  int updated = 0; // claims updated from the sheet
  int sent = 0; // claims written to the sheet
  int deleted = 0; // rows removed from the sheet
  int conflicts = 0; // edited on both sides; the newer one was kept
  int idMisses = 0; // new ids the script could not write back
  final List<String> skipped = <String>[]; // invalid rows, with the reason
}

class SheetsSyncService {
  SheetsSyncService(this.db, this.csv, {SheetsTransport? transport})
    : _transport = transport ?? httpTransport;

  final AppDatabase db;
  final ClaimsCsvService csv;
  final SheetsTransport _transport;

  static const String urlKey = 'sheets_sync_url';
  static const String tokenKey = 'sheets_sync_token';
  static const String lastSyncKey = 'sheets_sync_last_utc_ms';
  static const String _stamp = 'updated_at';

  Future<SheetsSyncReport> sync() async {
    final String url = (await db.setting(urlKey) ?? '').trim();
    final String token = (await db.setting(tokenKey) ?? '').trim();
    final Uri? uri = Uri.tryParse(url);
    if (uri == null || uri.scheme != 'https' || token.isEmpty) {
      throw const SheetsSyncException('not-configured');
    }

    final Map<String, Object?> pulled = await _transport(uri, <String, Object?>{
      'token': token,
      'action': 'pull',
    });
    final List<String> header = (pulled['header'] as List<Object?>? ?? const [])
        .map((Object? h) => '$h')
        .toList();
    final List<List<String>> rows =
        (pulled['rows'] as List<Object?>? ?? const [])
            .map((Object? r) => (r! as List<Object?>).map((v) => '$v').toList())
            .toList();

    final int stampCol = header.indexWhere(
      (String h) => h.trim().toLowerCase() == _stamp,
    );
    String? stampOf(int line) {
      final int i = line - 2; // header is sheet row 1
      if (stampCol < 0 || i < 0 || i >= rows.length) return null;
      final List<String> r = rows[i];
      return stampCol < r.length ? r[stampCol] : null;
    }

    // Every sheet row becomes one CSV line, so a record's line number is its
    // sheet row number (blank rows are skipped by the parser but counted).
    final StringBuffer text = StringBuffer();
    void line(List<String> cells) {
      text
        ..write(<String>[
          for (int i = 0; i < header.length; i++)
            if (i != stampCol) ClaimsCsv.cell(i < cells.length ? cells[i] : ''),
        ].join(','))
        ..write('\r\n');
    }

    line(header);
    rows.forEach(line);
    final CsvDocument doc = ClaimsCsv.parse(text.toString());
    if (doc.headerError != null) throw SheetsSyncException(doc.headerError!);

    final Map<int, String> known = await _loadState();
    final Map<int, Claim> local = <int, Claim>{
      for (final Claim c in await db.allClaims()) c.id: c,
    };
    final Map<int, String> next = <int, String>{};
    final Set<int> seen = <int>{};
    final List<int> createdIds = <int>[];
    final List<Map<String, Object?>> setIds = <Map<String, Object?>>[];
    final List<Map<String, String>> upserts = <Map<String, String>>[];
    final List<String> deletes = <String>[];
    final SheetsSyncReport report = SheetsSyncReport();

    try {
      for (final CsvRecord record in doc.records) {
        final String rawId = (record.values['id'] ?? '').trim();
        int? id = ClaimsCsv.idOf(record);

        if (id != null && !local.containsKey(id) && known.containsKey(id)) {
          deletes.add(rawId); // deleted in the app since the last sync
          continue;
        }
        if (id != null && (seen.contains(id) || !local.containsKey(id))) {
          id = null; // repeated or unknown id: this row is a new claim
        }

        final Claim? existing = id == null ? null : local[id];
        final SyncRowPlan plan = csv.planSyncRow(
          id == null && rawId.isNotEmpty
              ? CsvRecord(record.line, <String, String>{
                  ...record.values,
                  'id': '',
                }, extras: record.extras)
              : record,
          doc.dateOrder,
          existing,
        );
        if (id != null) seen.add(id);
        if (plan.target == null) {
          report.skipped.addAll(plan.errors);
          if (id != null) next[id] = known[id] ?? fingerprint(existing!);
          continue;
        }

        if (existing == null) {
          final int newId = await csv.applySyncRow(plan);
          createdIds.add(newId);
          seen.add(newId);
          setIds.add(<String, Object?>{
            'row': record.line,
            'old': rawId,
            'id': newId,
          });
          next[newId] = fingerprint((await db.claimById(newId))!);
          report.created++;
          continue;
        }

        final String mine = fingerprint(existing);
        final String theirs = fingerprint(plan.target!);
        final String? base = known[existing.id];
        if (mine == theirs) {
          next[existing.id] = mine;
          continue;
        }
        final bool sheetChanged = theirs != base;
        final bool appChanged = base != null && mine != base;
        bool takeSheet = sheetChanged;
        if (sheetChanged && appChanged) {
          report.conflicts++;
          final DateTime? edited = DateTime.tryParse(
            stampOf(record.line) ?? '',
          );
          takeSheet =
              edited == null || edited.isAfter(existing.updatedAtUtcMs);
        }
        if (takeSheet) {
          await csv.applySyncRow(plan);
          next[existing.id] = fingerprint((await db.claimById(existing.id))!);
          report.updated++;
        } else {
          upserts.add(_rowOf(existing));
          next[existing.id] = mine;
          report.sent++;
        }
      }

      // Claims the sheet does not have (new in the app, or row removed).
      for (final Claim c in local.values) {
        if (seen.contains(c.id)) continue;
        upserts.add(_rowOf(c));
        next[c.id] = fingerprint(c);
        report.sent++;
      }

      if (setIds.isNotEmpty || upserts.isNotEmpty || deletes.isNotEmpty) {
        final Map<String, Object?> pushed = await _transport(
          uri,
          <String, Object?>{
            'token': token,
            'action': 'push',
            'setIds': setIds,
            'upserts': upserts,
            'deletes': deletes,
          },
        );
        report.idMisses = (pushed['idMisses'] as num?)?.toInt() ?? 0;
        report.deleted = deletes.length;
      }
    } on Object {
      // The sheet never got their ids, so the next sync would create them
      // again: undo the new claims. Updates from the sheet are kept (they
      // simply match the sheet next time).
      final ClaimActions actions = ClaimActions(db, csv.scheduler);
      for (final int id in createdIds) {
        await actions.deleteClaim(id); // also cancels its follow-up alarm
      }
      rethrow;
    }

    await _saveState(next);
    await db.setSetting(
      lastSyncKey,
      DateTime.now().toUtc().millisecondsSinceEpoch.toString(),
    );
    return report;
  }

  /// The claim's content as the sheet shows it (everything but the id).
  static String fingerprint(Claim c) {
    final Map<String, String> v = ClaimsCsv.valuesOf(c)..remove('id');
    final List<String> extras = c.extraFields.keys.toList()..sort();
    final String body = jsonEncode(<Object>[
      v,
      <String>[for (final String k in extras) '$k=${c.extraFields[k]}'],
    ]);
    return sha1.convert(utf8.encode(body)).toString();
  }

  static Map<String, String> _rowOf(Claim c) => <String, String>{
    ...ClaimsCsv.valuesOf(c),
    ...c.extraFields,
  };

  Future<Map<int, String>> _loadState() async {
    final List<Map<String, Object?>> rows = await db.rawDb.query(
      'sheet_sync_state',
    );
    return <int, String>{
      for (final Map<String, Object?> r in rows)
        r['claim_id']! as int: r['fingerprint']! as String,
    };
  }

  Future<void> _saveState(Map<int, String> state) =>
      db.rawDb.transaction((txn) async {
        await txn.delete('sheet_sync_state');
        for (final MapEntry<int, String> e in state.entries) {
          await txn.insert('sheet_sync_state', <String, Object?>{
            'claim_id': e.key,
            'fingerprint': e.value,
          });
        }
      });

  /// POSTs [body] as JSON. Apps Script answers a POST with a redirect to the
  /// result, which is then fetched with GET.
  static Future<Map<String, Object?>> httpTransport(
    Uri url,
    Map<String, Object?> body,
  ) async {
    final HttpClient client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 20);
    try {
      final HttpClientRequest req = await client.postUrl(url);
      req.followRedirects = false;
      req.headers.contentType = ContentType('text', 'plain', charset: 'utf-8');
      req.add(utf8.encode(jsonEncode(body)));
      HttpClientResponse res = await req.close().timeout(
        const Duration(seconds: 90),
      );
      for (int hops = 0; res.isRedirect && hops < 5; hops++) {
        final String? location = res.headers.value(HttpHeaders.locationHeader);
        await res.drain<void>();
        if (location == null) break;
        res = await (await client.getUrl(url.resolve(location))).close().timeout(
          const Duration(seconds: 90),
        );
      }
      final String text = await res
          .transform(utf8.decoder)
          .join()
          .timeout(const Duration(seconds: 90));
      if (res.statusCode != 200) {
        throw SheetsSyncException('HTTP ${res.statusCode}');
      }
      final Object? decoded;
      try {
        decoded = jsonDecode(text);
      } on FormatException {
        throw const SheetsSyncException('bad-response');
      }
      if (decoded is! Map<String, Object?>) {
        throw const SheetsSyncException('bad-response');
      }
      if (decoded['ok'] != true) {
        throw SheetsSyncException('${decoded['error'] ?? 'bad-response'}');
      }
      return decoded;
    } finally {
      client.close();
    }
  }
}
