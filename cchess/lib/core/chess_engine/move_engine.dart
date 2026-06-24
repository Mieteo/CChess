import 'ai/bot_difficulty.dart';
import 'ai/game_analyzer.dart';
import 'move.dart';

enum EngineLevel { veryEasy, easy, medium, hard, veryHard, grandmaster }

enum EngineUseCase { bot, hint, analysis }

enum EngineSource { localMinimax, remotePikafish }

/// Why a result came from the local engine instead of remote Pikafish.
/// Lets the UI distinguish "server busy/offline" from "you're out of free
/// AI quota" (which warrants a VIP upsell rather than a retry).
enum EngineFallbackKind { network, quotaExceeded }

EngineLevel? engineLevelFromString(String? value) {
  if (value == null) return null;
  for (final level in EngineLevel.values) {
    if (level.name == value || level.apiName == value) return level;
  }
  return null;
}

extension EngineLevelX on EngineLevel {
  BotDifficulty get fallbackDifficulty {
    switch (this) {
      case EngineLevel.veryEasy:
        return BotDifficulty.veryEasy;
      case EngineLevel.easy:
        return BotDifficulty.easy;
      case EngineLevel.medium:
        return BotDifficulty.medium;
      case EngineLevel.hard:
        return BotDifficulty.hard;
      case EngineLevel.veryHard:
      case EngineLevel.grandmaster:
        return BotDifficulty.veryHard;
    }
  }

  String get apiName {
    switch (this) {
      case EngineLevel.veryEasy:
        return 'veryEasy';
      case EngineLevel.easy:
        return 'easy';
      case EngineLevel.medium:
        return 'medium';
      case EngineLevel.hard:
        return 'hard';
      case EngineLevel.veryHard:
        return 'veryHard';
      case EngineLevel.grandmaster:
        return 'grandmaster';
    }
  }
}

class EngineMove {
  final Move move;
  final String uci;
  final int? scoreCp;
  final int? depth;
  final EngineSource source;
  final bool usedFallback;
  final String? fallbackReason;

  /// Set when [usedFallback] is true, classifying why remote was skipped.
  final EngineFallbackKind? fallbackKind;

  const EngineMove({
    required this.move,
    required this.uci,
    required this.source,
    this.scoreCp,
    this.depth,
    this.usedFallback = false,
    this.fallbackReason,
    this.fallbackKind,
  });

  EngineMove copyWith({
    Move? move,
    String? uci,
    int? scoreCp,
    int? depth,
    EngineSource? source,
    bool? usedFallback,
    String? fallbackReason,
    EngineFallbackKind? fallbackKind,
  }) {
    return EngineMove(
      move: move ?? this.move,
      uci: uci ?? this.uci,
      scoreCp: scoreCp ?? this.scoreCp,
      depth: depth ?? this.depth,
      source: source ?? this.source,
      usedFallback: usedFallback ?? this.usedFallback,
      fallbackReason: fallbackReason ?? this.fallbackReason,
      fallbackKind: fallbackKind ?? this.fallbackKind,
    );
  }
}

abstract class MoveEngine {
  Future<EngineMove?> bestMove(
    String fen, {
    required EngineLevel level,
    EngineUseCase useCase = EngineUseCase.bot,
  });

  Future<GameAnalysis> analyze({
    required String startingFen,
    required List<String> moveUcis,
  });
}
