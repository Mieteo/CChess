// Standard Elo rating computation for Xiangqi ranked matches.
//
// Formula:
//   E_A = 1 / (1 + 10 ^ ((R_B - R_A) / 400))
//   R_A_new = R_A + K * (S_A - E_A)
//
// where S_A is actual score: 1 win, 0.5 draw, 0 loss.
// K-factor: 32 (amateur). Production can scale per rating tier later.

import type { GameResult } from './rooms';

export const DEFAULT_RATING = 1000;
export const K_FACTOR = 32;

export interface EloUpdate {
  redOld: number;
  blackOld: number;
  redNew: number;
  blackNew: number;
  redDelta: number;
  blackDelta: number;
}

/// Compute the new Elo ratings after a finished game.
/// Returns rounded integer ratings + signed delta per side.
export function computeElo(
  redOld: number,
  blackOld: number,
  result: GameResult,
): EloUpdate {
  const expectedRed = 1 / (1 + Math.pow(10, (blackOld - redOld) / 400));
  const expectedBlack = 1 - expectedRed;

  let scoreRed: number;
  switch (result) {
    case 'red-win': scoreRed = 1; break;
    case 'black-win': scoreRed = 0; break;
    case 'draw': scoreRed = 0.5; break;
  }
  const scoreBlack = 1 - scoreRed;

  const redNewRaw = redOld + K_FACTOR * (scoreRed - expectedRed);
  const blackNewRaw = blackOld + K_FACTOR * (scoreBlack - expectedBlack);
  const redNew = Math.round(redNewRaw);
  const blackNew = Math.round(blackNewRaw);

  return {
    redOld,
    blackOld,
    redNew,
    blackNew,
    redDelta: redNew - redOld,
    blackDelta: blackNew - blackOld,
  };
}
