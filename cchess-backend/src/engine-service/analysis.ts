import { GameStatus, parseUci, PieceColor, XiangqiGame } from '../engine';
import { normalizeFen, normalizeUci } from './fen';
import type { EngineBestMove, EngineLimit, MoveClassification } from './types';
import { EngineServiceError, type EngineAnalyzeMove, type EngineAnalyzeResult } from './types';

export interface BestMoveResolver {
  (fen: string, limit: EngineLimit): Promise<EngineBestMove>;
}

export interface AnalyzeProgress {
  completedMoves: number;
  totalMoves: number;
  latest: EngineAnalyzeMove;
}

export async function analyzeGame(
  startingFen: string,
  moveUcis: string[],
  limit: EngineLimit,
  resolveBestMove: BestMoveResolver,
  onProgress?: (progress: AnalyzeProgress) => void,
): Promise<EngineAnalyzeResult> {
  const game = XiangqiGame.fromFen(normalizeFen(startingFen));
  const perMove: EngineAnalyzeMove[] = [];

  // One search per POSITION, not two per move: the position after move i IS
  // the position before move i+1, so a single search serves both as move i's
  // verdict and move i+1's baseline. N moves cost N+1 searches (half the old
  // bill) and the eval series is self-consistent by construction.
  let current = await resolveBestMove(game.toFen(), limit);

  for (let i = 0; i < moveUcis.length; i++) {
    const uci = normalizeUci(moveUcis[i]);
    const coords = parseUci(uci);
    if (!coords || !game.isValidMove(coords.from, coords.to)) {
      throw new EngineServiceError(400, 'illegal-move', `Illegal move at index ${i}: ${uci}`);
    }

    const mover = game.turn;
    game.makeMove(coords.from, coords.to);

    let next: EngineBestMove | null = null;
    let actualFromMoverPerspective: number | null;
    if (game.status !== GameStatus.Playing) {
      // The mover just ended the game — score it directly, no search needed.
      actualFromMoverPerspective = terminalScore(game.status, mover);
    } else {
      next = await resolveBestMove(game.toFen(), limit);
      // `next` is scored from the opponent's (side to move) perspective.
      actualFromMoverPerspective = next.scoreCp === null ? null : -next.scoreCp;
    }

    const cpLoss = centipawnLoss(current.scoreCp, actualFromMoverPerspective);
    const analyzed: EngineAnalyzeMove = {
      moveIndex: i,
      uci,
      bestUci: current.uci,
      scoreCp: current.scoreCp,
      actualScoreCp: actualFromMoverPerspective,
      evalAfterCp: actualFromMoverPerspective === null
        ? null
        : mover === PieceColor.Red
          ? actualFromMoverPerspective
          : -actualFromMoverPerspective,
      centipawnLoss: cpLoss,
      classification: classifyMove(cpLoss, current.uci === uci),
      depth: current.depth,
    };
    perMove.push(analyzed);
    onProgress?.({ completedMoves: i + 1, totalMoves: moveUcis.length, latest: analyzed });

    if (game.status !== GameStatus.Playing || next === null) break;
    current = next;
  }

  return {
    perMove,
    summary: summarize(perMove, startingFen),
  };
}

/** Mover-perspective score for a game the mover's move just finished:
 * ±29999 for a win/loss (matches the mate scale) or 0 for a draw. */
function terminalScore(status: GameStatus, mover: PieceColor): number {
  if (status === GameStatus.Draw) return 0;
  const moverWon = (status === GameStatus.RedWin) === (mover === PieceColor.Red);
  return moverWon ? 29_999 : -29_999;
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
