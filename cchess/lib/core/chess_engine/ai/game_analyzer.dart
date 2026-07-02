import 'package:flutter/material.dart';

import '../../constants/piece_constants.dart';
import '../move.dart';
import '../xiangqi_game.dart';
import 'minimax.dart';

/// Coarse classification of a single move's quality. Bands are inspired by
/// Lichess but tuned to be a bit more forgiving for our shallow search.
enum MoveQuality { best, excellent, good, inaccuracy, mistake, blunder }

extension MoveQualityX on MoveQuality {
  String get nameVi {
    switch (this) {
      case MoveQuality.best:
        return 'Nước hay nhất';
      case MoveQuality.excellent:
        return 'Xuất sắc';
      case MoveQuality.good:
        return 'Tốt';
      case MoveQuality.inaccuracy:
        return 'Thiếu chính xác';
      case MoveQuality.mistake:
        return 'Sai lầm';
      case MoveQuality.blunder:
        return 'Sai lầm lớn';
    }
  }

  String get shortVi {
    switch (this) {
      case MoveQuality.best:
        return 'Hay nhất';
      case MoveQuality.excellent:
        return 'XS';
      case MoveQuality.good:
        return 'Tốt';
      case MoveQuality.inaccuracy:
        return 'Sơ ý';
      case MoveQuality.mistake:
        return 'Sai';
      case MoveQuality.blunder:
        return 'Đại sai';
    }
  }

  /// 0..100 quality score used to compute an aggregate accuracy.
  int get scoreOut100 {
    switch (this) {
      case MoveQuality.best:
        return 100;
      case MoveQuality.excellent:
        return 95;
      case MoveQuality.good:
        return 80;
      case MoveQuality.inaccuracy:
        return 60;
      case MoveQuality.mistake:
        return 30;
      case MoveQuality.blunder:
        return 0;
    }
  }
}

/// Analysis of one move in the game.
class MoveAnalysis {
  /// 0-based index into the original move list.
  final int moveIndex;

  /// The move that was actually played.
  final Move move;

  /// Color of the side that played [move].
  final PieceColor mover;

  /// Engine's recommended move from the position before the actual move.
  /// Null if there was no legal move at all (shouldn't normally happen).
  final Move? recommendedMove;

  /// Evaluation (Red-positive centipawns) of the position resulting from
  /// the engine's best move + opponent's best reply.
  final int bestEval;

  /// Evaluation (Red-positive centipawns) of the position resulting from
  /// the actual move + opponent's best reply.
  final int actualEval;

  /// Centipawn loss from the mover's perspective. Always non-negative.
  /// Capped to keep mate scores from skewing the aggregate accuracy.
  final int centipawnLoss;

  /// Classification of this move.
  final MoveQuality quality;

  const MoveAnalysis({
    required this.moveIndex,
    required this.move,
    required this.mover,
    required this.recommendedMove,
    required this.bestEval,
    required this.actualEval,
    required this.centipawnLoss,
    required this.quality,
  });

  bool get isCorrect => quality == MoveQuality.best;
}

/// Aggregate report covering the full game.
class GameAnalysis {
  final List<MoveAnalysis> moves;
  final double redAccuracy; // 0..100
  final double blackAccuracy;
  final int redBlunders;
  final int blackBlunders;
  final int redMistakes;
  final int blackMistakes;

  const GameAnalysis({
    required this.moves,
    required this.redAccuracy,
    required this.blackAccuracy,
    required this.redBlunders,
    required this.blackBlunders,
    required this.redMistakes,
    required this.blackMistakes,
  });

  /// Build the aggregate report from per-move analyses. Shared by every
  /// engine implementation so accuracy/blunder math never diverges.
  factory GameAnalysis.aggregate(List<MoveAnalysis> analyses) =>
      GameAnalyzer._aggregate(analyses);

  /// Accuracy for a given player.
  double accuracyFor(PieceColor color) =>
      color == PieceColor.red ? redAccuracy : blackAccuracy;

  /// Best moves per side — useful for the coach summary card.
  int bestMoveCountFor(PieceColor color) {
    return moves
        .where((m) => m.mover == color && m.isCorrect)
        .length;
  }
}

/// Step-by-step progress emitted by [GameAnalyzer.stream].
class AnalysisProgress {
  final int completedMoves;
  final int totalMoves;
  final MoveAnalysis? latest;

  const AnalysisProgress({
    required this.completedMoves,
    required this.totalMoves,
    required this.latest,
  });

  double get fraction =>
      totalMoves == 0 ? 1.0 : completedMoves / totalMoves;
}

/// Runs minimax on each position to grade the moves of a finished game.
///
/// Default search depth is intentionally shallow (2) so the analysis stays
/// snappy on phone hardware; raise it for stronger feedback at the cost of
/// running time.
class GameAnalyzer {
  final int depth;

  GameAnalyzer({this.depth = 2});

  static const int _cpLossCap = 1000;

  /// Run the full analysis and return the aggregated [GameAnalysis].
  Future<GameAnalysis> analyze({
    required String startingFen,
    required List<String> moveUcis,
  }) async {
    final analyses = <MoveAnalysis>[];
    await for (final progress in stream(
      startingFen: startingFen,
      moveUcis: moveUcis,
    )) {
      if (progress.latest != null) analyses.add(progress.latest!);
    }
    return _aggregate(analyses);
  }

