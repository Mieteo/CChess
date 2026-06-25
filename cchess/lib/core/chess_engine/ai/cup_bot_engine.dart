import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../../constants/piece_constants.dart';
import '../board.dart';
import '../cup_rules.dart';
import '../move.dart';
import '../piece.dart';
import '../position.dart';
import '../xiangqi_cup_game.dart';
import 'bot_difficulty.dart';
import 'evaluator.dart';

/// Bot for Cờ Úp (the blind variant). Unlike [BotEngine] it cannot reuse the
/// Pikafish / standard minimax path: those reason over a FULLY-VISIBLE board,
/// while Cờ Úp hides every non-general identity until it is revealed by a move.
///
/// **Fair play (no peeking):** the bot is given only what a human opponent can
/// see — the visible board (covers + already-revealed pieces) and which squares
/// are still face-down. It is NOT told the shuffled identities. Move generation
/// uses the cup rules (a face-down piece moves by its cover); the *value* of a
/// face-down piece is its statistical expectation, never its true worth.
///
/// **v2 — full expectiminimax (this file).** A face-down move is genuinely
/// uncertain: when the mover lands it reveals one of the identities still in the
/// bag. So the search models each reveal as a **chance node** — it branches over
/// the distinct remaining hidden types of that colour, weighted by how many of
/// each remain, and averages the children (expectiminimax). The static value of
/// a still-face-down piece is the **mean of its colour's current bag**, which
/// shifts as pieces reveal (e.g. once both chariots are out, the rest are worth
/// less). The bag is derived purely from the visible board — `M0` (the 15
/// non-general pieces) minus everything already revealed on board — so the bot
/// never cheats. This replaces v1's "a face-down piece reveals as its cover +
/// flat 320cp" approximation.
class CupBotEngine {
  CupBotEngine();

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
      depth: _depthFor(difficulty),
      timeBudgetMs: _budgetFor(difficulty),
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

  /// Cup search depth, capped: the branching factor is huge AND each face-down
  /// move fans out into a chance node, so deep plies explode. Iterative
  /// deepening inside the search means a shallower-than-cap result is still used
  /// when the time budget runs out.
  static const int _maxDepth = 3;

  static int _depthFor(BotDifficulty d) => min(d.settings.depth, _maxDepth);

  /// Wall-clock budget for the isolate search (ms). Iterative deepening returns
  /// the deepest fully-completed depth within this window, so the bot never
  /// hangs even in a chaotic full-of-covers opening.
  static int _budgetFor(BotDifficulty d) {
    switch (d) {
      case BotDifficulty.veryEasy:
        return 300;
      case BotDifficulty.easy:
        return 600;
      case BotDifficulty.medium:
        return 1000;
      case BotDifficulty.hard:
        return 1500;
      case BotDifficulty.veryHard:
        return 2000;
    }
  }
}

/// Top-level isolate entry point (must be a top-level/static function for
/// [compute]). Rebuilds a cheat-safe search position from the inputs: the
/// visible board + which squares are face-down + the per-colour identity bag
/// (`M0` minus everything already revealed on board). The true identities of
/// the face-down squares stay unknown to the search, exactly as for a human.
String? _runCupSearch(_CupSearchInput input) {
  final board = Board.fromFen(input.fen);
  final parts = input.fen.split(' ');
  final turn = (parts.length > 1 && parts[1] == 'b')
      ? PieceColor.black
      : PieceColor.red;

  final hidden = <Position>{};
  for (final idx in input.hidden) {
    hidden.add(Position(idx ~/ Board.cols, idx % Board.cols));
  }

  final root = _CupPosition(
    board: board,
    hidden: hidden,
    redBag: _initialBag(board, hidden, PieceColor.red),
    blackBag: _initialBag(board, hidden, PieceColor.black),
    turn: turn,
  );

  final search = _CupExpectiminimax(
    maxDepth: input.depth,
    timeBudgetMs: input.timeBudgetMs,
    seed: input.seed,
  );
  final best = search.choose(
    root,
    randomChance: input.randomChance,
    suboptimalChance: input.suboptimalChance,
  );
  return best?.toUci();
}

/// Counts of the 15 non-general pieces one side starts with, indexed by
/// [PieceType.index]. This is the full bag of hidden identities at game start.
List<int> _m0Bag() {
  final bag = List<int>.filled(PieceType.values.length, 0);
  bag[PieceType.chariot.index] = 2;
  bag[PieceType.horse.index] = 2;
  bag[PieceType.cannon.index] = 2;
  bag[PieceType.advisor.index] = 2;
  bag[PieceType.elephant.index] = 2;
  bag[PieceType.soldier.index] = 5;
  return bag;
}

