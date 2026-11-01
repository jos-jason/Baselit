// Visual style matched to the iOS app: grouped gray background, white rounded
// cards, soft gray icon tiles, monochrome accent (black in light, white in dark),
// and a floating pill tab bar.

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Corner radii and sizes taken from the iOS app.
class Radii {
  static const card = 26.0; // inset grouped list sections
  static const tile = 8.0; // icon tiles and photo thumbnails
  static const smallTile = 6.0;
  static const tabBar = 34.0;
}

class Sizes {
  static const tile = 44.0;
  static const roundButton = 44.0;
  static const pagePadding = 16.0;
}

/// iOS system colors, light and dark.
class BaselitColors extends ThemeExtension<BaselitColors> {
  const BaselitColors({
    required this.background,
    required this.card,
    required this.label,
    required this.secondaryLabel,
    required this.tertiaryLabel,
    required this.separator,
    required this.fill,
    required this.tabHighlight,
    required this.destructive,
  });

  final Color background;
  final Color card;
  final Color label;
  final Color secondaryLabel;
  final Color tertiaryLabel;
  final Color separator;
  final Color fill;
  final Color tabHighlight;
  final Color destructive;

  static const light = BaselitColors(
    background: Color(0xFFF2F2F7),
    card: Color(0xFFFFFFFF),
    label: Color(0xFF000000),
    secondaryLabel: Color(0x993C3C43),
    tertiaryLabel: Color(0x4D3C3C43),
    separator: Color(0x4A3C3C43),
    fill: Color(0x14747480),
    tabHighlight: Color(0xFFE6E6EB),
    destructive: Color(0xFFFF3B30),
  );

  static const dark = BaselitColors(
    background: Color(0xFF000000),
    card: Color(0xFF1C1C1E),
    label: Color(0xFFFFFFFF),
    secondaryLabel: Color(0x99EBEBF5),
    tertiaryLabel: Color(0x4DEBEBF5),
    separator: Color(0x99545458),
    fill: Color(0x2E767680),
    tabHighlight: Color(0xFF3A3A3C),
    destructive: Color(0xFFFF453A),
  );

  @override
  BaselitColors copyWith() => this;

  @override
  BaselitColors lerp(BaselitColors? other, double t) => t < 0.5 ? this : (other ?? this);
}

extension BaselitTheme on BuildContext {
  BaselitColors get colors => Theme.of(this).extension<BaselitColors>()!;
}

/// [fontFamily] replaces Inter, for rendering previews in tests without network.
ThemeData buildTheme(Brightness brightness, {String? fontFamily}) {
  final colors = brightness == Brightness.light ? BaselitColors.light : BaselitColors.dark;
  final base = ThemeData(brightness: brightness, fontFamily: fontFamily).textTheme;
  // Inter is the closest freely licensed match to Apple's SF Pro.
  final text = (fontFamily == null ? GoogleFonts.interTextTheme(base) : base)
      .apply(bodyColor: colors.label, displayColor: colors.label, fontFamily: fontFamily);

  return ThemeData(
    brightness: brightness,
    useMaterial3: true,
    scaffoldBackgroundColor: colors.background,
    colorScheme: ColorScheme.fromSeed(
      seedColor: colors.label,
      brightness: brightness,
      primary: colors.label,
      onPrimary: colors.card,
      surface: colors.card,
      error: colors.destructive,
    ),
    textTheme: text,
    splashFactory: NoSplash.splashFactory,
    highlightColor: colors.fill,
    dividerColor: colors.separator,
    extensions: [colors],
    pageTransitionsTheme: const PageTransitionsTheme(builders: {
      TargetPlatform.android: CupertinoPageTransitionsBuilder(),
      TargetPlatform.linux: CupertinoPageTransitionsBuilder(),
      TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
    }),
    inputDecorationTheme: InputDecorationTheme(
      border: InputBorder.none,
      hintStyle: TextStyle(color: colors.tertiaryLabel),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: colors.card,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.card)),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: colors.label,
      contentTextStyle: TextStyle(color: colors.card),
      shape: const StadiumBorder(),
    ),
  );
}

/// Text styles named after the iOS ones the app uses.
class TextStyles {
  static TextStyle largeTitle(BuildContext c) =>
      TextStyle(fontSize: 34, fontWeight: FontWeight.w700, letterSpacing: -0.6, color: c.colors.label);
  static TextStyle title(BuildContext c) =>
      TextStyle(fontSize: 28, fontWeight: FontWeight.w700, letterSpacing: -0.4, color: c.colors.label);
  static TextStyle navTitle(BuildContext c) =>
      TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: c.colors.label);
  static TextStyle headline(BuildContext c) =>
      TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: c.colors.label);
  static TextStyle body(BuildContext c) => TextStyle(fontSize: 17, color: c.colors.label);
  static TextStyle subheadline(BuildContext c) =>
      TextStyle(fontSize: 15, color: c.colors.secondaryLabel);
  static TextStyle caption(BuildContext c) => TextStyle(fontSize: 12, color: c.colors.secondaryLabel);
  static TextStyle sectionHeader(BuildContext c) =>
      TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: c.colors.secondaryLabel);
}
