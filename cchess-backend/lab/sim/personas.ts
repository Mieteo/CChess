import { Bot, type Msg } from '../bot';
import type { PlayerAgent } from './agent';
import type { MovePolicy } from './brain';
import type { SimWorld } from './world';

export class BotBackedAgent implements PlayerAgent {
  private bot?: Bot;

  constructor(
    readonly id: string,
    readonly uid: string,
    readonly brain: MovePolicy,
    readonly persona: string,
  ) {}

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

  replaceBot(bot: Bot): void {
    this.bot = bot;
  }

  waitFor(match: (m: Msg) => boolean, timeoutMs?: number): Promise<Msg> {
    return this.requireBot().waitFor(match, timeoutMs);
  }
}

export class CasualPlayer extends BotBackedAgent {
  constructor(id: string, uid: string, brain: MovePolicy) {
    super(id, uid, brain, 'casual');
  }
}

export class PrivateRoomPlayer extends BotBackedAgent {
  constructor(id: string, uid: string, brain: MovePolicy) {
    super(id, uid, brain, 'private-room');
  }
}

export class ReconnectPlayer extends BotBackedAgent {
  constructor(id: string, uid: string, brain: MovePolicy) {
    super(id, uid, brain, 'reconnect');
  }
}

export class SpectatorAgent extends BotBackedAgent {
  constructor(id: string, uid: string, brain: MovePolicy) {
    super(id, uid, brain, 'spectator');
  }
}

export class AbuseAgent extends BotBackedAgent {
  constructor(id: string, uid: string, brain: MovePolicy) {
    super(id, uid, brain, 'abuse');
  }
}
