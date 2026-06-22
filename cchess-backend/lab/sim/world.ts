import type { Msg } from '../bot';
import { Bot } from '../bot';
import { startLabServer, sleep, type LabServer } from '../harness';
import { resetState } from '../run-one';
import type { PlayerAgent } from './agent';
import type { SimColor } from './brain';
import { RandomLegalPolicy } from './brains/random_legal';
import { ScriptedPolicy } from './brains/scripted';
import {
  SimMonitor,
  type ProtocolViolation,
  type SimCommandType,
} from './monitor';
import {
  AbuseAgent,
  BotBackedAgent,
  CasualPlayer,
  PrivateRoomPlayer,
  ReconnectPlayer,
  SpectatorAgent,
} from './personas';
import {
  brainPlan,
  DEFAULT_PROFILE,
  personaPlan,
  type BrainKind,
  type PersonaKind,
  type SimProfile,
} from './profiles';
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
  ended: boolean;
  movesUci: string[];
  endedSeenBy: Set<string>;
  startedKeys: Set<string>;
  endedKeys: Set<string>;
  reconnectTested: boolean;
}

interface SimStats {
  gamesStarted: number;
  gamesEnded: number;
  moves: number;
  chatMessages: number;
  errors: number;
  reconnects: number;
  spectatorSessions: number;
  abuseActions: number;
  abuseErrors: number;
  privateRooms: number;
  rematches: number;
}

type GamePlayer = CasualPlayer | PrivateRoomPlayer | ReconnectPlayer;

export class SimWorld {
  readonly run: SimRun;
  readonly rng: SeededRandom;
  readonly reporter: SimReporter;
  readonly monitor = new SimMonitor();
  readonly agents: PlayerAgent[] = [];
  readonly profile: SimProfile = DEFAULT_PROFILE;

