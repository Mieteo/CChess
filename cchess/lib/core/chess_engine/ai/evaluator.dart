import '../../constants/piece_constants.dart';
import '../board.dart';
import '../piece.dart';

/// Static position evaluator returning a score in centipawns, positive when
/// Red is winning.
class Evaluator {
  Evaluator._();

  // ──────────────── Piece values (centipawns) ────────────────
  static const Map<PieceType, int> pieceValue = {
    PieceType.general: 10000,
    PieceType.chariot: 900,
    PieceType.cannon: 450,
    PieceType.horse: 400,
    PieceType.elephant: 200,
    PieceType.advisor: 200,
    PieceType.soldier: 100,
  };

  // ──────────────── Piece-Square Tables (PSQT), red point of view ────────────────
  // Each is 10 rows × 9 cols. Row 0 = top (Black side). Row 9 = bottom (Red side).
  // Tables are written from Red's perspective; for Black we mirror vertically.
  //
  // Values are small bonuses (centipawns) layered on top of piece value.

  static const List<List<int>> _soldierPst = [
    [0, 3, 6, 9, 12, 9, 6, 3, 0],
    [18, 36, 56, 80, 120, 80, 56, 36, 18],
    [14, 26, 42, 60, 80, 60, 42, 26, 14],
    [10, 20, 30, 34, 40, 34, 30, 20, 10],
    [6, 12, 18, 18, 20, 18, 18, 12, 6],
    [2, 0, 8, 0, 8, 0, 8, 0, 2],
    [0, 0, -2, 0, 4, 0, -2, 0, 0],
    [0, 0, 0, 0, 0, 0, 0, 0, 0],
    [0, 0, 0, 0, 0, 0, 0, 0, 0],
    [0, 0, 0, 0, 0, 0, 0, 0, 0],
  ];

  static const List<List<int>> _horsePst = [
    [4, 8, 16, 12, 4, 12, 16, 8, 4],
    [4, 10, 28, 16, 8, 16, 28, 10, 4],
    [12, 14, 16, 20, 18, 20, 16, 14, 12],
    [8, 24, 18, 24, 20, 24, 18, 24, 8],
    [6, 16, 14, 18, 16, 18, 14, 16, 6],
    [4, 12, 16, 14, 12, 14, 16, 12, 4],
    [2, 6, 8, 6, 10, 6, 8, 6, 2],
    [4, 2, 8, 8, 4, 8, 8, 2, 4],
    [0, 2, 4, 4, -2, 4, 4, 2, 0],
    [0, -4, 0, 0, 0, 0, 0, -4, 0],
  ];

  static const List<List<int>> _chariotPst = [
    [14, 14, 12, 18, 16, 18, 12, 14, 14],
    [16, 20, 18, 24, 26, 24, 18, 20, 16],
    [12, 12, 12, 18, 18, 18, 12, 12, 12],
    [12, 18, 16, 22, 22, 22, 16, 18, 12],
    [12, 14, 12, 18, 18, 18, 12, 14, 12],
    [12, 16, 14, 20, 20, 20, 14, 16, 12],
    [6, 10, 8, 14, 14, 14, 8, 10, 6],
    [4, 8, 6, 14, 12, 14, 6, 8, 4],
    [8, 4, 8, 16, 8, 16, 8, 4, 8],
    [-2, 10, 6, 14, 12, 14, 6, 10, -2],
  ];

  static const List<List<int>> _cannonPst = [
    [6, 4, 0, -10, -12, -10, 0, 4, 6],
    [2, 2, 0, -4, -14, -4, 0, 2, 2],
    [2, 2, 0, -10, -8, -10, 0, 2, 2],
    [0, 0, -2, 4, 10, 4, -2, 0, 0],
    [0, 0, 0, 2, 8, 2, 0, 0, 0],
    [-2, 0, 4, 2, 6, 2, 4, 0, -2],
    [0, 0, 0, 2, 4, 2, 0, 0, 0],
    [4, 0, 8, 6, 10, 6, 8, 0, 4],
    [0, 2, 4, 6, 6, 6, 4, 2, 0],
    [0, 0, 2, 6, 6, 6, 2, 0, 0],
  ];

