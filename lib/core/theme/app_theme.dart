/// Design tokens and Light/Dark themes (spec §3).
///
/// Palette direction (spec §3.1): deep navy `#101D35`, deep blue `#173D5C`,
/// teal `#19A99A`, soft neutral light background `#F3F5F8`. Colors are exposed
/// as semantic tokens — widgets must not use raw hex values.
library;

import 'package:flutter/material.dart';

import '../models/claim_status.dart';

abstract final class AppColors {
  // Brand palette (spec §3.1).
  static const Color navy = Color(0xFF101D35);
  static const Color deepBlue = Color(0xFF173D5C);
  static const Color teal = Color(0xFF19A99A);
  static const Color lightBackground = Color(0xFFF3F5F8);

  // Light theme neutrals.
  static const Color lightSurface = Color(0xFFFFFFFF);
  static const Color lightOnSurface = Color(0xFF1B2437);
  static const Color lightMutedText = Color(0xFF5A6579);
  static const Color lightOutline = Color(0xFFD8DEE8);

  // Dark theme neutrals.
  static const Color darkBackground = Color(0xFF0C1424);
  static const Color darkSurface = Color(0xFF152238);
  static const Color darkOnSurface = Color(0xFFE6EBF4);
  static const Color darkMutedText = Color(0xFF9AA7BD);
  static const Color darkOutline = Color(0xFF2C3B57);

  // Shared semantic colors.
  static const Color errorLight = Color(0xFFB3261E);
  static const Color errorDark = Color(0xFFF2A9A5);

  // Notes highlight (claim details screen): the notes row is the one field
  // that must stand out from every other section — a distinct orange in both
  // themes, each pair keeping ≥6.7:1 contrast against its own fill so the
  // text stays fully legible (WCAG AA with margin).
  static const Color lightNotesFill = Color(0xFFFFE0B2);
  static const Color lightNotesText = Color(0xFF7A3B08);
  static const Color lightNotesBorder = Color(0xFFF57C20);

  static const Color darkNotesFill = Color(0xFF4E2C10);
  static const Color darkNotesText = Color(0xFFFFB867);
  static const Color darkNotesBorder = Color(0xFFE8853B);
}

/// Concrete chip colors for each [StatusTone], per theme (spec §8: consistent
/// semantic mapping with adequate contrast in both themes).
class StatusChipColors {
  const StatusChipColors({required this.background, required this.foreground});

  final Color background;
  final Color foreground;
}

abstract final class StatusPalette {
  static const Map<StatusTone, StatusChipColors> light = {
    StatusTone.neutral: StatusChipColors(
      background: Color(0xFFE8ECF3),
      foreground: Color(0xFF39455A),
    ),
    StatusTone.info: StatusChipColors(
      background: Color(0xFFDCEAF7),
      foreground: Color(0xFF173D5C),
    ),
    StatusTone.progress: StatusChipColors(
      background: Color(0xFFE2E6F8),
      foreground: Color(0xFF2B3A67),
    ),
    StatusTone.warning: StatusChipColors(
      background: Color(0xFFFBEED3),
      foreground: Color(0xFF7A4E0E),
    ),
    StatusTone.success: StatusChipColors(
      background: Color(0xFFD9F0EC),
      foreground: Color(0xFF0E5B52),
    ),
    StatusTone.danger: StatusChipColors(
      background: Color(0xFFFBDEDC),
      foreground: Color(0xFF8C2B26),
    ),
  };

  static const Map<StatusTone, StatusChipColors> dark = {
    StatusTone.neutral: StatusChipColors(
      background: Color(0xFF2A3550),
      foreground: Color(0xFFC7D0E0),
    ),
    StatusTone.info: StatusChipColors(
      background: Color(0xFF1E3A5F),
      foreground: Color(0xFFA9CBF0),
    ),
    StatusTone.progress: StatusChipColors(
      background: Color(0xFF24305C),
      foreground: Color(0xFFB3BFF2),
    ),
    StatusTone.warning: StatusChipColors(
      background: Color(0xFF4A3A16),
      foreground: Color(0xFFF2CE8A),
    ),
    StatusTone.success: StatusChipColors(
      background: Color(0xFF12403B),
      foreground: Color(0xFF7FD8CC),
    ),
    StatusTone.danger: StatusChipColors(
      background: Color(0xFF4E2320),
      foreground: Color(0xFFF2A9A5),
    ),
  };

