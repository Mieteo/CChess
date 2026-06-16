import { WebSocket } from 'ws';

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

  /// Waiting-room TTL: cancels a lobby-created room that nobody joined.
  /// Set by the create-room handler, cleared when the game starts.
  waitingTimer?: NodeJS.Timeout;

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

  // Step 8 reconnect grace period. Keyed by SEAT (color), not uid: a seat is
  // identified by socket identity (colorOfSocket), so even a same-uid game
  // (one Firebase account on both seats — e.g. a user playing themselves on
  // two tabs) gets an independent grace entry + forfeit timer per seat. Keying
  // by uid used to collapse both seats into one entry, so reconnecting one seat
  // wiped the other seat's grace and left it stuck. `uid` is carried for
  // client-facing peer-disconnect countdowns.
  disconnectGrace?: Map<
    Color,
    { timer: NodeJS.Timeout; deadline: number; uid: string }
  >;

  // Sprint 12 A5: short in-memory chat history for reconnect/session UI.
  chatMessages?: ChatMessage[];
  lastChatAtByUid?: Record<string, number>;

  // Sprint 12 rematch: set of uids who have offered a rematch after the
  // game finished. When both players have offered, a fresh game starts in
  // the same room with colors swapped. Cleared on game start / leave.
  rematchOfferedBy?: Set<string>;
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

/// A room is a *live* game only while at least one of its players is still
/// connected. During the reconnect grace window a disconnected player's socket
/// is removed from `members` (see leaveRoom + preserveStatus), so a room where
/// BOTH players dropped has `members.size === 0` while still flagged 'playing'.
/// Such a "ghost" room must not be advertised as active — otherwise the lobby
/// keeps showing A,B as "đang đánh" after both have left, until the grace timer
/// finally forfeits it ~60s later.
export function activeRooms(): Room[] {
  return [...rooms.values()].filter(
    (room) => room.status === 'playing' && room.members.size > 0,
  );
}

/// Step 8: rebind a fresh socket to an existing room (reconnect path).
/// Caller is responsible for verifying uid matches one of redUid/blackUid
/// and that the uid has an entry in disconnectGrace. This just updates the maps.
export function attachReconnectingSocket(
  socket: WebSocket,
  room: Room,
  uid: string,
): Color {
  // Decide which seat this socket reclaims. Normally the uid uniquely
  // identifies the seat. For SAME-UID solo testing (red & black share one
  // Firebase uid) the seat is ambiguous — fill whichever seat's socket is
  // currently gone (the one that actually dropped), so a black reconnect
  // doesn't get wrongly slotted into the still-live red seat. The chosen seat
  // is returned so the caller reports a consistent `yourColor`.
  const sameUid = uid === room.redUid && uid === room.blackUid;
  let seat: Color;
  if (sameUid) {
    const redGone =
      !room.redSocket || room.redSocket.readyState !== WebSocket.OPEN;
    seat = redGone ? 'red' : 'black';
  } else {
    seat = uid === room.blackUid ? 'black' : 'red';
  }

  // Evict any prior socket holding this seat first, so room.members never
  // accumulates dead sockets across reconnects. A stale socket left behind
  // would still receive broadcasts (e.g. opponent-move would go to a dead
  // socket instead of the live one) and inflate members.size.
  const prior = seat === 'red' ? room.redSocket : room.blackSocket;
  if (prior && prior !== socket) {
    room.members.delete(prior);
    socketToRoom.delete(prior);
  }
  room.members.add(socket);
  socketToRoom.set(socket, room.id);
  if (seat === 'red') room.redSocket = socket;
  else room.blackSocket = socket;
  return seat;
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
  | {
      ok: false;
      code: 'room-not-found' | 'room-full' | 'already-in-room' | 'room-in-progress';
    };

export function joinRoom(socket: WebSocket, roomId: string): JoinResult {
  if (socketToRoom.has(socket)) return { ok: false, code: 'already-in-room' };
  const room = rooms.get(roomId);
  if (!room) return { ok: false, code: 'room-not-found' };
  // Only a room still WAITING for its second player is joinable. Joining a
  // 'playing' room (e.g. one with a player mid-reconnect, members.size===1) used
  // to slip past the size check and re-trigger startGameForRoom — resetting the
  // in-progress game and hijacking the disconnected player's seat. A 'finished'
  // room isn't joinable either.
  if (room.status !== 'waiting') return { ok: false, code: 'room-in-progress' };
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
    if (room.waitingTimer) {
      clearTimeout(room.waitingTimer);
      room.waitingTimer = undefined;
    }
    rooms.delete(room.id);
    return room;
  }
  return room;
}

/// Cancel pending grace timer(s). With a color, clears only that seat's entry;
/// without, clears every entry (game over / rematch reset).
export function clearDisconnectGrace(room: Room, color?: Color): void {
  const grace = room.disconnectGrace;
  if (!grace) return;
  if (color !== undefined) {
    const entry = grace.get(color);
    if (entry) {
      clearTimeout(entry.timer);
      grace.delete(color);
    }
    return;
  }
  for (const entry of grace.values()) clearTimeout(entry.timer);
  grace.clear();
}

