import { debugRooms } from '../../src/rooms';
import { checkInvariants, type InvariantViolation } from '../invariants';
import type { Msg } from '../bot';

export interface MonitorSnapshot {
  roomsAfterDrain: number;
  violations: InvariantViolation[];
}

export type AgentRole = 'idle' | 'waiting' | 'player' | 'spectator' | 'disconnected';
export type RoomStatus = 'waiting' | 'playing' | 'finished';
export type SimCommandType =
  | 'create-room'
  | 'join-room'
  | 'move'
  | 'chat'
  | 'resign'
  | 'leave-room'
  | 'drop'
  | 'reconnect-room'
  | 'spectate-room'
  | 'stop-spectating';

export interface ProtocolViolation {
  rule: string;
  detail: string;
  roomId?: string;
  agents?: string[];
  data?: unknown;
}

export interface ProtocolCommand {
  type: SimCommandType;
  agentId: string;
  uid: string;
  roomId?: string;
  data?: unknown;
}

export interface ServerMessageObservation {
  agentId: string;
  uid: string;
  roomId?: string;
  message: Msg;
}

interface AgentMemory {
  id: string;
  uid: string;
  connected: boolean;
  role: AgentRole;
  roomId?: string;
  color?: 'red' | 'black';
  lastRoomId?: string;
}

interface RoomMemory {
  roomId: string;
  status: RoomStatus;
  redUid?: string;
  blackUid?: string;
  movesUci: string[];
  spectators: Set<string>;
  endedSeenBy: Set<string>;
  endedMoves?: string[];
  endedResult?: unknown;
  endedReason?: unknown;
}

export class SimMonitor {
  private readonly agents = new Map<string, AgentMemory>();
  private readonly rooms = new Map<string, RoomMemory>();
  private readonly violations: ProtocolViolation[] = [];

  registerAgent(agent: { id: string; uid: string }): void {
    this.agent(agent.id, agent.uid);
  }

  observeCommand(command: ProtocolCommand): ProtocolViolation | undefined {
    const agent = this.agent(command.agentId, command.uid);
    const roomId = command.roomId ?? agent.roomId ?? agent.lastRoomId;

    switch (command.type) {
      case 'create-room':
        if (agent.role !== 'idle') {
          return this.violate('protocol-phase', `${agent.id} created a room while role=${agent.role}`, roomId, [agent.id]);
        }
        agent.role = 'waiting';
        break;
      case 'join-room':
        if (agent.role !== 'idle') {
          return this.violate('protocol-phase', `${agent.id} joined a room while role=${agent.role}`, roomId, [agent.id]);
        }
        break;
      case 'spectate-room':
        if (agent.role !== 'idle') {
          return this.violate('protocol-phase', `${agent.id} spectated while role=${agent.role}`, roomId, [agent.id]);
        }
        break;
      case 'stop-spectating':
        if (agent.role !== 'spectator') {
          return this.violate('protocol-phase', `${agent.id} stopped spectating while role=${agent.role}`, roomId, [agent.id]);
        }
        break;
      case 'move': {
        const room = roomId ? this.rooms.get(roomId) : undefined;
        const expectedColor = room ? colorToMove(room.movesUci.length) : undefined;
        if (agent.role !== 'player' || !roomId || room?.status !== 'playing') {
          return this.violate('protocol-phase', `${agent.id} moved while role=${agent.role} status=${room?.status ?? 'unknown'}`, roomId, [agent.id]);
        }
        if (agent.color !== expectedColor) {
          return this.violate('wrong-turn-command', `${agent.id} moved as ${agent.color}, expected ${expectedColor}`, roomId, [agent.id]);
        }
        break;
      }
      case 'chat': {
        const room = roomId ? this.rooms.get(roomId) : undefined;
        if ((agent.role !== 'player' && agent.role !== 'spectator') || room?.status === 'finished') {
          return this.violate('protocol-phase', `${agent.id} chatted while role=${agent.role} status=${room?.status ?? 'unknown'}`, roomId, [agent.id]);
        }
        break;
      }
      case 'resign': {
        const room = roomId ? this.rooms.get(roomId) : undefined;
        if (agent.role !== 'player' || room?.status !== 'playing') {
          return this.violate('protocol-phase', `${agent.id} resigned while role=${agent.role} status=${room?.status ?? 'unknown'}`, roomId, [agent.id]);
        }
        break;
      }
      case 'leave-room':
        if (agent.role !== 'player' && agent.role !== 'spectator') {
          return this.violate('protocol-phase', `${agent.id} left a room while role=${agent.role}`, roomId, [agent.id]);
        }
        break;
      case 'drop':
        if (!agent.connected) {
          return this.violate('protocol-phase', `${agent.id} dropped while already disconnected`, roomId, [agent.id]);
        }
        agent.connected = false;
        agent.lastRoomId = roomId;
        if (agent.role === 'player') agent.role = 'disconnected';
        break;
      case 'reconnect-room':
        if (agent.role !== 'disconnected') {
          return this.violate('protocol-phase', `${agent.id} reconnected while role=${agent.role}`, roomId, [agent.id]);
        }
        break;
    }
    return undefined;
  }

