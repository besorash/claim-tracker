/// Design tokens and Light/Dark themes — "Aurora" redesign.
///
/// Palette: electric indigo → violet brand gradient, a fresh mint accent and
/// soft lavender-tinted neutrals. Widgets read colors through these semantic
/// tokens (never raw hex in feature code).
library;

import 'package:flutter/material.dart';

import '../models/claim_status.dart';

abstract final class AppColors {
  // Brand palette.
  static const Color indigo = Color(0xFF4F46E5);
  static const Color violet = Color(0xFF7C3AED);
  static const Color magenta = Color(0xFFC026D3);
  static const Color mint = Color(0xFF10B981);
  static const Color sky = Color(0xFF0EA5E9);
  static const Color amber = Color(0xFFF59E0B);
  static const Color rose = Color(0xFFF43F5E);

  // Legacy names kept so existing call sites stay valid.
  static const Color navy = Color(0xFF1E1B4B);
  static const Color deepBlue = indigo;
  static const Color teal = mint;

  // Light theme neutrals.
  static const Color lightBackground = Color(0xFFF5F5FC);
  static const Color lightSurface = Color(0xFFFFFFFF);
  static const Color lightOnSurface = Color(0xFF1A1736);
  static const Color lightMutedText = Color(0xFF6B6888);
  static const Color lightOutline = Color(0xFFE4E2F3);

  // Dark theme neutrals.
  static const Color darkBackground = Color(0xFF0D0B1E);
  static const Color darkSurface = Color(0xFF18152F);
  static const Color darkOnSurface = Color(0xFFEDEBFF);
  static const Color darkMutedText = Color(0xFFA6A2C8);
  static const Color darkOutline = Color(0xFF2E2A52);

  // Shared semantic colors.
  static const Color errorLight = Color(0xFFDC2626);
  static const Color errorDark = Color(0xFFFCA5A5);

  // Notes highlight (claim details screen): must stand out from every other
  // section, keeping ≥6.7:1 text contrast against its fill in both themes.
  static const Color lightNotesFill = Color(0xFFFFE8C7);
  static const Color lightNotesText = Color(0xFF7A3B08);
  static const Color lightNotesBorder = Color(0xFFF59E0B);

  static const Color darkNotesFill = Color(0xFF3F2A12);
  static const Color darkNotesText = Color(0xFFFFC37A);
  static const Color darkNotesBorder = Color(0xFFE8953B);
}

/// Brand gradients used by heroes, tiles and the primary button.
abstract final class AppGradients {
  static const LinearGradient brand = LinearGradient(
    begin: AlignmentDirectional.topStart,
    end: AlignmentDirectional.bottomEnd,
    colors: <Color>[Color(0xFF4338CA), Color(0xFF6D28D9), Color(0xFFA21CAF)],
  );

  static LinearGradient tile(Color c) => LinearGradient(
    begin: AlignmentDirectional.topStart,
    end: AlignmentDirectional.bottomEnd,
    colors: <Color>[c, Color.lerp(c, Colors.black, 0.18)!],
  );
}

/// Concrete chip colors for each [StatusTone], per theme.
class StatusChipColors {
  const StatusChipColors({required this.background, required this.foreground});

  final Color background;
  final Color foreground;
}

abstract final class StatusPalette {
  static const Map<StatusTone, StatusChipColors> light = {
    StatusTone.neutral: StatusChipColors(
      background: Color(0xFFECEBF5),
      foreground: Color(0xFF45415F),
    ),
    StatusTone.info: StatusChipColors(
      background: Color(0xFFDDF0FD),
      foreground: Color(0xFF075985),
    ),
    StatusTone.progress: StatusChipColors(
      background: Color(0xFFE7E5FF),
      foreground: Color(0xFF3730A3),
    ),
    StatusTone.warning: StatusChipColors(
      background: Color(0xFFFEF0C7),
      foreground: Color(0xFF854D0E),
    ),
    StatusTone.success: StatusChipColors(
      background: Color(0xFFD5F5E8),
      foreground: Color(0xFF065F46),
    ),
    StatusTone.danger: StatusChipColors(
      background: Color(0xFFFFE1E5),
      foreground: Color(0xFF9F1239),
    ),
  };