/// Bag of identities still hidden for [color]: `M0` minus every revealed
/// (face-up, non-general) piece of that colour currently on the board. A
/// face-down square keeps its identity in the bag (that is the whole point);
/// only a revealed piece subtracts. Captured-while-face-down pieces can't be
/// subtracted (their identity was never seen) so the bag may slightly exceed
/// the live face-down count — a harmless over-estimate for a no-history bot.
List<int> _initialBag(Board board, Set<Position> hidden, PieceColor color) {
  final bag = _m0Bag();
  for (final (pos, piece) in board.occupied()) {
    if (piece.color != color) continue;
    if (piece.type == PieceType.general) continue;
    if (hidden.contains(pos)) continue; // still face-down → stays in the bag
    final i = piece.type.index;
    if (bag[i] > 0) bag[i]--;
  }
  return bag;
}

class _CupSearchInput {
  final String fen;
  final List<int> hidden;
  final int depth;
  final int timeBudgetMs;
  final double randomChance;
  final double suboptimalChance;
  final int seed;

  const _CupSearchInput({
    required this.fen,
    required this.hidden,
    required this.depth,
    required this.timeBudgetMs,
    required this.randomChance,
    required this.suboptimalChance,
    required this.seed,
  });
}

/// Immutable-ish search position. [board] holds covers on face-down squares and
/// true pieces on revealed squares; [hidden] is the set of face-down squares;
/// [redBag]/[blackBag] are the per-colour multisets of still-hidden identities
/// (indexed by [PieceType.index]). Children are produced functionally (board +
/// bags copied on write) so the recursive search never has to undo.
class _CupPosition {
  final Board board;
  final Set<Position> hidden;
  final List<int> redBag;
  final List<int> blackBag;
  final PieceColor turn;

  const _CupPosition({
    required this.board,
    required this.hidden,
    required this.redBag,
    required this.blackBag,
    required this.turn,
  });

  List<int> bagOf(PieceColor color) =>
      color == PieceColor.red ? redBag : blackBag;
}

/// Raised when the wall-clock budget is exhausted mid-search; caught at the root
/// so iterative deepening falls back to the last fully-completed depth.
class _TimeUp implements Exception {
  const _TimeUp();
}

/// A root move bundled with its expectiminimax value (Red-positive).
class _ScoredCupMove {
  final Move move;
  final double score;
  const _ScoredCupMove(this.move, this.score);
}

/// Expectiminimax over a [_CupPosition]: MAX for Red, MIN for Black, and a
/// CHANCE node at every reveal (a face-down piece moving). Decision layers use
/// alpha-beta; chance branches are evaluated with a full window because the
/// parent needs the exact expectation (the distinct reveal outcomes are few —
/// at most one per remaining piece type — so this stays cheap).
class _CupExpectiminimax {
  /// Score of an immediate mate; far larger than any material swing.
  static const double mateScore = 1000000;

  /// Fallback expected value of a face-down piece when its bag is somehow empty
  /// (should not happen for a real hidden square): the average of the 15
  /// starting non-general pieces.
  static const double faceDownFallback = 320;

  static const double _inf = 1e18;

  final int maxDepth;
  final int timeBudgetMs;
  final Random _random;
  final Stopwatch _sw = Stopwatch();

  _CupExpectiminimax({
    required this.maxDepth,
    required this.timeBudgetMs,
    int? seed,
  }) : _random = Random(seed);

  /// Pick a move for [root].turn. Returns null only if there is no legal reply.
  Move? choose(
    _CupPosition root, {
    double randomChance = 0,
    double suboptimalChance = 0,
  }) {
    var moves = _legalMoves(root);
    if (moves.isEmpty) return null;

    // Weak tiers occasionally just play a random legal move.
    if (randomChance > 0 && _random.nextDouble() < randomChance) {
      return moves[_random.nextInt(moves.length)];
    }

    _sw
      ..reset()
      ..start();
    moves = _ordered(root, moves);
    // Always have a usable answer even before depth 1 finishes.
    var best = <_ScoredCupMove>[for (final m in moves) _ScoredCupMove(m, 0)];

    for (var depth = 1; depth <= maxDepth; depth++) {
      try {
        final scored = _searchRoot(root, moves, depth);
        best = scored;
        // Search the previous depth's best first next time (better pruning).
        moves = [for (final s in scored) s.move];
      } on _TimeUp {
        break;
      }
      if (_sw.elapsedMilliseconds > timeBudgetMs) break;
    }

    if (suboptimalChance > 0 &&
        best.length > 1 &&
        _random.nextDouble() < suboptimalChance) {
      return best[1].move;
    }
    return best.first.move;
  }

