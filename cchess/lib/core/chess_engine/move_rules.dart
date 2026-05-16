import '../constants/piece_constants.dart';
import 'board.dart';
import 'piece.dart';
import 'position.dart';

/// Pseudo-legal move generation for each Xiangqi piece type.
///
/// "Pseudo-legal" means the moves obey piece movement rules but may leave
/// the moving side's general in check. The full legal filtering lives in
/// [XiangqiGame.getValidMoves].
class MoveRules {
  MoveRules._();

  /// Returns all pseudo-legal target squares for the piece sitting at [from].
  /// If [from] is empty, returns an empty list.
  static List<Position> pseudoLegalMoves(Board board, Position from) {
    final piece = board.at(from);
    if (piece == null) return const [];
    switch (piece.type) {
      case PieceType.general:
        return _generalMoves(board, from, piece);
      case PieceType.advisor:
        return _advisorMoves(board, from, piece);
      case PieceType.elephant:
        return _elephantMoves(board, from, piece);
      case PieceType.horse:
        return _horseMoves(board, from, piece);
      case PieceType.chariot:
        return _chariotMoves(board, from, piece);
      case PieceType.cannon:
        return _cannonMoves(board, from, piece);
      case PieceType.soldier:
        return _soldierMoves(board, from, piece);
    }
  }

  /// Whether [color]'s general is currently attacked.
  ///
  /// Includes the Xiangqi "flying-general" rule: if both generals stand on
  /// the same open file, they threaten each other.
  static bool isInCheck(Board board, PieceColor color) {
    final kingPos = board.generalPosition(color);
    if (kingPos == null) return false;
    if (areGeneralsFacing(board)) return true;
    return _isSquareAttackedBy(board, kingPos, color.opposite);
  }

  /// Whether the two generals stand on the same file with no piece between
  /// them (illegal end-state in Xiangqi: "flying general").
  static bool areGeneralsFacing(Board board) {
    final red = board.generalPosition(PieceColor.red);
    final black = board.generalPosition(PieceColor.black);
    if (red == null || black == null) return false;
    if (red.col != black.col) return false;
    final col = red.col;
    final low = red.row < black.row ? red.row + 1 : black.row + 1;
    final high = red.row < black.row ? black.row - 1 : red.row - 1;
    for (int r = low; r <= high; r++) {
      if (board.cell(r, col) != null) return false;
    }
    return true;
  }

  // ────────────────── individual piece rules ──────────────────

  static List<Position> _generalMoves(Board b, Position from, Piece p) {
    final out = <Position>[];
    const deltas = [(-1, 0), (1, 0), (0, -1), (0, 1)];
    for (final (dr, dc) in deltas) {
      final to = from.offset(dr, dc);
      if (!to.isValid) continue;
      if (!to.isInPalace(p.isRed)) continue;
      final occupant = b.at(to);
      if (occupant == null || occupant.color != p.color) out.add(to);
    }
    // Note: the "flying general" face-off rule is enforced as a global
    // legality check (see [areGeneralsFacing] + [isInCheck]). The general
    // piece itself never moves more than one square per turn.
    return out;
  }

  static List<Position> _advisorMoves(Board b, Position from, Piece p) {
    final out = <Position>[];
    const deltas = [(-1, -1), (-1, 1), (1, -1), (1, 1)];
    for (final (dr, dc) in deltas) {
      final to = from.offset(dr, dc);
      if (!to.isValid) continue;
      if (!to.isInPalace(p.isRed)) continue;
      final occupant = b.at(to);
      if (occupant == null || occupant.color != p.color) out.add(to);
    }
    return out;
  }

  static List<Position> _elephantMoves(Board b, Position from, Piece p) {
    final out = <Position>[];
    const deltas = [(-2, -2), (-2, 2), (2, -2), (2, 2)];
    for (final (dr, dc) in deltas) {
      final to = from.offset(dr, dc);
      if (!to.isValid) continue;
      // Elephants cannot cross the river.
      if (p.isRed && to.row < 5) continue;
      if (!p.isRed && to.row > 4) continue;
      // "Elephant eye" — the midpoint square must be empty.
      final eye = from.offset(dr ~/ 2, dc ~/ 2);
      if (b.at(eye) != null) continue;
      final occupant = b.at(to);
      if (occupant == null || occupant.color != p.color) out.add(to);
    }
    return out;
  }