  static const Map<StatusTone, StatusChipColors> dark = {
    StatusTone.neutral: StatusChipColors(
      background: Color(0xFF2B2846),
      foreground: Color(0xFFD3D0EA),
    ),
    StatusTone.info: StatusChipColors(
      background: Color(0xFF0C3550),
      foreground: Color(0xFF9DD8FB),
    ),
    StatusTone.progress: StatusChipColors(
      background: Color(0xFF2A2766),
      foreground: Color(0xFFC1BDFF),
    ),
    StatusTone.warning: StatusChipColors(
      background: Color(0xFF443312),
      foreground: Color(0xFFFCD98A),
    ),
    StatusTone.success: StatusChipColors(
      background: Color(0xFF0D3B2E),
      foreground: Color(0xFF7EE2BC),
    ),
    StatusTone.danger: StatusChipColors(
      background: Color(0xFF4A1A26),
      foreground: Color(0xFFFDA4B4),
    ),
  };

  static StatusChipColors forTone(StatusTone tone, Brightness brightness) =>
      (brightness == Brightness.dark ? dark : light)[tone]!;

  /// Solid accent per tone (card side stripe, timeline dot).
  static Color accent(StatusTone tone) => switch (tone) {
    StatusTone.neutral => const Color(0xFF8B87A8),
    StatusTone.info => AppColors.sky,
    StatusTone.progress => AppColors.indigo,
    StatusTone.warning => AppColors.amber,
    StatusTone.success => AppColors.mint,
    StatusTone.danger => AppColors.rose,
  };

  /// Icon per tone, so status is never shown by color alone.
  static IconData icon(StatusTone tone) => switch (tone) {
    StatusTone.neutral => Icons.fiber_new_rounded,
    StatusTone.info => Icons.send_rounded,
    StatusTone.progress => Icons.autorenew_rounded,
    StatusTone.warning => Icons.hourglass_top_rounded,
    StatusTone.success => Icons.verified_rounded,
    StatusTone.danger => Icons.cancel_rounded,
  };
}

abstract final class AppTheme {
  static const String fontFamily = 'Cairo';

  static ThemeData light() {
    final ColorScheme scheme = ColorScheme.fromSeed(
      seedColor: AppColors.indigo,
      brightness: Brightness.light,
      primary: AppColors.indigo,
      onPrimary: Colors.white,
      secondary: AppColors.violet,
      tertiary: AppColors.mint,
      surface: AppColors.lightSurface,
      onSurface: AppColors.lightOnSurface,
      error: AppColors.errorLight,
    );
    return _apply(
      ThemeData(
        useMaterial3: true,
        brightness: Brightness.light,
        colorScheme: scheme,
        fontFamily: fontFamily,
        scaffoldBackgroundColor: AppColors.lightBackground,
        cardColor: AppColors.lightSurface,
      ),
    );
  }

