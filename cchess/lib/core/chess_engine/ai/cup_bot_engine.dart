import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../../constants/piece_constants.dart';
import '../board.dart';
import '../move.dart';
import '../piece.dart';
import '../position.dart';
import '../xiangqi_cup_game.dart';
import 'bot_difficulty.dart';
import 'evaluator.dart';
import 'minimax.dart' show ScoredMove;

/// Bot for Cờ Úp (the blind variant). Unlike [BotEngine] it cannot reuse the
/// Pikafish / standard minimax path: those reason over a FULLY-VISIBLE board,
/// while Cờ Úp hides every non-general identity until it is revealed by a move.
///
/// **Fair play (no peeking):** the bot is given only what a human opponent can
/// see — the visible board (covers + already-revealed pieces) and which squares
/// are still face-down. It is NOT told the shuffled identities. Move generation
/// uses the cup rules (a face-down piece moves by its cover); evaluation values
/// each face-down piece at its *expected* worth (the average of an unrevealed
/// piece) rather than peeking at what it really is.
///
/// This is a deliberately pragmatic v1: inside the search a face-down piece that
/// moves is assumed to reveal as its cover. A fully principled engine would model
/// the reveal as a chance node (expectiminimax) — left as future work.
class CupBotEngine {
  CupBotEngine();

  /// Cup positions have a very high branching factor and the cup engine copies
  /// the board on every ply, so cap the search shallower than standard chess.
  static const int maxDepth = 3;

  Future<Move?> chooseMove(
    XiangqiCupGame game,
    BotDifficulty difficulty,
  ) async {
    if (game.status.isOver) return null;
    final settings = difficulty.settings;
    final input = _CupSearchInput(
      fen: game.toFen(),
      hidden: game.hiddenPositions
          .map((p) => p.row * Board.cols + p.col)
          .toList(growable: false),
      depth: min(settings.depth, maxDepth),
      randomChance: settings.randomMoveChance,
      suboptimalChance: settings.suboptimalChance,
      seed: DateTime.now().microsecondsSinceEpoch,
    );

    final startedAt = DateTime.now();
    final uci = await compute(_runCupSearch, input);

    // Honour the difficulty's minimum think time so the move doesn't snap in.
    final elapsed = DateTime.now().difference(startedAt);
    if (elapsed < settings.minThinkTime) {
      await Future.delayed(settings.minThinkTime - elapsed);
    }

    if (uci == null) return null;
    final coords = Move.parseUciCoords(uci);
    if (coords == null) return null;
    final (from, to) = coords;
    final piece = game.board.at(from);
    if (piece == null) return null;
    // moved/captured here are the VISIBLE (cover) pieces — the real cup game
    // reveals the true identity when the controller applies (from, to).
    return Move(from: from, to: to, moved: piece, captured: game.board.at(to));
  }
}

/// Top-level isolate entry point (must be a top-level/static function for
/// [compute]). Rebuilds a search game from the cheat-safe inputs: the visible
/// board + which squares are face-down. Face-down squares are assigned their
/// COVER identity so cup move generation works; their true identity stays
/// unknown to the search, exactly as for a human.
String? _runCupSearch(_CupSearchInput input) {
  final board = Board.fromFen(input.fen);
  final parts = input.fen.split(' ');
  final turn = (parts.length > 1 && parts[1] == 'b')
      ? PieceColor.black
      : PieceColor.red;

  final hidden = <Position, Piece>{};
  for (final idx in input.hidden) {
    final pos = Position(idx ~/ Board.cols, idx % Board.cols);
    final cover = board.at(pos);
    if (cover != null) hidden[pos] = cover;
  }

  final game = XiangqiCupGame.debug(
    board: board,
    turn: turn,
    hiddenAssignments: hidden,
  );
  final search = _CupMinimax(depth: input.depth, seed: input.seed);
  final result = search.choose(
    game,
    randomChance: input.randomChance,
    suboptimalChance: input.suboptimalChance,
  );
  return result?.move.toUci();
}

class _CupSearchInput {
  final String fen;
  final List<int> hidden;
  final int depth;
  final double randomChance;
  final double suboptimalChance;
  final int seed;

  const _CupSearchInput({
    required this.fen,
    required this.hidden,
    required this.depth,
    required this.randomChance,
    required this.suboptimalChance,
    required this.seed,
  });
}