/// Drop a room that no longer has any sockets attached — e.g. a game that
/// finished while both players were disconnected. No-op while anyone is
/// still connected (player or spectator).
export function deleteRoomIfEmpty(room: Room): boolean {
  if (room.members.size > 0 || room.spectators.size > 0) return false;
  clearDisconnectGrace(room);
  if (room.clockTimer) {
    clearInterval(room.clockTimer);
    room.clockTimer = undefined;
  }
  if (room.waitingTimer) {
    clearTimeout(room.waitingTimer);
    room.waitingTimer = undefined;
  }
  return rooms.delete(room.id);
}

export function isSpectator(room: Room, socket: WebSocket): boolean {
  return room.spectators.has(socket);
}

export function membersOf(room: Room, uidLookup: (s: WebSocket) => string | undefined): string[] {
  return [...room.members].map(uidLookup).filter((u): u is string => typeof u === 'string');
}

// ── Introspection (read-only) ─────────────────────────────────────────────
// Pure snapshots of the otherwise-private `rooms` + `socketToRoom` maps, used
// by the test lab (lab/) to assert invariants and drive the live dashboard.
// They have no side effects and never run unless explicitly called.

/// Serializable view of a single room's lifecycle state.
export interface RoomDebug {
  id: string;
  status: Room['status'];
  /// Connected PLAYER sockets currently attached (excludes those in grace).
  members: number;
  /// Of `members`, how many sockets are actually in the OPEN state. A gap here
  /// means a stale/dead socket is lingering in the room (socket-leak smell).
  membersOpen: number;
  spectators: number;
  redUid?: string;
  blackUid?: string;
  /// uids currently inside the reconnect grace window (for display).
  graceUids: string[];
  /// seats (colors) currently inside the grace window — the precise per-seat
  /// view; distinct from graceUids when both seats share one uid.
  graceColors: Color[];
  moveCount: number;
  /// movesUci.length — should equal moveCount for a consistent game.
  movesLen: number;
  /// Seat-socket liveness (null = seat socket unset). A 'playing' seat whose
  /// socket is not open should have its uid in graceUids.
  redSocketOpen: boolean | null;
  blackSocketOpen: boolean | null;
  hasClockTimer: boolean;
  hasWaitingTimer: boolean;
  hasClock: boolean;
  startedAt?: number;
}

export function debugRooms(): RoomDebug[] {
  const openOf = (s: WebSocket | undefined): boolean | null =>
    s === undefined ? null : s.readyState === WebSocket.OPEN;
  return [...rooms.values()].map((room) => ({
    id: room.id,
    status: room.status,
    members: room.members.size,
    membersOpen: [...room.members].filter((s) => s.readyState === WebSocket.OPEN)
      .length,
    spectators: room.spectators.size,
    redUid: room.redUid,
    blackUid: room.blackUid,
    graceUids: room.disconnectGrace
      ? [...room.disconnectGrace.values()].map((e) => e.uid)
      : [],
    graceColors: room.disconnectGrace ? [...room.disconnectGrace.keys()] : [],
    moveCount: room.moveCount,
    movesLen: room.movesUci?.length ?? 0,
    redSocketOpen: openOf(room.redSocket),
    blackSocketOpen: openOf(room.blackSocket),
    hasClockTimer: room.clockTimer !== undefined,
    hasWaitingTimer: room.waitingTimer !== undefined,
    hasClock: room.clockMsByColor !== undefined,
    startedAt: room.startedAt,
  }));
}

/// Cross-check the two internal maps that must always agree. Returns a list of
/// human-readable violations (empty == healthy). Catches the class of bug where
/// a socket lingers in `members` without a back-reference in `socketToRoom`
/// (or vice versa) after a messy disconnect/reconnect.
export function debugSocketMapIssues(): string[] {
  const issues: string[] = [];
  for (const [sock, id] of socketToRoom) {
    const room = rooms.get(id);
    if (!room) {
      issues.push(`socketToRoom points at missing room ${id}`);
      continue;
    }
    if (!room.members.has(sock) && !room.spectators.has(sock)) {
      issues.push(`socket mapped to ${id} but not in its members/spectators`);
    }
  }
  for (const room of rooms.values()) {
    for (const s of room.members) {
      if (socketToRoom.get(s) !== room.id) {
        issues.push(`member of ${room.id} missing/wrong back-ref in socketToRoom`);
      }
    }
    for (const s of room.spectators) {
      if (socketToRoom.get(s) !== room.id) {
        issues.push(`spectator of ${room.id} missing/wrong back-ref in socketToRoom`);
      }
    }
  }
  return issues;
}

/// Lab/test-only: wipe ALL room state (and any pending timers) so the headless
/// scenario runner can reuse one process across isolated scenarios. NOT used by
/// the production server.
export function __resetRoomsForLab(): void {
  for (const room of rooms.values()) {
    if (room.clockTimer) clearInterval(room.clockTimer);
    if (room.waitingTimer) clearTimeout(room.waitingTimer);
    if (room.disconnectGrace) {
      for (const entry of room.disconnectGrace.values()) clearTimeout(entry.timer);
    }
  }
  rooms.clear();
  socketToRoom.clear();
}
