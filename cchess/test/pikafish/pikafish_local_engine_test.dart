import 'package:cchess/core/chess_engine/chess_engine.dart';
import 'package:cchess/core/chess_engine/pikafish/uci_client.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_uci_transport.dart';

PikafishRuntime _runtime() => const PikafishRuntime(
      binaryPath: '/fake/pikafish',
      nnuePath: '/fake/pikafish.nnue',
    );

void main() {
  group('PikafishLocalEngine.bestMove', () {
    test('maps engine output onto an EngineMove with localPikafish source',
        () async {
      final transport = FakeUciTransport()
        ..searchScripts.add([
          'info depth 14 multipv 1 score cp 37 pv b2e2 h9g7',
          'bestmove b2e2',
        ]);
      final engine = PikafishLocalEngine(
        resolveRuntime: () async => _runtime(),
        startTransport: (_) async => transport,
      );

      final move = await engine.bestMove(
        kInitialFen,
        level: EngineLevel.grandmaster,
        useCase: EngineUseCase.hint,
      );
      expect(move, isNotNull);
      expect(move!.uci, 'b2e2');
      expect(move.scoreCp, 37);
      expect(move.depth, 14);
      expect(move.source, EngineSource.localPikafish);
      // NNUE + threads configured during the handshake.
      expect(
        transport.sent,
        contains('setoption name EvalFile value /fake/pikafish.nnue'),
      );
      await engine.dispose();
    });

    test('throws PikafishUnavailableException when not installed', () async {
      final engine = PikafishLocalEngine(
        resolveRuntime: () async => null,
        startTransport: (_) async => FakeUciTransport(),
      );
      expect(
        () => engine.bestMove(kInitialFen, level: EngineLevel.grandmaster),
        throwsA(isA<PikafishUnavailableException>()),
      );
    });

    test('blunderRate 1.0 plays a MultiPV alternate for bot play', () async {
      final transport = FakeUciTransport()
        ..searchScripts.add([
          'info depth 12 multipv 1 score cp 40 pv b2e2 h9g7',
          'info depth 12 multipv 2 score cp 25 pv h2e2 b9c7',
          'info depth 12 multipv 3 score cp 10 pv b0c2 h9g7',
          'info depth 12 multipv 4 score cp -5 pv h0g2 b9c7',
          'bestmove b2e2',
        ]);
      final engine = PikafishLocalEngine(
        resolveRuntime: () async => _runtime(),
        startTransport: (_) async => transport,
        seed: 7,
      );

      final move = await engine.bestMove(
        kInitialFen,
        level: EngineLevel.medium,
        useCase: EngineUseCase.bot,
        config: const EngineConfig(
          engine: EngineSource.remotePikafish,
          depth: 8,
          movetimeMs: 100,
          blunderRate: 1.0,
        ),
      );
      expect(transport.sent, contains('setoption name MultiPV value 4'));
      expect(move!.uci, isNot('b2e2')); // always blunders at rate 1.0
      expect(['h2e2', 'b0c2', 'h0g2'], contains(move.uci));
      await engine.dispose();
    });

    test('restarts a fresh process after the engine dies', () async {
      final first = FakeUciTransport()..respondToGo = false;
      final second = FakeUciTransport()
        ..searchScripts.add([
          'info depth 10 multipv 1 score cp 20 pv b2e2',
          'bestmove b2e2',
        ]);
      var starts = 0;
      final engine = PikafishLocalEngine(
        resolveRuntime: () async => _runtime(),
        startTransport: (_) async => ++starts == 1 ? first : second,
      );

      final pending = engine.bestMove(
        kInitialFen,
        level: EngineLevel.grandmaster,
        useCase: EngineUseCase.hint,
      );
      first.die();
      await expectLater(pending, throwsA(isA<UciException>()));

      final retry = await engine.bestMove(
        kInitialFen,
        level: EngineLevel.grandmaster,
        useCase: EngineUseCase.hint,
      );
      expect(retry!.uci, 'b2e2');
      expect(starts, 2);
      await engine.dispose();
    });
  });

  group('PikafishLocalEngine.analyze', () {
    test('grades moves with one search per position', () async {
      final transport = FakeUciTransport()
        ..searchScripts.addAll([
          // Position 0 (red to move): best b2e2, +30 for red.
          [
            'info depth 12 multipv 1 score cp 30 pv b2e2 h9g7',
            'bestmove b2e2',
          ],
          // Position 1 (black to move): best b7e7, -28 from black's view.
          [
            'info depth 12 multipv 1 score cp -28 pv b7e7 h0g2',
            'bestmove b7e7',
          ],
          // Position 2 (red to move) after black played h7e7 instead: +55.
          [
            'info depth 12 multipv 1 score cp 55 pv h0g2 b9c7',
            'bestmove h0g2',
          ],
        ]);
      final engine = PikafishLocalEngine(
        resolveRuntime: () async => _runtime(),
        startTransport: (_) async => transport,
      );

      final analysis = await engine.analyze(
        startingFen: kInitialFen,
        moveUcis: ['b2e2', 'h7e7'],
      );

      expect(analysis.moves, hasLength(2));
      // Red played the engine's best move → classified 'best' regardless of
      // the small cross-search noise (30 before vs 28 after → loss 2).
      final redMove = analysis.moves[0];
      expect(redMove.quality, MoveQuality.best);
      expect(redMove.centipawnLoss, 2);
      // eval after red's move == eval before black's move (one search each):
      // black best = -28 (mover view) but played h7e7 → next pos +55 for red
      // → actual = -55 for black → loss = -28 − (−55) = 27 → 'good'.
      final blackMove = analysis.moves[1];
      expect(blackMove.mover, PieceColor.black);
      expect(blackMove.centipawnLoss, 27);
      expect(blackMove.quality, MoveQuality.good);
      // Red-perspective evals for the chart: black best −28 → +28 red.
      expect(blackMove.bestEval, 28);
      expect(blackMove.actualEval, 55);
      // 3 positions → exactly 3 `go` commands (not 4).
      expect(
        transport.sent.where((c) => c.startsWith('go')).length,
        3,
      );
      expect(analysis.redAccuracy, 100);
      await engine.dispose();
    });

    test('stops gracefully at an illegal recorded move', () async {
      final transport = FakeUciTransport()
        ..searchScripts.add([
          'info depth 12 multipv 1 score cp 10 pv b2e2',
          'bestmove b2e2',
        ]);
      final engine = PikafishLocalEngine(
        resolveRuntime: () async => _runtime(),
        startTransport: (_) async => transport,
      );
      final analysis = await engine.analyze(
        startingFen: kInitialFen,
        moveUcis: ['a0a9'], // rook can't jump the whole column
      );
      expect(analysis.moves, isEmpty);
      await engine.dispose();
    });
  });
}