  private readonly rooms = new Map<string, SimRoomMemory>();
  private readonly personaCounts = new Map<string, number>();
  private readonly stats: SimStats = {
    gamesStarted: 0,
    gamesEnded: 0,
    moves: 0,
    chatMessages: 0,
    errors: 0,
    reconnects: 0,
    spectatorSessions: 0,
    abuseActions: 0,
    abuseErrors: 0,
    privateRooms: 0,
    rematches: 0,
  };
  private readonly lastChatAtByUid = new Map<string, number>();
  private readonly busySupportAgents = new Set<string>();
  private server?: LabServer;
  private wsUrl?: string;
  private stopAtMs = 0;
  private failure?: string;
  private failureViolation?: ProtocolViolation;

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
    const protocolViolations = this.monitor.protocolViolations();
    const firstProtocolViolation = this.failureViolation ?? protocolViolations[0];
    const ok =
      failure === undefined &&
      snapshot.roomsAfterDrain === 0 &&
      snapshot.violations.length === 0 &&
      protocolViolations.length === 0;
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
      reconnects: this.stats.reconnects,
      spectatorSessions: this.stats.spectatorSessions,
      abuseActions: this.stats.abuseActions,
      abuseErrors: this.stats.abuseErrors,
      privateRooms: this.stats.privateRooms,
      rematches: this.stats.rematches,
      personaCounts: Object.fromEntries(this.personaCounts),
      roomsAfterDrain: snapshot.roomsAfterDrain,
      invariantViolations: snapshot.violations,
      protocolViolations,
      reportDir: this.reporter.reportDir,
      replay: `npm run lab:sim -- --target=${this.run.target} --users=${this.run.users} --duration=${this.run.durationMs}ms --seed=${this.run.seed} --run-id=${this.run.runId}`,
      failureRule: firstProtocolViolation?.rule,
      failureRoomId: firstProtocolViolation?.roomId,
      failureAgents: firstProtocolViolation?.agents,
      recentEvents: this.reporter.recentEvents(),
      failure:
        failure ??
        firstProtocolViolation?.detail ??
        (ok ? undefined : 'simulation ended with leftover rooms or invariant violations'),
    };
    this.reporter.writeSummary(summary);
    await this.reporter.close();
    return summary;
  }

  async connectBot(agent: PlayerAgent): Promise<Bot> {
    if (!this.wsUrl) throw new Error('simulation server is not started');
    this.monitor.registerAgent(agent);
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

  private command(
    type: SimCommandType,
    agent: PlayerAgent,
    roomId?: string,
    data?: unknown,
  ): boolean {
    this.record(type, data, agent, roomId);
    const violation = this.monitor.observeCommand({
      type,
      agentId: agent.id,
      uid: agent.uid,
      roomId,
      data,
    });
    if (violation) this.fail(violation);
    return violation === undefined;
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

    const personas = personaPlan(this.run.users, this.profile);
    const playerCount = personas.filter(isPlayerPersona).length;
    const brains = brainPlan(playerCount, this.profile);
    let brainIndex = 0;
    for (let i = 0; i < personas.length; i++) {
      const persona = personas[i];
      const id = `sim_${String(i).padStart(3, '0')}`;
      const uid = `${id}_${this.run.runId}`;
      const brainKind = isPlayerPersona(persona) ? brains[brainIndex++] : 'random-legal';
      const agent = this.makeAgent(persona, id, uid, brainKind);
      this.agents.push(agent);
      this.personaCounts.set(agent.persona, (this.personaCounts.get(agent.persona) ?? 0) + 1);
    }
    await Promise.all(this.agents.map((agent) => agent.start(this)));
    this.record('sim-start', {
      url: this.wsUrl,
      users: this.agents.length,
      profile: this.profile.name,
      personas: Object.fromEntries(this.personaCounts),
    });
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
    const players = this.agents.filter(isGamePlayer);
    const spectators = this.agents.filter((agent): agent is SpectatorAgent => agent instanceof SpectatorAgent);
    const abusers = this.agents.filter((agent): agent is AbuseAgent => agent instanceof AbuseAgent);
    const tasks: Array<Promise<void>> = [];
    for (let i = 0; i + 1 < players.length; i += 2) {
      tasks.push(this.runPlayerLoop(players[i], players[i + 1], spectators, abusers));
    }
    if (players.length % 2 === 1) {
      this.record('idle-agent', { reason: 'odd player count' }, players[players.length - 1]);
    }
    await Promise.all(tasks);
  }

  private async runPlayerLoop(
    a: GamePlayer,
    b: GamePlayer,
    spectators: SpectatorAgent[],
    abusers: AbuseAgent[],
  ): Promise<void> {
    while (!this.shouldStop()) {
      await this.playPrivateRoomGame(a, b, spectators, abusers);
      await sleep(this.rng.int(40, 140));
    }
  }

  private async playPrivateRoomGame(
    a: GamePlayer,
    b: GamePlayer,
    spectators: SpectatorAgent[],
    abusers: AbuseAgent[],
  ): Promise<void> {
    const creator = this.rng.chance(0.5) ? a : b;
    const joiner = creator === a ? b : a;
    const creatorBot = creator.requireBot();
    const joinerBot = joiner.requireBot();

    if (this.command('create-room', creator)) creatorBot.createRoom(8000);
    const created = await creator.waitFor((m) => m.type === 'room-created', 3000);
    const roomId = String(created.roomId);
    this.stats.privateRooms++;
    if (this.command('join-room', joiner, roomId)) joinerBot.joinRoom(roomId);

    const creatorStart = await creator.waitFor((m) => m.type === 'game-start' && m.roomId === roomId, 3000);
    const joinerStart = await joiner.waitFor((m) => m.type === 'game-start' && m.roomId === roomId, 3000);
    const red = creatorStart.yourColor === 'red' ? creator : joinerStart.yourColor === 'red' ? joiner : null;
    const black = creatorStart.yourColor === 'black' ? creator : joinerStart.yourColor === 'black' ? joiner : null;
    if (!red || !black) throw new Error(`room ${roomId} did not assign both colors`);

    await this.maybeRunSpectator(roomId, spectators);
    await this.maybeRunAbuse(roomId, abusers);

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

      if (this.command('move', player, roomId, { uci, color, ply })) {
        player.requireBot().move(uci);
      }
      await player.waitFor((m) => m.type === 'move-ack' && m.uci === uci, 3000);
      await opponent.waitFor((m) => m.type === 'opponent-move' && m.uci === uci, 3000);

      if (this.rng.chance(0.08) && this.markChatAllowed(player)) {
        if (this.command('chat', player, roomId, { text: 'gg' })) {
          player.requireBot().chat('gg');
        }
      }
      if (ply >= 1) await this.maybeRunReconnect(roomId, red, black);
      if (ply >= 2) await this.maybeRunSpectator(roomId, spectators);
      if (ply >= 2) await this.maybeRunAbuse(roomId, abusers);
      await sleep(this.rng.int(15, 80));
    }

    if (!this.room(roomId).ended) {
      const resigner = this.rng.chance(0.5) ? red : black;
      if (this.command('resign', resigner, roomId)) {
        resigner.requireBot().resign();
      }
    }
    await red.waitFor((m) => m.type === 'game-ended' && m.roomId === roomId, 4000);
    await black.waitFor((m) => m.type === 'game-ended' && m.roomId === roomId, 4000);

    await this.maybeRunRematch(roomId, red, black, spectators, abusers);

    if (this.command('leave-room', red, roomId)) red.requireBot().leaveRoom();
    if (this.command('leave-room', black, roomId)) black.requireBot().leaveRoom();
    await red.waitFor((m) => m.type === 'left-room' && m.roomId === roomId, 3000);
    await black.waitFor((m) => m.type === 'left-room' && m.roomId === roomId, 3000);
    await sleep(20);
    this.monitor.assertHealthy(`after ${roomId}`);
  }

  private observeMessage(agent: PlayerAgent, bot: Bot, msg: Msg): void {
    const roomId = typeof msg.roomId === 'string' ? msg.roomId : bot.roomId;
    this.record('server-message', { message: msg }, agent, roomId);
    const violation = this.monitor.observeServerMessage({
      agentId: agent.id,
      uid: agent.uid,
      roomId,
      message: msg,
    });
    if (violation) this.fail(violation);
    if (msg.type === 'error') {
      if (agent instanceof AbuseAgent) this.stats.abuseErrors++;
      else this.stats.errors++;
    }
    if (msg.type === 'chat-message') this.stats.chatMessages++;
    if (msg.type === 'reconnected') this.stats.reconnects++;
    if (msg.type === 'spectate-started') this.stats.spectatorSessions++;
    if (msg.type === 'game-start' && typeof msg.roomId === 'string') {
      const room = this.room(msg.roomId);
      const startedKey = gameStartKey(msg);
      if (!room.startedKeys.has(startedKey)) {
        room.startedKeys.add(startedKey);
        this.stats.gamesStarted++;
      }
      room.ended = false;
      room.endedSeenBy.clear();
      room.reconnectTested = false;
      if (msg.rematch === true) room.movesUci = [];
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
        this.fail({
          rule: 'game-ended-duplicate',
          detail: `duplicate game-ended for ${agent.id} in room ${msg.roomId}`,
          roomId: msg.roomId,
          agents: [agent.id],
        });
        return;
      }
      room.endedSeenBy.add(agent.id);
      const endedKey = gameEndedKey(msg);
      if (!room.endedKeys.has(endedKey)) {
        room.endedKeys.add(endedKey);
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
      this.fail({
        rule: 'move-count-mismatch',
        detail: `room ${roomId} move ${moveNumber} mismatch: ${existing} vs ${uci}`,
        roomId,
      });
      return;
    }
    room.movesUci[index] = uci;
    this.stats.moves++;
  }

  private async maybeRunSpectator(roomId: string, spectators: SpectatorAgent[]): Promise<void> {
    if (this.shouldStop() || spectators.length === 0 || this.room(roomId).ended) return;
    if (!this.rng.chance(this.profile.spectatorChance)) return;
    const spectator = this.availableSupport(spectators);
    if (!spectator) return;
    await this.withSupport(spectator, async () => {
      if (this.command('spectate-room', spectator, roomId)) {
        spectator.requireBot().spectateRoom(roomId);
      }
      await spectator.waitFor((m) => m.type === 'spectate-started' && m.roomId === roomId, 3000);
      if (this.rng.chance(0.35) && this.markChatAllowed(spectator)) {
        if (this.command('chat', spectator, roomId, { text: 'watching' })) {
          spectator.requireBot().chat('watching');
        }
      }
      if (this.command('stop-spectating', spectator, roomId)) {
        spectator.requireBot().stopSpectating();
      }
      await spectator.waitFor((m) => m.type === 'spectate-stopped' && m.roomId === roomId, 3000);
    });
  }

  private async maybeRunReconnect(
    roomId: string,
    red: GamePlayer,
    black: GamePlayer,
  ): Promise<void> {
    const room = this.room(roomId);
    if (this.shouldStop() || room.ended || room.reconnectTested) return;
    const hasReconnectPersona = red instanceof ReconnectPlayer || black instanceof ReconnectPlayer;
    if (!hasReconnectPersona && !this.rng.chance(0.08)) return;
    if (!this.rng.chance(this.profile.reconnectChance)) return;

    const player =
      red instanceof ReconnectPlayer
        ? red
        : black instanceof ReconnectPlayer
        ? black
        : this.rng.chance(0.5)
        ? red
        : black;
    const peer = player === red ? black : red;
    const oldBot = player.requireBot();
    room.reconnectTested = true;
    if (this.command('drop', player, roomId)) oldBot.drop();
    await peer.waitFor((m) => m.type === 'peer-disconnected', 1500);

    const newBot = await this.connectBot(player);
    player.replaceBot(newBot);
    if (this.command('reconnect-room', player, roomId)) {
      newBot.reconnectRoom(roomId);
    }
    await player.waitFor((m) => m.type === 'reconnected' && m.roomId === roomId, 3000);
    await peer.waitFor((m) => m.type === 'peer-reconnected', 3000);
  }

  private async maybeRunAbuse(roomId: string, abusers: AbuseAgent[]): Promise<void> {
    if (this.shouldStop() || abusers.length === 0 || this.room(roomId).ended) return;
    if (!this.rng.chance(this.profile.abuseChance)) return;
    const abuser = this.availableSupport(abusers);
    if (!abuser) return;
    await this.withSupport(abuser, async () => {
      this.stats.abuseActions++;
      this.record('abuse-action', { action: 'spectator-invalid-move' }, abuser, roomId);
      abuser.requireBot().spectateRoom(roomId);
      await abuser.waitFor((m) => m.type === 'spectate-started' && m.roomId === roomId, 3000);
      abuser.requireBot().move('a0a1');
      await abuser.waitFor((m) => m.type === 'error', 3000);
      if (this.command('stop-spectating', abuser, roomId)) {
        abuser.requireBot().stopSpectating();
      }
      await abuser.waitFor((m) => m.type === 'spectate-stopped' && m.roomId === roomId, 3000);
    });
  }

  private async maybeRunRematch(
    roomId: string,
    red: GamePlayer,
    black: GamePlayer,
    spectators: SpectatorAgent[],
    abusers: AbuseAgent[],
  ): Promise<void> {
    if (this.shouldStop() || !this.rng.chance(this.profile.rematchChance)) return;
    red.requireBot().offerRematch();
    this.record('rematch-offer', undefined, red, roomId);
    await red.waitFor((m) => m.type === 'rematch-pending', 3000);
    await black.waitFor((m) => m.type === 'rematch-offered', 3000);
    black.requireBot().offerRematch();
    this.record('rematch-offer', undefined, black, roomId);
    const redStart = await red.waitFor((m) => m.type === 'game-start' && m.roomId === roomId && m.rematch === true, 3000);
    const blackStart = await black.waitFor((m) => m.type === 'game-start' && m.roomId === roomId && m.rematch === true, 3000);
    const rematchRed = redStart.yourColor === 'red' ? red : blackStart.yourColor === 'red' ? black : null;
    const rematchBlack = redStart.yourColor === 'black' ? red : blackStart.yourColor === 'black' ? black : null;
    if (!rematchRed || !rematchBlack) {
      throw new Error(`room ${roomId} rematch did not assign both colors`);
    }
    this.stats.rematches++;

    await this.maybeRunSpectator(roomId, spectators);
    await this.playTurns(roomId, rematchRed, rematchBlack, this.rng.int(4, 12));
    await this.maybeRunAbuse(roomId, abusers);

    const resigner = this.rng.chance(0.5) ? rematchRed : rematchBlack;
    if (this.command('resign', resigner, roomId)) {
      resigner.requireBot().resign();
    }
    await red.waitFor((m) => m.type === 'game-ended' && m.roomId === roomId, 4000);
    await black.waitFor((m) => m.type === 'game-ended' && m.roomId === roomId, 4000);
  }

  private async playTurns(
    roomId: string,
    red: GamePlayer,
    black: GamePlayer,
    maxMoves: number,
  ): Promise<void> {
    for (let ply = 0; ply < maxMoves && !this.shouldStop() && !this.room(roomId).ended; ply++) {
      const color: SimColor = this.room(roomId).movesUci.length % 2 === 0 ? 'red' : 'black';
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
      if (this.command('move', player, roomId, { uci, color, ply })) {
        player.requireBot().move(uci);
      }
      await player.waitFor((m) => m.type === 'move-ack' && m.uci === uci, 3000);
      await opponent.waitFor((m) => m.type === 'opponent-move' && m.uci === uci, 3000);
      await sleep(this.rng.int(12, 45));
    }
  }

  private fail(violation: ProtocolViolation | string): void {
    if (this.failure) return;
    const normalized =
      typeof violation === 'string'
        ? { rule: 'simulation-failure', detail: violation }
        : violation;
    this.failure = normalized.detail;
    this.failureViolation = normalized;
    this.record('monitor-failure', normalized, undefined, normalized.roomId);
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
        ended: false,
        movesUci: [],
        endedSeenBy: new Set<string>(),
        startedKeys: new Set<string>(),
        endedKeys: new Set<string>(),
        reconnectTested: false,
      };
      this.rooms.set(roomId, room);
    }
    return room;
  }

  private availableSupport<T extends BotBackedAgent>(agents: T[]): T | undefined {
    const available = agents.filter((agent) => !this.busySupportAgents.has(agent.id));
    return available.length === 0 ? undefined : this.rng.pick(available);
  }

  private async withSupport(agent: BotBackedAgent, fn: () => Promise<void>): Promise<void> {
    if (this.busySupportAgents.has(agent.id)) return;
    this.busySupportAgents.add(agent.id);
    try {
      await fn();
    } finally {
      this.busySupportAgents.delete(agent.id);
    }
  }

  private makeBrain(kind: BrainKind) {
    return kind === 'scripted' ? new ScriptedPolicy() : new RandomLegalPolicy();
  }

  private makeAgent(kind: PersonaKind, id: string, uid: string, brainKind: BrainKind): PlayerAgent {
    const brain = this.makeBrain(brainKind);
    switch (kind) {
      case 'casual':
        return new CasualPlayer(id, uid, brain);
      case 'private-room':
        return new PrivateRoomPlayer(id, uid, brain);
      case 'reconnect':
        return new ReconnectPlayer(id, uid, brain);
      case 'spectator':
        return new SpectatorAgent(id, uid, brain);
      case 'abuse':
        return new AbuseAgent(id, uid, brain);
    }
  }
}

function isGamePlayer(agent: PlayerAgent): agent is GamePlayer {
  return (
    agent instanceof CasualPlayer ||
    agent instanceof PrivateRoomPlayer ||
    agent instanceof ReconnectPlayer
  );
}

function isPlayerPersona(persona: PersonaKind): boolean {
  return persona === 'casual' || persona === 'private-room' || persona === 'reconnect';
}

function gameStartKey(msg: Msg): string {
  return `${String(msg.roomId)}:${String(msg.startedAt ?? 'unknown')}:${msg.rematch === true ? 'rematch' : 'initial'}`;
}

function gameEndedKey(msg: Msg): string {
  return `${String(msg.roomId)}:${String(msg.endedAt ?? 'unknown')}:${String(msg.result)}:${String(msg.reason)}`;
}
