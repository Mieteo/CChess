import 'package:cchess/core/chess_engine/chess_engine.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('XiangqiGame.initial', () {
    test('starts with Red to move and game in progress', () {
      final g = XiangqiGame.initial();
      expect(g.turn, PieceColor.red);
      expect(g.status, GameStatus.playing);
      expect(g.history, isEmpty);
    });

    test('Red has reasonable opening move count', () {
      final g = XiangqiGame.initial();
      int total = 0;
      for (final (pos, piece) in g.board.occupied()) {
        if (piece.color == PieceColor.red) {
          total += g.getValidMoves(pos).length;
        }
      }
      // Standard Xiangqi has 44 legal opening moves for Red.
      expect(total, 44);
    });

    test('Black to move only after a Red move', () {
      final g = XiangqiGame.initial();
      g.makeMove(const Position(7, 1), const Position(7, 4)); // cannon C2=C5
      expect(g.turn, PieceColor.black);
      expect(g.history.length, 1);
    });
  });

  group('makeMove validation', () {
    test('throws when a piece of the wrong color is moved', () {
      final g = XiangqiGame.initial();
      expect(
        () => g.makeMove(const Position(2, 1), const Position(2, 4)),
        throwsArgumentError,
      );
    });

    test('throws when the move is geometrically illegal', () {
      final g = XiangqiGame.initial();
      // Red soldier at (6,0) can't leap to (3,0).
      expect(
        () => g.makeMove(const Position(6, 0), const Position(3, 0)),
        throwsArgumentError,
      );
    });
  });

  group('undoMove', () {
    test('restores the previous position and turn', () {
      final g = XiangqiGame.initial();
      final fenBefore = g.toFen();
      g.makeMove(const Position(7, 1), const Position(7, 4));
      g.undoMove();
      expect(g.turn, PieceColor.red);
      expect(g.toFen(), fenBefore);
    });

    test('undoing nothing returns null', () {
      final g = XiangqiGame.initial();
      expect(g.undoMove(), isNull);
    });
  });

  group('check & checkmate detection', () {
    test('detects check when the chariot attacks the general', () {
      // Custom position: black chariot on the same file as red general.
      final g = XiangqiGame.fromFen(
        '4k4/9/9/9/9/9/9/9/9/4K1r2 w - - 0 1',
      );
      expect(g.isInCheck(PieceColor.red), isTrue);
    });

    test('back-rank style checkmate is detected', () {
      // Red general boxed in by two black chariots — no legal escape.
      final g = XiangqiGame.fromFen(
        '4k4/9/9/9/9/9/9/9/3r1r3/4K4 w - - 0 1',
      );
      expect(g.isInCheck(PieceColor.red), isTrue);
      expect(g.isCheckmate(PieceColor.red), isTrue);
    });

    test('move that exposes own general is illegal', () {
      // Red general (9,4); red advisor (8,4) pinned by black chariot (3,4).
      // Moving the advisor away should be illegal.
      final g = XiangqiGame.fromFen(
        '9/9/9/4r4/9/9/9/9/4A4/4K4 w - - 0 1',
      );
      expect(g.getValidMoves(const Position(8, 4)), isEmpty);
    });
  });

  group('flying-general legality', () {
    test('moves that line up the two generals are illegal', () {
      // Red K(9,4), Black K(0,4), Red soldier blocking on the same file (5,4).
      // Moving that soldier sideways would expose the file.
      final g = XiangqiGame.fromFen(
        '4k4/9/9/9/9/4P4/9/9/9/4K4 w - - 0 1',
      );
      final moves = g.getValidMoves(const Position(5, 4));
      // After crossing the river, red soldiers can step sideways — but doing
      // so would face the generals and must be filtered out.
      expect(moves.contains(const Position(5, 3)), isFalse);
      expect(moves.contains(const Position(5, 5)), isFalse);
      // Forward step is fine — it stays on the same file as the generals
      // but a piece (the soldier itself) still occupies a square between
      // the two kings after moving.
      expect(moves.contains(const Position(4, 4)), isTrue);
    });
  });

  group('FEN round-trip', () {
    test('toFen preserves side-to-move', () {
      final g = XiangqiGame.initial();
      g.makeMove(const Position(7, 1), const Position(7, 4));
      final fen = g.toFen();
      final g2 = XiangqiGame.fromFen(fen);
      expect(g2.turn, PieceColor.black);
    });
  });

  group('resign / draw', () {
    test('resign sets the opposite color as winner', () {
      final g = XiangqiGame.initial();
      g.resign(PieceColor.red);
      expect(g.status, GameStatus.blackWin);
      expect(g.endReason, EndReason.resignation);
    });

    test('agreeDraw stops further moves', () {
      final g = XiangqiGame.initial();
      g.agreeDraw();
      expect(g.status, GameStatus.draw);
      expect(
        () => g.makeMove(const Position(7, 1), const Position(7, 4)),
        throwsStateError,
      );
    });
  });
}