  /// Score every root move with a full window so the ranking is exact (needed
  /// for the suboptimal-move pick), then sort best-first for the mover.
  List<_ScoredCupMove> _searchRoot(
    _CupPosition root,
    List<Move> moves,
    int depth,
  ) {
    final scored = <_ScoredCupMove>[];
    for (final m in moves) {
      scored.add(_ScoredCupMove(m, _moveValue(root, m, depth, -_inf, _inf)));
    }
    final maximizing = root.turn == PieceColor.red;
    scored.sort((a, b) => maximizing
        ? b.score.compareTo(a.score)
        : a.score.compareTo(b.score));
    return scored;
  }

  /// Red-positive value of [pos] searched [depth] more plies.
  double _value(_CupPosition pos, int depth, double alpha, double beta) {
    if (_sw.elapsedMilliseconds > timeBudgetMs) throw const _TimeUp();
    if (depth <= 0) return _eval(pos);

    final moves = _ordered(pos, _legalMoves(pos));
    if (moves.isEmpty) {
      // No legal move in Xiangqi / Cờ Úp is a LOSS for the side to move.
      return pos.turn == PieceColor.red ? -mateScore : mateScore;
    }

    if (pos.turn == PieceColor.red) {
      var value = -_inf;
      for (final m in moves) {
        final v = _moveValue(pos, m, depth, alpha, beta);
        if (v > value) value = v;
        if (value > alpha) alpha = value;
        if (alpha >= beta) break;
      }
      return value;
    } else {
      var value = _inf;
      for (final m in moves) {
        final v = _moveValue(pos, m, depth, alpha, beta);
        if (v < value) value = v;
        if (value < beta) beta = value;
        if (alpha >= beta) break;
      }
      return value;
    }
  }

  /// Value of playing [m] from [pos]. A move OFF a face-down square reveals the
  /// mover, so it is a chance node; any other move is deterministic.
  double _moveValue(
    _CupPosition pos,
    Move m,
    int depth,
    double alpha,
    double beta,
  ) {
    if (pos.hidden.contains(m.from)) {
      return _chanceValue(pos, m, depth);
    }
    final child = _applyRevealedMove(pos, m);
    return _value(child, depth - 1, alpha, beta);
  }

  /// Expectation over the mover's possible revealed identities. Branches over
  /// the distinct types still in the mover's bag, weighted by their remaining
  /// count. Full window inside each branch: the caller needs the exact mean.
  double _chanceValue(_CupPosition pos, Move m, int depth) {
    final bag = pos.bagOf(pos.turn);
    var total = 0;
    for (final c in bag) {
      total += c;
    }
    if (total == 0) {
      // Degenerate (no identity info) — reveal as the cover and carry on.
      final cover = pos.board.at(m.from)!;
      final child = _applyRevealMove(pos, m, cover.type);
      return _value(child, depth - 1, -_inf, _inf);
    }
    var expected = 0.0;
    for (var i = 0; i < bag.length; i++) {
      final count = bag[i];
      if (count == 0) continue;
      final type = PieceType.values[i];
      final child = _applyRevealMove(pos, m, type);
      expected += (count / total) * _value(child, depth - 1, -_inf, _inf);
    }
    return expected;
  }

  /// Child after a deterministic move (mover already revealed, or a general):
  /// the piece keeps its identity; bags are untouched (no reveal). A captured
  /// face-down victim just leaves the hidden set (its identity stays unknown, so
  /// the opponent bag is intentionally left as-is — see [_initialBag]).
  _CupPosition _applyRevealedMove(_CupPosition pos, Move m) {
    final board = pos.board.copy();
    final mover = board.at(m.from)!;
    board.setAt(m.to, mover);
    board.setAt(m.from, null);
    final hidden = pos.hidden.contains(m.to)
        ? ({...pos.hidden}..remove(m.to))
        : pos.hidden;
    return _CupPosition(
      board: board,
      hidden: hidden,
      redBag: pos.redBag,
      blackBag: pos.blackBag,
      turn: pos.turn.opposite,
    );
  }

