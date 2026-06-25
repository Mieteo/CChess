import 'dart:math';

import '../constants/piece_constants.dart';
import 'board.dart';
import 'chess_game_session.dart';
import 'cup_rules.dart';
import 'move.dart';
import 'move_rules.dart';
import 'piece.dart';
import 'position.dart';

/// Co Up / Xiangqi blind variant.
///
/// Non-general pieces start face-down. A face-down piece moves once according to
/// its visible cover piece, then reveals its shuffled true identity on the
/// destination square. Generals stay fixed and face-up.
class XiangqiCupGame implements ChessGameSession {
  Board _board;
  PieceColor _turn;
  GameStatus _status;
  EndReason? _endReason;
  final List<Move> _history;
  int _halfmoveClock;
  int _fullmoveNumber;
  final Map<Position, Piece> _hiddenAssignments;
  final List<_CupSnapshot> _undoStack;

  XiangqiCupGame._(
    this._board,
    this._turn,
    this._status,
    this._history,
    this._halfmoveClock,
    this._fullmoveNumber,
    this._hiddenAssignments,
    this._undoStack,
  ) : _endReason = null;

  /// Test/debug hook for focused rule fixtures. Production play should use
  /// [XiangqiCupGame.initial] so hidden assignments are shuffled normally.
  factory XiangqiCupGame.debug({
    required Board board,
    PieceColor turn = PieceColor.red,
    GameStatus status = GameStatus.playing,
    List<Move> history = const <Move>[],
    int halfmoveClock = 0,
    int fullmoveNumber = 1,
    Map<Position, Piece> hiddenAssignments = const <Position, Piece>{},
  }) {
    return XiangqiCupGame._(
      board,
      turn,
      status,
      List<Move>.from(history),
      halfmoveClock,
      fullmoveNumber,
      Map<Position, Piece>.from(hiddenAssignments),
      <_CupSnapshot>[],
    );
  }

