import 'package:cchess/core/chess_engine/chess_engine.dart';
import 'package:flutter_test/flutter_test.dart';

/// A scalar proxy for "how strong is this config". Higher = stronger. Used only
/// to assert the ladder is monotonic; the exact formula doesn't matter as long
/// as engine source dominates depth, which dominates the blunder rate.
int _strength(EngineConfig c) {
  return c.engine.index * 1000000 +
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
      // Top band plays at the engine's actual best move — no blunders.
      expect(configForElo(kMaxBotElo).blunderRate, 0);
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

    test('Pikafish bands carry movetime + a valid blunderRate', () {
      final c = configForElo(2300);
      expect(c.engine, EngineSource.remotePikafish);
      expect(c.movetimeMs, isNotNull);
      expect(c.blunderRate, inInclusiveRange(0, 1));
    });

    test('Pikafish blunderRate decreases as ELO rises, reaching 0 at the top', () {
      final rates = [2000, 2200, 2400, 2600, 2800]
          .map((elo) => configForElo(elo).blunderRate)
          .toList();
      for (var i = 1; i < rates.length; i++) {
        expect(rates[i], lessThanOrEqualTo(rates[i - 1]), reason: 'index $i');
      }
      expect(rates.last, 0);
    });

    test('local bands carry no Pikafish-only fields', () {
      for (final elo in [1000, 1250, 1500, 1800]) {
        expect(configForElo(elo).movetimeMs, isNull, reason: 'elo=$elo');
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
