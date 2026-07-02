import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

abstract final class AppTheme {
  static const _green     = Color(0xFF4CAF50);
  static const _greenDark = Color(0xFF388E3C);

  static ThemeData get dark => _build(
        brightness:     Brightness.dark,
        scaffoldBg:     const Color(0xFF0A0A0A),
        surface:        const Color(0xFF111111),
        surfaceVar:     const Color(0xFF1C1C1C),
        card:           const Color(0xFF161618),
        border:         const Color(0x1AFFFFFF),   // white 10%
        onSurface:      const Color(0xFFFFFFFF),
        onSurfaceDim:   const Color(0x99FFFFFF),   // white 60%
        onSurfaceFaint: const Color(0x3DFFFFFF),   // white 24%
        primary:        _green,
        primaryDark:    _greenDark,
      );

  static ThemeData get light => _build(
        brightness:     Brightness.light,
        scaffoldBg:     const Color(0xFFF2F2F7),   // iOS-style warm off-white
        surface:        const Color(0xFFFFFFFF),
        surfaceVar:     const Color(0xFFE8E8ED),   // slightly deeper for separation
        card:           const Color(0xFFFFFFFF),
        border:         const Color(0x1A000000),   // black 10%
        onSurface:      const Color(0xFF0A0A0A),
        onSurfaceDim:   const Color(0x99000000),   // black 60%
        onSurfaceFaint: const Color(0x4D000000),   // black 30%
        primary:        _green,
        primaryDark:    _greenDark,
      );

  static ThemeData _build({
    required Brightness brightness,
    required Color scaffoldBg,
    required Color surface,
    required Color surfaceVar,
    required Color card,
    required Color border,
    required Color onSurface,
    required Color onSurfaceDim,
    required Color onSurfaceFaint,
    required Color primary,
    required Color primaryDark,
  }) {
    final isDark = brightness == Brightness.dark;
    final base   = isDark ? ThemeData.dark() : ThemeData.light();

    return base.copyWith(
      useMaterial3:            true,
      brightness:              brightness,
      scaffoldBackgroundColor: scaffoldBg,

      colorScheme: ColorScheme(
        brightness:  brightness,
        primary:     primary,
        onPrimary:   Colors.white,
        secondary:   primaryDark,
        onSecondary: Colors.white,
        error:       const Color(0xFFFF3B30),
        onError:     Colors.white,
        surface:     surface,
        onSurface:   onSurface,
      ),

      textTheme: GoogleFonts.dmSansTextTheme(base.textTheme).copyWith(
        bodyLarge:   GoogleFonts.dmSans(color: onSurface,      fontSize: 15),
        bodyMedium:  GoogleFonts.dmSans(color: onSurfaceDim,   fontSize: 13),
        bodySmall:   GoogleFonts.dmSans(color: onSurfaceFaint, fontSize: 11),
        labelLarge:  GoogleFonts.dmSans(
            color: onSurface, fontSize: 14, fontWeight: FontWeight.w600),
        titleMedium: GoogleFonts.dmSans(
            color: onSurface, fontSize: 17, fontWeight: FontWeight.w700),
      ),

      cardTheme: CardThemeData(
        color:     card,
        elevation: isDark ? 0 : 1,
        shadowColor: Colors.black.withValues(alpha: 0.06),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side:         BorderSide(color: border),
        ),
      ),

      dividerTheme: DividerThemeData(color: border, thickness: 1),

      inputDecorationTheme: InputDecorationTheme(
        filled:    false,
        fillColor: surfaceVar,
        
        border:   InputBorder.none,
        enabledBorder: InputBorder.none,
        focusedBorder: InputBorder.none,
        errorBorder:   InputBorder.none,
        focusedErrorBorder: InputBorder.none, 
        disabledBorder:     InputBorder.none,
        hintStyle: TextStyle(color: onSurfaceFaint),
      ),

      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: surface,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
      ),

      popupMenuTheme: PopupMenuThemeData(
        color:     surface,
        elevation: isDark ? 8 : 4,
        shadowColor: Colors.black.withValues(alpha: isDark ? 0.5 : 0.12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side:         BorderSide(color: border),
        ),
      ),

      extensions: [
        FocusBellColors(
          scaffoldBg:     scaffoldBg,
          surface:        surface,
          surfaceVar:     surfaceVar,
          card:           card,
          border:         border,
          onSurface:      onSurface,
          onSurfaceDim:   onSurfaceDim,
          onSurfaceFaint: onSurfaceFaint,
          primary:        primary,
          isDark:         isDark,
        ),
      ],
    );
  }
}

// ── FocusBellColors ────────────────────────────────────────────────

class FocusBellColors extends ThemeExtension<FocusBellColors> {
  final Color scaffoldBg;
  final Color surface;
  final Color surfaceVar;
  final Color card;
  final Color border;
  final Color onSurface;
  final Color onSurfaceDim;
  final Color onSurfaceFaint;
  final Color primary;
  final bool  isDark;

  const FocusBellColors({
    required this.scaffoldBg,
    required this.surface,
    required this.surfaceVar,
    required this.card,
    required this.border,
    required this.onSurface,
    required this.onSurfaceDim,
    required this.onSurfaceFaint,
    required this.primary,
    required this.isDark,
  });

  @override
  FocusBellColors copyWith({
    Color? scaffoldBg, Color? surface, Color? surfaceVar,
    Color? card, Color? border, Color? onSurface,
    Color? onSurfaceDim, Color? onSurfaceFaint, Color? primary,
    bool? isDark,
  }) =>
      FocusBellColors(
        scaffoldBg:     scaffoldBg     ?? this.scaffoldBg,
        surface:        surface        ?? this.surface,
        surfaceVar:     surfaceVar     ?? this.surfaceVar,
        card:           card           ?? this.card,
        border:         border         ?? this.border,
        onSurface:      onSurface      ?? this.onSurface,
        onSurfaceDim:   onSurfaceDim   ?? this.onSurfaceDim,
        onSurfaceFaint: onSurfaceFaint ?? this.onSurfaceFaint,
        primary:        primary        ?? this.primary,
        isDark:         isDark         ?? this.isDark,
      );

  @override
  FocusBellColors lerp(FocusBellColors? other, double t) {
    if (other == null) return this;
    return FocusBellColors(
      scaffoldBg:     Color.lerp(scaffoldBg,     other.scaffoldBg,     t)!,
      surface:        Color.lerp(surface,        other.surface,        t)!,
      surfaceVar:     Color.lerp(surfaceVar,      other.surfaceVar,     t)!,
      card:           Color.lerp(card,           other.card,           t)!,
      border:         Color.lerp(border,         other.border,         t)!,
      onSurface:      Color.lerp(onSurface,      other.onSurface,      t)!,
      onSurfaceDim:   Color.lerp(onSurfaceDim,   other.onSurfaceDim,   t)!,
      onSurfaceFaint: Color.lerp(onSurfaceFaint, other.onSurfaceFaint, t)!,
      primary:        Color.lerp(primary,        other.primary,        t)!,
      isDark:         t < 0.5 ? isDark : (other.isDark),
    );
  }
}

extension ThemeFB on ThemeData {
  FocusBellColors get fb => extension<FocusBellColors>()!;
}