/// Accident types offered in the claim form's accident-type dropdown.
///
/// A claim stores the English name ([AccidentType.en]); the list and the
/// details screen show the name in the app's language — same convention as
/// [Insurers]. The field used to be free text, so [display] falls back to the
/// stored value for anything outside this fixed list (legacy claims keep
/// showing what was typed).
library;

import '../l10n/app_strings.dart';

class AccidentType {
  const AccidentType(this.en, this.ar);

  /// Stored value and English display name.
  final String en;

  /// Arabic display name.
  final String ar;

  /// Name in the active UI language.
  String get label => AppLocale.locale.languageCode == 'ar' ? ar : en;
}

abstract final class AccidentTypes {
  static const List<AccidentType> all = <AccidentType>[
    AccidentType('Najem', 'نجم'),
    AccidentType('Moroor', 'مرور'),
    AccidentType('Police', 'الشرطة'),
    AccidentType('Glass', 'زجاج أمامي'),
    AccidentType('MTR', 'MTR'),
    AccidentType('Civil Defense', 'الدفاع المدني'),
    AccidentType('Others', 'أخرى'),
  ];

  /// The listed type a stored value refers to, matched on either name and
  /// ignoring case and spaces (e.g. `glass`, `زجاج أمامي`). Null when the
  /// value is not one of the fixed options.
  static AccidentType? match(String? value) {
    if (value == null) return null;
    final String wanted = _key(value);
    if (wanted.isEmpty) return null;
    for (final AccidentType t in all) {
      if (_key(t.en) == wanted || _key(t.ar) == wanted) return t;
    }
    return null;
  }

  /// How a stored value is shown: a listed type in the app's language,
  /// anything else as typed (legacy free-form values).
  static String display(String value) => match(value)?.label ?? value;

  static String _key(String s) => s.toLowerCase().replaceAll(' ', '').trim();
}