  observeServerMessage(observation: ServerMessageObservation): ProtocolViolation | undefined {
    const msg = observation.message;
    const agent = this.agent(observation.agentId, observation.uid);
    const roomId = typeof msg.roomId === 'string' ? msg.roomId : observation.roomId ?? agent.roomId;

    if (msg.type === 'welcome') return undefined;
    if (msg.type === 'authed') {
      agent.connected = true;
      if (typeof msg.uid === 'string' && msg.uid !== agent.uid) {
        return this.violate('auth-uid-mismatch', `${agent.id} authed as ${msg.uid}, expected ${agent.uid}`, roomId, [agent.id], msg);
      }
      return undefined;
    }
    if (msg.type === 'room-created' && roomId) {
      agent.role = 'waiting';
      agent.roomId = roomId;
      agent.lastRoomId = roomId;
      this.room(roomId).status = 'waiting';
      return undefined;
    }
    if (msg.type === 'room-joined' && roomId) {
      agent.role = 'player';
      agent.roomId = roomId;
      agent.lastRoomId = roomId;
      this.room(roomId).status = msg.status === 'playing' ? 'playing' : 'waiting';
      return undefined;
    }
    if (msg.type === 'game-start' && roomId) {
      return this.observeGameStart(agent, roomId, msg);
    }
    if (msg.type === 'spectate-started' && roomId) {
      return this.observeSpectateStarted(agent, roomId, msg);
    }
    if (msg.type === 'reconnected' && roomId) {
      return this.observeReconnected(agent, roomId, msg);
    }
    if ((msg.type === 'move-ack' || msg.type === 'opponent-move') && roomId && typeof msg.uci === 'string') {
      return this.observeMove(agent, roomId, msg);
    }
    if (msg.type === 'game-ended' && roomId) {
      return this.observeGameEnded(agent, roomId, msg);
    }
    if (msg.type === 'left-room' || msg.type === 'spectate-stopped') {
      agent.role = 'idle';
      agent.roomId = undefined;
      agent.color = undefined;
      return undefined;
    }
    if (msg.type === 'error' && agent.role === 'waiting') {
      agent.role = 'idle';
      agent.roomId = undefined;
    }
    return undefined;
  }

  protocolViolations(): ProtocolViolation[] {
    return [...this.violations];
  }

  movesFor(roomId: string): string[] {
    return [...(this.rooms.get(roomId)?.movesUci ?? [])];
  }

  snapshot(): MonitorSnapshot {
    return {
      roomsAfterDrain: debugRooms().length,
      violations: checkInvariants(),
    };
  }

  assertHealthy(label: string): void {
    const violations = checkInvariants();
    if (violations.length === 0) return;
    const detail = violations.map((v) => `[${v.rule}] ${v.detail}`).join('\n');
    throw new Error(`invariant violation at ${label}:\n${detail}`);
  }

