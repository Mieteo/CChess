import 'dart:math';
import 'dart:typed_data';

import '../../constants/piece_constants.dart';
import '../board.dart';
import '../move.dart';
import '../move_rules.dart';
import '../piece.dart';
import '../position.dart';
import '../xiangqi_game.dart';
import 'evaluator.dart';

// ─────────────────────── Zobrist keys ────────────────────────────────────────

/// Pre-computed Zobrist random numbers for incremental hashing.
///
/// Layout: `table[pieceKind * 90 + square]` where
///   pieceKind = `PieceType.index * 2 + PieceColor.index`   (0..13)
///   square    = `row * 9 + col`                             (0..89)
class _ZobristKeys {
  final List<int> table; // 14 * 90 = 1260 entries
  final int side; // XOR when it is Black's turn

  _ZobristKeys._({required this.table, required this.side});

  factory _ZobristKeys.init() {
    final rng = Random(0xBEEFCAFE); // fixed seed → reproducible across runs
    final table = List<int>.generate(14 * 90, (_) => _rand64(rng));
    final side = _rand64(rng);
    return _ZobristKeys._(table: table, side: side);
  }

  // 64-bit random via four 16-bit chunks (safe on both 64-bit native and web).
  static int _rand64(Random r) {
    final lo = r.nextInt(1 << 16) | (r.nextInt(1 << 16) << 16);
    final hi = r.nextInt(1 << 16) | (r.nextInt(1 << 16) << 16);
    return lo | (hi << 32);
  }
}

// ─────────────────────── TT flag constants ───────────────────────────────────

const int _ttExact = 0; // score is exact
const int _ttLower = 1; // score is a lower bound (fail-high / beta cutoff)
const int _ttUpper = 2; // score is an upper bound (fail-low / alpha cutoff)

// ─────────────────────── Minimax ─────────────────────────────────────────────

/// Pure-Dart Xiangqi search using minimax + alpha-beta pruning.
///
/// The engine is deliberately compact: it operates directly on the mutable
/// [XiangqiGame] / [Board] from the rest of the codebase, taking advantage
/// of the cheap [XiangqiGame.makeMove] / [XiangqiGame.undoMove] pair so we
/// never have to copy the board between plies.
///
/// **Transposition table (TT):** positions are identified by a 64-bit Zobrist
/// hash maintained incrementally as moves are made/undone. The TT is _static_
/// so its contents survive across [Minimax] instances — benefiting iterative-
/// deepening runs where depth-D results guide depth-(D+1) move ordering.
class Minimax {
  /// Static "draw-ish" score for the side to move when no legal moves exist
  /// but the position isn't checkmate (treated as a loss in Xiangqi).
  static const int stalemateScore = -50000;

  /// Score representing an immediate mate. Positive favors the side that
  /// just mated the opponent.
  static const int mateScore = 999999;

  // ──────── Zobrist keys (one per isolate, computed once at first use) ────────
  static final _ZobristKeys _zk = _ZobristKeys.init();

  // ──────── Transposition table ────────────────────────────────────────────
  // Static so the table persists across iterative-deepening iterations that
  // create fresh Minimax instances at each depth level.
  static const int _ttSize = 1 << 18; // 262 144 entries ≈ 4 MB
  static const int _ttMask = _ttSize - 1;

  static final Int64List _ttHashArr = Int64List(_ttSize);
  static final Int32List _ttScoreArr = Int32List(_ttSize);
  static final Uint8List _ttDepthArr = Uint8List(_ttSize);
  static final Uint8List _ttFlagArr = Uint8List(_ttSize);
  // from / to as flat square index (row*9+col); 255 = no best move stored.
  static final Uint8List _ttFromArr =
      Uint8List(_ttSize)..fillRange(0, _ttSize, 255);
  static final Uint8List _ttToArr =
      Uint8List(_ttSize)..fillRange(0, _ttSize, 255);

