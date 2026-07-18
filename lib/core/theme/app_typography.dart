import 'package:flutter/material.dart';

import 'app_colors.dart';

/// Typography for the «Clinic OS» look: **Manrope** for headings & numbers,
/// **Golos Text** for body & labels (bundled .ttf assets — see pubspec.yaml).
class AppTypography {
  const AppTypography._();

  static const String manrope = 'Manrope';
  static const String golos = 'Golos Text';

  /// Colours default to the light palette, so existing callers are unchanged.
  /// [KozTheme.dark()] passes the dark palette here to recolour every text
  /// role in one place (headings/body → [ink], secondary → [sub], tertiary →
  /// [muted]).
  static TextTheme textTheme({
    Color ink = AppColors.ink,
    Color sub = AppColors.sub,
    Color muted = AppColors.muted,
  }) {
    TextStyle h(double size, FontWeight w) => TextStyle(
      fontFamily: manrope,
      fontSize: size,
      fontWeight: w,
      color: ink,
      letterSpacing: -0.3,
      height: 1.2,
    );
    TextStyle b(double size, {Color? color, FontWeight w = FontWeight.w400}) =>
        TextStyle(
          fontFamily: golos,
          fontSize: size,
          fontWeight: w,
          color: color ?? ink,
        );
    return TextTheme(
      displayLarge: h(48, FontWeight.w800),
      displayMedium: h(40, FontWeight.w800),
      displaySmall: h(32, FontWeight.w800),
      headlineLarge: h(30, FontWeight.w800),
      headlineMedium: h(26, FontWeight.w800),
      headlineSmall: h(22, FontWeight.w700),
      titleLarge: h(20, FontWeight.w800),
      titleMedium: h(16, FontWeight.w700),
      titleSmall: b(14, w: FontWeight.w600),
      bodyLarge: b(16),
      bodyMedium: b(14, color: sub),
      bodySmall: b(12.5, color: muted),
      labelLarge: b(14, w: FontWeight.w600),
      labelMedium: b(12.5, color: sub),
      labelSmall: b(11.5, color: muted),
    );
  }

  /// Tabular Manrope figure — for KPI numbers, money, ticket numbers.
  static TextStyle number(
    double size, {
    FontWeight weight = FontWeight.w800,
    Color color = AppColors.ink,
  }) => TextStyle(
    fontFamily: manrope,
    fontSize: size,
    fontWeight: weight,
    color: color,
    letterSpacing: -0.5,
    fontFeatures: const [FontFeature.tabularFigures()],
  );
}
