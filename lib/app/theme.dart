import 'package:flutter/material.dart';

import '../core/theme/app_colors.dart';
import '../core/theme/app_typography.dart';

/// «Clinic OS» theme — explicit, token-driven [ColorScheme]s (no `fromSeed`) so
/// the whole app matches the prototype: teal brand #0F9D8F, cards radius 18,
/// Manrope/Golos type. Two genuine variants share one builder:
///
/// * [light] — light canvas #ECF1EF, white cards, ink text.
/// * [dark]  — calm deep-teal-tinted dark canvas, dark surfaces, light text,
///   the same teal accent. `themeMode.system` therefore renders a real dark UI.
///
/// The dark-teal sidebar is painted by the shell directly (always dark in both
/// modes), so the dark theme stays visually consistent with it. All surface and
/// text colours come from [AppColors]; recolouring happens here in one place.
class KozTheme {
  static ThemeData light() => _build(Brightness.light);
  static ThemeData dark() => _build(Brightness.dark);

  static const ColorScheme _light = ColorScheme.light(
    primary: AppColors.accent,
    onPrimary: Colors.white,
    primaryContainer: AppColors.tealBg,
    onPrimaryContainer: AppColors.tealDark,
    secondary: AppColors.mint,
    onSecondary: Colors.white,
    secondaryContainer: AppColors.tealBg,
    onSecondaryContainer: AppColors.tealDark,
    surface: AppColors.card,
    onSurface: AppColors.ink,
    surfaceContainerHighest: AppColors.line2,
    surfaceContainerHigh: AppColors.line2,
    onSurfaceVariant: AppColors.sub,
    outline: AppColors.muted,
    outlineVariant: AppColors.line,
    error: AppColors.red,
    onError: Colors.white,
    errorContainer: AppColors.redBg,
    onErrorContainer: AppColors.red,
  );

  static const ColorScheme _dark = ColorScheme.dark(
    primary: AppColors.accent,
    onPrimary: Colors.white,
    primaryContainer: AppColors.tealDark,
    onPrimaryContainer: AppColors.onDark,
    secondary: AppColors.mint,
    onSecondary: AppColors.sidebarBottom,
    secondaryContainer: AppColors.tealDark,
    onSecondaryContainer: AppColors.onDark,
    surface: AppColors.darkCard,
    onSurface: AppColors.darkInk,
    surfaceContainerHighest: AppColors.darkCard2,
    surfaceContainerHigh: AppColors.darkCard2,
    onSurfaceVariant: AppColors.darkSub,
    outline: AppColors.darkMuted,
    outlineVariant: AppColors.darkLine,
    error: AppColors.red,
    onError: Colors.white,
    errorContainer: AppColors.darkRedBg,
    onErrorContainer: AppColors.red,
  );

  static ThemeData _build(Brightness brightness) {
    final dark = brightness == Brightness.dark;
    final scheme = dark ? _dark : _light;

    // Per-mode surface/text tokens (light values reproduce the original theme
    // exactly; dark values come from the additive AppColors.dark* tokens).
    final canvas = dark ? AppColors.darkBg : AppColors.bg;
    final surface = dark ? AppColors.darkCard : AppColors.card;
    final field = dark ? AppColors.darkCard2 : AppColors.card;
    final line = dark ? AppColors.darkLine : AppColors.line;
    final ink = dark ? AppColors.darkInk : AppColors.ink;
    final sub = dark ? AppColors.darkSub : AppColors.sub;
    // Teal chip pair: subtle teal on dark, brand tint on light.
    final chipBg = dark ? AppColors.darkCard2 : AppColors.tealBg;
    final chipFg = dark ? AppColors.mintLight : AppColors.tealDark;

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: canvas,
      textTheme: dark
          ? AppTypography.textTheme(
              ink: AppColors.darkInk,
              sub: AppColors.darkSub,
              muted: AppColors.darkMuted,
            )
          : AppTypography.textTheme(),
      appBarTheme: AppBarTheme(
        backgroundColor: canvas,
        foregroundColor: ink,
        centerTitle: false,
        elevation: 0,
        scrolledUnderElevation: 0,
        titleTextStyle: TextStyle(
          fontFamily: 'Manrope',
          color: ink,
          fontWeight: FontWeight.w800,
          fontSize: 19,
        ),
      ),
      cardTheme: CardThemeData(
        color: surface,
        elevation: 0,
        clipBehavior: Clip.antiAlias,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppColors.rCard),
          side: BorderSide(color: line),
        ),
      ),
      dividerTheme: DividerThemeData(color: line, thickness: 1, space: 1),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: field,
        isDense: true,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppColors.rField),
          borderSide: BorderSide(color: line),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppColors.rField),
          borderSide: BorderSide(color: line),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppColors.rField),
          borderSide: const BorderSide(color: AppColors.accent, width: 1.6),
        ),
      ),
      chipTheme: ChipThemeData(
        shape: const StadiumBorder(),
        side: BorderSide.none,
        backgroundColor: chipBg,
        selectedColor: AppColors.accent,
        labelStyle: TextStyle(color: chipFg, fontWeight: FontWeight.w600),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          // Height-only minimum. `Size.fromHeight` sets width=infinity, which
          // throws "BoxConstraints forces an infinite width" for any button
          // placed in a Row (loose width). Full-width buttons get their width
          // from a tight parent (stretch Column / SizedBox), not from here.
          minimumSize: const Size(0, 48),
          backgroundColor: AppColors.accent,
          foregroundColor: Colors.white,
          textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppColors.rField),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          // Height-only minimum (see filledButtonTheme above): avoid infinite
          // width when an outlined button sits in a Row.
          minimumSize: const Size(0, 46),
          foregroundColor: sub,
          side: BorderSide(color: line),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppColors.rField),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: dark ? AppColors.mintLight : AppColors.tealDark,
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: dark ? AppColors.darkCard2 : AppColors.sidebarTop,
        contentTextStyle: TextStyle(
          color: dark ? AppColors.darkInk : AppColors.onDark,
        ),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}
