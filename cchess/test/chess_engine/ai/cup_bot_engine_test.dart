import 'package:cchess/core/chess_engine/chess_engine.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('CupBotEngine', () {
    test('returns a legal cup move for the side to move', () async {
      final game = XiangqiCupGame.initial(seed: 7);
      final move = await CupBotEngine().chooseMove(game, BotDifficulty.veryEasy);

      expect(move, isNotNull);
      // The move must be legal in the REAL game (which knows hidden identities),
      // proving the bot only ever proposes covers/revealed-legal moves.
      expect(game.isValidMove(move!.from, move.to), isTrue);
    });

    test('grabs a free face-down enemy piece (values it at expectation)', () async {
      // Red chariot can capture an undefended face-down black piece on (5,5).
      // Generals sit on different files so nothing about flying-general or check
      // interferes with the obviously-winning capture.
      final board = Board.empty()
        ..setAt(const Position(9, 3), Piece.redGeneral)
        ..setAt(const Position(0, 5), Piece.blackGeneral)
        ..setAt(const Position(5, 4), Piece.redChariot) // revealed
        ..setAt(const Position(5, 5), Piece.blackChariot); // cover of a hidden pc
      final game = XiangqiCupGame.debug(
        board: board,
        turn: PieceColor.red,
        // The hidden TRUE identity is something else entirely — the bot must not
        // peek at it; it should value the face-down piece at expectation (~320)
        // and still take the free capture.
        hiddenAssignments: {const Position(5, 5): Piece.blackHorse},
      );

      // hard → no randomness, deterministic best move.
      final move = await CupBotEngine().chooseMove(game, BotDifficulty.hard);

      expect(move, isNotNull);
      expect(move!.to, const Position(5, 5), reason: 'should capture the free piece');
      expect(game.isValidMove(move.from, move.to), isTrue);
    });

    test('returns null once the game is already over', () async {
      final board = Board.empty()
        ..setAt(const Position(9, 4), Piece.redGeneral)
        ..setAt(const Position(0, 4), Piece.blackGeneral);
      final game = XiangqiCupGame.debug(board: board);
      game.resign(PieceColor.red);

      final move = await CupBotEngine().chooseMove(game, BotDifficulty.easy);
      expect(move, isNull);
    });
  });
}
