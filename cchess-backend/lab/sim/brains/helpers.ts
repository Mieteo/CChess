import {
  GameStatus,
  parseUci,
  PieceColor,
  XiangqiGame,
  uciOfMove,
  type Piece,
} from '../../../src/engine';
import type { Position } from '../../../src/engine';
import type { MoveContext, SimColor } from '../brain';

export interface LegalMove {
  uci: string;
  from: Position;
  to: Position;
  moved: Piece;
  captured: Piece | null;
}

export function pieceColorOf(color: SimColor): PieceColor {
  return color === 'red' ? PieceColor.Red : PieceColor.Black;
}

export function gameFromHistory(ctx: MoveContext): XiangqiGame {
  const game = ctx.fen ? XiangqiGame.fromFen(ctx.fen) : XiangqiGame.initial();
  for (const uci of ctx.movesUci) {
    const parsed = parseUci(uci);
    if (!parsed) throw new Error(`invalid historical UCI ${uci}`);
    game.makeMove(parsed.from, parsed.to);
  }
  return game;
}

export function legalMovesForTurn(game: XiangqiGame): LegalMove[] {
  if (game.status !== GameStatus.Playing) return [];
  const legal: LegalMove[] = [];
  for (const [from, piece] of game.board.occupied()) {
    if (piece.color !== game.turn) continue;
    for (const to of game.getValidMoves(from)) {
      legal.push({
        uci: uciOfMove(from, to),
        from,
        to,
        moved: piece,
        captured: game.board.at(to),
      });
    }
  }
  return legal;
}

export function legalUciSet(game: XiangqiGame): Set<string> {
  return new Set(legalMovesForTurn(game).map((move) => move.uci));
}

export function isCorrectTurn(game: XiangqiGame, color: SimColor): boolean {
  return game.status === GameStatus.Playing && game.turn === pieceColorOf(color);
}

export function gameAfterMove(game: XiangqiGame, uci: string): XiangqiGame | null {
  const parsed = parseUci(uci);
  if (!parsed) return null;
  const copy = XiangqiGame.fromFen(game.toFen());
  try {
    copy.makeMove(parsed.from, parsed.to);
    return copy;
  } catch {
    return null;
  }
}
