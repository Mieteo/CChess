import type { WebSocket } from 'ws';

export type Color = 'red' | 'black';
export type EndReason = 'timeout' | 'resign' | 'disconnect';
export type GameResult = 'red-win' | 'black-win' | 'draw';

export interface Room {
  id: string;
  members: Set<WebSocket>;
  status: 'waiting' | 'playing' | 'finished';
  createdAt: number;
  moveCount: number;

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

export function createRoom(socket: WebSocket): Room {
  const room: Room = {
    id: generateRoomId(),
    members: new Set([socket]),
    status: 'waiting',
    createdAt: Date.now(),
    moveCount: 0,
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
export function leaveRoom(socket: WebSocket): Room | undefined {
  const id = socketToRoom.get(socket);
  if (!id) return undefined;
  const room = rooms.get(id);
  if (!room) {
    socketToRoom.delete(socket);
    return undefined;
  }
  room.members.delete(socket);
  socketToRoom.delete(socket);
  if (room.members.size === 0) {
    rooms.delete(room.id);
    return room;
  }
  room.status = 'waiting';
  return room;
}

export function membersOf(room: Room, uidLookup: (s: WebSocket) => string | undefined): string[] {
  return [...room.members].map(uidLookup).filter((u): u is string => typeof u === 'string');
}
