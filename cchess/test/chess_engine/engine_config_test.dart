import 'package:cchess/core/chess_engine/chess_engine.dart';
import 'package:flutter_test/flutter_test.dart';

/// A scalar proxy for "how strong is this config". Higher = stronger. Used only
/// to assert the ladder is monotonic; the exact formula doesn't matter as long
/// as engine source dominates depth/skill, which dominate the blunder rate.
int _strength(EngineConfig c) {
  return c.engine.index * 1000000 +
      (c.skillLevel ?? 0) * 1000 +
      (c.uciElo ?? 0) +
      c.depth * 100 -
      (c.blunderRate * 1000).round();
}

void main() {
  group('configForElo', () {
    test('clamps below the floor to the weakest config', () {
      expect(configForElo(500), configForElo(kMinBotElo));
      expect(configForElo(kMinBotElo).engine, EngineSource.localMinimax);
      expect(configForElo(kMinBotElo).depth, 1);
      expect(configForElo(kMinBotElo).blunderRate, greaterThan(0));
    });

    test('clamps above the ceiling to the strongest config', () {
      expect(configForElo(5000), configForElo(kMaxBotElo));
      expect(configForElo(kMaxBotElo).engine, EngineSource.remotePikafish);
      expect(configForElo(kMaxBotElo).skillLevel, 20);
    });

    test('picks the right engine per band', () {
      expect(configForElo(1000).engine, EngineSource.localMinimax);
      expect(configForElo(1399).engine, EngineSource.localMinimax);
      expect(configForElo(1500).engine, EngineSource.localElephantEye);
      expect(configForElo(1999).engine, EngineSource.localElephantEye);
      expect(configForElo(2000).engine, EngineSource.remotePikafish);
      expect(configForElo(2900).engine, EngineSource.remotePikafish);
    });

    test('band edges are inclusive on the lower bound', () {
      // 1400 is the top of the minimax range; 1399 is one band lower.
      expect(configForElo(1400).blunderRate, lessThan(configForElo(1399).blunderRate));
      // 1500 crosses minimax -> ElephantEye.
      expect(configForElo(1499).engine, EngineSource.localMinimax);
      expect(configForElo(1500).engine, EngineSource.localElephantEye);
    });

    test('Pikafish bands carry skill + uciElo + movetime', () {
      final c = configForElo(2300);
      expect(c.engine, EngineSource.remotePikafish);
      expect(c.skillLevel, isNotNull);
      expect(c.uciElo, isNotNull);
      expect(c.movetimeMs, isNotNull);
    });

    test('local bands carry no Pikafish-only fields', () {
      for (final elo in [1000, 1250, 1500, 1800]) {
        final c = configForElo(elo);
        expect(c.skillLevel, isNull, reason: 'elo=$elo');
        expect(c.uciElo, isNull, reason: 'elo=$elo');
        expect(c.movetimeMs, isNull, reason: 'elo=$elo');
      }
    });

    test('strength is monotonic non-decreasing across the whole ladder', () {
      var previous = _strength(configForElo(kMinBotElo));
      for (var elo = kMinBotElo; elo <= kMaxBotElo; elo += 10) {
        final current = _strength(configForElo(elo));
        expect(
          current,
          greaterThanOrEqualTo(previous),
          reason: 'strength dropped at elo=$elo',
        );
        previous = current;
      }
    });

    test('every 200-ELO step is strictly stronger', () {
      for (var elo = kMinBotElo; elo + 200 <= kMaxBotElo; elo += 200) {
        expect(
          _strength(configForElo(elo + 200)),
          greaterThan(_strength(configForElo(elo))),
          reason: 'elo $elo -> ${elo + 200}',
        );
      }
    });
  });
}
