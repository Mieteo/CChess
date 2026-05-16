/// 5 bot strength tiers exposed to the user.
///
/// The internal search depth and randomization rate are tuned so each tier
/// feels distinctly different; numbers may be re-balanced later once we
/// gather user feedback.
enum BotDifficulty {
  veryEasy,
  easy,
  medium,
  hard,
  veryHard,
}

class BotSettings {
  /// Minimax search depth (plies). Higher = stronger but slower.
  final int depth;

  /// Probability (0..1) of picking a random legal move instead of the
  /// engine's best. Used to make easy bots feel beatable.
  final double randomMoveChance;

  /// Probability (0..1) of picking the engine's 2nd-best move instead of the
  /// best. Smoothes out playing strength for mid-tier difficulty.
  final double suboptimalChance;

  /// Minimum think time injected so the UI doesn't feel instant.
  final Duration minThinkTime;

  const BotSettings({
    required this.depth,
    required this.randomMoveChance,
    required this.suboptimalChance,
    required this.minThinkTime,
  });
}

extension BotDifficultyX on BotDifficulty {
  String get nameVi {
    switch (this) {
      case BotDifficulty.veryEasy:
        return 'Tập Sự';
      case BotDifficulty.easy:
        return 'Sơ Cấp';
      case BotDifficulty.medium:
        return 'Trung Cấp';
      case BotDifficulty.hard:
        return 'Cao Thủ';
      case BotDifficulty.veryHard:
        return 'Đại Sư';
    }
  }

  String get descriptionVi {
    switch (this) {
      case BotDifficulty.veryEasy:
        return 'Đi gần như ngẫu nhiên. Phù hợp người mới làm quen.';
      case BotDifficulty.easy:
        return 'Bắt được quân hớ, hiểu các thế đơn giản.';
      case BotDifficulty.medium:
        return 'Tính trước 3 nước, biết phối hợp quân.';
      case BotDifficulty.hard:
        return 'Tính sâu 4 nước, ít sai lầm chiến thuật.';
      case BotDifficulty.veryHard:
        return 'Đỉnh cao engine offline — chuẩn bị kỹ trước khi chơi.';
    }
  }

  /// Estimated equivalent ELO (rough — varies a lot with engine quality).
  int get estimatedElo {
    switch (this) {
      case BotDifficulty.veryEasy:
        return 900;
      case BotDifficulty.easy:
        return 1200;
      case BotDifficulty.medium:
        return 1500;
      case BotDifficulty.hard:
        return 1800;
      case BotDifficulty.veryHard:
        return 2100;
    }
  }

  BotSettings get settings {
    switch (this) {
      case BotDifficulty.veryEasy:
        return const BotSettings(
          depth: 1,
          randomMoveChance: 0.6,
          suboptimalChance: 0.0,
          minThinkTime: Duration(milliseconds: 350),
        );
      case BotDifficulty.easy:
        return const BotSettings(
          depth: 2,
          randomMoveChance: 0.15,
          suboptimalChance: 0.2,
          minThinkTime: Duration(milliseconds: 500),
        );
      case BotDifficulty.medium:
        return const BotSettings(
          depth: 3,
          randomMoveChance: 0.0,
          suboptimalChance: 0.1,
          minThinkTime: Duration(milliseconds: 700),
        );
      case BotDifficulty.hard:
        return const BotSettings(
          depth: 4,
          randomMoveChance: 0.0,
          suboptimalChance: 0.0,
          minThinkTime: Duration(milliseconds: 900),
        );
      case BotDifficulty.veryHard:
        return const BotSettings(
          depth: 5,
          randomMoveChance: 0.0,
          suboptimalChance: 0.0,
          minThinkTime: Duration(milliseconds: 1200),
        );
    }
  }

  static BotDifficulty? fromString(String? value) {
    if (value == null) return null;
    for (final d in BotDifficulty.values) {
      if (d.name == value) return d;
    }
    return null;
  }
}
