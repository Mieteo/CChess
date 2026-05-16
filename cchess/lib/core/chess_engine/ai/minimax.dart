import 'dart:math';

import '../../constants/piece_constants.dart';
import '../board.dart';
import '../move.dart';
import '../move_rules.dart';
import '../piece.dart';
import '../position.dart';
import '../xiangqi_game.dart';
import 'evaluator.dart';

/// Pure-Dart Xiangqi search using minimax + alpha-beta pruning.
///
/// The engine is deliberately compact: it operates directly on the mutable
/// [XiangqiGame] / [Board] from the rest of the codebase, taking advantage
/// of the cheap [XiangqiGame.makeMove] / [XiangqiGame.undoMove] pair so we
/// never have to copy the board between plies.
class Minimax {
  /// Static "draw-ish" score for the side to move when no legal moves exist
  /// but the position isn't checkmate (treated as a loss in Xiangqi).
  static const int stalemateScore = -50000;

  /// Score representing an immediate mate. Positive favors the side that
  /// just mated the opponent.
  static const int mateScore = 999999;

  final int depth;
  final Random _random;

  Minimax({required this.depth, int? seed}) : _random = Random(seed);

  /// Choose a move for the side currently to move in [game]. Returns null
  /// only if the game is already over or there are no legal replies.
  ///
  /// [randomChance]: probability of returning a random legal move instead
  /// of the search result (only used to weaken easy bots).
  /// [suboptimalChance]: probability of returning the 2nd-best move.
  ScoredMove? choose(
    XiangqiGame game, {
    double randomChance = 0,
    double suboptimalChance = 0,
  }) {
    final ranked = _rankMoves(game);
    if (ranked.isEmpty) return null;

    if (randomChance > 0 && _random.nextDouble() < randomChance) {
      // Pick uniformly among legal moves (not just the ranked head).
      final allLegal = _allLegalMoves(game, game.turn);
      final pick = allLegal[_random.nextInt(allLegal.length)];
      return ScoredMove(pick, 0);
    }

    if (suboptimalChance > 0 &&
        ranked.length > 1 &&
        _random.nextDouble() < suboptimalChance) {
      return ranked[1];
    }
    return ranked.first;
  }

  /// Returns the top moves sorted from best→worst for the side to move.
  /// Always returns at least one element (or empty if no legal moves).
  List<ScoredMove> _rankMoves(XiangqiGame game) {
    final color = game.turn;
    final moves = _allLegalMoves(game, color);
    if (moves.isEmpty) return const [];

    final scored = <ScoredMove>[];
    final isMaximizing = color == PieceColor.red;
    int alpha = -mateScore * 2;
    int beta = mateScore * 2;

    // Order moves first (captures + central) so alpha-beta prunes earlier.
    moves.sort((a, b) => _moveOrderScore(b).compareTo(_moveOrderScore(a)));

    for (final m in moves) {
      game.makeMove(m.from, m.to);
      final score = _alphaBeta(game, depth - 1, alpha, beta, !isMaximizing);
      game.undoMove();
      scored.add(ScoredMove(m, score));
      if (isMaximizing) {
        if (score > alpha) alpha = score;
      } else {
        if (score < beta) beta = score;
      }
    }

    scored.sort((a, b) => isMaximizing
        ? b.score.compareTo(a.score)
        : a.score.compareTo(b.score));
    return scored;
  }

  int _alphaBeta(
    XiangqiGame game,
    int remainingDepth,
    int alpha,
    int beta,
    bool maximizing,
  ) {
    if (remainingDepth <= 0) {
      return Evaluator.evaluate(game.board);
    }
    final color = game.turn;
    final moves = _allLegalMoves(game, color);
    if (moves.isEmpty) {
      // No legal move: in Xiangqi that's a loss for the side to move.
      // From the static eval frame (Red-positive), losing for Red = very
      // negative score; losing for Black = very positive.
      return color == PieceColor.red ? -mateScore : mateScore;
    }
    moves.sort((a, b) => _moveOrderScore(b).compareTo(_moveOrderScore(a)));

    if (maximizing) {
      int value = -mateScore * 2;
      for (final m in moves) {
        game.makeMove(m.from, m.to);
        final score = _alphaBeta(game, remainingDepth - 1, alpha, beta, false);
        game.undoMove();
        if (score > value) value = score;
        if (value > alpha) alpha = value;
        if (alpha >= beta) break;
      }
      return value;
    } else {
      int value = mateScore * 2;
      for (final m in moves) {
        game.makeMove(m.from, m.to);
        final score = _alphaBeta(game, remainingDepth - 1, alpha, beta, true);
        game.undoMove();
        if (score < value) value = score;
        if (value < beta) beta = value;
        if (alpha >= beta) break;
      }
      return value;
    }
  }

  /// Higher score = try earlier. We use MVV-LVA: captures first, big-victim
  /// captures first within those.
  int _moveOrderScore(Move m) {
    if (m.captured == null) return 0;
    final v = Evaluator.pieceValue[m.captured!.type] ?? 0;
    final a = Evaluator.pieceValue[m.moved.type] ?? 0;
    return v * 10 - a;
  }

  /// All legal moves for [color] in the current position. Each move records
  /// the captured piece (if any) so we can sort by MVV-LVA before searching.
  static List<Move> _allLegalMoves(XiangqiGame game, PieceColor color) {
    final out = <Move>[];
    final board = game.board;
    for (final (pos, piece) in board.occupied()) {
      if (piece.color != color) continue;
      final targets = MoveRules.pseudoLegalMoves(board, pos);
      for (final to in targets) {
        if (!_isLegalAfter(board, pos, to, piece)) continue;
        out.add(Move(
          from: pos,
          to: to,
          moved: piece,
          captured: board.at(to),
        ));
      }
    }
    return out;
  }

  /// Like XiangqiGame's internal _isLegalMove — but inlined here so we don't
  /// need to expose the private. Uses a board copy.
  static bool _isLegalAfter(
    Board b,
    Position from,
    Position to,
    Piece piece,
  ) {
    final copy = b.copy();
    copy.setAt(to, piece);
    copy.setAt(from, null);
    if (MoveRules.isInCheck(copy, piece.color)) return false;
    if (MoveRules.areGeneralsFacing(copy)) return false;
    return true;
  }
}

/// A move bundled with its minimax score (Red-positive).
class ScoredMove {
  final Move move;
  final int score;

  const ScoredMove(this.move, this.score);

  @override
  String toString() => '${move.toUci()}@$score';
}