  /// Stream incremental progress — useful for showing a progress bar in UI.
  Stream<AnalysisProgress> stream({
    required String startingFen,
    required List<String> moveUcis,
  }) async* {
    final game = XiangqiGame.fromFen(startingFen);
    final total = moveUcis.length;
    for (int i = 0; i < moveUcis.length; i++) {
      final coords = Move.parseUciCoords(moveUcis[i]);
      if (coords == null) {
        yield AnalysisProgress(
          completedMoves: i + 1,
          totalMoves: total,
          latest: null,
        );
        continue;
      }
      final (from, to) = coords;
      final mover = game.turn;
      final piece = game.board.at(from);
      if (piece == null) break;

      // 1. Best move at current position (depth = depth).
      final search = Minimax(depth: depth, seed: 1);
      final best = search.choose(game);
      final bestEval = best?.score ?? 0;
      final recommended = best?.move;

      // 2. Apply the actual move.
      final actualMove = Move(
        from: from,
        to: to,
        moved: piece,
        captured: game.board.at(to),
      );
      if (!game.isValidMove(from, to)) {
        // Shouldn't happen with a saved record, but bail out gracefully.
        yield AnalysisProgress(
          completedMoves: i + 1,
          totalMoves: total,
          latest: null,
        );
        break;
      }
      game.makeMove(from, to);

      // 3. Engine's response to the actual move (depth - 1, since we already
      // burned one ply on the actual move).
      int actualEval;
      if (depth <= 1 || game.status.isOver) {
        // Static eval after the move if no further depth.
        actualEval = best?.score ?? 0;
        // Use the static evaluator directly via a 0-ply Minimax.
        actualEval = Minimax(depth: 1, seed: 1).choose(game)?.score ?? 0;
      } else {
        actualEval =
            Minimax(depth: depth - 1, seed: 1).choose(game)?.score ?? 0;
      }

      // 4. Loss is direction-aware: Red maximizes, Black minimizes.
      int loss;
      if (mover == PieceColor.red) {
        loss = bestEval - actualEval;
      } else {
        loss = actualEval - bestEval;
      }
      if (loss < 0) loss = 0;
      if (loss > _cpLossCap) loss = _cpLossCap;

      final quality = _classify(loss, isBestMove: recommended != null &&
          recommended.from == from &&
          recommended.to == to);

      final analysis = MoveAnalysis(
        moveIndex: i,
        move: actualMove,
        mover: mover,
        recommendedMove: recommended,
        bestEval: bestEval,
        actualEval: actualEval,
        centipawnLoss: loss,
        quality: quality,
      );

      yield AnalysisProgress(
        completedMoves: i + 1,
        totalMoves: total,
        latest: analysis,
      );
    }
  }

  static MoveQuality _classify(int cpLoss, {required bool isBestMove}) {
    if (isBestMove) return MoveQuality.best;
    if (cpLoss <= 15) return MoveQuality.excellent;
    if (cpLoss <= 60) return MoveQuality.good;
    if (cpLoss <= 150) return MoveQuality.inaccuracy;
    if (cpLoss <= 300) return MoveQuality.mistake;
    return MoveQuality.blunder;
  }

  static GameAnalysis _aggregate(List<MoveAnalysis> analyses) {
    int redCount = 0, blackCount = 0;
    int redScore = 0, blackScore = 0;
    int redBlunder = 0, blackBlunder = 0;
    int redMistake = 0, blackMistake = 0;
    for (final m in analyses) {
      if (m.mover == PieceColor.red) {
        redCount++;
        redScore += m.quality.scoreOut100;
        if (m.quality == MoveQuality.blunder) redBlunder++;
        if (m.quality == MoveQuality.mistake) redMistake++;
      } else {
        blackCount++;
        blackScore += m.quality.scoreOut100;
        if (m.quality == MoveQuality.blunder) blackBlunder++;
        if (m.quality == MoveQuality.mistake) blackMistake++;
      }
    }
    return GameAnalysis(
      moves: analyses,
      redAccuracy: redCount == 0 ? 0 : redScore / redCount,
      blackAccuracy: blackCount == 0 ? 0 : blackScore / blackCount,
      redBlunders: redBlunder,
      blackBlunders: blackBlunder,
      redMistakes: redMistake,
      blackMistakes: blackMistake,
    );
  }
}

/// Convenience colors / icons for displaying move quality.
extension MoveQualityVisual on MoveQuality {
  Color get color {
    switch (this) {
      case MoveQuality.best:
        return const Color(0xFF4A7C59); // tealSuccess
      case MoveQuality.excellent:
        return const Color(0xFF6BAA76);
      case MoveQuality.good:
        return const Color(0xFFA3CED6); // tertiary
      case MoveQuality.inaccuracy:
        return const Color(0xFFC8960C); // accentGold
      case MoveQuality.mistake:
        return const Color(0xFFE07A1F);
      case MoveQuality.blunder:
        return const Color(0xFF8B0000); // vermilionRed
    }
  }

  IconData get icon {
    switch (this) {
      case MoveQuality.best:
        return Icons.workspace_premium;
      case MoveQuality.excellent:
        return Icons.star_rounded;
      case MoveQuality.good:
        return Icons.check_circle_outline;
      case MoveQuality.inaccuracy:
        return Icons.error_outline;
      case MoveQuality.mistake:
        return Icons.warning_amber;
      case MoveQuality.blunder:
        return Icons.dangerous;
    }
  }
}
