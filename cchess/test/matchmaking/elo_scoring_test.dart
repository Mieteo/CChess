import 'package:cchess/core/matchmaking/bot_matchmaker.dart' show EloBracket;
import 'package:cchess/core/matchmaking/elo_scoring.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('eloDelta', () {
    test('equal bracket is a fair ±10', () {
      expect(eloDelta(bracket: EloBracket.equal, won: true, drew: false), 10);
      expect(eloDelta(bracket: EloBracket.equal, won: false, drew: false), -10);
    });

    test('higher bracket rewards punching up (+15 / -5)', () {
      expect(eloDelta(bracket: EloBracket.higher, won: true, drew: false), 15);
      expect(eloDelta(bracket: EloBracket.higher, won: false, drew: false), -5);
    });

    test('lower bracket penalises farming (+5 / -10)', () {
      expect(eloDelta(bracket: EloBracket.lower, won: true, drew: false), 5);
      expect(eloDelta(bracket: EloBracket.lower, won: false, drew: false), -10);
    });

    test('a draw is always 0 and takes precedence over won', () {
      for (final bracket in EloBracket.values) {
        expect(eloDelta(bracket: bracket, won: false, drew: true), 0);
        expect(eloDelta(bracket: bracket, won: true, drew: true), 0);
      }
    });

    test('incentive ordering: punching up pays best, farming pays worst', () {
      expect(EloScoring.higherWin, greaterThan(EloScoring.equalWin));
      expect(EloScoring.equalWin, greaterThan(EloScoring.lowerWin));
      // Losing to a stronger bot is the cheapest defeat.
      expect(EloScoring.higherLoss, greaterThan(EloScoring.equalLoss));
    });

    test('expected value matches the design (doc 13 §4)', () {
      // E[Δ] = p·win + (1-p)·loss, with the design win probabilities.
      double expected(double p, int win, int loss) => p * win + (1 - p) * loss;

      // Equal match (p≈0.50) is drift-free.
      expect(
        expected(0.50, EloScoring.equalWin, EloScoring.equalLoss),
        closeTo(0.0, 1e-9),
      );
      // Higher bracket (p≈0.36) nets positive → encourages playing up.
      expect(
        expected(0.36, EloScoring.higherWin, EloScoring.higherLoss),
        closeTo(2.2, 1e-9),
      );
      // Lower bracket (p≈0.64) nets negative → discourages farming.
      expect(
        expected(0.64, EloScoring.lowerWin, EloScoring.lowerLoss),
        closeTo(-0.4, 1e-9),
      );
    });
  });
}