  /// Child after a face-down mover reveals as [revealType]: the destination now
  /// holds the revealed piece, both endpoints leave the hidden set, and the
  /// mover's bag loses one [revealType].
  _CupPosition _applyRevealMove(_CupPosition pos, Move m, PieceType revealType) {
    final color = pos.turn;
    final board = pos.board.copy();
    board.setAt(m.to, Piece(revealType, color));
    board.setAt(m.from, null);
    final hidden = {...pos.hidden}
      ..remove(m.from)
      ..remove(m.to);
    final redBag = color == PieceColor.red ? [...pos.redBag] : pos.redBag;
    final blackBag = color == PieceColor.black ? [...pos.blackBag] : pos.blackBag;
    final bag = color == PieceColor.red ? redBag : blackBag;
    if (bag[revealType.index] > 0) bag[revealType.index]--;
    return _CupPosition(
      board: board,
      hidden: hidden,
      redBag: redBag,
      blackBag: blackBag,
      turn: color.opposite,
    );
  }

  /// Static evaluation, Red-positive. A revealed piece uses the full material +
  /// piece-square score; a face-down piece is worth the MEAN of its colour's
  /// current bag (its true identity is unknown, but the distribution is).
  double _eval(_CupPosition pos) {
    final redMean = _bagMean(pos.redBag);
    final blackMean = _bagMean(pos.blackBag);
    var score = 0.0;
    for (final (p, piece) in pos.board.occupied()) {
      final double v;
      if (pos.hidden.contains(p)) {
        v = piece.color == PieceColor.red ? redMean : blackMean;
      } else {
        v = Evaluator.pieceScore(piece, p.row, p.col).toDouble();
      }
      score += piece.color == PieceColor.red ? v : -v;
    }
    return score;
  }

  /// Mean value of the identities left in [bag] (the expected worth of one
  /// random face-down piece of that colour).
  double _bagMean(List<int> bag) {
    var total = 0;
    var sum = 0;
    for (var i = 0; i < bag.length; i++) {
      final c = bag[i];
      if (c == 0) continue;
      total += c;
      sum += c * (Evaluator.pieceValue[PieceType.values[i]] ?? 0);
    }
    return total == 0 ? faceDownFallback : sum / total;
  }

  /// All legal moves for [pos].turn (cup move-gen + self-check filter).
  List<Move> _legalMoves(_CupPosition pos) {
    final out = <Move>[];
    for (final (from, piece) in pos.board.occupied()) {
      if (piece.color != pos.turn) continue;
      for (final to in CupRules.pseudoLegalOn(pos.board, pos.hidden, from)) {
        final target = pos.board.at(to);
        if (target != null && target.color == piece.color) continue;
        if (_leavesOwnKingInCheck(pos, from, to)) continue;
        out.add(Move(from: from, to: to, moved: piece, captured: target));
      }
    }
    return out;
  }

  /// Whether moving [from]→[to] leaves [pos].turn's general in check. Cup
  /// legality is identity-independent, so the cover piece stands in for the
  /// (possibly face-down) mover when testing the resulting position.
  bool _leavesOwnKingInCheck(_CupPosition pos, Position from, Position to) {
    final copy = pos.board.copy();
    final mover = copy.at(from)!;
    copy.setAt(to, mover);
    copy.setAt(from, null);
    final hiddenAfter = {...pos.hidden}
      ..remove(from)
      ..remove(to);
    return CupRules.inCheck(copy, hiddenAfter, pos.turn);
  }

  /// Order moves captures-first (MVV-LVA) so alpha-beta prunes earlier. A
  /// face-down victim is valued at the opponent bag mean (expectation).
  List<Move> _ordered(_CupPosition pos, List<Move> moves) {
    moves.sort((a, b) => _moveOrder(pos, b).compareTo(_moveOrder(pos, a)));
    return moves;
  }

  double _moveOrder(_CupPosition pos, Move m) {
    if (m.captured == null) return 0;
    final victim = pos.hidden.contains(m.to)
        ? _bagMean(pos.bagOf(pos.turn.opposite))
        : (Evaluator.pieceValue[m.captured!.type]?.toDouble() ?? 0);
    final attacker = Evaluator.pieceValue[m.moved.type]?.toDouble() ?? 0;
    return victim * 10 - attacker;
  }
}
