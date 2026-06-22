import { Bot, type Msg } from '../bot';
import type { PlayerAgent } from './agent';
import type { MovePolicy } from './brain';
import type { SimWorld } from './world';

export class CasualPlayer implements PlayerAgent {
  private bot?: Bot;

  constructor(
    readonly id: string,
    readonly uid: string,
    readonly brain: MovePolicy,
  ) {}

  readonly persona = 'casual';

  async start(world: SimWorld): Promise<void> {
    this.bot = await world.connectBot(this);
  }

  async tick(_world: SimWorld): Promise<void> {
    return Promise.resolve();
  }

  async stop(_world: SimWorld): Promise<void> {
    if (!this.bot) return;
    await this.bot.close().catch(() => {});
  }

  requireBot(): Bot {
    if (!this.bot) throw new Error(`${this.id} has not started`);
    return this.bot;
  }

  waitFor(match: (m: Msg) => boolean, timeoutMs?: number): Promise<Msg> {
    return this.requireBot().waitFor(match, timeoutMs);
  }
}

