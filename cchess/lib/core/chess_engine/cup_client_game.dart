import '../constants/piece_constants.dart';
import 'board.dart';
import 'chess_game_session.dart';
import 'cup_rules.dart';
import 'move.dart';
import 'move_rules.dart';
import 'piece.dart';
import 'position.dart';

/// Online client view of a Cờ Úp game.
///
/// Unlike [XiangqiCupGame] (which owns every hidden identity for offline play),
/// this session NEVER knows what is under a face-down cover — exactly like the
/// human across the board. It tracks only:
///   * [board]            — covers on face-down squares, true pieces on revealed
///     ones (this is the server's cheat-safe public view);
///   * [hiddenPositions]  — which squares are still face-down.
///
/// The server is authoritative: it sends a `reveal` ({revealed, captured}) with
/// every move so this client can flip the right cover. Because cup move LEGALITY
/// depends only on covers + revealed pieces (see [CupRules]) — never on a hidden
/// identity — the client can still validate and optimistically apply the local
/// player's own moves, then correct the revealed identity when the ack arrives.
class CupClientGame implements ChessGameSession {
  Board _board;
  PieceColor _turn;
  GameStatus _status;
  EndReason? _endReason;
  final Set<Position> _hidden;
  final List<Move> _history;
  final List<_Snapshot> _undoStack;

  CupClientGame._(
    this._board,
    this._turn,
    this._status,
    this._hidden,
    this._history,
  ) : _endReason = null,
      _undoStack = <_Snapshot>[];

  /// Fresh game: standard opening, all non-general pieces face-down, Red to move.
  factory CupClientGame.initial() {
    final board = Board.initial();
    final hidden = <Position>{};
    for (final (pos, piece) in board.occupied()) {
      if (piece.type != PieceType.general) hidden.add(pos);
    }
    return CupClientGame._(
      board,
      PieceColor.red,
      GameStatus.playing,
      hidden,
      <Move>[],
    );
  }

  /// Rebuild from the server's cheat-safe public snapshot (reconnect / spectate).
  /// [fen] places covers on face-down squares and true pieces on revealed ones;
  /// [hiddenIndices] are `row * Board.cols + col` indices of the face-down squares.
  factory CupClientGame.fromSnapshot({
    required String fen,
    required Iterable<int> hiddenIndices,
    required PieceColor turn,
  }) {
    final board = Board.fromFen(fen);
    final hidden = <Position>{
      for (final i in hiddenIndices)
        Position(i ~/ Board.cols, i % Board.cols),
    };
    return CupClientGame._(board, turn, GameStatus.playing, hidden, <Move>[]);
  }

  /// Build a [Piece] from a Xiangqi FEN char (uppercase = red), or null.
  static Piece? pieceFromFenChar(String? ch) {
    if (ch == null || ch.isEmpty) return null;
    final parsed = PieceTypeX.fromFenLetter(ch);
    if (parsed == null) return null;
    final (type, color) = parsed;
    return Piece(type, color);
  }

  @override
  Board get board => _board;
  @override
  PieceColor get turn => _turn;
  @override
  GameStatus get status => _status;
  @override
  EndReason? get endReason => _endReason;
  @override
  List<Move> get history => List.unmodifiable(_history);
  @override
  int get halfmoveClock => 0;
  @override
  int get fullmoveNumber => (_history.length ~/ 2) + 1;
  @override
  Move? get lastMove => _history.isEmpty ? null : _history.last;

  Set<Position> get hiddenPositions => Set.unmodifiable(_hidden);
  int get hiddenCount => _hidden.length;
  bool isHidden(Position pos) => _hidden.contains(pos);

  @override
  String toFen() {
    final side = _turn == PieceColor.red ? 'w' : 'b';
    return '${_board.toFenPlacement()} $side - - 0 $fullmoveNumber';
  }

  @override
  List<Position> getValidMoves(Position from) {
    final piece = _board.at(from);
    if (piece == null || piece.color != _turn) return const [];
    final out = <Position>[];
    for (final to in CupRules.pseudoLegalOn(_board, _hidden, from)) {
      if (_isLegal(from, to, piece)) out.add(to);
    }
    return out;
  }

  @override
  bool isValidMove(Position from, Position to) {
    if (_status.isOver) return false;
    final piece = _board.at(from);
    if (piece == null || piece.color != _turn) return false;
    if (!CupRules.pseudoLegalOn(_board, _hidden, from).contains(to)) {
      return false;
    }
    return _isLegal(from, to, piece);
  }

