import 'package:cchess/core/chess_engine/chess_engine.dart';
import 'package:flutter_test/flutter_test.dart';

/// These tests run on the host VM (desktop), where the native ElephantEye `.so`
/// is not present, so [LocalElephantEye] must transparently fall back to the
/// injected Dart engine for every request. The fallback path is the contract we
/// can verify off-device; on Android the same wiring routes strong tiers to the
/// native engine instead.
void main() {
  group('LocalElephantEye (native unavailable → fallback)', () {
    test('routes a strong bot tier to the fallback engine', () async {
      final fallback = _RecordingEngine();
      final engine = LocalElephantEye(fallback: fallback);

      final result = await engine.bestMove(
        kInitialFen,
        level: EngineLevel.veryHard,
      );

      expect(result, isNotNull);
      expect(result!.source, EngineSource.localMinimax);
      expect(fallback.bestMoveCalls, 1);
    });

    test('routes weak/medium tiers to the fallback engine', () async {
      final fallback = _RecordingEngine();
      final engine = LocalElephantEye(fallback: fallback);

      await engine.bestMove(kInitialFen, level: EngineLevel.easy);
      await engine.bestMove(kInitialFen, level: EngineLevel.medium);

      expect(fallback.bestMoveCalls, 2);
    });

    test('routes hint/analysis bestMove to the fallback engine', () async {
      final fallback = _RecordingEngine();
      final engine = LocalElephantEye(fallback: fallback);

      await engine.bestMove(
        kInitialFen,
        level: EngineLevel.medium,
        useCase: EngineUseCase.hint,
      );

      expect(fallback.bestMoveCalls, 1);
    });

    test('delegates analyze to the fallback engine', () async {
      final fallback = _RecordingEngine();
      final engine = LocalElephantEye(fallback: fallback);

      await engine.analyze(startingFen: kInitialFen, moveUcis: const []);

      expect(fallback.analyzeCalls, 1);
    });

    test('returns a legal move end-to-end via the default minimax fallback',
        () async {
      // No injected fallback → uses the real LocalMinimaxEngine.
      final engine = LocalElephantEye();
      final result = await engine.bestMove(
        kInitialFen,
        level: EngineLevel.hard,
      );

      expect(result, isNotNull);
      final game = XiangqiGame.initial();
      expect(game.isValidMove(result!.move.from, result.move.to), isTrue);
    });
  });
}

class _RecordingEngine implements MoveEngine {
  int bestMoveCalls = 0;
  int analyzeCalls = 0;

  @override
  Future<EngineMove?> bestMove(
    String fen, {
    required EngineLevel level,
    EngineUseCase useCase = EngineUseCase.bot,
    EngineConfig? config,
  }) async {
    bestMoveCalls++;
    final game = XiangqiGame.fromFen(fen);
    const from = Position(7, 1);
    const to = Position(7, 4);
    final piece = game.board.at(from)!;
    final move = Move(
      from: from,
      to: to,
      moved: piece,
      captured: game.board.at(to),
    );
    return EngineMove(
      move: move,
      uci: move.toUci(),
      source: EngineSource.localMinimax,
    );
  }

  @override
  Future<GameAnalysis> analyze({
    required String startingFen,
    required List<String> moveUcis,
  }) async {
    analyzeCalls++;
    return const GameAnalysis(
      moves: [],
      redAccuracy: 0,
      blackAccuracy: 0,
      redBlunders: 0,
      blackBlunders: 0,
      redMistakes: 0,
      blackMistakes: 0,
    );
  }
}
