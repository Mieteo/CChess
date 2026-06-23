import '../constants/piece_constants.dart';
import 'board.dart';
import 'move.dart';
import 'position.dart';

/// Minimal game API used by the board/controller layer.
///
/// Standard Xiangqi and Co Up share the same UI surface but differ in how a
/// move mutates piece identity, so presentation talks to this contract instead
/// of a concrete game class.
abstract interface class ChessGameSession {
  Board get board;
  PieceColor get turn;
  GameStatus get status;
  EndReason? get endReason;
  List<Move> get history;
  int get halfmoveClock;
  int get fullmoveNumber;
  Move? get lastMove;

  String toFen();
  List<Position> getValidMoves(Position from);
  bool isValidMove(Position from, Position to);
  Move makeMove(Position from, Position to);
  Move? undoMove();
  bool isInCheck(PieceColor color);
  bool isCheckmate(PieceColor color);
  bool isStalemate(PieceColor color);
  bool areGeneralsFacing();
  void resign(PieceColor resigningColor);
  void agreeDraw();
}