  /// Self-check test using the COVER as a stand-in for an unknown identity. Only
  /// occupancy matters for whether the mover's own king is left in check (the
  /// mover is own-colour, so it only ever blocks rays), so this matches the
  /// server's full-information result without knowing the hidden identity.
  bool _isLegal(Position from, Position to, Piece coverPiece) {
    final target = _board.at(to);
    if (target != null && target.color == coverPiece.color) return false;
    final copy = _board.copy();
    copy.setAt(to, coverPiece);
    copy.setAt(from, null);
    final hiddenAfter = _hidden.toSet()
      ..remove(from)
      ..remove(to);
    return !CupRules.inCheck(copy, hiddenAfter, coverPiece.color);
  }

  /// Optimistic local apply of the LOCAL player's own move, before the server's
  /// reveal arrives. The moved piece keeps its current face; if it was face-down
  /// the destination stays face-down (blank) until [applyReveal] flips it — so we
  /// never flash the wrong cover. Throws if the move is illegal.
  @override
  Move makeMove(Position from, Position to) {
    if (_status.isOver) throw StateError('Game is over (${_status.name})');
    final piece = _board.at(from);
    if (piece == null) throw ArgumentError('No piece at $from');
    if (piece.color != _turn) {
      throw ArgumentError(
        "It is ${_turn.name}'s turn but piece is ${piece.color.name}",
      );
    }
    if (!isValidMove(from, to)) {
      throw ArgumentError('Illegal move: $from -> $to');
    }

    _undoStack.add(_snapshot());
    final wasHidden = _hidden.contains(from);
    final captured = _board.at(to);
    final move = Move(from: from, to: to, moved: piece, captured: captured);
    _board.setAt(to, piece);
    _board.setAt(from, null);
    _hidden.remove(from);
    _hidden.remove(to);
    // Keep the destination face-down until the server reveals the true identity,
    // so a face-down mover slides as a blank disc and only then flips.
    if (wasHidden) _hidden.add(to);
    _history.add(move);
    _turn = _turn.opposite;
    return move;
  }

  /// Flip the just-moved local piece to its true identity once the server's
  /// `move-ack` reveal arrives (no-op when the piece was already face-up).
  void applyReveal(Position to, Piece revealed) {
    _board.setAt(to, revealed);
    _hidden.remove(to);
  }

  /// Authoritative apply of the OPPONENT's move from an `opponent-move` event.
  /// [revealed] is the true identity now standing on [to]; [captured] is what it
  /// took (kept only for the move record).
  Move applyServerMove(
    Position from,
    Position to, {
    required Piece revealed,
    Piece? captured,
  }) {
    final captured0 = captured ?? _board.at(to);
    final move = Move(from: from, to: to, moved: revealed, captured: captured0);
    _board.setAt(to, revealed);
    _board.setAt(from, null);
    _hidden.remove(from);
    _hidden.remove(to);
    _history.add(move);
    _turn = _turn.opposite;
    return move;
  }

  @override
  Move? undoMove() {
    if (_undoStack.isEmpty) return null;
    final undone = _history.isEmpty ? null : _history.last;
    final snap = _undoStack.removeLast();
    _board = snap.board;
    _turn = snap.turn;
    _status = snap.status;
    _endReason = snap.endReason;
    _hidden
      ..clear()
      ..addAll(snap.hidden);
    _history
      ..clear()
      ..addAll(snap.history);
    return undone;
  }

  @override
  bool isInCheck(PieceColor color) => CupRules.inCheck(_board, _hidden, color);

  // Game-over detection is server-authoritative for online cup; the client never
  // declares checkmate / stalemate on its own.
  @override
  bool isCheckmate(PieceColor color) => false;
  @override
  bool isStalemate(PieceColor color) => false;
  @override
  bool areGeneralsFacing() => MoveRules.areGeneralsFacing(_board);

  @override
  void resign(PieceColor resigningColor) {
    if (_status.isOver) return;
    _status = resigningColor == PieceColor.red
        ? GameStatus.blackWin
        : GameStatus.redWin;
    _endReason = EndReason.resignation;
  }

  @override
  void agreeDraw() {
    if (_status.isOver) return;
    _status = GameStatus.draw;
    _endReason = EndReason.drawAgreed;
  }

  _Snapshot _snapshot() => _Snapshot(
    board: _board.copy(),
    turn: _turn,
    status: _status,
    endReason: _endReason,
    hidden: _hidden.toSet(),
    history: List<Move>.from(_history),
  );
}

class _Snapshot {
  final Board board;
  final PieceColor turn;
  final GameStatus status;
  final EndReason? endReason;
  final Set<Position> hidden;
  final List<Move> history;

  const _Snapshot({
    required this.board,
    required this.turn,
    required this.status,
    required this.endReason,
    required this.hidden,
    required this.history,
  });
}
