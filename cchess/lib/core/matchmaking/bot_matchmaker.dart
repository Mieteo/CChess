import 'dart:math';

import '../chess_engine/ai/engine_config.dart' show kMinBotElo, kMaxBotElo;

/// Where a matched bot's ELO sits relative to the player.
///
/// Drives the asymmetric scoring in `eloDelta`: punching up ([higher]) is
/// rewarded, grinding weaker bots ([lower]) is mildly penalised, and an even
/// match ([equal]) is a fair ±.
enum EloBracket { lower, equal, higher }

/// ELO gap between the player and a non-equal-bracket bot (±100).
const int kBracketSpread = 100;

/// The result of matchmaking: a concrete bot ELO and which bracket it landed in.
///
/// The bracket always reflects the *actual* [botElo] after clamping — so a
/// player at the floor who rolls "lower" gets an [equal] match against a
/// floor bot, never a sub-floor opponent.
class BotMatch {
  final int botElo;
  final EloBracket bracket;

  const BotMatch({required this.botElo, required this.bracket});

  @override
  bool operator ==(Object other) =>
      other is BotMatch && other.botElo == botElo && other.bracket == bracket;

  @override
  int get hashCode => Object.hash(botElo, bracket);

  @override
  String toString() => 'BotMatch(botElo: $botElo, bracket: ${bracket.name})';
}

/// Pick a bot for [playerElo]: uniformly choose one of the three brackets
/// (−100 / equal / +100), then clamp the resulting ELO into the ladder range.
///
/// [playerElo] itself is clamped to `[kMinBotElo, kMaxBotElo]` so out-of-range
/// players (e.g. a fresh account below 1000) still get sane matches. Pass [rng]
/// to make the draw deterministic in tests.
BotMatch pickBot(int playerElo, {Random? rng}) {
  final random = rng ?? Random();
  final base = playerElo.clamp(kMinBotElo, kMaxBotElo).toInt();

  const offsets = <int>[-kBracketSpread, 0, kBracketSpread];
  final offset = offsets[random.nextInt(offsets.length)];
  final botElo = (base + offset).clamp(kMinBotElo, kMaxBotElo).toInt();

  return BotMatch(botElo: botElo, bracket: _bracketFor(base, botElo));
}

EloBracket _bracketFor(int playerElo, int botElo) {
  if (botElo > playerElo) return EloBracket.higher;
  if (botElo < playerElo) return EloBracket.lower;
  return EloBracket.equal;
}
