import {
  GameStatus,
  parseUci,
  PieceColor,
  XiangqiGame,
  uciOfMove,
} from '../../../src/engine';
import type { MoveContext, MovePolicy, SimColor } from '../brain';

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

export class RandomLegalPolicy implements MovePolicy {
  readonly name = 'random-legal';

  async chooseMove(ctx: MoveContext): Promise<string | null> {
    const game = gameFromHistory(ctx);
    if (game.status !== GameStatus.Playing) return null;
    if (game.turn !== pieceColorOf(ctx.color)) return null;

    const legal: string[] = [];
    for (const [from, piece] of game.board.occupied()) {
      if (piece.color !== game.turn) continue;
      for (const to of game.getValidMoves(from)) {
        legal.push(uciOfMove(from, to));
      }
    }
    return legal.length === 0 ? null : ctx.random.pick(legal);
  }
}

