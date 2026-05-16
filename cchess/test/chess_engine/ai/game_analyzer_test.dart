import 'package:cchess/core/chess_engine/chess_engine.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('GameAnalyzer', () {
    test('returns one MoveAnalysis per move', () async {
      // Two-move opening: red cannon e2, black cannon e7.
      final analyzer = GameAnalyzer(depth: 2);
      final analysis = await analyzer.analyze(
        startingFen: kInitialFen,
        moveUcis: const ['b2e2', 'b7e7'],
      );
      expect(analysis.moves, hasLength(2));
      expect(analysis.moves[0].mover, PieceColor.red);
      expect(analysis.moves[1].mover, PieceColor.black);
    });

    test('flags an engine-recommended move as "best"', () async {
      // Engine should choose a sensible opening; whichever it picks counts
      // as the best move. If we make the same move it should be classified
      // as MoveQuality.best.
      final analyzer = GameAnalyzer(depth: 2);
      // Force the analyzer to grade itself by reusing its own choice.
      final search = Minimax(depth: 2, seed: 1);
      final engineMove = search.choose(XiangqiGame.initial())!.move.toUci();

      final analysis = await analyzer.analyze(
        startingFen: kInitialFen,
        moveUcis: [engineMove],
      );
      expect(analysis.moves, hasLength(1));
      expect(analysis.moves.first.quality, MoveQuality.best);
      expect(analysis.moves.first.centipawnLoss, 0);
    });

    test('giving up material is classified as a blunder', () async {
      // From a sharp test position, deliberately make a hanging move:
      // Red has a free chariot capture available (the "win the cannon"
      // tactic from puzzle p001). Walking the king instead is a blunder.
      final analyzer = GameAnalyzer(depth: 2);
      final analysis = await analyzer.analyze(
        startingFen: '4k4/9/9/9/R3c4/9/9/9/9/4K4 w - - 0 1',
        // Move red K(9,4) → (9,3) instead of capturing the cannon at e5.
        // UCI for (9,4)->(9,3): file e->d, rank 0->0 => e0d0
        moveUcis: const ['e0d0'],
      );
      expect(analysis.moves, hasLength(1));
      // Skipping a free cannon should produce a meaningful cp-loss.
      expect(analysis.moves.first.centipawnLoss, greaterThan(150));
      expect(
        analysis.moves.first.quality,
        anyOf(
          MoveQuality.mistake,
          MoveQuality.blunder,
        ),
      );
    });

    test('accuracy is 100 when every move was the engine\'s choice', () async {
      final analyzer = GameAnalyzer(depth: 2);
      final ucis = <String>[];
      final game = XiangqiGame.initial();
      for (int i = 0; i < 4; i++) {
        final search = Minimax(depth: 2, seed: 1);
        final best = search.choose(game);
        if (best == null) break;
        ucis.add(best.move.toUci());
        game.makeMove(best.move.from, best.move.to);
      }

      final analysis = await analyzer.analyze(
        startingFen: kInitialFen,
        moveUcis: ucis,
      );
      expect(analysis.redAccuracy, 100);
      expect(analysis.blackAccuracy, 100);
      expect(analysis.redBlunders, 0);
      expect(analysis.blackBlunders, 0);
    });

    test('stream emits progress for every move', () async {
      final analyzer = GameAnalyzer(depth: 2);
      final progressEvents = <AnalysisProgress>[];
      await for (final p in analyzer.stream(
        startingFen: kInitialFen,
        moveUcis: const ['b2e2', 'b7e7'],
      )) {
        progressEvents.add(p);
      }
      expect(progressEvents, hasLength(2));
      expect(progressEvents.first.completedMoves, 1);
      expect(progressEvents.last.completedMoves, 2);
      expect(progressEvents.last.fraction, 1.0);
    });
  });

  group('MoveQuality scoring', () {
    test('scoreOut100 covers all 6 tiers monotonically', () {
      final scores = MoveQuality.values.map((q) => q.scoreOut100).toList();
      // best > excellent > good > inaccuracy > mistake > blunder
      expect(scores[0] >= scores[1], isTrue);
      expect(scores[1] >= scores[2], isTrue);
      expect(scores[2] >= scores[3], isTrue);
      expect(scores[3] >= scores[4], isTrue);
      expect(scores[4] >= scores[5], isTrue);
    });
  });
}
