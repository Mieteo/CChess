import '../constants/piece_constants.dart';
import 'board.dart';
import 'move.dart';
import 'move_rules.dart';
import 'piece.dart';
import 'position.dart';

/// Top-level Xiangqi (Chinese chess) game state.
///
/// Holds the board, side to move, full move history, and lifecycle status.
/// All move-related methods operate on the local mutable copy — callers
/// should treat the game as a state-machine they drive forward with
/// [makeMove] / [undoMove].
class XiangqiGame {
  Board _board;
  PieceColor _turn;
  GameStatus _status;
  EndReason? _endReason;
  final List<Move> _history;
  int _halfmoveClock; // For 50-move-like rule (Xiangqi uses 60 by tradition).
  int _fullmoveNumber;

  XiangqiGame._(
    this._board,
    this._turn,
    this._status,
    this._history,
    this._halfmoveClock,
    this._fullmoveNumber,
  ) : _endReason = null;

  /// Standard starting position, Red to move.
  factory XiangqiGame.initial() => XiangqiGame._(
        Board.initial(),
        PieceColor.red,
        GameStatus.playing,
        <Move>[],
        0,
        1,
      );

  /// Load a position from FEN. The FEN side-to-move field decides whose turn
  /// it is; if absent we default to Red.
  factory XiangqiGame.fromFen(String fen) {
    final parts = fen.split(' ');
    final board = Board.fromFen(parts[0]);
    PieceColor turn = PieceColor.red;
    if (parts.length > 1) {
      turn = parts[1] == 'b' ? PieceColor.black : PieceColor.red;
    }
    int halfmove = 0;
    int fullmove = 1;
    if (parts.length > 4) halfmove = int.tryParse(parts[4]) ?? 0;
    if (parts.length > 5) fullmove = int.tryParse(parts[5]) ?? 1;
    return XiangqiGame._(
      board,
      turn,
      GameStatus.playing,
      <Move>[],
      halfmove,
      fullmove,
    );
  }

  // ──────────────── public read-only state ────────────────

  Board get board => _board;
  PieceColor get turn => _turn;
  GameStatus get status => _status;
  EndReason? get endReason => _endReason;
  List<Move> get history => List.unmodifiable(_history);
  int get halfmoveClock => _halfmoveClock;
  int get fullmoveNumber => _fullmoveNumber;
  Move? get lastMove => _history.isEmpty ? null : _history.last;

  /// Render the current position as a FEN string (board + side-to-move + dashes
  /// for castling/en-passant which Xiangqi doesn't use + halfmove + fullmove).
  String toFen() {
    final placement = _board.toFenPlacement();
    final side = _turn == PieceColor.red ? 'w' : 'b';
    return '$placement $side - - $_halfmoveClock $_fullmoveNumber';
  }

  // ──────────────── move generation ────────────────

  /// All fully-legal moves for the piece at [from]. Filters pseudo-legal
  /// moves by ensuring the resulting position does not leave the moving
  /// side's general attacked (which includes the flying-general rule).
  List<Position> getValidMoves(Position from) {
    final piece = _board.at(from);
    if (piece == null) return const [];
    if (piece.color != _turn) return const [];

    final candidates = MoveRules.pseudoLegalMoves(_board, from);
    final legal = <Position>[];
    for (final to in candidates) {
      if (_isLegalMove(from, to, piece)) legal.add(to);
    }
    return legal;
  }

  /// True if the (from, to) pair is currently a legal move.
  bool isValidMove(Position from, Position to) {
    if (_status.isOver) return false;
    final piece = _board.at(from);
    if (piece == null || piece.color != _turn) return false;
    final candidates = MoveRules.pseudoLegalMoves(_board, from);
    if (!candidates.contains(to)) return false;
    return _isLegalMove(from, to, piece);
  }