  factory XiangqiCupGame.initial({int? seed}) {
    final board = Board.initial();
    final hidden = _randomizeHiddenPieces(board, seed: seed);
    return XiangqiCupGame._(
      board,
      PieceColor.red,
      GameStatus.playing,
      <Move>[],
      0,
      1,
      hidden,
      <_CupSnapshot>[],
    );
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
  int get halfmoveClock => _halfmoveClock;
  @override
  int get fullmoveNumber => _fullmoveNumber;
  @override
  Move? get lastMove => _history.isEmpty ? null : _history.last;

  Set<Position> get hiddenPositions =>
      Set.unmodifiable(_hiddenAssignments.keys);
  int get hiddenCount => _hiddenAssignments.length;
  bool isHidden(Position pos) => _hiddenAssignments.containsKey(pos);

  /// Test/debug hook for verifying deterministic shuffles. UI should not use it.
  Piece? debugHiddenPieceAt(Position pos) => _hiddenAssignments[pos];

  @override
  String toFen() {
    final placement = _board.toFenPlacement();
    final side = _turn == PieceColor.red ? 'w' : 'b';
    return '$placement $side - - $_halfmoveClock $_fullmoveNumber';
  }

  @override
  List<Position> getValidMoves(Position from) {
    final piece = _board.at(from);
    if (piece == null) return const [];
    if (piece.color != _turn) return const [];

    final candidates = _cupPseudoLegal(from);
    final legal = <Position>[];
    for (final to in candidates) {
      if (_isLegalMove(from, to, piece)) legal.add(to);
    }
    return legal;
  }

  @override
  bool isValidMove(Position from, Position to) {
    if (_status.isOver) return false;
    final piece = _board.at(from);
    if (piece == null || piece.color != _turn) return false;
    final candidates = _cupPseudoLegal(from);
    if (!candidates.contains(to)) return false;
    return _isLegalMove(from, to, piece);
  }

  bool _isLegalMove(Position from, Position to, Piece coverPiece) {
    final target = _board.at(to);
    if (target != null && target.color == coverPiece.color) return false;

    final movedAfterReveal = _hiddenAssignments[from] ?? coverPiece;
    final copy = _board.copy();
    copy.setAt(to, movedAfterReveal);
    copy.setAt(from, null);
    // After the move `from` is empty and `to` holds the now-revealed piece, so
    // neither is face-down when we test the resulting position for check.
    final hiddenAfter = _hiddenAssignments.keys.toSet()
      ..remove(from)
      ..remove(to);
    if (CupRules.inCheck(copy, hiddenAfter, coverPiece.color)) return false;
    return true;
  }

  @override
  Move makeMove(Position from, Position to) {
    if (_status.isOver) {
      throw StateError('Game is over (${_status.name})');
    }
    final coverPiece = _board.at(from);
    if (coverPiece == null) {
      throw ArgumentError('No piece at $from');
    }
    if (coverPiece.color != _turn) {
      throw ArgumentError(
        'It is ${_turn.name}\'s turn but piece is ${coverPiece.color.name}',
      );
    }
    if (!isValidMove(from, to)) {
      throw ArgumentError('Illegal move: $from -> $to');
    }

    _undoStack.add(_snapshot());

    final moved = _hiddenAssignments.remove(from) ?? coverPiece;
    final captured = _hiddenAssignments.remove(to) ?? _board.at(to);
    final move = Move(from: from, to: to, moved: moved, captured: captured);

    _board.setAt(to, moved);
    _board.setAt(from, null);
    _history.add(move);

    if (captured != null || moved.type == PieceType.soldier) {
      _halfmoveClock = 0;
    } else {
      _halfmoveClock++;
    }
    if (_turn == PieceColor.black) _fullmoveNumber++;
    _turn = _turn.opposite;

    _refreshStatus();
    return move;
  }

  @override
  Move? undoMove() {
    if (_history.isEmpty || _undoStack.isEmpty) return null;
    final undone = _history.last;
    final snap = _undoStack.removeLast();
    _board = snap.board;
    _turn = snap.turn;
    _status = snap.status;
    _endReason = snap.endReason;
    _history
      ..clear()
      ..addAll(snap.history);
    _halfmoveClock = snap.halfmoveClock;
    _fullmoveNumber = snap.fullmoveNumber;
    _hiddenAssignments
      ..clear()
      ..addAll(snap.hiddenAssignments);
    return undone;
  }

  void _refreshStatus() {
    final color = _turn;
    final inCheck = _inCheckNow(color);
    final hasAnyMove = _sideHasAnyLegalMove(color);

    if (!hasAnyMove) {
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
      final candidates = _cupPseudoLegal(pos);
      for (final to in candidates) {
        if (_isLegalMove(pos, to, piece)) return true;
      }
    }
    return false;
  }

  @override
  bool isInCheck(PieceColor color) => _inCheckNow(color);

  @override
  bool isCheckmate(PieceColor color) =>
      _inCheckNow(color) && !_sideHasAnyLegalMove(color);

  @override
  bool isStalemate(PieceColor color) =>
      !_inCheckNow(color) && !_sideHasAnyLegalMove(color);

  @override
  bool areGeneralsFacing() => MoveRules.areGeneralsFacing(_board);

  bool _inCheckNow(PieceColor color) =>
      CupRules.inCheck(_board, _hiddenAssignments.keys.toSet(), color);

  /// Cờ úp move generation — delegated to the shared [CupRules] so the offline
  /// (full-information) and online (cover-only) engines never diverge. A
  /// FACE-DOWN piece moves by its cover; a REVEALED Sĩ/Tượng roams the whole
  /// board on its diagonal pattern.
  List<Position> _cupPseudoLegal(Position from) =>
      CupRules.pseudoLegalOn(_board, _hiddenAssignments.keys.toSet(), from);

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

  _CupSnapshot _snapshot() => _CupSnapshot(
    board: _board.copy(),
    turn: _turn,
    status: _status,
    endReason: _endReason,
    history: List<Move>.from(_history),
    halfmoveClock: _halfmoveClock,
    fullmoveNumber: _fullmoveNumber,
    hiddenAssignments: Map<Position, Piece>.from(_hiddenAssignments),
  );

  static Map<Position, Piece> _randomizeHiddenPieces(Board board, {int? seed}) {
    final random = Random(seed);
    final hidden = <Position, Piece>{};
    for (final color in PieceColor.values) {
      final entries = board.occupied().where((entry) {
        final (_, piece) = entry;
        return piece.color == color && piece.type != PieceType.general;
      }).toList()..sort((a, b) => a.$1.compareTo(b.$1));
      final pieces = entries.map((entry) => entry.$2).toList()..shuffle(random);
      for (var i = 0; i < entries.length; i++) {
        hidden[entries[i].$1] = pieces[i];
      }
    }
    return hidden;
  }
}

class _CupSnapshot {
  final Board board;
  final PieceColor turn;
  final GameStatus status;
  final EndReason? endReason;
  final List<Move> history;
  final int halfmoveClock;
  final int fullmoveNumber;
  final Map<Position, Piece> hiddenAssignments;

  const _CupSnapshot({
    required this.board,
    required this.turn,
    required this.status,
    required this.endReason,
    required this.history,
    required this.halfmoveClock,
    required this.fullmoveNumber,
    required this.hiddenAssignments,
  });
}
