import 'package:flutter/material.dart';

/// DocMedRepo design system — Material 3 theme with light and dark variants.
///
/// Aesthetic direction: Clinical precision meets warmth.
/// Deep navy + clean white + teal accent — trustworthy, modern, calm.
class AppTheme {
  AppTheme._();

  // ── Brand colours ────────────────────────────────────────────────────────
  static const Color _primaryLight   = Color(0xFF0A4D8C); // deep navy
  static const Color _primaryDark    = Color(0xFF4FA3E0); // sky blue
  static const Color _secondary      = Color(0xFF0D9488); // teal
  static const Color _error          = Color(0xFFDC2626); // crisp red
  static const Color _warningAmber   = Color(0xFFF59E0B);
  static const Color _successGreen   = Color(0xFF16A34A);

  static const Color _surfaceLight   = Color(0xFFF8FAFC);
  static const Color _surfaceDark    = Color(0xFF0F172A);
  static const Color _cardLight      = Color(0xFFFFFFFF);
  static const Color _cardDark       = Color(0xFF1E293B);

  // ── Public accent tokens ─────────────────────────────────────────────────
  static const Color accent          = _secondary;
  static const Color warning         = _warningAmber;
  static const Color success         = _successGreen;
  static const Color errorColor      = _error;

  // ── Text theme ────────────────────────────────────────────────────────────
  static TextTheme _buildTextTheme(Color primary, Color secondary) {
    return TextTheme(
      displayLarge: TextStyle(
        fontFamily: 'Merriweather',
        fontSize: 32,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.5,
        color: primary,
      ),
      displayMedium: TextStyle(
        fontFamily: 'Merriweather',
        fontSize: 26,
        fontWeight: FontWeight.w700,
        color: primary,
      ),
      titleLarge: TextStyle(
        fontFamily: 'Merriweather',
        fontSize: 20,
        fontWeight: FontWeight.w600,
        color: primary,
      ),
      titleMedium: TextStyle(
        fontFamily: 'DMSans',
        fontSize: 16,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.1,
        color: primary,
      ),
      titleSmall: TextStyle(
        fontFamily: 'DMSans',
        fontSize: 14,
        fontWeight: FontWeight.w600,
        color: primary,
      ),
      bodyLarge: TextStyle(
        fontFamily: 'DMSans',
        fontSize: 16,
        fontWeight: FontWeight.w400,
        color: secondary,
      ),
      bodyMedium: TextStyle(
        fontFamily: 'DMSans',
        fontSize: 14,
        fontWeight: FontWeight.w400,
        color: secondary,
      ),
      bodySmall: TextStyle(
        fontFamily: 'DMSans',
        fontSize: 12,
        color: secondary.withValues(alpha: 0.7),
      ),
      labelLarge: TextStyle(
        fontFamily: 'DMSans',
        fontSize: 14,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.5,
        color: primary,
      ),
      labelSmall: TextStyle(
        fontFamily: 'DMSans',
        fontSize: 11,
        fontWeight: FontWeight.w500,
        letterSpacing: 0.8,
        color: secondary.withValues(alpha: 0.6),
      ),
    );
  }

