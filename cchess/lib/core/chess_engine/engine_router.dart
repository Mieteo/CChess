import 'dart:async';

import 'ai/engine_config.dart';
import 'ai/game_analyzer.dart';
import 'engine_quota.dart';
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
    EngineConfig? config,
  }) async {
    String? fallbackReason;
    EngineFallbackKind? fallbackKind;
    if (await _shouldTryRemote(level, useCase, config)) {
      try {
        final result = await remote!.bestMove(
          fen,
          level: level,
          useCase: useCase,
          config: config,
        );
        if (result != null) return result;
      } on EngineQuotaExceededException catch (error) {
        fallbackReason = error.toString();
        fallbackKind = EngineFallbackKind.quotaExceeded;
      } catch (error) {
        fallbackReason = error.toString();
        fallbackKind = EngineFallbackKind.network;
      }
    }

    final fallback = await local.bestMove(
      fen,
      level: level,
      useCase: useCase,
      config: config,
    );
    if (fallback == null || fallbackReason == null) return fallback;
    return fallback.copyWith(
      usedFallback: true,
      fallbackReason: fallbackReason,
      fallbackKind: fallbackKind,
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
    EngineConfig? config,
  ) async {
    if (!await _remoteAvailable()) return false;
    if (useCase == EngineUseCase.hint || useCase == EngineUseCase.analysis) {
      return true;
    }
    // ELO ladder: the config decides which engine plays. Legacy callers
    // (config == null) keep the old "grandmaster tier → remote" behaviour.
    if (config != null) return config.engine == EngineSource.remotePikafish;
    return level == EngineLevel.grandmaster;
  }

  Future<bool> _remoteAvailable() async {
    if (!remoteEnabled || remote == null) return false;
    final probe = _canUseRemote;
    if (probe == null) return true;
    return Future<bool>.value(probe());
  }
}
