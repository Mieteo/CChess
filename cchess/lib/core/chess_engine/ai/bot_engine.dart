import 'dart:async';

import 'package:flutter/foundation.dart';

import '../move.dart';
import '../xiangqi_game.dart';
import 'bot_difficulty.dart';
import 'minimax.dart';

/// Public API used by the game screen to ask the bot for its move.
///
/// Runs the search inside [compute] so the UI isolate stays smooth even at
/// depth 5. Callers receive a fully-resolved [Move] reconstructed against
/// the live game state.
class BotEngine {
  BotEngine();

  /// Deepest ply attempted by the best-effort (hint/analysis) search.
  static const int bestEffortMaxDepth = 6;

  /// Pick a move for the side currently to move. Returns null when the
  /// position has no legal moves (caller should handle game-over).
  ///
  /// [bestEffort] is the hint/analysis mode: no randomness, no artificial
  /// think delay, and iterative deepening bounded by [timeBudget] instead of
  /// a fixed depth — light positions search DEEPER than the bot would
  /// (up to [bestEffortMaxDepth]), heavy midgames return the depth they
  /// completed in time instead of hanging.
  Future<Move?> chooseMove(
    XiangqiGame game,
    BotDifficulty difficulty, {
    bool bestEffort = false,
    Duration timeBudget = const Duration(seconds: 2),
  }) async {
    if (game.status.isOver) return null;
    final settings = difficulty.settings;
    final input = _BotSearchInput(
      fen: game.toFen(),
      depth: settings.depth,
      randomChance: bestEffort ? 0 : settings.randomMoveChance,
      suboptimalChance: bestEffort ? 0 : settings.suboptimalChance,
      // Seeded so deterministic in tests, but the seed itself includes time
      // so production play feels non-repeating.
      seed: DateTime.now().microsecondsSinceEpoch,
      timeBudgetMs: bestEffort ? timeBudget.inMilliseconds : null,
    );

    final startedAt = DateTime.now();

    // On web `compute` falls back to running synchronously — that's fine for
    // our depth, and lets unit tests run without spawning isolates.
    final uci = await compute(_runSearch, input);

    // Honor the minimum think time so users have a moment to read the move.
    // A hint should arrive as fast as possible — skip the theatrics.
    if (!bestEffort) {
      final elapsed = DateTime.now().difference(startedAt);
      if (elapsed < settings.minThinkTime) {
        await Future.delayed(settings.minThinkTime - elapsed);
      }
    }

    if (uci == null) return null;
    final coords = Move.parseUciCoords(uci);
    if (coords == null) return null;
    final (from, to) = coords;
    final piece = game.board.at(from);
    if (piece == null) return null;
    return Move(
      from: from,
      to: to,
      moved: piece,
      captured: game.board.at(to),
    );
  }
}

/// Top-level isolate entry point. Pure function (required by compute()).
String? _runSearch(_BotSearchInput input) {
  final game = XiangqiGame.fromFen(input.fen);

  final budgetMs = input.timeBudgetMs;
  if (budgetMs == null) {
    // Bot mode: fixed depth + difficulty randomness, as before.
    final search = Minimax(depth: input.depth, seed: input.seed);
    final result = search.choose(
      game,
      randomChance: input.randomChance,
      suboptimalChance: input.suboptimalChance,
    );
    return result?.move.toUci();
  }

  // Best-effort mode: iterative deepening. Depth 2 always completes; each
  // further ply costs roughly 4-6x the previous one, so we only START the
  // next depth while elapsed time is still under a quarter of the budget —
  // total time stays around the budget even in heavy midgames.
  final stopwatch = Stopwatch()..start();
  String? best;
  for (var depth = 2; depth <= BotEngine.bestEffortMaxDepth; depth++) {
    final result = Minimax(depth: depth, seed: input.seed).choose(game);
    if (result != null) best = result.move.toUci();
    if (stopwatch.elapsedMilliseconds > budgetMs ~/ 4) break;
  }
  return best;
}

class _BotSearchInput {
  final String fen;
  final int depth;
  final double randomChance;
  final double suboptimalChance;
  final int seed;

  /// Non-null switches the search to best-effort iterative deepening.
  final int? timeBudgetMs;

  const _BotSearchInput({
    required this.fen,
    required this.depth,
    required this.randomChance,
    required this.suboptimalChance,
    required this.seed,
    this.timeBudgetMs,
  });
}
