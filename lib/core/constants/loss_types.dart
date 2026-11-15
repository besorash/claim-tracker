/// Loss type of a claim: total loss or partial loss (optional).
///
/// Stored as a stable key ([total] / [partial]); shown in the app's
/// language. [parse] also accepts the English and Arabic names so CSV,
/// Sheets and the assistant can pass either.
library;

import '../l10n/app_strings.dart';

abstract final class LossTypes {
  static const String total = 'total';
  static const String partial = 'partial';
  static const List<String> all = <String>[total, partial];

  /// Label in the app's language; anything unknown is shown as stored.
  static String label(String key) => switch (key) {
    total => S.lossTotal,
    partial => S.lossPartial,
    _ => key,
  };

  /// Key for a stored key or an English/Arabic name; null when unknown.
  static String? parse(String? raw) {
    final String v = (raw ?? '').trim().toLowerCase().replaceAll(' ', '');
    if (v.isEmpty) return null;
    if (const <String>{
      'total',
      'totalloss',
      'كلية',
      'خسارةكلية',
      'كلي',
    }.contains(v)) {
      return total;
    }
    if (const <String>{
      'partial',
      'partialloss',
      'جزئية',
      'خسارةجزئية',
      'جزئي',
    }.contains(v)) {
      return partial;
    }
    return null;
  }
}
