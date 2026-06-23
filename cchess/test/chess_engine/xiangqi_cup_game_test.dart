import 'package:cchess/core/chess_engine/chess_engine.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('XiangqiCupGame.initial', () {
    test('hides every non-general piece and keeps generals face-up', () {
      final game = XiangqiCupGame.initial(seed: 13);

      expect(game.turn, PieceColor.red);
      expect(game.status, GameStatus.playing);
      expect(game.hiddenCount, 30);
      expect(game.isHidden(const Position(0, 4)), isFalse);
      expect(game.isHidden(const Position(9, 4)), isFalse);
      expect(game.board.at(const Position(0, 4))?.type, PieceType.general);
      expect(game.board.at(const Position(9, 4))?.type, PieceType.general);
    });

    test('uses cover-piece movement before revealing the shuffled piece', () {
      final game = XiangqiCupGame.initial(seed: 13);
      const from = Position(7, 1); // red cannon cover
      const to = Position(7, 4);
      final hiddenPiece = game.debugHiddenPieceAt(from);

      expect(hiddenPiece, isNotNull);
      expect(game.isHidden(from), isTrue);
      expect(game.getValidMoves(from), contains(to));

      final move = game.makeMove(from, to);

      expect(move.from, from);
      expect(move.to, to);
      expect(move.moved, hiddenPiece);
      expect(game.board.at(from), isNull);
      expect(game.board.at(to), hiddenPiece);
      expect(game.isHidden(from), isFalse);
      expect(game.isHidden(to), isFalse);
      expect(game.turn, PieceColor.black);
      expect(game.hiddenCount, 29);
    });

    test('undo restores board, turn, and hidden assignment', () {
      final game = XiangqiCupGame.initial(seed: 13);
      const from = Position(7, 1);
      const to = Position(7, 4);
      final fenBefore = game.toFen();
      final hiddenBefore = game.debugHiddenPieceAt(from);

      game.makeMove(from, to);
      final undone = game.undoMove();

      expect(undone, isNotNull);
      expect(game.toFen(), fenBefore);
      expect(game.turn, PieceColor.red);
      expect(game.hiddenCount, 30);
      expect(game.isHidden(from), isTrue);
      expect(game.debugHiddenPieceAt(from), hiddenBefore);
      expect(game.board.at(to), isNull);
    });
  });
}