  static StatusChipColors forTone(StatusTone tone, Brightness brightness) =>
      (brightness == Brightness.dark ? dark : light)[tone]!;
}

abstract final class AppTheme {
  static const String fontFamily = 'Cairo';

  static ThemeData light() {
    final ColorScheme scheme = ColorScheme.fromSeed(
      seedColor: AppColors.teal,
      brightness: Brightness.light,
      primary: AppColors.teal,
      onPrimary: Colors.white,
      secondary: AppColors.deepBlue,
      surface: AppColors.lightSurface,
      error: AppColors.errorLight,
    );

    final ThemeData base = ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorScheme: scheme,
      fontFamily: fontFamily,
      scaffoldBackgroundColor: AppColors.lightBackground,
      cardColor: AppColors.lightSurface,
    );

    return _apply(base);
  }

  static ThemeData dark() {
    final ColorScheme scheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFF2FC4B4), // teal lightened for dark contrast
      brightness: Brightness.dark,
      primary: const Color(0xFF2FC4B4),
      onPrimary: AppColors.navy,
      secondary: const Color(0xFF7FB3E8),
      surface: AppColors.darkSurface,
      error: AppColors.errorDark,
    );

    final ThemeData base = ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: scheme,
      fontFamily: fontFamily,
      scaffoldBackgroundColor: AppColors.darkBackground,
      cardColor: AppColors.darkSurface,
    );

    return _apply(base);
  }

  static ThemeData _apply(ThemeData base) {
    final bool isDark = base.brightness == Brightness.dark;
    final Color outline = isDark
        ? AppColors.darkOutline
        : AppColors.lightOutline;

    return base
        .copyWith(
          appBarTheme: AppBarTheme(
            backgroundColor: isDark
                ? AppColors.darkSurface
                : Colors.transparent,
            foregroundColor: isDark ? AppColors.darkOnSurface : AppColors.navy,
            elevation: 0,
            scrolledUnderElevation: 0,
            centerTitle: false,
          ),
          navigationRailTheme: NavigationRailThemeData(
            backgroundColor:
                AppColors.navy, // deep navy for navigation (spec §3.1)
            indicatorColor: Colors.white.withValues(alpha: 0.16),
            labelType: NavigationRailLabelType.all,
            selectedIconTheme: const IconThemeData(color: Colors.white),
            unselectedIconTheme: IconThemeData(
              color: Colors.white.withValues(alpha: 0.72),
            ),
            selectedLabelTextStyle: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w600,
            ),
            unselectedLabelTextStyle: TextStyle(
              color: Colors.white.withValues(alpha: 0.78),
            ),
          ),
          cardTheme: CardThemeData(
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(color: outline.withValues(alpha: 0.6)),
            ),
            margin: EdgeInsets.zero,
          ),
          inputDecorationTheme: InputDecorationTheme(
            filled: true,
            fillColor: isDark
                ? Colors.white.withValues(alpha: 0.05)
                : Colors.white,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: outline),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: outline),
            ),
          ),
          chipTheme: base.chipTheme.copyWith(
            side: BorderSide.none,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(999),
            ),
          ),
          snackBarTheme: SnackBarThemeData(
            behavior: SnackBarBehavior.floating,
            backgroundColor: isDark ? AppColors.darkSurface : Colors.white,
          ),
          dividerColor: outline.withValues(alpha: 0.5),
          textTheme: base.textTheme.apply(bodyColor: null, displayColor: null),
        )
        .copyWith(
          // Expose muted text via a custom style for consistent secondary labels.
          listTileTheme: ListTileThemeData(
            iconColor: isDark ? AppColors.darkOnSurface : AppColors.navy,
          ),
        );
  }

  /// Secondary label color helper (kept out of raw widget code).
  static Color muted(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
      ? AppColors.darkMutedText
      : AppColors.lightMutedText;
}
