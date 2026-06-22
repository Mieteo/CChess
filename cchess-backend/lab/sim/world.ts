import type { Msg } from '../bot';
import { Bot } from '../bot';
import { startLabServer, sleep, type LabServer } from '../harness';
import { resetState } from '../run-one';
import type { PlayerAgent } from './agent';
import type { SimColor } from './brain';
import { RandomLegalPolicy } from './brains/random_legal';
import { SimMonitor } from './monitor';
import { CasualPlayer } from './personas';
import { SeededRandom } from './random';
import { SimReporter, type SimSummary } from './reporter';

export type SimTarget = 'in-process' | 'local' | 'staging' | 'prod-smoke';

export interface SimRun {
  runId: string;
  seed: number;
  target: SimTarget;
  startedAt: string;
  users: number;
  durationMs: number;
}

export interface SimConfig {
  runId: string;
  seed: number;
  target: SimTarget;
  users: number;
  durationMs: number;
  wsUrl?: string;
}

interface SimRoomMemory {
  roomId: string;
  redUid?: string;
  blackUid?: string;
  started: boolean;
  ended: boolean;
  movesUci: string[];
  endedSeenBy: Set<string>;
}

interface SimStats {
  gamesStarted: number;
  gamesEnded: number;
  moves: number;
  chatMessages: number;
  errors: number;
}

export class SimWorld {
  readonly run: SimRun;
  readonly rng: SeededRandom;
  readonly reporter: SimReporter;
  readonly monitor = new SimMonitor();
  readonly agents: PlayerAgent[] = [];

  private readonly rooms = new Map<string, SimRoomMemory>();
  private readonly stats: SimStats = {
    gamesStarted: 0,
    gamesEnded: 0,
    moves: 0,
    chatMessages: 0,
    errors: 0,
  };
  private readonly lastChatAtByUid = new Map<string, number>();
  private server?: LabServer;
  private wsUrl?: string;
  private stopAtMs = 0;
  private failure?: string;

  constructor(private readonly config: SimConfig) {
    this.run = {
      runId: config.runId,
      seed: config.seed,
      target: config.target,
      startedAt: new Date().toISOString(),
      users: config.users,
      durationMs: config.durationMs,
    };
    this.rng = new SeededRandom(config.seed);
    this.reporter = new SimReporter(config.runId);
  }

  async execute(): Promise<SimSummary> {
    const t0 = Date.now();
    let failure: string | undefined;

    try {
      await this.start();
      await this.runPairs();
      if (this.failure) throw new Error(this.failure);
      await this.stop();
      await sleep(1200);
      this.monitor.assertHealthy('drain');
    } catch (e) {
      failure = e instanceof Error ? e.message : String(e);
      this.record('failure', { message: failure });
      await this.stop().catch(() => {});
      await sleep(1200);
    } finally {
      await this.closeServer();
    }

    const snapshot = this.monitor.snapshot();
    const ok = failure === undefined && snapshot.roomsAfterDrain === 0 && snapshot.violations.length === 0;
    const summary: SimSummary = {
      ok,
      runId: this.run.runId,
      seed: this.run.seed,
      target: this.run.target,
      users: this.run.users,
      durationMs: this.run.durationMs,
      elapsedMs: Date.now() - t0,
      gamesStarted: this.stats.gamesStarted,
      gamesEnded: this.stats.gamesEnded,
      moves: this.stats.moves,
      chatMessages: this.stats.chatMessages,
      errors: this.stats.errors,
      roomsAfterDrain: snapshot.roomsAfterDrain,
      invariantViolations: snapshot.violations,
      reportDir: this.reporter.reportDir,
      replay: `npm run lab:sim -- --target=${this.run.target} --users=${this.run.users} --duration=${this.run.durationMs}ms --seed=${this.run.seed} --run-id=${this.run.runId}`,
      failure: failure ?? (ok ? undefined : 'simulation ended with leftover rooms or invariant violations'),
    };
    this.reporter.writeSummary(summary);
    await this.reporter.close();
    return summary;
  }

  async connectBot(agent: PlayerAgent): Promise<Bot> {
    if (!this.wsUrl) throw new Error('simulation server is not started');
    const bot = new Bot(this.wsUrl, agent.uid);
    bot.observe((msg) => this.observeMessage(agent, bot, msg));
    await bot.connectAuthed();
    return bot;
  }