/// Minimax + alpha-beta over a [XiangqiCupGame]. Mirrors [Minimax] but uses the
/// cup move rules ([XiangqiCupGame.getValidMoves]) and a cup-aware evaluator
/// (face-down pieces scored at their expected value).
class _CupMinimax {
  static const int mateScore = 999999;

  /// Expected value of a face-down piece: the average value of a side's 15
  /// non-general pieces (2×900 + 2×450 + 2×400 + 2×200 + 2×200 + 5×100) / 15.
  static const int faceDownValue = 320;

  final int depth;
  final Random _random;

  _CupMinimax({required this.depth, int? seed}) : _random = Random(seed);

  ScoredMove? choose(
    XiangqiCupGame game, {
    double randomChance = 0,
    double suboptimalChance = 0,
  }) {
    final ranked = _rankMoves(game);
    if (ranked.isEmpty) return null;

    if (randomChance > 0 && _random.nextDouble() < randomChance) {
      final all = _allLegalMoves(game, game.turn);
      return ScoredMove(all[_random.nextInt(all.length)], 0);
    }
    if (suboptimalChance > 0 &&
        ranked.length > 1 &&
        _random.nextDouble() < suboptimalChance) {
      return ranked[1];
    }
    return ranked.first;
  }

  List<ScoredMove> _rankMoves(XiangqiCupGame game) {
    final color = game.turn;
    final moves = _allLegalMoves(game, color);
    if (moves.isEmpty) return const [];

    final isMaximizing = color == PieceColor.red;
    int alpha = -mateScore * 2;
    int beta = mateScore * 2;
    moves.sort((a, b) => _moveOrder(game, b).compareTo(_moveOrder(game, a)));

    final scored = <ScoredMove>[];
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
    XiangqiCupGame game,
    int remainingDepth,
    int alpha,
    int beta,
    bool maximizing,
  ) {
    // A move may have ended the game (mate, stalemate-as-loss, or the 120-ply
    // draw). Stop here — calling makeMove on a finished game would throw.
    if (game.status.isOver) return _terminalScore(game);
    if (remainingDepth <= 0) return _evaluate(game);

    final color = game.turn;
    final moves = _allLegalMoves(game, color);
    if (moves.isEmpty) {
      // No legal move in Xiangqi/Cờ Úp is a LOSS for the side to move.
      return color == PieceColor.red ? -mateScore : mateScore;
    }
    moves.sort((a, b) => _moveOrder(game, b).compareTo(_moveOrder(game, a)));

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

  /// Red-positive terminal score for a finished game.
  int _terminalScore(XiangqiCupGame game) {
    switch (game.status) {
      case GameStatus.redWin:
        return mateScore;
      case GameStatus.blackWin:
        return -mateScore;
      case GameStatus.draw:
        return 0;
      case GameStatus.playing:
        return _evaluate(game);
    }
  }

  /// Static evaluation, Red-positive. Face-down pieces count at expected value
  /// (no piece-square bonus — their identity is unknown); revealed pieces use
  /// the full material + piece-square score.
  int _evaluate(XiangqiCupGame game) {
    int score = 0;
    for (final (pos, piece) in game.board.occupied()) {
      final int value = game.isHidden(pos)
          ? faceDownValue
          : Evaluator.pieceScore(piece, pos.row, pos.col);
      score += piece.color == PieceColor.red ? value : -value;
    }
    return score;
  }

  /// MVV-LVA ordering so alpha-beta prunes earlier. Capturing a face-down piece
  /// is valued at the expected face-down worth.
  int _moveOrder(XiangqiCupGame game, Move m) {
    if (m.captured == null) return 0;
    final victim = game.isHidden(m.to)
        ? faceDownValue
        : (Evaluator.pieceValue[m.captured!.type] ?? 0);
    final attacker = Evaluator.pieceValue[m.moved.type] ?? 0;
    return victim * 10 - attacker;
  }

  List<Move> _allLegalMoves(XiangqiCupGame game, PieceColor color) {
    final out = <Move>[];
    for (final (pos, piece) in game.board.occupied()) {
      if (piece.color != color) continue;
      for (final to in game.getValidMoves(pos)) {
        out.add(Move(
          from: pos,
          to: to,
          moved: piece,
          captured: game.board.at(to),
        ));
      }
    }
    return out;
  }
}
