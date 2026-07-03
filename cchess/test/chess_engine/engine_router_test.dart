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

    test('routes to remote when the ELO config selects Pikafish', () async {
      final local = _FakeEngine(EngineSource.localMinimax);
      final remote = _FakeEngine(EngineSource.remotePikafish);
      final router = EngineRouter(local: local, remote: remote);

      // A mid level normally stays local, but a Pikafish config overrides it.
      final result = await router.bestMove(
        kInitialFen,
        level: EngineLevel.medium,
        config: configForElo(2300),
      );

      expect(result?.source, EngineSource.remotePikafish);
      expect(remote.bestMoveCalls, 1);
      expect(local.bestMoveCalls, 0);
      expect(remote.lastConfig, configForElo(2300));
    });

    test('stays local when the ELO config selects a local engine', () async {
      final local = _FakeEngine(EngineSource.localMinimax);
      final remote = _FakeEngine(EngineSource.remotePikafish);
      final router = EngineRouter(local: local, remote: remote);

      // grandmaster level would normally go remote — the config wins.
      final result = await router.bestMove(
        kInitialFen,
        level: EngineLevel.grandmaster,
        config: configForElo(1200),
      );

      expect(result?.source, EngineSource.localMinimax);
      expect(local.bestMoveCalls, 1);
      expect(remote.bestMoveCalls, 0);
      expect(local.lastConfig, configForElo(1200));
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
  EngineConfig? lastConfig;

  @override
  Future<EngineMove?> bestMove(
    String fen, {
    required EngineLevel level,
    EngineUseCase useCase = EngineUseCase.bot,
    EngineConfig? config,
  }) async {
    bestMoveCalls++;
    lastConfig = config;
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
    void Function(double progress)? onProgress,
    bool allowWeakFallback = true,
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