  shouldStop(): boolean {
    return this.failure !== undefined || Date.now() >= this.stopAtMs;
  }

  record(type: string, data?: unknown, agent?: PlayerAgent, roomId?: string): void {
    this.reporter.event({
      runId: this.run.runId,
      ts: Date.now(),
      type,
      agentId: agent?.id,
      uid: agent?.uid,
      roomId,
      data,
    });
  }

  private async start(): Promise<void> {
    if (this.config.target !== 'in-process') {
      throw new Error(`Phase 1 supports only --target=in-process, got ${this.config.target}`);
    }
    resetState();
    this.server = await startLabServer({
      reconnectGraceMs: 700,
      waitingRoomTtlMs: 900,
      heartbeatIntervalMs: 5000,
      livenessTimeoutMs: 60_000,
      minClockMs: 200,
    });
    this.wsUrl = this.config.wsUrl ?? this.server.url;
    this.stopAtMs = Date.now() + this.run.durationMs;

    const brain = new RandomLegalPolicy();
    for (let i = 0; i < this.run.users; i++) {
      const id = `sim_${String(i).padStart(3, '0')}`;
      const uid = `${id}_${this.run.runId}`;
      this.agents.push(new CasualPlayer(id, uid, brain));
    }
    await Promise.all(this.agents.map((agent) => agent.start(this)));
    this.record('sim-start', { url: this.wsUrl, users: this.agents.length });
  }

  private async stop(): Promise<void> {
    await Promise.all(this.agents.map((agent) => agent.stop(this)));
    this.record('sim-stop');
  }

  private async closeServer(): Promise<void> {
    if (!this.server) return;
    await this.server.close();
    this.server = undefined;
  }

  private async runPairs(): Promise<void> {
    const casual = this.agents.filter((agent): agent is CasualPlayer => agent instanceof CasualPlayer);
    const tasks: Array<Promise<void>> = [];
    for (let i = 0; i + 1 < casual.length; i += 2) {
      tasks.push(this.runCasualLoop(casual[i], casual[i + 1]));
    }
    if (casual.length % 2 === 1) {
      this.record('idle-agent', { reason: 'odd user count' }, casual[casual.length - 1]);
    }
    await Promise.all(tasks);
  }

  private async runCasualLoop(a: CasualPlayer, b: CasualPlayer): Promise<void> {
    while (!this.shouldStop()) {
      await this.playCasualGame(a, b);
      await sleep(this.rng.int(40, 140));
    }
  }

  private async playCasualGame(a: CasualPlayer, b: CasualPlayer): Promise<void> {
    const creator = this.rng.chance(0.5) ? a : b;
    const joiner = creator === a ? b : a;
    const creatorBot = creator.requireBot();
    const joinerBot = joiner.requireBot();

    creatorBot.createRoom(8000);
    this.record('create-room', undefined, creator);
    const created = await creator.waitFor((m) => m.type === 'room-created', 3000);
    const roomId = String(created.roomId);
    joinerBot.joinRoom(roomId);
    this.record('join-room', undefined, joiner, roomId);

    const creatorStart = await creator.waitFor((m) => m.type === 'game-start' && m.roomId === roomId, 3000);
    const joinerStart = await joiner.waitFor((m) => m.type === 'game-start' && m.roomId === roomId, 3000);
    const red = creatorStart.yourColor === 'red' ? creator : joinerStart.yourColor === 'red' ? joiner : null;
    const black = creatorStart.yourColor === 'black' ? creator : joinerStart.yourColor === 'black' ? joiner : null;
    if (!red || !black) throw new Error(`room ${roomId} did not assign both colors`);

    const maxMoves = this.rng.int(8, 28);
    for (let ply = 0; ply < maxMoves && !this.shouldStop() && !this.room(roomId).ended; ply++) {
      const color: SimColor = ply % 2 === 0 ? 'red' : 'black';
      const player = color === 'red' ? red : black;
      const opponent = color === 'red' ? black : red;
      const room = this.room(roomId);
      const uci = await player.brain.chooseMove({
        uid: player.uid,
        roomId,
        color,
        movesUci: [...room.movesUci],
        nowMs: Date.now(),
        random: this.rng,
      });
      if (uci === null) break;

      player.requireBot().move(uci);
      this.record('move', { uci, color, ply }, player, roomId);
      await player.waitFor((m) => m.type === 'move-ack' && m.uci === uci, 3000);
      await opponent.waitFor((m) => m.type === 'opponent-move' && m.uci === uci, 3000);

      if (this.rng.chance(0.08) && this.markChatAllowed(player)) {
        player.requireBot().chat('gg');
        this.record('chat', { text: 'gg' }, player, roomId);
      }
      await sleep(this.rng.int(15, 80));
    }

    if (!this.room(roomId).ended) {
      const resigner = this.rng.chance(0.5) ? red : black;
      resigner.requireBot().resign();
      this.record('resign', undefined, resigner, roomId);
    }
    await red.waitFor((m) => m.type === 'game-ended' && m.roomId === roomId, 4000);
    await black.waitFor((m) => m.type === 'game-ended' && m.roomId === roomId, 4000);

    red.requireBot().leaveRoom();
    black.requireBot().leaveRoom();
    await red.waitFor((m) => m.type === 'left-room' && m.roomId === roomId, 3000);
    await black.waitFor((m) => m.type === 'left-room' && m.roomId === roomId, 3000);
    await sleep(20);
    this.monitor.assertHealthy(`after ${roomId}`);
  }

