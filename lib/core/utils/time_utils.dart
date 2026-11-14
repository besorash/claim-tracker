/// Time helpers anchored to Asia/Riyadh (spec §2, §10).
library;

import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../constants/app_constants.dart';
import '../l10n/app_strings.dart';

class TimeUtils {
  static bool _initialized = false;

  /// Loads the IANA database and pins the default zone to Asia/Riyadh.
  /// Safe to call multiple times (idempotent).
  /// Must be awaited before any [DateFormat] usage (locale data for both
  /// supported UI languages — English is the default, Arabic on switch).
  static Future<void> ensureInitialized() async {
    if (_initialized) return;
    await initializeDateFormatting('en');
    await initializeDateFormatting('ar');
    tzdata.initializeTimeZones();
    tz.setLocalLocation(tz.getLocation(AppConstants.timeZoneId));
    _initialized = true;
  }

  static tz.TZDateTime toRiyadh(DateTime utc) =>
      tz.TZDateTime.from(utc.toUtc(), tz.getLocation(AppConstants.timeZoneId));

  /// The [startUtc, endUtc] bounds of the current calendar day in Asia/Riyadh.
  static (DateTime startUtc, DateTime endUtc) riyadhDayRange(DateTime nowUtc) =>
      _dayBounds(nowUtc.toUtc());

  static (DateTime startUtc, DateTime endUtc) _dayBounds(DateTime utc) {
    final tz.TZDateTime local = toRiyadh(utc);
    final tz.TZDateTime dayStartLocal = tz.TZDateTime(
      local.location,
      local.year,
      local.month,
      local.day,
    );
    return (
      dayStartLocal.toUtc(),
      dayStartLocal.add(const Duration(days: 1)).toUtc(),
    );
  }

  static bool isSameRiyadhDay(DateTime aUtc, DateTime bUtc) {
    final tz.TZDateTime la = toRiyadh(aUtc);
    final tz.TZDateTime lb = toRiyadh(bUtc);
    return la.year == lb.year && la.month == lb.month && la.day == lb.day;
  }

  // ---------------------------------------------------------------------------
  // Display formatting (current UI language, Asia/Riyadh) — spec §3.4, §2.
  // ---------------------------------------------------------------------------

  /// Locale-aware formatters, rebuilt when the UI language changes so dates
  /// follow the active locale (en: `11/11/2026`, ar: «١١/١١/٢٠٢٦»).
  static String? _fmtLocale;
  static DateFormat? _dateFmt;
  static DateFormat? _dateTimeFmt;

  static void _ensureFormatters() {
    final String locale = AppLocale.locale.languageCode;
    if (_fmtLocale != locale || _dateFmt == null) {
      _fmtLocale = locale;
      _dateFmt = DateFormat.yMd(locale);
      _dateTimeFmt = DateFormat.Md(locale).add_Hms();
    }
  }

  /// e.g. «11/11/2026» (en) or «١١/١١/٢٠٢٦» (ar — Arabic-Indic digits).
  static String formatDate(DateTime utc) {
    _ensureFormatters();
    return _dateFmt!.format(toRiyadh(utc));
  }

  /// Date + time, e.g. «11/11/2026 3:45 PM» (en) or «١١/١١/٢٠٢٦ ٣:٤٥ م» (ar).
  static String formatDateTime(DateTime utc) {
    _ensureFormatters();
    return _dateTimeFmt!.format(toRiyadh(utc));
  }

  /// SAR amount with thousands separators + the localized currency label.
  static String formatSar(double? amount) {
    if (amount == null) return '—';
    final String s = amount.toStringAsFixed(
      amount.truncateToDouble() == amount ? 0 : 2,
    );
    final List<String> parts = s.split('.');
    final StringBuffer intPart = StringBuffer();
    for (var i = 0; i < parts[0].length; i++) {
      if (i > 0 && (parts[0].length - i) % 3 == 0) intPart.write(',');
      intPart.write(parts[0][i]);
    }
    final String joined = parts.length > 1
        ? '$intPart.${parts[1]}'
        : intPart.toString();
    return '$joined ${S.currencySar}';
  }

  /// Relative localized label for follow-up urgency (spec §6 indicators).
  static String followUpLabel(DateTime? utc, {required DateTime nowUtc}) {
    if (utc == null) return '';
    final tz.TZDateTime local = toRiyadh(utc);
    final tz.TZDateTime nowLocal = toRiyadh(nowUtc);
    if (local.isBefore(nowLocal)) return S.followUpOverdue;
    if (isSameRiyadhDay(utc, nowUtc)) return S.followUpToday;
    return formatDateTime(utc);
  }
}
