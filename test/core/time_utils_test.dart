/// Time utility tests: Asia/Riyadh day boundaries and formatting (spec §2, §10).
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:claim_tracker/core/l10n/app_strings.dart';
import 'package:claim_tracker/core/models/claim_status.dart';
import 'package:claim_tracker/core/utils/time_utils.dart';

void main() {
  setUpAll(() => TimeUtils.ensureInitialized());

  group('riyadh day range', () {
    test('bounds are UTC and span exactly 24h', () {
      final (DateTime startUtc, DateTime endUtc) = TimeUtils.riyadhDayRange(
        DateTime.utc(2026, 11, 11, 12),
      );
      expect(startUtc.isUtc, isTrue);
      expect(endUtc.difference(startUtc), const Duration(hours: 24));
    });

    test('Riyadh midnight maps to 21:00 UTC (UTC+3)', () {
      // 2026-11-11 00:00 Asia/Riyadh == 2026-11-10 21:00 UTC.
      final (DateTime startUtc, _) = TimeUtils.riyadhDayRange(
        DateTime.utc(2026, 11, 10, 21, 30),
      ); // inside that Riyadh day
      expect(startUtc, DateTime.utc(2026, 11, 10, 21));
    });

    test('isSameRiyadhDay respects the local calendar day', () {
      final DateTime a = DateTime.utc(2026, 11, 10, 23); // Riyadh: Nov 11 02:00
      final DateTime b = DateTime.utc(2026, 11, 11, 1); // Riyadh: Nov 11 04:00
      expect(TimeUtils.isSameRiyadhDay(a, b), isTrue);

      final DateTime c = DateTime.utc(2026, 11, 9, 23); // Riyadh: Nov 10 02:00
      expect(TimeUtils.isSameRiyadhDay(a, c), isFalse);
    });
  });

  group('formatting', () {
    test('dates render in the default (English) locale without throwing', () {
      AppLocale.locale = const Locale('en');
      final String s = TimeUtils.formatDate(DateTime.utc(2026, 11, 11));
      expect(s, isNotEmpty);
      // English digits + separators.
      expect(s, contains('2026'));
    });

    test('dates follow the active locale (ar renders differently from en)', () {
      final DateTime d = DateTime.utc(2026, 11, 11);
      AppLocale.locale = const Locale('en');
      final String en = TimeUtils.formatDate(d);

      AppLocale.locale = const Locale('ar');
      final String ar = TimeUtils.formatDate(d);
      expect(ar, isNotEmpty);
      // The locale switch must change the rendered output (intl 0.20 renders
      // ar with RTL marks; digits may stay Latin depending on intl version).
      expect(ar, isNot(en));

      AppLocale.locale = const Locale('en'); // restore default
    });

    test('SAR formatting includes the localized currency label (spec §2)', () {
      AppLocale.locale = const Locale('en');
      expect(TimeUtils.formatSar(1250.75), contains('SAR'));
      expect(TimeUtils.formatSar(null), '—');

      AppLocale.locale = const Locale('ar');
      expect(TimeUtils.formatSar(1250.75), contains('ر.س'));
    });

    test('follow-up urgency labels are localized', () {
      final DateTime nowUtc = DateTime.utc(2026, 11, 11, 12);

      AppLocale.locale = const Locale('en');
      expect(
        TimeUtils.followUpLabel(
          nowUtc.subtract(const Duration(days: 1)),
          nowUtc: nowUtc,
        ),
        'Overdue',
      );
      expect(TimeUtils.followUpLabel(nowUtc, nowUtc: nowUtc), 'Today');

      AppLocale.locale = const Locale('ar');
      expect(
        TimeUtils.followUpLabel(
          nowUtc.subtract(const Duration(days: 1)),
          nowUtc: nowUtc,
        ),
        'متأخرة',
      );
      expect(TimeUtils.followUpLabel(nowUtc, nowUtc: nowUtc), 'اليوم');

      AppLocale.locale = const Locale('en'); // restore default
    });
  });

  group('claim status registry', () {
    test('all ten spec §8 statuses exist with unique keys + EN labels', () {
      AppLocale.locale = const Locale('en');
      final List<String> keys = ClaimStatus.all.map((m) => m.key).toList();
      expect(keys.length, 10);
      expect(keys.toSet().length, 10);
      expect(
        ClaimStatus.all.map((m) => m.label),
        containsAll(<String>[
          'New',
          'Claim Submitted',
          'Awaiting Review',
          'Awaiting Documents',
          'In Processing',
          'Awaiting Approval',
          'Approved',
          'Compensated',
          'Rejected',
          'Closed',
        ]),
      );
    });

    test('status labels follow the active locale (ar)', () {
      AppLocale.locale = const Locale('ar');
      expect(
        ClaimStatus.all.map((m) => m.label),
        containsAll(<String>[
          'جديدة',
          'تم تقديم المطالبة',
          'بانتظار المراجعة',
          'بانتظار مستندات',
          'تحت المعالجة',
          'بانتظار الموافقة',
          'تمت الموافقة',
          'تم التعويض',
          'مرفوضة',
          'مغلقة',
        ]),
      );
      AppLocale.locale = const Locale('en'); // restore default
    });

    test('only مغلقة/Closed counts as closed (spec §5)', () {
      for (final meta in ClaimStatus.all) {
        if (meta.key == 'closed') {
          expect(meta.isClosed, isTrue);
        } else {
          expect(meta.isClosed, isFalse, reason: meta.label);
        }
      }
    });

    test('byKey throws on unknown keys', () {
      expect(() => ClaimStatus.byKey('nope'), throwsArgumentError);
    });
  });
}
