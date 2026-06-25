import '../constants/piece_constants.dart';
import 'board.dart';
import 'move_rules.dart';
import 'piece.dart';
import 'position.dart';

/// Shared Cờ Úp (Xiangqi blind variant) move-generation + check rules.
///
/// Both the local full-information [XiangqiCupGame] (which owns every hidden
/// identity for offline play) and the online thin client (which only ever sees
/// covers + revealed pieces) generate moves the SAME way:
///   * a FACE-DOWN piece moves by its COVER — the nominal role of the square it
///     sits on — so a cover Sĩ/Tượng stays confined like in standard cờ tướng;
///   * once REVEALED, Sĩ and Tượng shed the palace / river limits and roam the
///     whole board on their 1-/2-step diagonal pattern (Tượng still blocked by a
///     "cản mắt"). Every other piece uses the standard rules.
///
/// The crucial property that lets the online client run these rules without
/// knowing what is under each cover: legality depends only on covers + the true
/// types of ALREADY-REVEALED pieces (for blocking / check) — never on a
/// face-down piece's hidden identity. A face-down mover only ever blocks rays by
/// occupancy, and occupancy is type-independent.
class CupRules {
  const CupRules._();

  /// Pseudo-legal targets for the piece on [from], honouring cup reach.
  /// [hidden] is the set of squares that are still face-down.
  static List<Position> pseudoLegalOn(
    Board board,
    Set<Position> hidden,
    Position from,
  ) {
    final piece = board.at(from);
    if (piece == null) return const [];
    if (!hidden.contains(from)) {
      if (piece.type == PieceType.advisor) {
        return _freeDiagonalMoves(board, from, piece, 1);
      }
      if (piece.type == PieceType.elephant) {
        return _freeDiagonalMoves(board, from, piece, 2);
      }
    }
    return MoveRules.pseudoLegalMoves(board, from);
  }

  /// Diagonal slider for a revealed Sĩ ([step] 1) and Tượng ([step] 2): no palace
  /// / river bounds, but the 2-step Tượng is still blocked when the midpoint
  /// ("mắt Tượng") is occupied.
  static List<Position> _freeDiagonalMoves(
    Board b,
    Position from,
    Piece p,
    int step,
  ) {
    final out = <Position>[];
    final deltas = [
      (-step, -step),
      (-step, step),
      (step, -step),
      (step, step),
    ];
    for (final (dr, dc) in deltas) {
      final to = from.offset(dr, dc);
      if (!to.isValid) continue;
      if (step == 2 && b.at(from.offset(dr ~/ 2, dc ~/ 2)) != null) {
        continue; // cản mắt Tượng
      }
      final occupant = b.at(to);
      if (occupant == null || occupant.color != p.color) out.add(to);
    }
    return out;
  }

  /// Whether [color]'s general is currently in check, honouring the cup reach of
  /// revealed Sĩ/Tượng and the flying-general face-off. Face-down pieces still
  /// threaten by their cover.
  static bool inCheck(Board board, Set<Position> hidden, PieceColor color) {
    final kingPos = board.generalPosition(color);
    if (kingPos == null) return false;
    if (MoveRules.areGeneralsFacing(board)) return true;
    for (final (pos, piece) in board.occupied()) {
      if (piece.color == color) continue;
      if (pseudoLegalOn(board, hidden, pos).contains(kingPos)) return true;
    }
    return false;
  }
}
