import 'dart:async';

import 'ai/engine_config.dart';
import 'ai/game_analyzer.dart';
import 'engine_quota.dart';
import 'local_minimax_engine.dart';
import 'move_engine.dart';

typedef EngineAvailabilityProbe = FutureOr<bool> Function();

/// Routes engine work across up to three tiers:
///
///   1. [remote]  — server Pikafish (strongest, costs quota, needs network);
///   2. [offline] — on-device Pikafish child process (strong, free, only
///      present when the user installed the NNUE — see pikafish_support);
///   3. [local]   — ElephantEye/minimax (always available, weakest).
///
/// Offline Pikafish is deliberately *not* used for beatable bot tiers — those
/// keep the tuned minimax/ElephantEye feel — only where full strength is
/// wanted: hints, analysis, and the ELO bands that would have gone to the
/// server.
class EngineRouter implements MoveEngine {
  EngineRouter({
    MoveEngine? local,
    this.remote,
    this.offline,
    EngineAvailabilityProbe? canUseRemote,
    EngineAvailabilityProbe? canUseOffline,
    this.remoteEnabled = true,
  })  : local = local ?? LocalMinimaxEngine(),
        _canUseRemote = canUseRemote,
        _canUseOffline = canUseOffline;

  final MoveEngine local;
  final MoveEngine? remote;
  final MoveEngine? offline;
  final EngineAvailabilityProbe? _canUseRemote;
  final EngineAvailabilityProbe? _canUseOffline;
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

    // Server unavailable (or not wanted): a strong request goes to on-device
    // Pikafish when it's installed, before degrading to minimax/ElephantEye.
    if (_wantsFullStrength(level, useCase, config) &&
        await _offlineAvailable()) {
      try {
        final result = await offline!.bestMove(
          fen,
          level: level,
          useCase: useCase,
          config: config,
        );
        if (result != null) {
          return fallbackReason == null
              ? result
              : result.copyWith(
                  usedFallback: true,
                  fallbackReason: fallbackReason,
                  fallbackKind: fallbackKind,
                );
        }
      } catch (error) {
        fallbackReason ??= error.toString();
        fallbackKind ??= EngineFallbackKind.network;
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
        // Fall through to the offline / local analyzers.
      }
    }
    if (await _offlineAvailable()) {
      try {
        return await offline!.analyze(
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
    return _wantsFullStrength(level, useCase, config);
  }

  /// Requests that deserve the strongest engine we can reach: hints and
  /// analysis always; bot play only for the Pikafish ELO bands (legacy
  /// callers: grandmaster tier). Beatable bands keep the local engines.
  bool _wantsFullStrength(
    EngineLevel level,
    EngineUseCase useCase,
    EngineConfig? config,
  ) {
    if (useCase == EngineUseCase.hint || useCase == EngineUseCase.analysis) {
      return true;
    }
    if (config != null) return config.engine == EngineSource.remotePikafish;
    return level == EngineLevel.grandmaster;
  }

  Future<bool> _remoteAvailable() async {
    if (!remoteEnabled || remote == null) return false;
    final probe = _canUseRemote;
    if (probe == null) return true;
    return Future<bool>.value(probe());
  }

  Future<bool> _offlineAvailable() async {
    if (offline == null) return false;
    final probe = _canUseOffline;
    if (probe == null) return true;
    return Future<bool>.value(probe());
  }
}
