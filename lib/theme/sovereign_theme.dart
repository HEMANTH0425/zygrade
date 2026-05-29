// lib/theme/sovereign_theme.dart
// Glassmorphic dark theme matching the Zygarde WebUI aesthetic.

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class SovereignTheme {
  // ── Color palette ──────────────────────────────────────────────────────────
  static const Color bgDeep      = Color(0xFF07071A);
  static const Color bgDeepGhost = Color(0xFF000000); // True Black
  static const Color bgLayer     = Color(0xFF0D0D2B);
  
  static bool isGhostMode = false;

  static Color get currentBg => isGhostMode ? bgDeepGhost : bgDeep;

  static const Color accentViolet= Color(0xFF7C3AED);
  static const Color accentCyan  = Color(0xFF06B6D4);
  static const Color glassWhite  = Color(0x0DFFFFFF);   // 5% white
  static const Color glassBorder = Color(0x1AFFFFFF);   // 10% white
  static const Color textPrimary = Color(0xFFE2E8F0);
  static const Color textMuted   = Color(0xFF94A3B8);
  static const Color success     = Color(0xFF22C55E);
  static const Color danger      = Color(0xFFEF4444);

  // ── Gradient ───────────────────────────────────────────────────────────────
  static LinearGradient get bgGradient => LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [currentBg, isGhostMode ? Colors.black : const Color(0xFF0F0527), currentBg],
  );

  static const LinearGradient accentGradient = LinearGradient(
    colors: [accentViolet, Color(0xFF4F46E5)],
  );

  // ── ThemeData ──────────────────────────────────────────────────────────────
  static ThemeData get theme => ThemeData(
    brightness: Brightness.dark,
    scaffoldBackgroundColor: currentBg,
    colorScheme: const ColorScheme.dark(
      primary     : accentViolet,
      secondary   : accentCyan,
      surface     : bgLayer,
      onPrimary   : Colors.white,
      onSurface   : textPrimary,
    ),
    textTheme: GoogleFonts.spaceGroteskTextTheme(
      ThemeData.dark().textTheme.copyWith(
        displayLarge: const TextStyle(color: textPrimary, fontWeight: FontWeight.w700),
        bodyMedium  : const TextStyle(color: textPrimary),
        bodySmall   : const TextStyle(color: textMuted),
      ),
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: Colors.transparent,
      elevation      : 0,
      centerTitle    : true,
      titleTextStyle : GoogleFonts.rajdhani(
        fontSize: 20,
        fontWeight: FontWeight.w600,
        color: textPrimary,
        letterSpacing: 1.5,
      ),
      iconTheme: const IconThemeData(color: textPrimary),
    ),
    tabBarTheme: TabBarThemeData(
      labelColor        : Colors.white,
      unselectedLabelColor: textMuted,
      indicator: const UnderlineTabIndicator(
        borderSide: BorderSide(color: accentViolet, width: 3),
      ),
      labelStyle: GoogleFonts.rajdhani(
        fontSize: 14, fontWeight: FontWeight.w600, letterSpacing: 1.2,
      ),
    ),
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: accentViolet,
      foregroundColor: Colors.white,
      elevation: 0,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled     : true,
      fillColor  : glassWhite,
      border     : OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide  : const BorderSide(color: glassBorder),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide  : const BorderSide(color: glassBorder),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide  : const BorderSide(color: accentViolet, width: 2),
      ),
      labelStyle: const TextStyle(color: textMuted, fontSize: 12),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    ),
    dividerColor: glassBorder,
  );
}

// ── Reusable glass card ────────────────────────────────────────────────────────
class GlassCard extends StatelessWidget {
  const GlassCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.borderRadius = 16,
  });

  final Widget child;
  final EdgeInsets padding;
  final double borderRadius;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: SovereignTheme.glassWhite,
        borderRadius: BorderRadius.circular(borderRadius),
        border: Border.all(color: SovereignTheme.glassBorder),
        boxShadow: [
          BoxShadow(
            color: SovereignTheme.accentViolet.withOpacity(0.08),
            blurRadius: 20,
            spreadRadius: 2,
          ),
        ],
      ),
      child: Padding(padding: padding, child: child),
    );
  }
}

// ── Gradient text ──────────────────────────────────────────────────────────────
class GradientText extends StatelessWidget {
  const GradientText(this.text, {super.key, this.style});
  final String text;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    return ShaderMask(
      shaderCallback: (bounds) =>
          SovereignTheme.accentGradient.createShader(bounds),
      child: Text(text, style: (style ?? const TextStyle()).copyWith(color: Colors.white)),
    );
  }
}
