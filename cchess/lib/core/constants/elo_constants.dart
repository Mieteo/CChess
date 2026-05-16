import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';

/// Rank tier definitions following the spec (Tập Sự → Kỳ Thánh).
enum RankTier {
  apprentice, // Tập Sự
  novice, // Kỳ Sinh
  warrior, // Kỳ Sĩ
  general, // Kỳ Tướng
  marshal, // Kỳ Soái
  king, // Kỳ Vương
  sage, // Kỳ Thánh
}

class RankInfo {
  final RankTier tier;
  final String nameVi;
  final int minElo;
  final int? maxElo;
  final int stars;
  final Color color;
  final IconData icon;

  const RankInfo({
    required this.tier,
    required this.nameVi,
    required this.minElo,
    required this.maxElo,
    required this.stars,
    required this.color,
    required this.icon,
  });
}

class EloConstants {
  EloConstants._();

  static const int initialElo = 1000;

  /// K-factor used in Elo update formula. Drops as the player matures.
  static int kFactor(int totalGames) {
    if (totalGames < 30) return 32;
    if (totalGames < 100) return 24;
    return 16;
  }

  static const List<RankInfo> ranks = [
    RankInfo(
      tier: RankTier.apprentice,
      nameVi: 'Tập Sự',
      minElo: 0,
      maxElo: 1199,
      stars: 1,
      color: AppColors.rankApprentice,
      icon: Icons.spa_outlined,
    ),
    RankInfo(
      tier: RankTier.novice,
      nameVi: 'Kỳ Sinh',
      minElo: 1200,
      maxElo: 1399,
      stars: 2,
      color: AppColors.rankNovice,
      icon: Icons.school_outlined,
    ),
    RankInfo(
      tier: RankTier.warrior,
      nameVi: 'Kỳ Sĩ',
      minElo: 1400,
      maxElo: 1599,
      stars: 3,
      color: AppColors.rankWarrior,
      icon: Icons.military_tech_outlined,
    ),
    RankInfo(
      tier: RankTier.general,
      nameVi: 'Kỳ Tướng',
      minElo: 1600,
      maxElo: 1799,
      stars: 3,
      color: AppColors.rankGeneral,
      icon: Icons.shield_outlined,
    ),
    RankInfo(
      tier: RankTier.marshal,
      nameVi: 'Kỳ Soái',
      minElo: 1800,
      maxElo: 1999,
      stars: 3,
      color: AppColors.rankMarshal,
      icon: Icons.fort_outlined,
    ),
    RankInfo(
      tier: RankTier.king,
      nameVi: 'Kỳ Vương',
      minElo: 2000,
      maxElo: 2199,
      stars: 3,
      color: AppColors.rankKing,
      icon: Icons.workspace_premium_outlined,
    ),
    RankInfo(
      tier: RankTier.sage,
      nameVi: 'Kỳ Thánh',
      minElo: 2200,
      maxElo: null,
      stars: 3,
      color: AppColors.rankSage,
      icon: Icons.auto_awesome,
    ),
  ];

  static RankInfo rankForElo(int elo) {
    for (final r in ranks) {
      if (elo >= r.minElo && (r.maxElo == null || elo <= r.maxElo!)) {
        return r;
      }
    }
    return ranks.first;
  }
}
