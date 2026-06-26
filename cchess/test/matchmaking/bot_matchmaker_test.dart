import 'dart:math';

import 'package:cchess/core/chess_engine/ai/engine_config.dart'
    show kMinBotElo, kMaxBotElo;
import 'package:cchess/core/matchmaking/bot_matchmaker.dart';
import 'package:flutter_test/flutter_test.dart';

/// A [Random] whose `nextInt` always returns a fixed index, so we can force
/// pickBot down each of its three bracket branches.
class _FixedRandom implements Random {
  _FixedRandom(this.fixed);
  final int fixed;

  @override
  int nextInt(int max) => fixed;

  @override
  double nextDouble() => 0;

  @override
  bool nextBool() => false;
}

// Index → offset: 0 → −100 (lower), 1 → 0 (equal), 2 → +100 (higher).
final _lower = _FixedRandom(0);
final _equal = _FixedRandom(1);
final _higher = _FixedRandom(2);

void main() {
  group('pickBot', () {
    test('produces the three brackets for a mid-ladder player', () {
      expect(
        pickBot(1500, rng: _lower),
        const BotMatch(botElo: 1400, bracket: EloBracket.lower),
      );
      expect(
        pickBot(1500, rng: _equal),
        const BotMatch(botElo: 1500, bracket: EloBracket.equal),
      );
      expect(
        pickBot(1500, rng: _higher),
        const BotMatch(botElo: 1600, bracket: EloBracket.higher),
      );
    });

    test('floor player is never matched below the floor', () {
      // Rolling "lower" at the floor must clamp to an equal match, not 900.
      final match = pickBot(kMinBotElo, rng: _lower);
      expect(match.botElo, kMinBotElo);
      expect(match.bracket, EloBracket.equal);

      expect(
        pickBot(kMinBotElo, rng: _higher),
        const BotMatch(botElo: 1100, bracket: EloBracket.higher),
      );
    });

    test('ceiling player is never matched above the ceiling', () {
      final match = pickBot(kMaxBotElo, rng: _higher);
      expect(match.botElo, kMaxBotElo);
      expect(match.bracket, EloBracket.equal);

      expect(
        pickBot(kMaxBotElo, rng: _lower),
        const BotMatch(botElo: 2800, bracket: EloBracket.lower),
      );
    });

    test('clamps an out-of-range player into the ladder', () {
      // A sub-floor player is treated as if at the floor.
      final match = pickBot(700, rng: _lower);
      expect(match.botElo, kMinBotElo);
      expect(match.bracket, EloBracket.equal);
    });

    test('always returns an in-range bot with a consistent bracket', () {
      final rng = Random(42);
      for (var i = 0; i < 1000; i++) {
        final playerElo = kMinBotElo + rng.nextInt(kMaxBotElo - kMinBotElo + 1);
        final match = pickBot(playerElo, rng: rng);

        expect(match.botElo, inInclusiveRange(kMinBotElo, kMaxBotElo));
        switch (match.bracket) {
          case EloBracket.lower:
            expect(match.botElo, lessThan(playerElo));
          case EloBracket.equal:
            expect(match.botElo, playerElo);
          case EloBracket.higher:
            expect(match.botElo, greaterThan(playerElo));
        }
      }
    });
  });
}
