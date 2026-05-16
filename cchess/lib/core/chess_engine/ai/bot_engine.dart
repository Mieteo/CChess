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

  /// Pick a move for the side currently to move. Returns null when the
  /// position has no legal moves (caller should handle game-over).
  Future<Move?> chooseMove(
    XiangqiGame game,
    BotDifficulty difficulty,
  ) async {
    if (game.status.isOver) return null;
    final settings = difficulty.settings;
    final input = _BotSearchInput(
      fen: game.toFen(),
      depth: settings.depth,
      randomChance: settings.randomMoveChance,
      suboptimalChance: settings.suboptimalChance,
      // Seeded so deterministic in tests, but the seed itself includes time
      // so production play feels non-repeating.
      seed: DateTime.now().microsecondsSinceEpoch,
    );

    final startedAt = DateTime.now();

    // On web `compute` falls back to running synchronously — that's fine for
    // our depth, and lets unit tests run without spawning isolates.
    final uci = await compute(_runSearch, input);

    // Honor the minimum think time so users have a moment to read the move.
    final elapsed = DateTime.now().difference(startedAt);
    if (elapsed < settings.minThinkTime) {
      await Future.delayed(settings.minThinkTime - elapsed);
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
  final search = Minimax(depth: input.depth, seed: input.seed);
  final result = search.choose(
    game,
    randomChance: input.randomChance,
    suboptimalChance: input.suboptimalChance,
  );
  return result?.move.toUci();
}

class _BotSearchInput {
  final String fen;
  final int depth;
  final double randomChance;
  final double suboptimalChance;
  final int seed;

  const _BotSearchInput({
    required this.fen,
    required this.depth,
    required this.randomChance,
    required this.suboptimalChance,
    required this.seed,
  });
}