  // ── Input decoration ──────────────────────────────────────────────────────
  static InputDecorationTheme _inputDecoration(
    ColorScheme scheme,
  ) {
    return InputDecorationTheme(
      filled: true,
      fillColor: scheme.surfaceContainerHighest.withValues(alpha: 0.4),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: scheme.outline.withValues(alpha: 0.3)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: scheme.outline.withValues(alpha: 0.3)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: scheme.primary, width: 2),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: scheme.error),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: scheme.error, width: 2),
      ),
      labelStyle: TextStyle(fontFamily: 'DMSans', fontSize: 14),
      hintStyle: TextStyle(
        fontFamily: 'DMSans',
        fontSize: 14,
        color: scheme.onSurface.withValues(alpha: 0.4),
      ),
    );
  }

  // ── Card theme ────────────────────────────────────────────────────────────
  static CardThemeData _cardTheme(Color surface) => CardThemeData(
        color: surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: Colors.grey.withValues(alpha: 0.12)),
        ),
        margin: const EdgeInsets.symmetric(vertical: 6),
      );

  // ── Elevated button ───────────────────────────────────────────────────────
  static ElevatedButtonThemeData _elevatedButton(ColorScheme scheme) =>
      ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: scheme.primary,
          foregroundColor: scheme.onPrimary,
          minimumSize: const Size.fromHeight(52),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          textStyle: const TextStyle(
            fontFamily: 'DMSans',
            fontSize: 15,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.3,
          ),
          elevation: 0,
        ),
      );

  // ── Outlined button ───────────────────────────────────────────────────────
  static OutlinedButtonThemeData _outlinedButton(ColorScheme scheme) =>
      OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: scheme.primary,
          minimumSize: const Size.fromHeight(52),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          side: BorderSide(color: scheme.primary, width: 1.5),
          textStyle: const TextStyle(
            fontFamily: 'DMSans',
            fontSize: 15,
            fontWeight: FontWeight.w600,
          ),
        ),
      );

  // ── App bar ───────────────────────────────────────────────────────────────
  static AppBarTheme _appBar(ColorScheme scheme) => AppBarTheme(
        backgroundColor: scheme.surface,
        foregroundColor: scheme.onSurface,
        elevation: 0,
        scrolledUnderElevation: 1,
        titleTextStyle: TextStyle(
          fontFamily: 'Merriweather',
          fontSize: 18,
          fontWeight: FontWeight.w700,
          color: scheme.onSurface,
        ),
      );

  // ── LIGHT THEME ───────────────────────────────────────────────────────────
  static ThemeData get light {
    final scheme = ColorScheme.fromSeed(
      seedColor: _primaryLight,
      brightness: Brightness.light,
      primary: _primaryLight,
      secondary: _secondary,
      error: _error,
      surface: _surfaceLight,
      background: _surfaceLight,
    ).copyWith(
      surfaceContainerHighest: const Color(0xFFE8F0F8),
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: _surfaceLight,
      textTheme: _buildTextTheme(
        const Color(0xFF0F172A),
        const Color(0xFF475569),
      ),
      inputDecorationTheme: _inputDecoration(scheme),
      cardTheme: _cardTheme(_cardLight),
      elevatedButtonTheme: _elevatedButton(scheme),
      outlinedButtonTheme: _outlinedButton(scheme),
      appBarTheme: _appBar(scheme),
      dividerTheme: const DividerThemeData(
        color: Color(0xFFE2E8F0),
        thickness: 1,
        space: 1,
      ),
      chipTheme: ChipThemeData(
        backgroundColor: const Color(0xFFE8F0F8),
        labelStyle: const TextStyle(fontFamily: 'DMSans', fontSize: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }

  // ── DARK THEME ────────────────────────────────────────────────────────────
  static ThemeData get dark {
    final scheme = ColorScheme.fromSeed(
      seedColor: _primaryDark,
      brightness: Brightness.dark,
      primary: _primaryDark,
      secondary: _secondary,
      error: _error,
      surface: _surfaceDark,
      background: _surfaceDark,
    ).copyWith(
      surfaceContainerHighest: const Color(0xFF1E293B),
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: _surfaceDark,
      textTheme: _buildTextTheme(
        const Color(0xFFF1F5F9),
        const Color(0xFF94A3B8),
      ),
      inputDecorationTheme: _inputDecoration(scheme),
      cardTheme: _cardTheme(_cardDark),
      elevatedButtonTheme: _elevatedButton(scheme),
      outlinedButtonTheme: _outlinedButton(scheme),
      appBarTheme: _appBar(scheme),
      dividerTheme: const DividerThemeData(
        color: Color(0xFF1E293B),
        thickness: 1,
        space: 1,
      ),
      chipTheme: ChipThemeData(
        backgroundColor: const Color(0xFF1E293B),
        labelStyle: const TextStyle(
          fontFamily: 'DMSans',
          fontSize: 12,
          color: Color(0xFF94A3B8),
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }
}
