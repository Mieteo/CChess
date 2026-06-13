import 'package:cchess/core/chess_engine/chess_engine.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('BotEngine best-effort (hint) mode', () {
    test('returns a legal move without the artificial think delay', () async {
      final game = XiangqiGame.initial();
      final started = DateTime.now();

      // veryHard normally enforces minThinkTime=1200ms; a tiny budget keeps
      // the iterative search at shallow depth, so finishing well under that
      // proves both the delay skip and the time bound.
      final move = await BotEngine().chooseMove(
        game,
        BotDifficulty.veryHard,
        bestEffort: true,
        timeBudget: const Duration(milliseconds: 100),
      );
      final elapsed = DateTime.now().difference(started);

      expect(move, isNotNull);
      expect(game.isValidMove(move!.from, move.to), isTrue);
      expect(elapsed, lessThan(const Duration(milliseconds: 1200)));
    });

    test('bot mode still honors the minimum think time', () async {
      final game = XiangqiGame.initial();
      final started = DateTime.now();

      final move = await BotEngine().chooseMove(game, BotDifficulty.veryEasy);
      final elapsed = DateTime.now().difference(started);

      expect(move, isNotNull);
      // veryEasy minThinkTime is 350ms — bot replies must not feel instant.
      expect(elapsed, greaterThanOrEqualTo(const Duration(milliseconds: 350)));
    });
  });
}
