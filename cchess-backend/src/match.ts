// Step 6: clock + game lifecycle helpers for an active room.
// Step 5 (full Xiangqi rule validation) is deferred — we only track:
//   - whose turn it is
//   - per-color remaining clock
//   - timeout
//   - resign + disconnect ending the game

import type { WebSocket } from 'ws';
import type { Color, EndReason, GameResult, Room } from './rooms';

/// Initial total clock per color (in ms). Currently 10 minutes — Fischer
/// increment will come later. Configurable per room via lobby is the next
/// UX iteration.
export const INITIAL_CLOCK_MS = 600_000;

/// Step 8 reconnect: grace window after a player disconnects mid-game.
/// If they reconnect with the same uid within this window, the room is
/// resumed; otherwise the game ends with reason='disconnect'.
export const RECONNECT_GRACE_MS = 60_000;

/// Called when 2nd player joins → status becomes 'playing'.
/// Members are iterated in insertion order; first joiner = red.
/// Color is tracked by SOCKET reference (not uid) so that same-uid testing
/// (2 sockets from same Firebase user) works correctly.
export function startMatch(room: Room, uidOf: (s: WebSocket) => string | undefined): void {
  const members = [...room.members];
  if (members.length !== 2) return;
  const uids = members.map(uidOf).filter((u): u is string => typeof u === 'string');
  if (uids.length !== 2) return;

  room.redSocket = members[0];
  room.blackSocket = members[1];
  room.redUid = uids[0];
  room.blackUid = uids[1];
  room.clockMsByColor = { red: INITIAL_CLOCK_MS, black: INITIAL_CLOCK_MS };
  room.currentTurn = 'red';
  const now = Date.now();
  room.turnStartedAt = now;
  room.startedAt = now;
  room.movesUci = [];
  room.status = 'playing';
}

/// Determine color by socket identity (the only reliable way when both sockets
/// might share the same Firebase uid during testing).
export function colorOfSocket(room: Room, socket: WebSocket): Color | null {
  if (socket === room.redSocket) return 'red';
  if (socket === room.blackSocket) return 'black';
  return null;
}

export function opponentOf(color: Color): Color {
  return color === 'red' ? 'black' : 'red';
}

export interface ApplyMoveOk {
  ok: true;
  /// Color that just moved.
  color: Color;
  /// Remaining ms after this move (for the moving color).
  remainingMs: number;
  /// New move number (1-indexed).
  moveNumber: number;
}

export interface ApplyMoveErr {
  ok: false;
  code: 'not-playing' | 'not-player' | 'not-your-turn' | 'time-out';
}

/// Apply a UCI move to the room. Caller already validated UCI format.
/// Returns ok with updated clock, or err code. On `time-out`, caller
/// must end the match with red-win/black-win for the OTHER color.
export function applyMove(room: Room, socket: WebSocket, uci: string): ApplyMoveOk | ApplyMoveErr {
  if (room.status !== 'playing') return { ok: false, code: 'not-playing' };
  const color = colorOfSocket(room, socket);
  if (!color) return { ok: false, code: 'not-player' };
  if (color !== room.currentTurn) return { ok: false, code: 'not-your-turn' };

  const clocks = room.clockMsByColor!;
  const now = Date.now();
  const elapsed = now - (room.turnStartedAt ?? now);
  clocks[color] -= elapsed;
  if (clocks[color] <= 0) {
    clocks[color] = 0;
    return { ok: false, code: 'time-out' };
  }

  room.movesUci!.push(uci);
  room.moveCount++;
  room.currentTurn = opponentOf(color);
  room.turnStartedAt = now;

  return {
    ok: true,
    color,
    remainingMs: clocks[color],
    moveNumber: room.moveCount,
  };
}

/// Check whether the current player has run out of time. Called by interval timer.
export function isTimedOut(room: Room): boolean {
  if (room.status !== 'playing') return false;
  if (!room.currentTurn || !room.turnStartedAt || !room.clockMsByColor) return false;
  const elapsed = Date.now() - room.turnStartedAt;
  return elapsed >= room.clockMsByColor[room.currentTurn];
}

export function endMatch(room: Room, result: GameResult, reason: EndReason): void {
  if (room.status === 'finished') return;
  room.status = 'finished';
  room.result = result;
  room.endReason = reason;
  room.endedAt = Date.now();
  if (room.clockTimer) {
    clearInterval(room.clockTimer);
    room.clockTimer = undefined;
  }
}

/// Snapshot of clock + turn for sending to clients.
export function clockSnapshot(room: Room): {
  red: number;
  black: number;
  currentTurn: Color | undefined;
} {
  return {
    red: room.clockMsByColor?.red ?? 0,
    black: room.clockMsByColor?.black ?? 0,
    currentTurn: room.currentTurn,
  };
}
