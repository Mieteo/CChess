import type { RandomSource } from './random';

export type SimColor = 'red' | 'black';

export interface MoveContext {
  uid: string;
  roomId: string;
  color: SimColor;
  movesUci: string[];
  fen?: string;
  nowMs: number;
  random: RandomSource;
}

export interface MovePolicy {
  readonly name: string;
  chooseMove(ctx: MoveContext): Promise<string | null>;
}

