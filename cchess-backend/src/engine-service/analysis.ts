import { parseUci, PieceColor, XiangqiGame } from '../engine';
import { normalizeFen, normalizeUci } from './fen';
import type { EngineBestMove, EngineLimit, MoveClassification } from './types';
import { EngineServiceError, type EngineAnalyzeMove, type EngineAnalyzeResult } from './types';

export interface BestMoveResolver {
  (fen: string, limit: EngineLimit): Promise<EngineBestMove>;
}

export async function analyzeGame(
  startingFen: string,
  moveUcis: string[],
  limit: EngineLimit,
  resolveBestMove: BestMoveResolver,
): Promise<EngineAnalyzeResult> {
  const game = XiangqiGame.fromFen(normalizeFen(startingFen));
  const perMove: EngineAnalyzeMove[] = [];

  for (let i = 0; i < moveUcis.length; i++) {
    const uci = normalizeUci(moveUcis[i]);
    const beforeFen = game.toFen();
    const best = await resolveBestMove(beforeFen, limit);

    const coords = parseUci(uci);
    if (!coords || !game.isValidMove(coords.from, coords.to)) {
      throw new EngineServiceError(400, 'illegal-move', `Illegal move at index ${i}: ${uci}`);
    }

    game.makeMove(coords.from, coords.to);
    const actual = await resolveBestMove(game.toFen(), limit);
    const actualFromMoverPerspective = actual.scoreCp === null ? null : -actual.scoreCp;
    const cpLoss = centipawnLoss(best.scoreCp, actualFromMoverPerspective);
    perMove.push({
      moveIndex: i,
      uci,
      bestUci: best.uci,
      scoreCp: best.scoreCp,
      actualScoreCp: actualFromMoverPerspective,
      centipawnLoss: cpLoss,
      classification: classifyMove(cpLoss, best.uci === uci),
      depth: best.depth,
    });
    if (game.status !== 'playing') break;
  }

  return {
    perMove,
    summary: summarize(perMove, startingFen),
  };
}

export function classifyMove(cpLoss: number, isBestMove: boolean): MoveClassification {
  if (isBestMove) return 'best';
  if (cpLoss <= 15) return 'excellent';
  if (cpLoss <= 60) return 'good';
  if (cpLoss <= 150) return 'inaccuracy';
  if (cpLoss <= 300) return 'mistake';
  return 'blunder';
}

function centipawnLoss(bestScore: number | null, actualScore: number | null): number {
  if (bestScore === null || actualScore === null) return 0;
  return Math.max(0, Math.min(1000, bestScore - actualScore));
}

function summarize(perMove: EngineAnalyzeMove[], startingFen: string): EngineAnalyzeResult['summary'] {
  const game = XiangqiGame.fromFen(normalizeFen(startingFen));
  const scores = {
    redCount: 0,
    blackCount: 0,
    redScore: 0,
    blackScore: 0,
    redBlunders: 0,
    blackBlunders: 0,
    redMistakes: 0,
    blackMistakes: 0,
  };

  for (const item of perMove) {
    const isRed = game.turn === PieceColor.Red;
    const score = scoreOut100(item.classification);
    if (isRed) {
      scores.redCount++;
      scores.redScore += score;
      if (item.classification === 'blunder') scores.redBlunders++;
      if (item.classification === 'mistake') scores.redMistakes++;
    } else {
      scores.blackCount++;
      scores.blackScore += score;
      if (item.classification === 'blunder') scores.blackBlunders++;
      if (item.classification === 'mistake') scores.blackMistakes++;
    }
    const coords = parseUci(item.uci);
    if (!coords || !game.isValidMove(coords.from, coords.to)) break;
    game.makeMove(coords.from, coords.to);
  }

  return {
    redAccuracy: scores.redCount === 0 ? 0 : scores.redScore / scores.redCount,
    blackAccuracy: scores.blackCount === 0 ? 0 : scores.blackScore / scores.blackCount,
    redBlunders: scores.redBlunders,
    blackBlunders: scores.blackBlunders,
    redMistakes: scores.redMistakes,
    blackMistakes: scores.blackMistakes,
  };
}

function scoreOut100(classification: MoveClassification): number {
  switch (classification) {
    case 'best':
      return 100;
    case 'excellent':
      return 95;
    case 'good':
      return 80;
    case 'inaccuracy':
      return 60;
    case 'mistake':
      return 30;
    case 'blunder':
      return 0;
  }
}