  static ThemeData dark() {
    final ColorScheme scheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFF8B80FF),
      brightness: Brightness.dark,
      primary: const Color(0xFF9C93FF),
      onPrimary: const Color(0xFF15112E),
      secondary: const Color(0xFFC4A5FF),
      tertiary: const Color(0xFF5EEAB4),
      surface: AppColors.darkSurface,
      onSurface: AppColors.darkOnSurface,
      error: AppColors.errorDark,
    );
    return _apply(
      ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorScheme: scheme,
        fontFamily: fontFamily,
        scaffoldBackgroundColor: AppColors.darkBackground,
        cardColor: AppColors.darkSurface,
      ),
    );
  }

  static ThemeData _apply(ThemeData base) {
    final bool isDark = base.brightness == Brightness.dark;
    final ColorScheme cs = base.colorScheme;
    final Color outline = isDark
        ? AppColors.darkOutline
        : AppColors.lightOutline;
    final Color onSurface = isDark
        ? AppColors.darkOnSurface
        : AppColors.lightOnSurface;
    final Color muted = isDark
        ? AppColors.darkMutedText
        : AppColors.lightMutedText;
    final RoundedRectangleBorder pill = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(16),
    );

    return base.copyWith(
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        foregroundColor: onSurface,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          fontFamily: fontFamily,
          fontSize: 22,
          fontWeight: FontWeight.w800,
          color: onSurface,
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: 72,
        elevation: 0,
        backgroundColor: isDark ? AppColors.darkSurface : Colors.white,
        surfaceTintColor: Colors.transparent,
        indicatorColor: cs.primary.withValues(alpha: isDark ? 0.24 : 0.12),
        indicatorShape: pill,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        iconTheme: WidgetStateProperty.resolveWith(
          (Set<WidgetState> s) => IconThemeData(
            size: 26,
            color: s.contains(WidgetState.selected) ? cs.primary : muted,
          ),
        ),
        labelTextStyle: WidgetStateProperty.resolveWith(
          (Set<WidgetState> s) => TextStyle(
            fontFamily: fontFamily,
            fontSize: 12.5,
            fontWeight: s.contains(WidgetState.selected)
                ? FontWeight.w800
                : FontWeight.w600,
            color: s.contains(WidgetState.selected) ? cs.primary : muted,
          ),
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: isDark ? AppColors.darkSurface : Colors.white,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(22),
          side: BorderSide(
            color: outline.withValues(alpha: isDark ? 0.9 : 0.7),
          ),
        ),
        margin: EdgeInsets.zero,
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: cs.primary,
        foregroundColor: cs.onPrimary,
        elevation: 6,
        highlightElevation: 10,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        extendedTextStyle: const TextStyle(
          fontFamily: fontFamily,
          fontWeight: FontWeight.w800,
          fontSize: 15,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(48, 52),
          shape: pill,
          textStyle: const TextStyle(
            fontFamily: fontFamily,
            fontWeight: FontWeight.w700,
            fontSize: 15,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(48, 48),
          shape: pill,
          side: BorderSide(color: outline, width: 1.4),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          shape: pill,
          textStyle: const TextStyle(
            fontFamily: fontFamily,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.white,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 16,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: outline),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: outline),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: cs.primary, width: 2),
        ),
        prefixIconColor: cs.primary,
      ),
      chipTheme: base.chipTheme.copyWith(
        side: BorderSide(color: outline),
        backgroundColor: isDark ? AppColors.darkSurface : Colors.white,
        selectedColor: cs.primary,
        checkmarkColor: cs.onPrimary,
        labelStyle: TextStyle(
          fontFamily: fontFamily,
          fontWeight: FontWeight.w600,
          color: onSurface,
        ),
        secondaryLabelStyle: TextStyle(
          fontFamily: fontFamily,
          fontWeight: FontWeight.w700,
          color: cs.onPrimary,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: isDark ? AppColors.darkSurface : Colors.white,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: isDark ? AppColors.darkSurface : Colors.white,
        surfaceTintColor: Colors.transparent,
        showDragHandle: true,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: isDark ? AppColors.darkSurface : Colors.white,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: isDark ? const Color(0xFF2A2650) : AppColors.navy,
        contentTextStyle: const TextStyle(
          fontFamily: fontFamily,
          color: Colors.white,
          fontWeight: FontWeight.w600,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      dividerColor: outline,
      dividerTheme: DividerThemeData(color: outline, thickness: 1),
      listTileTheme: ListTileThemeData(
        iconColor: cs.primary,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    );
  }

  /// Secondary label color helper (kept out of raw widget code).
  static Color muted(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
      ? AppColors.darkMutedText
      : AppColors.lightMutedText;

  /// Soft drop shadow for floating surfaces (hero cards, tiles).
  static List<BoxShadow> softShadow(Color c) => <BoxShadow>[
    BoxShadow(
      color: c.withValues(alpha: 0.28),
      blurRadius: 24,
      offset: const Offset(0, 10),
    ),
  ];
}
