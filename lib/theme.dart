import 'package:flutter/material.dart';

/// Taken from the logo: beans arranged as a compass rose on a warm tan ground.
const kTan = Color(0xFFDDBC8E);
const kMidBrown = Color(0xFF9A6B4A);
const kDarkBrown = Color(0xFF5A3825);
const kBean = Color(0xFF2E1A0F);

ThemeData kopiTheme(Brightness brightness) {
  final isLight = brightness == Brightness.light;
  final scheme =
      ColorScheme.fromSeed(
        seedColor: kDarkBrown,
        brightness: brightness,
      ).copyWith(
        primary: isLight ? kDarkBrown : kTan,
        secondary: kMidBrown,
        surface: isLight ? const Color(0xFFFBF3E8) : kBean,
      );

  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
    scaffoldBackgroundColor: scheme.surface,
  );
}

/// The muted ink the Phase 3 full log reads in.
///
/// It lives in the theme rather than in that screen so the archive treatment
/// is a property of the design rather than of one widget that could drift
/// away from it.
Color kopiArchiveColor(Brightness brightness) => brightness == Brightness.light
    ? kMidBrown.withValues(alpha: 0.75)
    : kTan.withValues(alpha: 0.55);
