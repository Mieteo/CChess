import 'package:equatable/equatable.dart';

import 'piece.dart';
import 'position.dart';

/// A single move on the Xiangqi board.
///
/// `captured` is non-null if the move ate an opposing piece; we keep it on
/// the Move so we can undo without re-deriving from board history.
class Move extends Equatable {
  final Position from;
  final Position to;
  final Piece moved;
  final Piece? captured;

  const Move({
    required this.from,
    required this.to,
    required this.moved,
    this.captured,
  });

  bool get isCapture => captured != null;

  /// UCI-like coordinate notation used for transport / FEN move history.
  /// Column letter a..i, then row digit 0..9 measured from Red's bottom rank.
  String toUci() {
    String fileLetter(int col) => String.fromCharCode('a'.codeUnitAt(0) + col);
    // Row 9 is Red's bottom rank (rank 0 in UCI conventions).
    int rankDigit(int row) => 9 - row;
    return '${fileLetter(from.col)}${rankDigit(from.row)}'
        '${fileLetter(to.col)}${rankDigit(to.row)}';
  }

  /// Parse a UCI string like "e0e1" → from/to. The board state is needed to
  /// know what was moved/captured, so this only returns the coordinates.
  static (Position from, Position to)? parseUciCoords(String uci) {
    if (uci.length < 4) return null;
    final fromCol = uci.codeUnitAt(0) - 'a'.codeUnitAt(0);
    final fromRank = int.tryParse(uci[1]);
    final toCol = uci.codeUnitAt(2) - 'a'.codeUnitAt(0);
    final toRank = int.tryParse(uci[3]);
    if (fromRank == null || toRank == null) return null;
    final from = Position(9 - fromRank, fromCol);
    final to = Position(9 - toRank, toCol);
    if (!from.isValid || !to.isValid) return null;
    return (from, to);
  }

  @override
  String toString() => toUci();

  @override
  List<Object?> get props => [from, to, moved, captured];
}

/// Lifecycle status of a Xiangqi game.
enum GameStatus {
  /// Game in progress.
  playing,

  /// Red won by checkmate / resignation / etc.
  redWin,

  /// Black won.
  blackWin,

  /// Draw (stalemate, agreed, perpetual chase, repetition, etc.).
  draw,
}

extension GameStatusX on GameStatus {
  bool get isOver => this != GameStatus.playing;
}

/// Why the game ended.
enum EndReason {
  checkmate,
  stalemate,
  resignation,
  timeout,
  drawAgreed,
  repetition,
}
