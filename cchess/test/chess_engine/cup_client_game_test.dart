import 'package:cchess/core/chess_engine/chess_engine.dart';
import 'package:flutter_test/flutter_test.dart';

/// Online client engine for Cờ Úp: covers-only view that the human player sees,
/// driven by the server's `reveal` events. These tests pin the cheat-resistant
/// invariant (the client never invents hidden identities) and the apply paths
/// for the local move (optimistic + reveal), the opponent move (authoritative),
/// reconnect/spectate snapshots, and rollback.
void main() {
  group('CupClientGame.initial', () {
    test('all non-general pieces start face-down, generals stay face-up', () {
      final game = CupClientGame.initial();
      // 32 pieces on a standard opening, 2 generals → 30 face-down covers.
      expect(game.hiddenCount, 30);
      final redGeneral = game.board.generalPosition(PieceColor.red)!;
      final blackGeneral = game.board.generalPosition(PieceColor.black)!;
      expect(game.isHidden(redGeneral), isFalse);
      expect(game.isHidden(blackGeneral), isFalse);
      expect(game.turn, PieceColor.red);
    });

    test('a face-down piece moves by its COVER (soldier advances)', () {
      final game = CupClientGame.initial();
      // Red soldier cover at (6,0) advances toward Black (decreasing row).
      const from = Position(6, 0);
      expect(game.isHidden(from), isTrue);
      final moves = game.getValidMoves(from);
      expect(moves, contains(const Position(5, 0)));
    });

    test('cannot move the opponent piece / before your turn', () {
      final game = CupClientGame.initial();
      // Black soldier cover at (3,0) — not Red's to move on turn 1.
      expect(game.getValidMoves(const Position(3, 0)), isEmpty);
      expect(game.isValidMove(const Position(3, 0), const Position(4, 0)),
          isFalse);
    });
  });

  group('optimistic local move + reveal', () {
    test('mover stays face-down until applyReveal flips it', () {
      final game = CupClientGame.initial();
      const from = Position(6, 0);
      const to = Position(5, 0);
      final move = game.makeMove(from, to);

      expect(move.toUci(), 'a3a4');
      expect(game.board.at(from), isNull);
      expect(game.board.at(to), isNotNull);
      // Destination kept blank (face-down) until the server reveals identity.
      expect(game.isHidden(to), isTrue);
      expect(game.turn, PieceColor.black);

      game.applyReveal(to, const Piece(PieceType.cannon, PieceColor.red));
      expect(game.isHidden(to), isFalse);
      expect(game.board.at(to), const Piece(PieceType.cannon, PieceColor.red));
    });

    test('undoMove rolls back an optimistic move (board, hidden, turn)', () {
      final game = CupClientGame.initial();
      const from = Position(6, 0);
      const to = Position(5, 0);
      game.makeMove(from, to);
      game.undoMove();

      expect(game.board.at(to), isNull);
      expect(game.board.at(from), isNotNull);
      expect(game.isHidden(from), isTrue);
      expect(game.turn, PieceColor.red);
      expect(game.history, isEmpty);
    });
  });

  group('authoritative opponent move', () {
    test('applyServerMove places the revealed identity + flips turn', () {
      final game = CupClientGame.initial();
      const from = Position(6, 0);
      const to = Position(5, 0);
      const revealed = Piece(PieceType.chariot, PieceColor.red);

      game.applyServerMove(from, to, revealed: revealed);

      expect(game.board.at(from), isNull);
      expect(game.board.at(to), revealed);
      expect(game.isHidden(to), isFalse);
      expect(game.turn, PieceColor.black);
      expect(game.lastMove!.moved, revealed);
    });

    test('pieceFromFenChar maps FEN chars to coloured pieces', () {
      expect(CupClientGame.pieceFromFenChar('R'),
          const Piece(PieceType.chariot, PieceColor.red));
      expect(CupClientGame.pieceFromFenChar('c'),
          const Piece(PieceType.cannon, PieceColor.black));
      expect(CupClientGame.pieceFromFenChar(null), isNull);
      expect(CupClientGame.pieceFromFenChar(''), isNull);
    });
  });

  group('fromSnapshot (reconnect / spectate)', () {
    test('rebuilds covers + revealed pieces + hidden squares + turn', () {
      final placement = Board.initial().toFenPlacement();
      // Mark (0,0) and (0,1) as still face-down; everything else "revealed".
      final game = CupClientGame.fromSnapshot(
        fen: placement,
        hiddenIndices: const [0, 1], // row*9+col
        turn: PieceColor.black,
      );

      expect(game.turn, PieceColor.black);
      expect(game.isHidden(const Position(0, 0)), isTrue);
      expect(game.isHidden(const Position(0, 1)), isTrue);
      expect(game.isHidden(const Position(0, 2)), isFalse);
      expect(game.board.at(const Position(0, 0)), isNotNull);
      // A revealed Sĩ (advisor) now roams freely — snapshot keeps cup reach.
      expect(game.hiddenCount, 2);
    });
  });
}
