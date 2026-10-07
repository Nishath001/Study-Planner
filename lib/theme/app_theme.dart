import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Design tokens for StudySync.
/// Brand: indigo → violet gradient, teal accent, soft neutral surfaces.
class AppColors {
  static const primary = Color(0xFF6366F1);
  static const primaryDeep = Color(0xFF4F46E5);
  static const violet = Color(0xFF8B5CF6);
  static const teal = Color(0xFF14B8A6);
  static const amber = Color(0xFFF59E0B);
  static const rose = Color(0xFFF43F5E);
  static const green = Color(0xFF22C55E);
  static const sky = Color(0xFF0EA5E9);

  static const brandGradient = LinearGradient(
    colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const aiGradient = LinearGradient(
    colors: [Color(0xFF4F46E5), Color(0xFF8B5CF6), Color(0xFFEC4899)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const focusGradient = LinearGradient(
    colors: [Color(0xFF0F766E), Color(0xFF14B8A6)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const subjectPalette = <Color>[
    Color(0xFF6366F1),
    Color(0xFF14B8A6),
    Color(0xFFF43F5E),
    Color(0xFFF59E0B),
    Color(0xFFEC4899),
    Color(0xFF0EA5E9),
    Color(0xFF22C55E),
    Color(0xFF8B5CF6),
  ];
}

/// Surface/text colours that change with brightness. Use `context.pal`.
class Palette {
  final Color bg, surface, surfaceAlt, border, text, textSoft, textMuted;
  final bool isDark;
  const Palette._(this.isDark, this.bg, this.surface, this.surfaceAlt,
      this.border, this.text, this.textSoft, this.textMuted);

  static const light = Palette._(
    false,
    Color(0xFFF5F6FB),
    Color(0xFFFFFFFF),
    Color(0xFFEEF0F8),
    Color(0xFFE4E7F1),
    Color(0xFF0F172A),
    Color(0xFF475569),
    Color(0xFF94A3B8),
  );

  static const dark = Palette._(
    true,
    Color(0xFF0A0C14),
    Color(0xFF141824),
    Color(0xFF1D2232),
    Color(0xFF262C3E),
    Color(0xFFF1F5F9),
    Color(0xFFA5B0C4),
    Color(0xFF64708A),
  );
}

extension PaletteX on BuildContext {
  Palette get pal =>
      Theme.of(this).brightness == Brightness.dark ? Palette.dark : Palette.light;
}

class AppTheme {
  // Sinhala glyphs are not in Plus Jakarta Sans, so fall back to Noto Sans Sinhala.
  static List<String> get _fallback =>
      [GoogleFonts.notoSansSinhala().fontFamily!];

  static TextStyle font({
    double size = 14,
    FontWeight weight = FontWeight.w500,
    Color? color,
    double? height,
    double? spacing,
  }) =>
      GoogleFonts.plusJakartaSans(
        fontSize: size,
        fontWeight: weight,
        color: color,
        height: height,
        letterSpacing: spacing,
      ).copyWith(fontFamilyFallback: _fallback);

  static ThemeData light() => _build(Palette.light, Brightness.light);
  static ThemeData dark() => _build(Palette.dark, Brightness.dark);

  static ThemeData _build(Palette p, Brightness b) {
    final base = GoogleFonts.plusJakartaSansTextTheme(
      b == Brightness.dark ? ThemeData.dark().textTheme : ThemeData.light().textTheme,
    ).apply(
      bodyColor: p.text,
      displayColor: p.text,
      fontFamilyFallback: _fallback,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: b,
      scaffoldBackgroundColor: p.bg,
      colorScheme: ColorScheme.fromSeed(
        seedColor: AppColors.primary,
        brightness: b,
        primary: AppColors.primary,
        secondary: AppColors.teal,
        surface: p.surface,
      ),
      textTheme: base,
      splashFactory: InkSparkle.splashFactory,
      appBarTheme: AppBarTheme(
        backgroundColor: p.bg,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: font(size: 20, weight: FontWeight.w800, color: p.text),
        iconTheme: IconThemeData(color: p.text),
      ),
      cardTheme: CardTheme(
        color: p.surface,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(22),
          side: BorderSide(color: p.border),
        ),
      ),
      dividerTheme: DividerThemeData(color: p.border, thickness: 1, space: 1),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          minimumSize: const Size(64, 54),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          textStyle: font(size: 15, weight: FontWeight.w700),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: p.text,
          minimumSize: const Size(64, 54),
          side: BorderSide(color: p.border, width: 1.4),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          textStyle: font(size: 15, weight: FontWeight.w700),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.primary,
          textStyle: font(size: 14, weight: FontWeight.w700),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: p.surfaceAlt,
        hintStyle: font(color: p.textMuted, size: 14),
        labelStyle: font(color: p.textSoft, size: 14),
        prefixIconColor: p.textMuted,
        suffixIconColor: p.textMuted,
        contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 17),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: p.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: AppColors.primary, width: 1.8),
        ),
      ),
      sliderTheme: SliderThemeData(
        trackHeight: 6,
        activeTrackColor: AppColors.primary,
        inactiveTrackColor: p.surfaceAlt,
        thumbColor: Colors.white,
        overlayColor: AppColors.primary.withOpacity(0.12),
        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 11, elevation: 3),
        valueIndicatorColor: AppColors.primary,
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.all(Colors.white),
        trackColor: WidgetStateProperty.resolveWith((s) =>
            s.contains(WidgetState.selected) ? AppColors.primary : p.surfaceAlt),
        trackOutlineColor: WidgetStateProperty.all(Colors.transparent),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: p.surface,
        surfaceTintColor: Colors.transparent,
        showDragHandle: true,
        dragHandleColor: p.border,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
      ),
      dialogTheme: DialogTheme(
        backgroundColor: p.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: p.isDark ? const Color(0xFF262C3E) : const Color(0xFF0F172A),
        contentTextStyle: font(color: Colors.white, size: 13, weight: FontWeight.w600),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: p.surfaceAlt,
        side: BorderSide.none,
        labelStyle: font(size: 12, weight: FontWeight.w600, color: p.textSoft),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      datePickerTheme: DatePickerThemeData(
        backgroundColor: p.surface,
        surfaceTintColor: Colors.transparent,
      ),
      timePickerTheme: TimePickerThemeData(
        backgroundColor: p.surface,
      ),
    );
  }
}