  static const List<List<int>> _advisorPst = [
    [0, 0, 0, 0, 0, 0, 0, 0, 0],
    [0, 0, 0, 0, 0, 0, 0, 0, 0],
    [0, 0, 0, 20, 0, 20, 0, 0, 0],
    [0, 0, 0, 0, 0, 0, 0, 0, 0],
    [0, 0, 0, 0, 0, 0, 0, 0, 0],
    [0, 0, 0, 0, 0, 0, 0, 0, 0],
    [0, 0, 0, 0, 0, 0, 0, 0, 0],
    [0, 0, 0, 20, 0, 20, 0, 0, 0],
    [0, 0, 0, 0, 23, 0, 0, 0, 0],
    [0, 0, 0, 20, 0, 20, 0, 0, 0],
  ];

  static const List<List<int>> _elephantPst = [
    [0, 0, 20, 0, 0, 0, 20, 0, 0],
    [0, 0, 0, 0, 0, 0, 0, 0, 0],
    [0, 0, 0, 0, 23, 0, 0, 0, 0],
    [0, 0, 0, 0, 0, 0, 0, 0, 0],
    [0, 0, 20, 0, 0, 0, 20, 0, 0],
    [0, 0, 20, 0, 0, 0, 20, 0, 0],
    [0, 0, 0, 0, 0, 0, 0, 0, 0],
    [0, 0, 0, 0, 23, 0, 0, 0, 0],
    [0, 0, 0, 0, 0, 0, 0, 0, 0],
    [0, 0, 20, 0, 0, 0, 20, 0, 0],
  ];

  static const List<List<int>> _generalPst = [
    [0, 0, 0, 0, 0, 0, 0, 0, 0],
    [0, 0, 0, 0, 0, 0, 0, 0, 0],
    [0, 0, 0, 0, 0, 0, 0, 0, 0],
    [0, 0, 0, 0, 0, 0, 0, 0, 0],
    [0, 0, 0, 0, 0, 0, 0, 0, 0],
    [0, 0, 0, 0, 0, 0, 0, 0, 0],
    [0, 0, 0, 0, 0, 0, 0, 0, 0],
    [0, 0, 0, 1, 5, 1, 0, 0, 0],
    [0, 0, 0, -8, -8, -8, 0, 0, 0],
    [0, 0, 0, 1, 5, 1, 0, 0, 0],
  ];

  /// Material value + piece-square bonus for one piece at (row, col), from its
  /// OWN perspective (not signed by color). Used by the Cờ Úp bot to value a
  /// revealed piece with the same tuning the standard evaluator uses.
  static int pieceScore(Piece piece, int row, int col) =>
      pieceValue[piece.type]! + _pstValue(piece, row, col);

  /// Evaluate the position from Red's perspective. Positive favors Red.
  static int evaluate(Board board) {
    int score = 0;
    for (final (pos, piece) in board.occupied()) {
      int value = pieceValue[piece.type]!;
      value += _pstValue(piece, pos.row, pos.col);
      score += piece.color == PieceColor.red ? value : -value;
    }
    return score;
  }

  static int _pstValue(Piece piece, int row, int col) {
    // For Black, mirror the row index so the table reads from their POV.
    final int r = piece.color == PieceColor.red ? row : 9 - row;
    final int c = col;
    switch (piece.type) {
      case PieceType.soldier:
        return _soldierPst[r][c];
      case PieceType.horse:
        return _horsePst[r][c];
      case PieceType.chariot:
        return _chariotPst[r][c];
      case PieceType.cannon:
        return _cannonPst[r][c];
      case PieceType.advisor:
        return _advisorPst[r][c];
      case PieceType.elephant:
        return _elephantPst[r][c];
      case PieceType.general:
        return _generalPst[r][c];
    }
  }
}
