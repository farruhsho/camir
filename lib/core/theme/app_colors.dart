import 'package:flutter/material.dart';

/// Design tokens for the KO'Z SHIFO «Clinic OS» look (mirrors the product
/// prototype). One source of truth for colours, radii and gradients — the
/// theme ([KozTheme]) and the shared widgets ([koz_widgets.dart]) read these,
/// so the whole app recolours from here.
@immutable
class AppColors {
  const AppColors._();

  // Surfaces
  static const bg = Color(0xFFECF1EF);
  static const card = Color(0xFFFFFFFF);
  static const line = Color(0xFFE4EAE7);
  static const line2 = Color(0xFFEEF3F1);

  // Text
  static const ink = Color(0xFF12201E);
  static const sub = Color(0xFF5C6F6A);
  static const muted = Color(0xFF8C9C97);

  // Brand teal
  static const accent = Color(0xFF0F9D8F);
  static const tealDark = Color(0xFF0B7468);
  static const tealLight = Color(0xFF13B3A1);
  static const mint = Color(0xFF15C7B3);
  static const mintLight = Color(0xFF34D3BE);
  static const tealBg = Color(0xFFE8F6F3);

  // Status fg/bg pairs
  static const green = Color(0xFF1FA971);
  static const greenBg = Color(0xFFEAF7F0);
  static const amber = Color(0xFFE0962A);
  static const amberBg = Color(0xFFFFF4E2);
  static const red = Color(0xFFE0564F);
  static const redBg = Color(0xFFFDECEC);
  static const blue = Color(0xFF3E92CC);
  static const blueBg = Color(0xFFEAF2FA);

  // Dark mode surfaces/text — a calm, deep teal-tinted dark that pairs with the
  // always-dark sidebar (below). Additive: the light tokens above are unchanged,
  // so nothing that reads them in the light UI shifts. Only [KozTheme.dark()]
  // consumes these.
  static const darkBg = Color(0xFF0B1413); // scaffold canvas
  static const darkCard = Color(0xFF14201E); // primary surface / cards
  static const darkCard2 = Color(
    0xFF1B2926,
  ); // elevated surface / fields / hover
  static const darkLine = Color(0xFF243330); // hairline borders / dividers
  static const darkInk = Color(0xFFE9F1EE); // primary text
  static const darkSub = Color(0xFFA4B7B2); // secondary text
  static const darkMuted = Color(0xFF6F847F); // tertiary / disabled text
  static const darkRedBg = Color(0xFF3A1E1E); // error container on dark

  // Sidebar (always dark in both theme modes)
  static const sidebarTop = Color(0xFF0E332D);
  static const sidebarBottom = Color(0xFF0A2521);
  static const sidebarItem = Color(0xFF9FBDB7);
  static const sidebarItemActive = Color(0xFFEAFBF7);
  static const sidebarActiveBg = Color(0x2415C7B3);
  static const sidebarAccent = Color(0xFF15C7B3);
  static const sidebarSub = Color(0xFF5FA79D);
  static const onDark = Color(0xFFEAF6F3);

  // Radii
  static const double rCard = 18;
  static const double rField = 12;
  static const double rPill = 999;

  static const sidebarGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [sidebarTop, sidebarBottom],
  );
  static const primaryGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [tealLight, tealDark],
  );
  static const avatarGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [green, tealDark],
  );
}
