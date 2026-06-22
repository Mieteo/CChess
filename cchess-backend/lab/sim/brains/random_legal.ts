import type { MoveContext, MovePolicy } from '../brain';
import { gameFromHistory, isCorrectTurn, legalMovesForTurn } from './helpers';

export class RandomLegalPolicy implements MovePolicy {
  readonly name = 'random-legal';

  async chooseMove(ctx: MoveContext): Promise<string | null> {
    const game = gameFromHistory(ctx);
    if (!isCorrectTurn(game, ctx.color)) return null;

    const legal = legalMovesForTurn(game).map((move) => move.uci);
    return legal.length === 0 ? null : ctx.random.pick(legal);
  }
}