  // ──────── Instance state ──────────────────────────────────────────────────
  final int depth;
  final Random _random;

  /// Running Zobrist hash of the current board position; updated incrementally
  /// as moves are made and undone during search.
  int _currentHash = 0;

  Minimax({required this.depth, int? seed}) : _random = Random(seed);

  // ─────────────────────────────────────────────────────────────────────────
  // Public API
  // ─────────────────────────────────────────────────────────────────────────

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
    _currentHash = _computeHash(game);
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

  // ─────────────────────────────────────────────────────────────────────────
  // Zobrist hashing helpers
  // ─────────────────────────────────────────────────────────────────────────

  static int _pieceKind(Piece p) => p.type.index * 2 + p.color.index;
  static int _squareIdx(Position pos) => pos.row * 9 + pos.col;

  int _computeHash(XiangqiGame game) {
    int h = 0;
    for (final (pos, piece) in game.board.occupied()) {
      h ^= _zk.table[_pieceKind(piece) * 90 + _squareIdx(pos)];
    }
    if (game.turn == PieceColor.black) h ^= _zk.side;
    return h;
  }

  /// XOR the hash with all position deltas caused by [m]. Because XOR is its
  /// own inverse, calling this method twice in succession (make + undo) restores
  /// the original hash.
  void _hashApplyMove(Move m) {
    _currentHash ^= _zk.table[_pieceKind(m.moved) * 90 + _squareIdx(m.from)];
    _currentHash ^= _zk.table[_pieceKind(m.moved) * 90 + _squareIdx(m.to)];
    if (m.captured != null) {
      _currentHash ^=
          _zk.table[_pieceKind(m.captured!) * 90 + _squareIdx(m.to)];
    }
    _currentHash ^= _zk.side; // flip side-to-move bit
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Transposition table operations
  // ─────────────────────────────────────────────────────────────────────────

  /// Probe the TT for the current position. Returns a usable score if the
  /// stored entry is deep enough and the flag allows a cutoff; null otherwise.
  int? _ttProbe(int remainingDepth, int alpha, int beta) {
    final idx = _currentHash & _ttMask;
    if (_ttHashArr[idx] != _currentHash) return null; // miss or hash collision
    if (_ttDepthArr[idx] < remainingDepth) return null; // entry too shallow
    final score = _ttScoreArr[idx];
    final flag = _ttFlagArr[idx];
    if (flag == _ttExact) return score;
    if (flag == _ttLower && score >= beta) return score;
    if (flag == _ttUpper && score <= alpha) return score;
    return null;
  }

  void _ttStore(int remainingDepth, int score, int flag, Move? best) {
    final idx = _currentHash & _ttMask;
    _ttHashArr[idx] = _currentHash;
    _ttScoreArr[idx] = score;
    _ttDepthArr[idx] = remainingDepth;
    _ttFlagArr[idx] = flag;
    _ttFromArr[idx] = best != null ? _squareIdx(best.from) : 255;
    _ttToArr[idx] = best != null ? _squareIdx(best.to) : 255;
  }

  /// Return the best move stored in the TT for the current position, or null
  /// if there is no valid entry. Used as the first move tried at each node.
  Move? _ttBestMove(Board board) {
    final idx = _currentHash & _ttMask;
    if (_ttHashArr[idx] != _currentHash) return null;
    final fromIdx = _ttFromArr[idx];
    if (fromIdx == 255) return null;
    final toIdx = _ttToArr[idx];
    final from = Position(fromIdx ~/ 9, fromIdx % 9);
    final to = Position(toIdx ~/ 9, toIdx % 9);
    final moved = board.at(from);
    if (moved == null) return null; // stale entry after board changed
    return Move(from: from, to: to, moved: moved, captured: board.at(to));
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Search
  // ─────────────────────────────────────────────────────────────────────────

  /// Returns the top moves sorted from best→worst for the side to move.
  /// Always returns at least one element (or empty if no legal moves).
  List<ScoredMove> _rankMoves(XiangqiGame game) {
    final color = game.turn;
    final moves = _allLegalMoves(game, color);
    if (moves.isEmpty) return const [];

    final ttBest = _ttBestMove(game.board);
    final scored = <ScoredMove>[];
    final isMaximizing = color == PieceColor.red;
    int alpha = -mateScore * 2;
    int beta = mateScore * 2;

    moves.sort(
        (a, b) => _moveOrderScore(b, ttBest).compareTo(_moveOrderScore(a, ttBest)));

    for (final m in moves) {
      _hashApplyMove(m);
      game.makeMove(m.from, m.to);
      final score = _alphaBeta(game, depth - 1, alpha, beta, !isMaximizing);
      game.undoMove();
      _hashApplyMove(m); // XOR is its own inverse — restores _currentHash

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
    // Leaf node: static evaluation (fast, no TT overhead worth it).
    if (remainingDepth <= 0) {
      return Evaluator.evaluate(game.board);
    }

    // TT probe — may return immediately with a usable bound.
    final ttScore = _ttProbe(remainingDepth, alpha, beta);
    if (ttScore != null) return ttScore;

    final color = game.turn;
    final moves = _allLegalMoves(game, color);
    if (moves.isEmpty) {
      // No legal move in Xiangqi = loss for the side to move.
      return color == PieceColor.red ? -mateScore : mateScore;
    }

    // Move ordering: TT best move first, then MVV-LVA captures, then quiet.
    final ttBest = _ttBestMove(game.board);
    moves.sort(
        (a, b) => _moveOrderScore(b, ttBest).compareTo(_moveOrderScore(a, ttBest)));

    final origAlpha = alpha;
    final origBeta = beta;
    Move? bestMove;

    if (maximizing) {
      int value = -mateScore * 2;
      for (final m in moves) {
        _hashApplyMove(m);
        game.makeMove(m.from, m.to);
        final score = _alphaBeta(game, remainingDepth - 1, alpha, beta, false);
        game.undoMove();
        _hashApplyMove(m);
        if (score > value) {
          value = score;
          bestMove = m;
        }
        if (value > alpha) alpha = value;
        if (alpha >= beta) break; // beta cutoff
      }
      // Determine bound type: fail-high → lower bound, fail-low → upper bound, else exact.
      final flag = value >= origBeta
          ? _ttLower
          : value <= origAlpha
              ? _ttUpper
              : _ttExact;
      _ttStore(remainingDepth, value, flag, bestMove);
      return value;
    } else {
      int value = mateScore * 2;
      for (final m in moves) {
        _hashApplyMove(m);
        game.makeMove(m.from, m.to);
        final score = _alphaBeta(game, remainingDepth - 1, alpha, beta, true);
        game.undoMove();
        _hashApplyMove(m);
        if (score < value) {
          value = score;
          bestMove = m;
        }
        if (value < beta) beta = value;
        if (alpha >= beta) break; // alpha cutoff
      }
      final flag = value >= origBeta
          ? _ttLower
          : value <= origAlpha
              ? _ttUpper
              : _ttExact;
      _ttStore(remainingDepth, value, flag, bestMove);
      return value;
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Move ordering
  // ─────────────────────────────────────────────────────────────────────────

  /// Higher score = try earlier.
  /// Priority: TT best move > MVV-LVA captures > quiet moves.
  int _moveOrderScore(Move m, Move? ttBest) {
    if (ttBest != null && m.from == ttBest.from && m.to == ttBest.to) {
      return 20000; // try TT best move first
    }
    if (m.captured == null) return 0;
    // MVV-LVA: big victim, small attacker → higher score.
    final v = Evaluator.pieceValue[m.captured!.type] ?? 0;
    final a = Evaluator.pieceValue[m.moved.type] ?? 0;
    return v * 10 - a;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Legal move generation
  // ─────────────────────────────────────────────────────────────────────────

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
