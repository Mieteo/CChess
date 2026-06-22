import {
  GameStatus,
  parseUci,
  PieceColor,
  XiangqiGame,
  uciOfMove,
} from '../../../src/engine';
import type { MoveContext, MovePolicy, SimColor } from '../brain';
import { RandomLegalPolicy } from './random_legal';

const OPENING_LINES: readonly string[][] = [
  ['a3a4', 'a6a5', 'c3c4', 'c6c5', 'e3e4', 'e6e5'],
  ['i3i4', 'i6i5', 'g3g4', 'g6g5', 'b2e2', 'b7e7'],
  ['b0c2', 'b9c7', 'h0g2', 'h9g7', 'a0a1', 'a9a8'],
];

export class ScriptedPolicy implements MovePolicy {
  readonly name = 'scripted';
  private readonly fallback = new RandomLegalPolicy();

  constructor(private readonly lines: readonly string[][] = OPENING_LINES) {}

  async chooseMove(ctx: MoveContext): Promise<string | null> {
    const game = gameFromHistory(ctx);
    if (game.status !== GameStatus.Playing) return null;
    if (game.turn !== pieceColorOf(ctx.color)) return null;

    const legal = legalMoves(game);
    for (const line of this.lines) {
      const candidate = line[ctx.movesUci.length];
      if (candidate && legal.has(candidate)) return candidate;
    }
    return this.fallback.chooseMove(ctx);
  }
}

function pieceColorOf(color: SimColor): PieceColor {
  return color === 'red' ? PieceColor.Red : PieceColor.Black;
}

function gameFromHistory(ctx: MoveContext): XiangqiGame {
  const game = ctx.fen ? XiangqiGame.fromFen(ctx.fen) : XiangqiGame.initial();
  for (const uci of ctx.movesUci) {
    const parsed = parseUci(uci);
    if (!parsed) throw new Error(`invalid historical UCI ${uci}`);
    game.makeMove(parsed.from, parsed.to);
  }
  return game;
}

function legalMoves(game: XiangqiGame): Set<string> {
  const legal = new Set<string>();
  for (const [from, piece] of game.board.occupied()) {
    if (piece.color !== game.turn) continue;
    for (const to of game.getValidMoves(from)) {
      legal.add(uciOfMove(from, to));
    }
  }
  return legal;
}