  static List<Position> _horseMoves(Board b, Position from, Piece p) {
    final out = <Position>[];
    // For each orthogonal "leg" direction, check the chẹt-chân block then
    // try both outward diagonal landings.
    const legs = <(int, int, List<(int, int)>)>[
      (-1, 0, [(-2, -1), (-2, 1)]), // leg up: land up-left / up-right
      (1, 0, [(2, -1), (2, 1)]),    // leg down
      (0, -1, [(-1, -2), (1, -2)]), // leg left
      (0, 1, [(-1, 2), (1, 2)]),    // leg right
    ];
    for (final (legDr, legDc, landings) in legs) {
      final legPos = from.offset(legDr, legDc);
      if (!legPos.isValid) continue;
      if (b.at(legPos) != null) continue; // blocked
      for (final (dr, dc) in landings) {
        final to = from.offset(dr, dc);
        if (!to.isValid) continue;
        final occupant = b.at(to);
        if (occupant == null || occupant.color != p.color) out.add(to);
      }
    }
    return out;
  }

  static List<Position> _chariotMoves(Board b, Position from, Piece p) {
    final out = <Position>[];
    const directions = [(-1, 0), (1, 0), (0, -1), (0, 1)];
    for (final (dr, dc) in directions) {
      int r = from.row + dr, c = from.col + dc;
      while (r >= 0 && r < Board.rows && c >= 0 && c < Board.cols) {
        final occupant = b.cell(r, c);
        if (occupant == null) {
          out.add(Position(r, c));
        } else {
          if (occupant.color != p.color) out.add(Position(r, c));
          break;
        }
        r += dr;
        c += dc;
      }
    }
    return out;
  }

  static List<Position> _cannonMoves(Board b, Position from, Piece p) {
    final out = <Position>[];
    const directions = [(-1, 0), (1, 0), (0, -1), (0, 1)];
    for (final (dr, dc) in directions) {
      int r = from.row + dr, c = from.col + dc;
      // First leg: empty squares (non-capture moves).
      while (r >= 0 && r < Board.rows && c >= 0 && c < Board.cols) {
        if (b.cell(r, c) == null) {
          out.add(Position(r, c));
          r += dr;
          c += dc;
        } else {
          break;
        }
      }
      // Second leg after the carriage: hop over exactly one piece, then the
      // first enemy piece encountered may be captured.
      if (r >= 0 && r < Board.rows && c >= 0 && c < Board.cols) {
        // Skip the carriage itself.
        r += dr;
        c += dc;
        while (r >= 0 && r < Board.rows && c >= 0 && c < Board.cols) {
          final occupant = b.cell(r, c);
          if (occupant != null) {
            if (occupant.color != p.color) out.add(Position(r, c));
            break;
          }
          r += dr;
          c += dc;
        }
      }
    }
    return out;
  }

  static List<Position> _soldierMoves(Board b, Position from, Piece p) {
    final out = <Position>[];
    // Forward direction: red moves "up the screen" toward row 0.
    final forwardDr = p.isRed ? -1 : 1;

    // Forward step.
    final fwd = from.offset(forwardDr, 0);
    if (fwd.isValid) {
      final occupant = b.at(fwd);
      if (occupant == null || occupant.color != p.color) out.add(fwd);
    }

    // After crossing the river, soldiers can also move sideways.
    final hasCrossed = p.isRed ? from.row <= 4 : from.row >= 5;
    if (hasCrossed) {
      for (final dc in [-1, 1]) {
        final side = from.offset(0, dc);
        if (!side.isValid) continue;
        final occupant = b.at(side);
        if (occupant == null || occupant.color != p.color) out.add(side);
      }
    }
    return out;
  }

  /// True if [target] is attacked by any piece of color [attacker] on [board].
  ///
  /// We re-use the pseudo-legal generators, except the general's
  /// "flying general" pseudo-move is intentionally included — that is how
  /// generals threaten each other.
  static bool _isSquareAttackedBy(
    Board board,
    Position target,
    PieceColor attacker,
  ) {
    for (final (pos, piece) in board.occupied()) {
      if (piece.color != attacker) continue;
      final moves = pseudoLegalMoves(board, pos);
      for (final m in moves) {
        if (m == target) return true;
      }
    }
    return false;
  }
}
