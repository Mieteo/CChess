import 'package:cchess/core/chess_engine/chess_engine.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('EngineRouter', () {
    test('uses local minimax for normal bot levels', () async {
      final local = _FakeEngine(EngineSource.localMinimax);
      final remote = _FakeEngine(EngineSource.remotePikafish);
      final router = EngineRouter(local: local, remote: remote);

      final result = await router.bestMove(
        kInitialFen,
        level: EngineLevel.medium,
      );

      expect(result?.source, EngineSource.localMinimax);
      expect(local.bestMoveCalls, 1);
      expect(remote.bestMoveCalls, 0);
    });

    test('uses remote Pikafish for grandmaster bot level', () async {
      final local = _FakeEngine(EngineSource.localMinimax);
      final remote = _FakeEngine(EngineSource.remotePikafish);
      final router = EngineRouter(local: local, remote: remote);

      final result = await router.bestMove(
        kInitialFen,
        level: EngineLevel.grandmaster,
      );

      expect(result?.source, EngineSource.remotePikafish);
      expect(local.bestMoveCalls, 0);
      expect(remote.bestMoveCalls, 1);
    });

    test('falls back to local minimax when remote throws', () async {
      final local = _FakeEngine(EngineSource.localMinimax);
      final remote = _FakeEngine(EngineSource.remotePikafish, fail: true);
      final router = EngineRouter(local: local, remote: remote);

      final result = await router.bestMove(
        kInitialFen,
        level: EngineLevel.grandmaster,
      );

      expect(result?.source, EngineSource.localMinimax);
      expect(result?.usedFallback, isTrue);
      expect(result?.fallbackKind, EngineFallbackKind.network);
      expect(local.bestMoveCalls, 1);
      expect(remote.bestMoveCalls, 1);
    });

    test('tags fallback as quotaExceeded when remote is out of free quota',
        () async {
      final local = _FakeEngine(EngineSource.localMinimax);
      final remote = _FakeEngine(
        EngineSource.remotePikafish,
        throwError: const EngineQuotaExceededException('hint'),
      );
      final router = EngineRouter(local: local, remote: remote);

      final result = await router.bestMove(
        kInitialFen,
        level: EngineLevel.grandmaster,
        useCase: EngineUseCase.hint,
      );

      expect(result?.source, EngineSource.localMinimax);
      expect(result?.usedFallback, isTrue);
      expect(result?.fallbackKind, EngineFallbackKind.quotaExceeded);
    });
  });
}

class _FakeEngine implements MoveEngine {
  _FakeEngine(this.source, {this.fail = false, this.throwError});

  final EngineSource source;
  final bool fail;
  final Object? throwError;
  int bestMoveCalls = 0;

  @override
  Future<EngineMove?> bestMove(
    String fen, {
    required EngineLevel level,
    EngineUseCase useCase = EngineUseCase.bot,
  }) async {
    bestMoveCalls++;
    if (throwError != null) throw throwError!;
    if (fail) throw StateError('remote down');
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
    return EngineMove(move: move, uci: move.toUci(), source: source);
  }

  @override
  Future<GameAnalysis> analyze({
    required String startingFen,
    required List<String> moveUcis,
  }) async {
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
