import 'package:cchess/core/chess_engine/chess_engine.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('General', () {
    test('moves one step orthogonally inside the palace', () {
      final b = Board.empty();
      b.setAt(const Position(9, 4), Piece.redGeneral);
      b.setAt(const Position(0, 4), Piece.blackGeneral); // required: any spot
      final moves = MoveRules.pseudoLegalMoves(b, const Position(9, 4));
      expect(moves.toSet(), {
        const Position(8, 4),
        const Position(9, 3),
        const Position(9, 5),
      });
    });

    test('cannot leave the palace', () {
      final b = Board.empty();
      b.setAt(const Position(7, 3), Piece.redGeneral);
      b.setAt(const Position(0, 4), Piece.blackGeneral);
      final moves = MoveRules.pseudoLegalMoves(b, const Position(7, 3));
      // (6,3) is outside the palace and must NOT be generated.
      expect(moves.contains(const Position(6, 3)), isFalse);
    });

    test('open face-off counts as check via the flying-general rule', () {
      final b = Board.empty();
      b.setAt(const Position(9, 4), Piece.redGeneral);
      b.setAt(const Position(0, 4), Piece.blackGeneral);
      expect(MoveRules.areGeneralsFacing(b), isTrue);
      expect(MoveRules.isInCheck(b, PieceColor.red), isTrue);
      expect(MoveRules.isInCheck(b, PieceColor.black), isTrue);
    });

    test('general piece itself never moves more than one square', () {
      final b = Board.empty();
      b.setAt(const Position(9, 4), Piece.redGeneral);
      b.setAt(const Position(0, 4), Piece.blackGeneral);
      final moves = MoveRules.pseudoLegalMoves(b, const Position(9, 4));
      // (0,4) must NOT be a pseudo-legal target — generals move one step.
      expect(moves.contains(const Position(0, 4)), isFalse);
    });
  });

  group('Advisor', () {
    test('moves diagonally inside the palace only', () {
      final b = Board.empty();
      b.setAt(const Position(9, 4), Piece.redGeneral);
      b.setAt(const Position(0, 4), Piece.blackGeneral);
      b.setAt(const Position(8, 4), Piece.redAdvisor); // palace center
      final moves = MoveRules.pseudoLegalMoves(b, const Position(8, 4));
      expect(moves.toSet(), {
        const Position(7, 3),
        const Position(7, 5),
        const Position(9, 3),
        const Position(9, 5),
      });
    });
  });

  group('Elephant', () {
    test('moves two diagonal squares with empty eye', () {
      final b = Board.empty();
      b.setAt(const Position(9, 2), Piece.redElephant);
      final moves = MoveRules.pseudoLegalMoves(b, const Position(9, 2));
      expect(moves.toSet(), {
        const Position(7, 0),
        const Position(7, 4),
      });
    });

    test('blocked by an occupied eye', () {
      final b = Board.empty();
      b.setAt(const Position(9, 2), Piece.redElephant);
      b.setAt(const Position(8, 3), Piece.redSoldier); // blocks (9,2)->(7,4)
      final moves = MoveRules.pseudoLegalMoves(b, const Position(9, 2));
      expect(moves.contains(const Position(7, 4)), isFalse);
    });

    test('cannot cross the river', () {
      final b = Board.empty();
      b.setAt(const Position(5, 2), Piece.redElephant);
      final moves = MoveRules.pseudoLegalMoves(b, const Position(5, 2));
      // From (5,2) red elephant could theoretically reach (3,0)/(3,4) but
      // those are on the black side and must be filtered out.
      expect(moves.any((p) => p.row < 5), isFalse);
    });
  });

  group('Horse', () {
    test('makes 8 L-shape moves from center on an empty board', () {
      final b = Board.empty();
      b.setAt(const Position(4, 4), Piece.redHorse);
      final moves = MoveRules.pseudoLegalMoves(b, const Position(4, 4));
      expect(moves.toSet(), {
        const Position(2, 3),
        const Position(2, 5),
        const Position(3, 2),
        const Position(3, 6),
        const Position(5, 2),
        const Position(5, 6),
        const Position(6, 3),
        const Position(6, 5),
      });
    });

    test('is blocked by the chẹt-chân piece', () {
      final b = Board.empty();
      b.setAt(const Position(4, 4), Piece.redHorse);
      b.setAt(const Position(3, 4), Piece.blackSoldier); // blocks up-leg
      final moves = MoveRules.pseudoLegalMoves(b, const Position(4, 4));
      expect(moves.contains(const Position(2, 3)), isFalse);
      expect(moves.contains(const Position(2, 5)), isFalse);
      // Down/side legs unaffected.
      expect(moves.contains(const Position(5, 2)), isTrue);
    });
  });

  group('Chariot', () {
    test('rides until it hits a piece or the edge', () {
      final b = Board.empty();
      b.setAt(const Position(4, 4), Piece.redChariot);
      b.setAt(const Position(4, 7), Piece.blackSoldier);
      b.setAt(const Position(7, 4), Piece.redCannon);
      final moves = MoveRules.pseudoLegalMoves(b, const Position(4, 4));
      // Right: up to (4,7) inclusive (capture).
      expect(moves.contains(const Position(4, 7)), isTrue);
      expect(moves.contains(const Position(4, 8)), isFalse);
      // Down: blocked at (7,4) — own piece, cannot land on it.
      expect(moves.contains(const Position(6, 4)), isTrue);
      expect(moves.contains(const Position(7, 4)), isFalse);
    });
  });

  group('Cannon', () {
    test('moves like a chariot when not capturing', () {
      final b = Board.empty();
      b.setAt(const Position(4, 4), Piece.redCannon);
      final moves = MoveRules.pseudoLegalMoves(b, const Position(4, 4));
      // Should cover all empty squares along the 4 directions.
      expect(moves.contains(const Position(4, 0)), isTrue);
      expect(moves.contains(const Position(0, 4)), isTrue);
    });

    test('captures only by jumping exactly one piece', () {
      final b = Board.empty();
      b.setAt(const Position(7, 1), Piece.redCannon);
      b.setAt(const Position(5, 1), Piece.redSoldier); // carriage
      b.setAt(const Position(2, 1), Piece.blackSoldier); // target
      final moves = MoveRules.pseudoLegalMoves(b, const Position(7, 1));
      // Direct empty squares above the carriage are NOT reachable.
      expect(moves.contains(const Position(6, 1)), isTrue); // before carriage
      expect(moves.contains(const Position(4, 1)), isFalse); // beyond carriage
      // Capture must include (2,1).
      expect(moves.contains(const Position(2, 1)), isTrue);
    });
  });

  group('Soldier', () {
    test('only forward before crossing the river', () {
      final b = Board.empty();
      b.setAt(const Position(6, 4), Piece.redSoldier);
      final moves = MoveRules.pseudoLegalMoves(b, const Position(6, 4));
      expect(moves.toSet(), {const Position(5, 4)});
    });

    test('forward + sideways after crossing the river', () {
      final b = Board.empty();
      b.setAt(const Position(4, 4), Piece.redSoldier);
      final moves = MoveRules.pseudoLegalMoves(b, const Position(4, 4));
      expect(moves.toSet(), {
        const Position(3, 4),
        const Position(4, 3),
        const Position(4, 5),
      });
    });

    test('cannot go off the board at the last rank', () {
      final b = Board.empty();
      b.setAt(const Position(0, 4), Piece.redSoldier);
      final moves = MoveRules.pseudoLegalMoves(b, const Position(0, 4));
      expect(moves.contains(const Position(-1, 4)), isFalse);
      // Only sideways remains.
      expect(moves.toSet(), {const Position(0, 3), const Position(0, 5)});
    });
  });

  group('Flying-general (face-off) detection', () {
    test('returns true on an open file', () {
      final b = Board.empty();
      b.setAt(const Position(9, 4), Piece.redGeneral);
      b.setAt(const Position(0, 4), Piece.blackGeneral);
      expect(MoveRules.areGeneralsFacing(b), isTrue);
    });

    test('returns false when a piece sits between', () {
      final b = Board.empty();
      b.setAt(const Position(9, 4), Piece.redGeneral);
      b.setAt(const Position(0, 4), Piece.blackGeneral);
      b.setAt(const Position(5, 4), Piece.redSoldier);
      expect(MoveRules.areGeneralsFacing(b), isFalse);
    });
  });
}