  bool _isLegalMove(Position from, Position to, Piece piece) {
    // Try the move on a copy, then check.
    final copy = _board.copy();
    final captured = copy.at(to);
    copy.setAt(to, piece);
    copy.setAt(from, null);
    if (MoveRules.isInCheck(copy, piece.color)) return false;
    if (MoveRules.areGeneralsFacing(copy)) return false;
    // captured used only for clarity; no further checks needed.
    return captured == null || captured.color != piece.color;
  }

  /// Apply the given move, advancing the game state. Throws if illegal.
  Move makeMove(Position from, Position to) {
    if (_status.isOver) {
      throw StateError('Game is over (${_status.name})');
    }
    final piece = _board.at(from);
    if (piece == null) {
      throw ArgumentError('No piece at $from');
    }
    if (piece.color != _turn) {
      throw ArgumentError(
        'It is ${_turn.name}\'s turn but piece is ${piece.color.name}',
      );
    }
    if (!isValidMove(from, to)) {
      throw ArgumentError('Illegal move: $from → $to');
    }

    final captured = _board.at(to);
    final move = Move(
      from: from,
      to: to,
      moved: piece,
      captured: captured,
    );

    _board.setAt(to, piece);
    _board.setAt(from, null);
    _history.add(move);

    if (captured != null || piece.type == PieceType.soldier) {
      _halfmoveClock = 0;
    } else {
      _halfmoveClock++;
    }
    if (_turn == PieceColor.black) _fullmoveNumber++;
    _turn = _turn.opposite;

    _refreshStatus();
    return move;
  }

  /// Revert the last move. Returns it, or null if there was no move to undo.
  Move? undoMove() {
    if (_history.isEmpty) return null;
    final last = _history.removeLast();

    _board.setAt(last.from, last.moved);
    _board.setAt(last.to, last.captured);

    if (_turn == PieceColor.red) _fullmoveNumber--;
    _turn = _turn.opposite;
    // halfmove clock is not perfectly restored — we accept the imprecision
    // here, since callers that care should snapshot before makeMove.
    if (_halfmoveClock > 0) _halfmoveClock--;

    _status = GameStatus.playing;
    _endReason = null;
    return last;
  }

  void _refreshStatus() {
    final color = _turn;
    final inCheck = MoveRules.isInCheck(_board, color);
    final hasAnyMove = _sideHasAnyLegalMove(color);

    if (!hasAnyMove) {
      // Stalemate is a LOSS for the side to move in Xiangqi.
      _status = color == PieceColor.red
          ? GameStatus.blackWin
          : GameStatus.redWin;
      _endReason = inCheck ? EndReason.checkmate : EndReason.stalemate;
    } else if (_halfmoveClock >= 120) {
      _status = GameStatus.draw;
      _endReason = EndReason.drawAgreed;
    }
  }

  bool _sideHasAnyLegalMove(PieceColor color) {
    for (final (pos, piece) in _board.occupied()) {
      if (piece.color != color) continue;
      final candidates = MoveRules.pseudoLegalMoves(_board, pos);
      for (final to in candidates) {
        if (_isLegalMove(pos, to, piece)) return true;
      }
    }
    return false;
  }

  // ──────────────── queries ────────────────

  bool isInCheck(PieceColor color) => MoveRules.isInCheck(_board, color);

  bool isCheckmate(PieceColor color) =>
      MoveRules.isInCheck(_board, color) && !_sideHasAnyLegalMove(color);

  bool isStalemate(PieceColor color) =>
      !MoveRules.isInCheck(_board, color) && !_sideHasAnyLegalMove(color);

  bool areGeneralsFacing() => MoveRules.areGeneralsFacing(_board);

  /// Mark the game as resigned by [resigningColor]. Opposite color wins.
  void resign(PieceColor resigningColor) {
    if (_status.isOver) return;
    _status = resigningColor == PieceColor.red
        ? GameStatus.blackWin
        : GameStatus.redWin;
    _endReason = EndReason.resignation;
  }

  /// Force the game to a draw by mutual agreement.
  void agreeDraw() {
    if (_status.isOver) return;
    _status = GameStatus.draw;
    _endReason = EndReason.drawAgreed;
  }
}
