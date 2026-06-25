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

    test(
      'prefers a known high-value capture over a face-down one (no peeking)',
      () async {
        // Red chariot on row 5 can capture EITHER a REVEALED black chariot
        // (worth ~900) to its left, or a FACE-DOWN black piece to its right.
        // The face-down piece is SECRETLY a chariot too, but a fair bot can't
        // see that — it must value it at the bag expectation (~280, since one
        // black chariot is already revealed) and therefore grab the known 900.
        // Generals sit in their palaces on DIFFERENT files (3 vs 5) so nothing
        // about flying-general or a lucky check competes with the material call.
        final board = Board.empty()
          ..setAt(const Position(9, 3), Piece.redGeneral)
          ..setAt(const Position(0, 5), Piece.blackGeneral)
          ..setAt(const Position(5, 4), Piece.redChariot) // revealed mover
          ..setAt(const Position(5, 1), Piece.blackChariot) // revealed victim
          ..setAt(const Position(5, 7), Piece.blackSoldier); // cover of a hidden
        final game = XiangqiCupGame.debug(
          board: board,
          turn: PieceColor.red,
          hiddenAssignments: {const Position(5, 7): Piece.blackChariot},
        );

        // hard → deterministic, no randomness.
        final move = await CupBotEngine().chooseMove(game, BotDifficulty.hard);

        expect(move, isNotNull);
        expect(
          move!.to,
          const Position(5, 1),
          reason: 'take the KNOWN chariot (900), not the face-down ~280',
        );
        expect(game.isValidMove(move.from, move.to), isTrue);
      },
    );

    test(
      'searches a full face-down opening at depth without hanging',
      () async {
        // A fresh cup position is almost all covers, so EVERY developing move is
        // a reveal → a chance node. This exercises the expectiminimax fan-out at
        // its heaviest; the time-budgeted iterative deepening must still return a
        // legal move promptly.
        final game = XiangqiCupGame.initial(seed: 11);
        final sw = Stopwatch()..start();
        final move = await CupBotEngine().chooseMove(
          game,
          BotDifficulty.medium,
        );
        sw.stop();

        expect(move, isNotNull);
        expect(game.isValidMove(move!.from, move.to), isTrue);
        // Budget is ~1s + min think time; allow generous slack for slow CI.
        expect(sw.elapsedMilliseconds, lessThan(8000));
      },
    );
  });
}
