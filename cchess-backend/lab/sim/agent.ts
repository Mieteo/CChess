import type { MovePolicy } from './brain';
import type { SimWorld } from './world';

export interface PlayerAgent {
  readonly id: string;
  readonly uid: string;
  readonly persona: string;
  readonly brain: MovePolicy;
  start(world: SimWorld): Promise<void>;
  tick(world: SimWorld): Promise<void>;
  stop(world: SimWorld): Promise<void>;
}

