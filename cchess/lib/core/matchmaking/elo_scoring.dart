import 'bot_matchmaker.dart' show EloBracket;

/// Fixed, asymmetric ELO rewards for ranked games against bots.
///
/// This replaces the K-factor formula for vs-bot results (doc 13 §4). The
/// numbers are deliberately simple constants so they're easy to re-tune:
///   * equal  : +10 / −10  → fair, zero expected drift at a 50% win rate;
///   * higher : +15 / −5   → punching up is encouraged;
///   * lower  : +5  / −10  → grinding weaker bots is mildly penalised;
///   * draw   : 0 in every bracket.
class EloScoring {
  EloScoring._();

  static const int equalWin = 10;
  static const int equalLoss = -10;
  static const int higherWin = 15;
  static const int higherLoss = -5;
  static const int lowerWin = 5;
  static const int lowerLoss = -10;
  static const int draw = 0;
}

/// ELO delta to apply after a ranked bot game.
///
/// [drew] takes precedence over [won]; a draw is always [EloScoring.draw] (0).
int eloDelta({
  required EloBracket bracket,
  required bool won,
  required bool drew,
}) {
  if (drew) return EloScoring.draw;
  switch (bracket) {
    case EloBracket.equal:
      return won ? EloScoring.equalWin : EloScoring.equalLoss;
    case EloBracket.higher:
      return won ? EloScoring.higherWin : EloScoring.higherLoss;
    case EloBracket.lower:
      return won ? EloScoring.lowerWin : EloScoring.lowerLoss;
  }
}