  private observeMessage(agent: PlayerAgent, bot: Bot, msg: Msg): void {
    const roomId = typeof msg.roomId === 'string' ? msg.roomId : bot.roomId;
    this.record('server-message', { message: msg }, agent, roomId);
    if (msg.type === 'error') this.stats.errors++;
    if (msg.type === 'chat-message') this.stats.chatMessages++;
    if (msg.type === 'game-start' && typeof msg.roomId === 'string') {
      const room = this.room(msg.roomId);
      if (!room.started) {
        room.started = true;
        this.stats.gamesStarted++;
      }
      if (typeof msg.redUid === 'string') room.redUid = msg.redUid;
      if (typeof msg.blackUid === 'string') room.blackUid = msg.blackUid;
      return;
    }
    if ((msg.type === 'move-ack' || msg.type === 'opponent-move') && roomId && typeof msg.uci === 'string') {
      this.noteMove(roomId, msg.uci, typeof msg.moveNumber === 'number' ? msg.moveNumber : undefined);
      return;
    }
    if (msg.type === 'game-ended' && typeof msg.roomId === 'string') {
      const room = this.room(msg.roomId);
      if (room.endedSeenBy.has(agent.id)) {
        this.fail(`duplicate game-ended for ${agent.id} in room ${msg.roomId}`);
        return;
      }
      room.endedSeenBy.add(agent.id);
      if (!room.ended) {
        room.ended = true;
        this.stats.gamesEnded++;
      }
    }
  }

  private noteMove(roomId: string, uci: string, moveNumber?: number): void {
    const room = this.room(roomId);
    if (moveNumber === undefined) {
      if (room.movesUci[room.movesUci.length - 1] !== uci) {
        room.movesUci.push(uci);
        this.stats.moves++;
      }
      return;
    }
    const index = moveNumber - 1;
    const existing = room.movesUci[index];
    if (existing === uci) return;
    if (existing !== undefined && existing !== uci) {
      this.fail(`room ${roomId} move ${moveNumber} mismatch: ${existing} vs ${uci}`);
      return;
    }
    room.movesUci[index] = uci;
    this.stats.moves++;
  }

  private fail(message: string): void {
    if (this.failure) return;
    this.failure = message;
    this.record('monitor-failure', { message });
  }

  private markChatAllowed(agent: PlayerAgent): boolean {
    const now = Date.now();
    const last = this.lastChatAtByUid.get(agent.uid) ?? 0;
    if (now - last < 2100) return false;
    this.lastChatAtByUid.set(agent.uid, now);
    return true;
  }

  private room(roomId: string): SimRoomMemory {
    let room = this.rooms.get(roomId);
    if (!room) {
      room = {
        roomId,
        started: false,
        ended: false,
        movesUci: [],
        endedSeenBy: new Set<string>(),
      };
      this.rooms.set(roomId, room);
    }
    return room;
  }
}
