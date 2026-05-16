import 'package:equatable/equatable.dart';
import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';

enum AchievementTier { bronze, silver, gold }

extension AchievementTierX on AchievementTier {
  Color get color {
    switch (this) {
      case AchievementTier.bronze:
        return AppColors.rankNovice;
      case AchievementTier.silver:
        return AppColors.outline;
      case AchievementTier.gold:
        return AppColors.accentGold;
    }
  }

  String get nameVi {
    switch (this) {
      case AchievementTier.bronze:
        return 'Đồng';
      case AchievementTier.silver:
        return 'Bạc';
      case AchievementTier.gold:
        return 'Vàng';
    }
  }
}

enum AchievementCategory { play, win, learn, social, milestone }

extension AchievementCategoryX on AchievementCategory {
  String get nameVi {
    switch (this) {
      case AchievementCategory.play:
        return 'Tham gia';
      case AchievementCategory.win:
        return 'Chiến thắng';
      case AchievementCategory.learn:
        return 'Học cờ';
      case AchievementCategory.social:
        return 'Xã hội';
      case AchievementCategory.milestone:
        return 'Cột mốc';
    }
  }
}

/// Definition of an achievement (static — same for everyone).
class Achievement extends Equatable {
  final String id;
  final String nameVi;
  final String descVi;
  final IconData icon;
  final AchievementCategory category;
  final AchievementTier tier;

  /// Target value the user must reach. Compared against the current stat
  /// referenced by [statKey].
  final int target;

  /// Which stat to compare against:
  ///   "wins" | "totalGames" | "puzzlesSolved" | "winStreak" |
  ///   "eloChess" | "loginStreak"
  final String statKey;

  const Achievement({
    required this.id,
    required this.nameVi,
    required this.descVi,
    required this.icon,
    required this.category,
    required this.tier,
    required this.target,
    required this.statKey,
  });

  @override
  List<Object?> get props =>
      [id, nameVi, descVi, category, tier, target, statKey];
}

/// User's progress on an achievement.
class AchievementProgress extends Equatable {
  final String id;
  final bool unlocked;
  final DateTime? unlockedAt;

  const AchievementProgress({
    required this.id,
    this.unlocked = false,
    this.unlockedAt,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'unlocked': unlocked,
        'unlockedAt': unlockedAt?.toIso8601String(),
      };

  factory AchievementProgress.fromJson(Map<dynamic, dynamic> json) {
    return AchievementProgress(
      id: json['id'] as String,
      unlocked: json['unlocked'] as bool? ?? false,
      unlockedAt: (json['unlockedAt'] as String?) == null
          ? null
          : DateTime.tryParse(json['unlockedAt'] as String),
    );
  }

  @override
  List<Object?> get props => [id, unlocked, unlockedAt];
}

/// Snapshot of all user stats relevant to achievement evaluation.
class AchievementStats extends Equatable {
  final int totalGames;
  final int wins;
  final int winStreak;
  final int eloChess;
  final int puzzlesSolved;
  final int loginStreak;

  const AchievementStats({
    required this.totalGames,
    required this.wins,
    required this.winStreak,
    required this.eloChess,
    required this.puzzlesSolved,
    required this.loginStreak,
  });

  int statValue(String key) {
    switch (key) {
      case 'wins':
        return wins;
      case 'totalGames':
        return totalGames;
      case 'puzzlesSolved':
        return puzzlesSolved;
      case 'winStreak':
        return winStreak;
      case 'eloChess':
        return eloChess;
      case 'loginStreak':
        return loginStreak;
      default:
        return 0;
    }
  }

  @override
  List<Object?> get props =>
      [totalGames, wins, winStreak, eloChess, puzzlesSolved, loginStreak];
}
