import 'package:cchess/core/chess_engine/chess_engine.dart';
import 'package:cchess/presentation/game/game_controller.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('GameController interaction', () {
    test('initial state has Red to move and no selection', () {
      final c = GameController();
      expect(c.state.turn, PieceColor.red);
      expect(c.state.selected, isNull);
      expect(c.state.validTargets, isEmpty);
    });

    test('tapping a Red piece selects it and shows targets', () {
      final c = GameController();
      // Red cannon (row 7, col 1).
      c.onTap(7, 1);
      expect(c.state.selected, const Position(7, 1));
      expect(c.state.validTargets, isNotEmpty);
    });

    test('tapping a Black piece on Red\'s turn is ignored', () {
      final c = GameController();
      c.onTap(2, 1); // Black cannon
      expect(c.state.selected, isNull);
    });

    test('tapping a valid target makes the move and clears selection', () {
      final c = GameController();
      c.onTap(7, 1); // select red cannon
      c.onTap(7, 4); // move it horizontally
      expect(c.state.selected, isNull);
      expect(c.state.validTargets, isEmpty);
      expect(c.state.turn, PieceColor.black);
      expect(c.state.lastMove?.from, const Position(7, 1));
      expect(c.state.lastMove?.to, const Position(7, 4));
    });

    test('tapping the same square deselects', () {
      final c = GameController();
      c.onTap(7, 1);
      expect(c.state.selected, const Position(7, 1));
      c.onTap(7, 1);
      expect(c.state.selected, isNull);
    });

    test('tapping a different own piece re-selects', () {
      final c = GameController();
      c.onTap(7, 1); // red cannon
      c.onTap(9, 0); // red chariot
      expect(c.state.selected, const Position(9, 0));
    });

    test('undo reverts the last move and switches turn back', () {
      final c = GameController();
      c.onTap(7, 1);
      c.onTap(7, 4);
      expect(c.state.turn, PieceColor.black);
      c.undo();
      expect(c.state.turn, PieceColor.red);
      expect(c.state.lastMove, isNull);
    });

    test('newGame resets the board', () {
      final c = GameController();
      c.onTap(7, 1);
      c.onTap(7, 4);
      c.newGame();
      expect(c.state.turn, PieceColor.red);
      expect(c.state.game.history, isEmpty);
    });

    test('toggleFlip flips the boardFlipped flag', () {
      final c = GameController();
      expect(c.state.boardFlipped, isFalse);
      c.toggleFlip();
      expect(c.state.boardFlipped, isTrue);
    });

    test('resign ends the game and the opposite color wins', () {
      final c = GameController();
      c.resign(PieceColor.red);
      expect(c.state.game.status, GameStatus.blackWin);
      expect(c.state.acceptsInput, isFalse);
    });

    test('agreeDraw ends the game as draw', () {
      final c = GameController();
      c.agreeDraw();
      expect(c.state.game.status, GameStatus.draw);
    });
  });
}
