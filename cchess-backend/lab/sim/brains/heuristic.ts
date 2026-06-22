import { GameStatus, PieceColor, PieceType, type Position, type XiangqiGame } from '../../../src/engine';
import type { MoveContext, MovePolicy } from '../brain';
import {
  gameAfterMove,
  gameFromHistory,
  isCorrectTurn,
  legalMovesForTurn,
  type LegalMove,
} from './helpers';
import { RandomLegalPolicy } from './random_legal';

const PIECE_VALUES: Readonly<Record<PieceType, number>> = {
  [PieceType.General]: 10_000,
  [PieceType.Chariot]: 90,
  [PieceType.Cannon]: 45,
  [PieceType.Horse]: 45,
  [PieceType.Elephant]: 22,
  [PieceType.Advisor]: 20,
  [PieceType.Soldier]: 12,
};

export class HeuristicPolicy implements MovePolicy {
  readonly name = 'heuristic';
  private readonly fallback = new RandomLegalPolicy();

  async chooseMove(ctx: MoveContext): Promise<string | null> {
    const game = gameFromHistory(ctx);
    if (!isCorrectTurn(game, ctx.color)) return null;

    const legal = legalMovesForTurn(game);
    if (legal.length === 0) return null;

    const scored = legal.map((move) => ({
      move,
      score: scoreMove(game, move) + ctx.random.next() * 0.75,
    }));
    scored.sort((a, b) => b.score - a.score);

    const best = scored[0]?.score;
    if (best === undefined) return this.fallback.chooseMove(ctx);
    const candidates = scored
      .filter((entry, index) => index < 4 || best - entry.score <= 8)
      .map((entry) => entry.move.uci);
    return ctx.random.pick(candidates);
  }
}

function scoreMove(game: XiangqiGame, move: LegalMove): number {
  const after = gameAfterMove(game, move.uci);
  if (!after) return -10_000;

  let score = 0;
  if (move.captured) score += PIECE_VALUES[move.captured.type] * 1.8;
  if (after.status !== GameStatus.Playing) score += 20_000;
  else if (after.isInCheck(after.turn)) score += 36;

  score += centerBonus(move.to);
  score += soldierAdvanceBonus(move);
  score -= hangingPenalty(after, move);

  return score;
}

function centerBonus(to: Position): number {
  return 5 - Math.abs(4 - to.col) - Math.abs(4.5 - to.row) * 0.35;
}

function soldierAdvanceBonus(move: LegalMove): number {
  if (move.moved.type !== PieceType.Soldier) return 0;
  const direction = move.moved.color === PieceColor.Red ? -1 : 1;
  const forward = move.to.row - move.from.row === direction ? 5 : 0;
  const crossedRiver =
    move.moved.color === PieceColor.Red ? move.to.row <= 4 : move.to.row >= 5;
  return forward + (crossedRiver ? 4 : 0);
}

function hangingPenalty(after: XiangqiGame, move: LegalMove): number {
  const movedValue = PIECE_VALUES[move.moved.type];
  const capturedValue = move.captured ? PIECE_VALUES[move.captured.type] : 0;
  if (capturedValue >= movedValue) return 0;
  if (!opponentCanCapture(after, move.to)) return 0;
  return Math.min(80, (movedValue - capturedValue) * 0.55);
}

function opponentCanCapture(game: XiangqiGame, target: Position): boolean {
  for (const [from, piece] of game.board.occupied()) {
    if (piece.color !== game.turn) continue;
    for (const to of game.getValidMoves(from)) {
      if (to.equals(target)) return true;
    }
  }
  return false;
}
