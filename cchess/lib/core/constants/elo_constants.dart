import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';

/// ELO is the single measure of strength — there are no danh-xưng rank tiers.
/// The old `RankTier` / `RankInfo` / `rankForElo` were removed in favour of the
/// raw ELO number plus a purely-cosmetic [colorForElo] band.
class EloConstants {
  EloConstants._();

  static const int initialElo = 1000;

  /// K-factor used in the online PvP Elo update. Drops as the player matures.
  /// (Bot games use the fixed asymmetric scoring in `elo_scoring.dart`.)
  static int kFactor(int totalGames) {
    if (totalGames < 30) return 32;
    if (totalGames < 100) return 24;
    return 16;
  }

  /// Color band for an ELO, used for avatar rings and the ELO chip. Cosmetic
  /// only — every ~200 ELO shifts hue so progress stays visible, with no name.
  static Color colorForElo(int elo) {
    if (elo < 1200) return AppColors.rankApprentice;
    if (elo < 1400) return AppColors.rankNovice;
    if (elo < 1600) return AppColors.rankWarrior;
    if (elo < 1800) return AppColors.rankGeneral;
    if (elo < 2000) return AppColors.rankMarshal;
    if (elo < 2200) return AppColors.rankKing;
    return AppColors.rankSage;
  }
}
