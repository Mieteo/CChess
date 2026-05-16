import 'package:flutter/material.dart';

/// CChess color palette — Á Đông wood + ink-wash theme.
///
/// Values mirror the design system in
/// stitch_document_to_ui_designer/cchess_design_system/DESIGN.md.
class AppColors {
  AppColors._();

  // ──────────────── Brand wood + ink palette ────────────────
  static const Color woodDark = Color(0xFF5C3A1E);
  static const Color woodLight = Color(0xFFD4A96A);
  static const Color accentGold = Color(0xFFC8960C);
  static const Color vermilionRed = Color(0xFF8B0000);
  static const Color inkBlack = Color(0xFF2C1810);
  static const Color parchmentTan = Color(0xFF7D5A3C);
  static const Color ivoryPanel = Color(0xFFF5E6C8);
  static const Color tealSuccess = Color(0xFF4A7C59);
  static const Color deepNavyBlack = Color(0xFF1A3A5C);
  static const Color charcoalDark = Color(0xFF3A2010);
  static const Color shadowBrown = Color(0x335C3A1E);

  // ──────────────── Material 3 dark scheme ────────────────
  static const Color background = Color(0xFF161310);
  static const Color onBackground = Color(0xFFEAE1DC);

  static const Color surface = Color(0xFF161310);
  static const Color surfaceDim = Color(0xFF161310);
  static const Color surfaceBright = Color(0xFF3D3835);
  static const Color surfaceContainerLowest = Color(0xFF110D0B);
  static const Color surfaceContainerLow = Color(0xFF1F1B18);
  static const Color surfaceContainer = Color(0xFF231F1C);
  static const Color surfaceContainerHigh = Color(0xFF2E2926);
  static const Color surfaceContainerHighest = Color(0xFF393431);
  static const Color onSurface = Color(0xFFEAE1DC);
  static const Color onSurfaceVariant = Color(0xFFD4C3B9);
  static const Color surfaceVariant = Color(0xFF393431);
  static const Color surfaceTint = Color(0xFFEFBC97);

  static const Color inverseSurface = Color(0xFFEAE1DC);
  static const Color inverseOnSurface = Color(0xFF342F2C);
  static const Color inversePrimary = Color(0xFF7C5638);

  static const Color outline = Color(0xFF9D8E84);
  static const Color outlineVariant = Color(0xFF50443D);

  static const Color primary = Color(0xFFEFBC97);
  static const Color onPrimary = Color(0xFF48290E);
  static const Color primaryContainer = Color(0xFF5C3A1E);
  static const Color onPrimaryContainer = Color(0xFFD5A481);
  static const Color primaryFixed = Color(0xFFFFDCC4);
  static const Color primaryFixedDim = Color(0xFFEFBC97);
  static const Color onPrimaryFixed = Color(0xFF2F1500);
  static const Color onPrimaryFixedVariant = Color(0xFF623F22);

  static const Color secondary = Color(0xFFECBF7E);
  static const Color onSecondary = Color(0xFF442B00);
  static const Color secondaryContainer = Color(0xFF5F410A);
  static const Color onSecondaryContainer = Color(0xFFD9AE6E);
  static const Color secondaryFixed = Color(0xFFFFDDB0);
  static const Color secondaryFixedDim = Color(0xFFECBF7E);
  static const Color onSecondaryFixed = Color(0xFF291800);
  static const Color onSecondaryFixedVariant = Color(0xFF5F410A);

  static const Color tertiary = Color(0xFFA3CED6);
  static const Color onTertiary = Color(0xFF03363D);
  static const Color tertiaryContainer = Color(0xFF1C484F);
  static const Color onTertiaryContainer = Color(0xFF8BB6BE);
  static const Color tertiaryFixed = Color(0xFFBEEAF3);
  static const Color tertiaryFixedDim = Color(0xFFA3CED6);
  static const Color onTertiaryFixed = Color(0xFF001F24);
  static const Color onTertiaryFixedVariant = Color(0xFF214D54);

  static const Color error = Color(0xFFFFB4AB);
  static const Color onError = Color(0xFF690005);
  static const Color errorContainer = Color(0xFF93000A);
  static const Color onErrorContainer = Color(0xFFFFDAD6);

  // ──────────────── Rank tier colors (for badges, avatar rings) ────────────────
  static const Color rankApprentice = Color(0xFF9D8E84); // grey-stone
  static const Color rankNovice = Color(0xFF7C5638);     // bronze
  static const Color rankWarrior = Color(0xFFA3CED6);    // jade
  static const Color rankGeneral = Color(0xFFC8960C);    // gold
  static const Color rankMarshal = Color(0xFFEFBC97);    // rose-gold
  static const Color rankKing = Color(0xFFFFDCC4);       // pale-gold
  static const Color rankSage = Color(0xFFFFB4AB);       // vermilion glow

  // ──────────────── Helper gradients ────────────────
  static const LinearGradient appBarGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [woodDark, charcoalDark],
  );

  static const LinearGradient woodBoardGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [woodLight, Color(0xFFA07850)],
  );

  static const LinearGradient goldButtonGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [accentGold, woodLight],
  );

  static const LinearGradient redButtonGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [vermilionRed, Color(0xFF5C0000)],
  );
}
