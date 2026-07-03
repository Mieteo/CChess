import 'package:flutter/foundation.dart';

import 'ai/engine_config.dart';
import 'ai/game_analyzer.dart';
import 'ffi/eleeye_ffi.dart';
import 'local_minimax_engine.dart';
import 'move.dart';
import 'move_engine.dart';
import 'xiangqi_game.dart';

/// Local move engine backed by the native ElephantEye search (Android only).
///
/// Falls back to a pure-Dart [LocalMinimaxEngine] whenever the native engine
/// can't or shouldn't be used:
///   - the platform has no `.so` (web / iOS / desktop) or it failed to load;
///   - the requested bot tier is weak/medium — those keep the minimax engine
///     for human-like, beatable play (ElephantEye has no randomness knob);
///   - the native search returns no move (e.g. checkmate / stalemate).
///
/// Strong bot tiers (hard and above) and every hint/analysis request use the
/// native engine, giving a much stronger offline experience.
class LocalElephantEye implements MoveEngine {
  LocalElephantEye({MoveEngine? fallback, this.analysisDepth = 2})
      : _fallback =
            fallback ?? LocalMinimaxEngine(analysisDepth: analysisDepth);

  final MoveEngine _fallback;
  final int analysisDepth;

  @override
  Future<EngineMove?> bestMove(
    String fen, {
    required EngineLevel level,
    EngineUseCase useCase = EngineUseCase.bot,
    EngineConfig? config,
  }) async {
    final depth = config != null
        ? _nativeDepthForConfig(config, useCase)
        : _nativeDepthFor(level, useCase);
    if (depth == null || !EleeyeFfi.isSupported) {
      return _fallback.bestMove(
        fen,
        level: level,
        useCase: useCase,
        config: config,
      );
    }

    // Run the (blocking) native search off the UI isolate.
    final uci = await compute(_runNativeSearch, _EleeyeInput(fen, depth));
    if (uci == null) {
      // Native unavailable at runtime or no legal move — defer to the fallback.
      return _fallback.bestMove(
        fen,
        level: level,
        useCase: useCase,
        config: config,
      );
    }

    final move = _moveFromUci(fen, uci);
    if (move == null) {
      return _fallback.bestMove(
        fen,
        level: level,
        useCase: useCase,
        config: config,
      );
    }
    return EngineMove(
      move: move,
      uci: uci,
      depth: depth,
      source: EngineSource.localElephantEye,
    );
  }

  @override
  Future<GameAnalysis> analyze({
    required String startingFen,
    required List<String> moveUcis,
    void Function(double progress)? onProgress,
    bool allowWeakFallback = true,
  }) {
    // The native engine exposes no analyze entrypoint; use the Dart analyzer.
    return _fallback.analyze(
      startingFen: startingFen,
      moveUcis: moveUcis,
      onProgress: onProgress,
      allowWeakFallback: allowWeakFallback,
    );
  }

  /// Native search depth for an ELO-ladder [config], or null to defer to the
  /// minimax fallback.
  ///
  /// * minimax configs (the low/beatable band) keep the pure-Dart engine;
  /// * ElephantEye configs use their tuned native depth;
  /// * Pikafish configs only reach here when the remote call fell back to the
  ///   local engine, so play as strong as the native search reasonably allows.
  static int? _nativeDepthForConfig(EngineConfig config, EngineUseCase useCase) {
    if (useCase != EngineUseCase.bot) return 8; // strong offline hint/analysis
    switch (config.engine) {
      case EngineSource.localMinimax:
        return null;
      case EngineSource.localElephantEye:
        return config.depth;
      case EngineSource.localPikafish:
      case EngineSource.remotePikafish:
        return config.depth.clamp(6, 12);
    }
  }

  /// Native search depth for the given request, or null to defer to the
  /// minimax fallback (weak/medium bot tiers keep their tuned, beatable feel).
  static int? _nativeDepthFor(EngineLevel level, EngineUseCase useCase) {
    if (useCase != EngineUseCase.bot) return 8; // strong offline hint/analysis
    switch (level) {
      case EngineLevel.veryEasy:
      case EngineLevel.easy:
      case EngineLevel.medium:
        return null;
      case EngineLevel.hard:
        return 6;
      case EngineLevel.veryHard:
        return 8;
      case EngineLevel.grandmaster:
        return 10;
    }
  }

  static Move? _moveFromUci(String fen, String uci) {
    final coords = Move.parseUciCoords(uci);
    if (coords == null) return null;
    final game = XiangqiGame.fromFen(fen);
    final (from, to) = coords;
    final piece = game.board.at(from);
    if (piece == null) return null;
    return Move(from: from, to: to, moved: piece, captured: game.board.at(to));
  }
}

/// Isolate entry point — must be a top-level function for [compute].
String? _runNativeSearch(_EleeyeInput input) =>
    EleeyeFfi.bestMoveUci(input.fen, input.depth);

class _EleeyeInput {
  final String fen;
  final int depth;
  const _EleeyeInput(this.fen, this.depth);
}