  private observeGameStart(agent: AgentMemory, roomId: string, msg: Msg): ProtocolViolation | undefined {
    const room = this.room(roomId);
    if (agent.role === 'spectator' && msg.yourColor !== null) {
      return this.violate('spectator-became-player', `${agent.id} was a spectator but received game-start as ${String(msg.yourColor)}`, roomId, [agent.id], msg);
    }
    if (typeof msg.redUid === 'string') room.redUid = msg.redUid;
    if (typeof msg.blackUid === 'string') room.blackUid = msg.blackUid;
    room.status = 'playing';
    room.endedSeenBy.clear();
    room.endedMoves = undefined;
    room.endedResult = undefined;
    room.endedReason = undefined;
    if (msg.rematch === true) room.movesUci = [];

    if (msg.yourColor === 'red' || msg.yourColor === 'black') {
      const expectedUid = msg.yourColor === 'red' ? room.redUid : room.blackUid;
      if (expectedUid && expectedUid !== agent.uid) {
        return this.violate('color-uid-mismatch', `${agent.id} got ${msg.yourColor} but uid=${agent.uid}, expected ${expectedUid}`, roomId, [agent.id], msg);
      }
      agent.role = 'player';
      agent.roomId = roomId;
      agent.lastRoomId = roomId;
      agent.color = msg.yourColor;
    } else if (msg.yourColor === null) {
      agent.role = 'spectator';
      agent.roomId = roomId;
      agent.lastRoomId = roomId;
      agent.color = undefined;
      room.spectators.add(agent.id);
    }
    return undefined;
  }

  private observeSpectateStarted(agent: AgentMemory, roomId: string, msg: Msg): ProtocolViolation | undefined {
    if (agent.role === 'player') {
      return this.violate('player-became-spectator', `${agent.id} is a player but received spectate-started`, roomId, [agent.id], msg);
    }
    const room = this.room(roomId);
    agent.role = 'spectator';
    agent.roomId = roomId;
    agent.lastRoomId = roomId;
    agent.color = undefined;
    room.spectators.add(agent.id);
    room.status = 'playing';
    if (typeof msg.redUid === 'string') room.redUid = msg.redUid;
    if (typeof msg.blackUid === 'string') room.blackUid = msg.blackUid;
    if (Array.isArray(msg.moves)) {
      const incoming = stringArray(msg.moves);
      const known = room.movesUci;
      if (known.length > 0 && !sameMoves(known, incoming)) {
        return this.violate('spectator-snapshot-mismatch', `spectator snapshot moves do not match room memory`, roomId, [agent.id], { known, incoming });
      }
      room.movesUci = incoming;
    }
    return undefined;
  }

  private observeReconnected(agent: AgentMemory, roomId: string, msg: Msg): ProtocolViolation | undefined {
    const room = this.room(roomId);
    if (Array.isArray(msg.moves)) {
      const incoming = stringArray(msg.moves);
      if (!sameMoves(room.movesUci, incoming)) {
        return this.violate('reconnect-snapshot-mismatch', `reconnect moves snapshot does not match room memory`, roomId, [agent.id], { known: room.movesUci, incoming });
      }
    }
    const expectedTurn = colorToMove(room.movesUci.length);
    if (msg.currentTurn !== undefined && msg.currentTurn !== expectedTurn) {
      return this.violate('reconnect-snapshot-mismatch', `reconnect currentTurn=${String(msg.currentTurn)} expected=${expectedTurn}`, roomId, [agent.id], msg);
    }
    if (typeof msg.redUid === 'string') room.redUid = msg.redUid;
    if (typeof msg.blackUid === 'string') room.blackUid = msg.blackUid;
    if (msg.yourColor !== 'red' && msg.yourColor !== 'black') {
      return this.violate('reconnect-snapshot-mismatch', `reconnect returned invalid color ${String(msg.yourColor)}`, roomId, [agent.id], msg);
    }
    const expectedUid = msg.yourColor === 'red' ? room.redUid : room.blackUid;
    if (expectedUid && expectedUid !== agent.uid) {
      return this.violate('reconnect-snapshot-mismatch', `reconnect color ${msg.yourColor} belongs to ${expectedUid}, not ${agent.uid}`, roomId, [agent.id], msg);
    }
    agent.connected = true;
    agent.role = 'player';
    agent.roomId = roomId;
    agent.lastRoomId = roomId;
    agent.color = msg.yourColor;
    return undefined;
  }

