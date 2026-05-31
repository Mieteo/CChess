import type { WebSocket } from 'ws';

export type Color = 'red' | 'black';
export type EndReason =
  | 'timeout'
  | 'resign'
  | 'disconnect'
  | 'checkmate'
  | 'stalemate';
export type GameResult = 'red-win' | 'black-win' | 'draw';

export interface ChatMessage {
  id: string;
  from: string;
  text: string;
  ts: number;
}

export interface Room {
  id: string;
  // Two player sockets only. Spectators are tracked separately.
  members: Set<WebSocket>;
  spectators: Set<WebSocket>;
  status: 'waiting' | 'playing' | 'finished';
  createdAt: number;
  moveCount: number;

  /// Step A5: initial clock per side (ms). Set when room is created from
  /// lobby; falls back to engine default if absent.
  initialClockMs?: number;

  // Step 6 game state (populated when status -> 'playing')
  redSocket?: WebSocket;
  blackSocket?: WebSocket;
  redUid?: string;
  blackUid?: string;
  clockMsByColor?: { red: number; black: number };
  currentTurn?: Color;
  turnStartedAt?: number;
  startedAt?: number;
  endedAt?: number;
  result?: GameResult;
  endReason?: EndReason;
  movesUci?: string[];
  clockTimer?: NodeJS.Timeout;

  // Step 5: server-side Xiangqi engine validates every move + detects
  // checkmate/stalemate. Type is `unknown` here to avoid a circular import;
  // server.ts/match.ts cast to XiangqiGame.
  engine?: unknown;

  // Step 8 reconnect grace period.
  disconnectedUid?: string;
  disconnectTimer?: NodeJS.Timeout;

  // Sprint 12 A5: short in-memory chat history for reconnect/session UI.
  chatMessages?: ChatMessage[];
  lastChatAtByUid?: Record<string, number>;
}

const rooms = new Map<string, Room>();
const socketToRoom = new Map<WebSocket, string>();

const ROOM_ID_LEN = 6;
const MAX_MEMBERS = 2;

export function generateRoomId(): string {
  const alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'; // skip ambiguous 0/O/1/I
  let id = '';
  do {
    id = '';
    for (let i = 0; i < ROOM_ID_LEN; i++) {
      id += alphabet[Math.floor(Math.random() * alphabet.length)];
    }
  } while (rooms.has(id));
  return id;
}

export function roomOf(socket: WebSocket): Room | undefined {
  const id = socketToRoom.get(socket);
  return id ? rooms.get(id) : undefined;
}

export function getRoomById(roomId: string): Room | undefined {
  return rooms.get(roomId);
}

/// Step 8: rebind a fresh socket to an existing room (reconnect path).
/// Caller is responsible for verifying uid matches one of redUid/blackUid
/// and that disconnectedUid was set. This just updates the maps.
export function attachReconnectingSocket(
  socket: WebSocket,
  room: Room,
  uid: string,
): void {
  room.members.add(socket);
  socketToRoom.set(socket, room.id);
  if (uid === room.redUid) room.redSocket = socket;
  else if (uid === room.blackUid) room.blackSocket = socket;
}

export type SpectateResult =
  | { ok: true; room: Room }
  | {
      ok: false;
      code: 'room-not-found' | 'already-in-room' | 'game-not-active';
    };

export function spectateRoom(socket: WebSocket, roomId: string): SpectateResult {
  if (socketToRoom.has(socket)) return { ok: false, code: 'already-in-room' };
  const room = rooms.get(roomId);
  if (!room) return { ok: false, code: 'room-not-found' };
  if (room.status !== 'playing') return { ok: false, code: 'game-not-active' };
  room.spectators.add(socket);
  socketToRoom.set(socket, room.id);
  return { ok: true, room };
}

export function createRoom(socket: WebSocket, options?: { initialClockMs?: number }): Room {
  const room: Room = {
    id: generateRoomId(),
    members: new Set([socket]),
    spectators: new Set(),
    status: 'waiting',
    createdAt: Date.now(),
    moveCount: 0,
    initialClockMs: options?.initialClockMs,
    chatMessages: [],
    lastChatAtByUid: {},
  };
  rooms.set(room.id, room);
  socketToRoom.set(socket, room.id);
  return room;
}

export type JoinResult =
  | { ok: true; room: Room }
  | { ok: false; code: 'room-not-found' | 'room-full' | 'already-in-room' };

export function joinRoom(socket: WebSocket, roomId: string): JoinResult {
  if (socketToRoom.has(socket)) return { ok: false, code: 'already-in-room' };
  const room = rooms.get(roomId);
  if (!room) return { ok: false, code: 'room-not-found' };
  if (room.members.size >= MAX_MEMBERS) return { ok: false, code: 'room-full' };
  room.members.add(socket);
  socketToRoom.set(socket, room.id);
  if (room.members.size === MAX_MEMBERS) {
    room.status = 'playing';
  }
  return { ok: true, room };
}

/// Returns the room the socket was in, or undefined if it wasn't in any.
/// Caller is responsible for notifying the room's other peers.
///
/// When `preserveStatus` is true (used by the disconnect-during-game path),
/// neither `room.status` nor the room itself is changed — only the socket
/// is removed from the maps. This lets the grace period + reconnect flow
/// keep operating against an in-progress room.
export function leaveRoom(
  socket: WebSocket,
  options?: { preserveStatus?: boolean },
): Room | undefined {
  const id = socketToRoom.get(socket);
  if (!id) return undefined;
  const room = rooms.get(id);
  if (!room) {
    socketToRoom.delete(socket);
    return undefined;
  }
  const wasSpectator = room.spectators.delete(socket);
  if (wasSpectator) {
    socketToRoom.delete(socket);
    if (room.members.size === 0 && room.spectators.size === 0) {
      rooms.delete(room.id);
    }
    return room;
  }
  room.members.delete(socket);
  socketToRoom.delete(socket);
  if (options?.preserveStatus) {
    return room;
  }
  if (room.members.size === 0 && room.spectators.size === 0) {
    rooms.delete(room.id);
    return room;
  }
  return room;
}

export function isSpectator(room: Room, socket: WebSocket): boolean {
  return room.spectators.has(socket);
}

export function membersOf(room: Room, uidLookup: (s: WebSocket) => string | undefined): string[] {
  return [...room.members].map(uidLookup).filter((u): u is string => typeof u === 'string');
}
