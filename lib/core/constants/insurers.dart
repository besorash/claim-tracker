/// Insurance companies offered in the claim form's insurer list.
///
/// A claim stores the English name ([Insurer.en]); the list and the details
/// screen show the name in the app's language. Any other company can still
/// be typed in through the "Other" choice and is stored as typed.
library;

import '../l10n/app_strings.dart';

class Insurer {
  const Insurer(this.en, this.ar);

  /// Stored value and English display name.
  final String en;

  /// Arabic display name.
  final String ar;

  /// Name in the active UI language.
  String get label => AppLocale.locale.languageCode == 'ar' ? ar : en;
}

abstract final class Insurers {
  static const List<Insurer> all = <Insurer>[
    Insurer('GIG', 'شركة الخليجية للتأمين'),
    Insurer('Walaa', 'شركة ولاء للتأمين'),
    Insurer('Wataniya', 'شركة الوطنية للتأمين'),
    Insurer('Tawuniya', 'شركة التعاونية للتأمين'),
    Insurer('Liva', 'شركة ليفا للتأمين'),
    Insurer('Chubb', 'شركة تشب للتأمين'),
    Insurer('Orient', 'شركة أورينت للتأمين'),
    Insurer('Arabia', 'شركة العربية للتأمين'),
    Insurer('Mutakamela', 'شركة المتكاملة للتأمين'),
    Insurer('Etihad', 'شركة الإتحاد للتأمين'),
    Insurer('Malath', 'شركة ملاذ للتأمين'),
    Insurer('Takaful AlRajhi', 'شركة تكافل الراجحي للتأمين'),
    Insurer('UCA', 'شركة المتحدة للتأمين'),
    Insurer('Salama', 'شركة سلامة للتأمين'),
    Insurer('Arabian Shield', 'شركة الدرع العربي للتأمين'),
  ];

  /// The listed company a stored value refers to, matched on either name and
  /// ignoring case and spaces (`ORIENT`, `orient`, `شركة أورينت للتأمين`).
  /// Null for a company that is not in the list.
  static Insurer? match(String? value) {
    if (value == null) return null;
    final String wanted = _key(value);
    if (wanted.isEmpty) return null;
    for (final Insurer i in all) {
      if (_key(i.en) == wanted || _key(i.ar) == wanted) return i;
    }
    return null;
  }

  /// How a stored value is shown: a listed company in the app's language,
  /// anything else as typed.
  static String display(String value) => match(value)?.label ?? value;

  /// Stored (English) names of listed companies whose name in either
  /// language contains [query] — lets a search for "الخليجية" find "GIG".
  static List<String> namesContaining(String query) {
    final String q = _key(query);
    if (q.isEmpty) return const <String>[];
    return <String>[
      for (final Insurer i in all)
        if (_key(i.en).contains(q) || _key(i.ar).contains(q)) i.en,
    ];
  }

  static String _key(String s) => s.toLowerCase().replaceAll(' ', '').trim();
}