  private observeMove(agent: AgentMemory, roomId: string, msg: Msg): ProtocolViolation | undefined {
    const room = this.room(roomId);
    if (room.status !== 'playing') {
      return this.violate('move-after-finish', `room ${roomId} received ${msg.type} while status=${room.status}`, roomId, [agent.id], msg);
    }
    const uci = String(msg.uci);
    const moveNumber = typeof msg.moveNumber === 'number' ? msg.moveNumber : room.movesUci.length + 1;
    if (!Number.isInteger(moveNumber) || moveNumber < 1) {
      return this.violate('move-count-mismatch', `invalid moveNumber ${String(msg.moveNumber)}`, roomId, [agent.id], msg);
    }
    const index = moveNumber - 1;
    if (index > room.movesUci.length) {
      return this.violate('move-count-mismatch', `moveNumber ${moveNumber} skipped from known length ${room.movesUci.length}`, roomId, [agent.id], msg);
    }
    const expectedMover = colorToMove(index);
    if (msg.type === 'move-ack' && agent.role === 'player' && agent.color !== expectedMover) {
      return this.violate('move-color-mismatch', `${agent.id} acked move ${moveNumber} as ${agent.color}, expected ${expectedMover}`, roomId, [agent.id], msg);
    }
    if (msg.type === 'opponent-move' && agent.role === 'player' && agent.color === msg.color) {
      return this.violate('move-echoed-to-mover', `${agent.id} received opponent-move for their own ${String(msg.color)} move`, roomId, [agent.id], msg);
    }
    const existing = room.movesUci[index];
    if (existing !== undefined && existing !== uci) {
      return this.violate('move-count-mismatch', `move ${moveNumber} is ${existing} in memory but server sent ${uci}`, roomId, [agent.id], msg);
    }
    if (existing === undefined) room.movesUci[index] = uci;
    return undefined;
  }

  private observeGameEnded(agent: AgentMemory, roomId: string, msg: Msg): ProtocolViolation | undefined {
    const room = this.room(roomId);
    if (room.endedSeenBy.has(agent.id)) {
      return this.violate('game-ended-duplicate', `${agent.id} received duplicate game-ended`, roomId, [agent.id], msg);
    }
    room.endedSeenBy.add(agent.id);
    room.status = 'finished';
    if (Array.isArray(msg.moves)) {
      const incoming = stringArray(msg.moves);
      if (!sameMoves(room.movesUci, incoming)) {
        return this.violate('game-ended-move-mismatch', `game-ended moves do not match room memory`, roomId, [agent.id], { known: room.movesUci, incoming });
      }
      if (room.endedMoves && !sameMoves(room.endedMoves, incoming)) {
        return this.violate('game-ended-duplicate', `game-ended payload changed between recipients`, roomId, [agent.id], { previous: room.endedMoves, incoming });
      }
      room.endedMoves = incoming;
    }
    if (room.endedResult !== undefined && room.endedResult !== msg.result) {
      return this.violate('game-ended-duplicate', `game-ended result changed from ${String(room.endedResult)} to ${String(msg.result)}`, roomId, [agent.id], msg);
    }
    if (room.endedReason !== undefined && room.endedReason !== msg.reason) {
      return this.violate('game-ended-duplicate', `game-ended reason changed from ${String(room.endedReason)} to ${String(msg.reason)}`, roomId, [agent.id], msg);
    }
    room.endedResult = msg.result;
    room.endedReason = msg.reason;
    return undefined;
  }

  private agent(agentId: string, uid: string): AgentMemory {
    let agent = this.agents.get(agentId);
    if (!agent) {
      agent = { id: agentId, uid, connected: false, role: 'idle' };
      this.agents.set(agentId, agent);
    }
    return agent;
  }

  private room(roomId: string): RoomMemory {
    let room = this.rooms.get(roomId);
    if (!room) {
      room = {
        roomId,
        status: 'waiting',
        movesUci: [],
        spectators: new Set<string>(),
        endedSeenBy: new Set<string>(),
      };
      this.rooms.set(roomId, room);
    }
    return room;
  }

  private violate(
    rule: string,
    detail: string,
    roomId?: string,
    agents?: string[],
    data?: unknown,
  ): ProtocolViolation {
    const violation: ProtocolViolation = { rule, detail, roomId, agents, data };
    this.violations.push(violation);
    return violation;
  }
}

function colorToMove(moveCount: number): 'red' | 'black' {
  return moveCount % 2 === 0 ? 'red' : 'black';
}

function stringArray(value: unknown[]): string[] {
  return value.filter((item): item is string => typeof item === 'string');
}

function sameMoves(a: readonly string[], b: readonly string[]): boolean {
  return a.length === b.length && a.every((move, i) => move === b[i]);
}
