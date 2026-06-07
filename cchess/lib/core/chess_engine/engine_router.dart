import 'dart:async';

import 'ai/game_analyzer.dart';
import 'local_minimax_engine.dart';
import 'move_engine.dart';

typedef EngineAvailabilityProbe = FutureOr<bool> Function();

class EngineRouter implements MoveEngine {
  EngineRouter({
    MoveEngine? local,
    this.remote,
    EngineAvailabilityProbe? canUseRemote,
    this.remoteEnabled = true,
  }) : local = local ?? LocalMinimaxEngine(),
       _canUseRemote = canUseRemote;

  final MoveEngine local;
  final MoveEngine? remote;
  final EngineAvailabilityProbe? _canUseRemote;
  final bool remoteEnabled;

  @override
  Future<EngineMove?> bestMove(
    String fen, {
    required EngineLevel level,
    EngineUseCase useCase = EngineUseCase.bot,
  }) async {
    String? fallbackReason;
    if (await _shouldTryRemote(level, useCase)) {
      try {
        final result = await remote!.bestMove(
          fen,
          level: level,
          useCase: useCase,
        );
        if (result != null) return result;
      } catch (error) {
        fallbackReason = error.toString();
      }
    }

    final fallback = await local.bestMove(fen, level: level, useCase: useCase);
    if (fallback == null || fallbackReason == null) return fallback;
    return fallback.copyWith(
      usedFallback: true,
      fallbackReason: fallbackReason,
    );
  }

  @override
  Future<GameAnalysis> analyze({
    required String startingFen,
    required List<String> moveUcis,
  }) async {
    if (await _remoteAvailable()) {
      try {
        return await remote!.analyze(
          startingFen: startingFen,
          moveUcis: moveUcis,
        );
      } catch (_) {
        // Fall through to the offline analyzer.
      }
    }
    return local.analyze(startingFen: startingFen, moveUcis: moveUcis);
  }

  Future<bool> _shouldTryRemote(
    EngineLevel level,
    EngineUseCase useCase,
  ) async {
    if (!await _remoteAvailable()) return false;
    if (useCase == EngineUseCase.hint || useCase == EngineUseCase.analysis) {
      return true;
    }
    return level == EngineLevel.grandmaster;
  }

  Future<bool> _remoteAvailable() async {
    if (!remoteEnabled || remote == null) return false;
    final probe = _canUseRemote;
    if (probe == null) return true;
    return Future<bool>.value(probe());
  }
}
