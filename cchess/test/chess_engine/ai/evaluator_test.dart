import 'package:cchess/core/chess_engine/chess_engine.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Evaluator', () {
    test('starting position is balanced (close to zero)', () {
      final score = Evaluator.evaluate(Board.initial());
      expect(score.abs(), lessThan(100));
    });

    test('Red ahead a Chariot evaluates positively', () {
      // Remove Black's right Chariot.
      final fen = 'rnbakabn1/9/1c5c1/p1p1p1p1p/9/9/P1P1P1P1P/1C5C1/9/RNBAKABNR w - - 0 1';
      final score = Evaluator.evaluate(Board.fromFen(fen));
      expect(score, greaterThan(800));
    });

    test('Black ahead a Cannon evaluates negatively', () {
      final board = Board.initial();
      board.setAt(const Position(7, 1), null); // remove red cannon
      final score = Evaluator.evaluate(board);
      expect(score, lessThan(-400));
    });

    test('Red soldier across the river is worth more than at start', () {
      final start = Board.initial();
      final startScore = Evaluator.evaluate(start);

      // Move red soldier at (6,4) to (3,4) without changing anything else.
      final advanced = Board.initial();
      advanced.setAt(const Position(6, 4), null);
      advanced.setAt(const Position(3, 4), Piece.redSoldier);
      final advancedScore = Evaluator.evaluate(advanced);

      expect(advancedScore, greaterThan(startScore));
    });
  });
}
