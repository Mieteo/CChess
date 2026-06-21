// Step 5-8: game lifecycle helpers for an active room.
// This module owns turn/clock state, server-side Xiangqi move validation,
// timeout, resign, reconnect grace, and auto-finish detection.

import type { WebSocket } from 'ws';
import type { Color, EndReason, GameResult, Room } from './rooms';
import { clearDisconnectGrace, deleteRoomIfEmpty } from './rooms';
import { XiangqiGame, GameStatus, parseUci, EndReason as EngineEndReason } from './engine';

/// Initial total clock per color (in ms). Currently 10 minutes — Fischer
/// increment will come later. Configurable per room via lobby is the next
/// UX iteration.
export const INITIAL_CLOCK_MS = 600_000;

/// Hard cap per move. This keeps a connected-but-idle player from making the
/// opponent wait until the whole-game clock runs out.
export const MOVE_TIME_LIMIT_MS = 90_000;

/// Step 8 reconnect: grace window after a player disconnects mid-game.
/// If they reconnect with the same uid within this window, the room is
/// resumed; otherwise the game ends with reason='disconnect'.
/// Overridable via env so integration tests can use a short window.
export const RECONNECT_GRACE_MS =
  Number(process.env.CCHESS_RECONNECT_GRACE_MS ?? '') || 60_000;

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
  const clock = room.initialClockMs ?? INITIAL_CLOCK_MS;
  room.clockMsByColor = { red: clock, black: clock };
  room.moveTimeLimitMs = MOVE_TIME_LIMIT_MS;
  room.currentTurn = 'red';
  const now = Date.now();
  room.turnStartedAt = now;
  room.startedAt = now;
  room.movesUci = [];
  room.status = 'playing';
  // Step 5: fresh Xiangqi engine for legality validation.
  room.engine = XiangqiGame.initial();
}

/// Sprint 12 rematch: start a fresh game in an existing (finished) room with
/// colors SWAPPED from the previous game (chess etiquette — alternate the
/// first-move advantage). Both player sockets must still be connected.
/// Returns false if the room isn't in a valid state to rematch.
export function startRematch(room: Room): boolean {
  if (room.members.size !== 2) return false;
  const prevRedSocket = room.redSocket;
  const prevBlackSocket = room.blackSocket;
  const prevRedUid = room.redUid;
  const prevBlackUid = room.blackUid;
  if (!prevRedSocket || !prevBlackSocket || !prevRedUid || !prevBlackUid) {
    return false;
  }
  // Swap: previous black plays red this time.
  room.redSocket = prevBlackSocket;
  room.blackSocket = prevRedSocket;
  room.redUid = prevBlackUid;
  room.blackUid = prevRedUid;

  const clock = room.initialClockMs ?? INITIAL_CLOCK_MS;
  room.clockMsByColor = { red: clock, black: clock };
  room.moveTimeLimitMs = MOVE_TIME_LIMIT_MS;
  room.currentTurn = 'red';
  const now = Date.now();
  room.turnStartedAt = now;
  room.startedAt = now;
  room.endedAt = undefined;
  room.result = undefined;
  room.endReason = undefined;
  room.movesUci = [];
  room.moveCount = 0;
  room.status = 'playing';
  room.engine = XiangqiGame.initial();
  room.rematchOfferedBy = undefined;
  clearDisconnectGrace(room);
  return true;
}

/// Cast helper — engine is stored as `unknown` on Room to avoid a circular import.
function engineOf(room: Room): XiangqiGame | null {
  return (room.engine as XiangqiGame | undefined) ?? null;
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
  code: 'not-playing' | 'not-player' | 'not-your-turn' | 'time-out' | 'illegal-move' | 'engine-missing';
}

/// Result returned to caller when applyMove ends the game by itself (checkmate
/// or stalemate). Caller should call finishGame() with the included result.
export interface AutoFinishResult {
  result: GameResult;
  reason: EndReason;
}

export interface ApplyMoveOkWithFinish extends ApplyMoveOk {
  autoFinish?: AutoFinishResult;
}

/// Apply a UCI move to the room. Validates:
///   - room playing, socket is a player, correct turn
///   - clock not timed out
///   - UCI parses to valid coords
///   - move is LEGAL per Xiangqi rules (Step 5)
/// Returns ok with updated clock + optional autoFinish (checkmate / stalemate),
/// or err code. On `time-out`, caller must end the match with red-win/black-win
/// for the OTHER color.
export function applyMove(
  room: Room,
  socket: WebSocket,
  uci: string,
): ApplyMoveOkWithFinish | ApplyMoveErr {
  if (room.status !== 'playing') return { ok: false, code: 'not-playing' };
  const color = colorOfSocket(room, socket);
  if (!color) return { ok: false, code: 'not-player' };
  if (color !== room.currentTurn) return { ok: false, code: 'not-your-turn' };

  const engine = engineOf(room);
  if (!engine) return { ok: false, code: 'engine-missing' };

  // Timeout blocks any move; invalid moves inside the window do not cost time.
  const clocks = room.clockMsByColor!;
  const moveLimit = room.moveTimeLimitMs ?? MOVE_TIME_LIMIT_MS;
  const now = Date.now();
  const elapsed = Math.max(0, now - (room.turnStartedAt ?? now));
  if (elapsed >= clocks[color] || elapsed >= moveLimit) {
    clocks[color] = Math.max(0, clocks[color] - elapsed);
    return { ok: false, code: 'time-out' };
  }

  const coords = parseUci(uci);
  if (!coords) return { ok: false, code: 'illegal-move' };
  if (!engine.isValidMove(coords.from, coords.to)) {
    return { ok: false, code: 'illegal-move' };
  }

  clocks[color] = Math.max(0, clocks[color] - elapsed);

  // Apply on engine (status auto-updates: checkmate/stalemate detection).
  try {
    engine.makeMove(coords.from, coords.to);
  } catch (e) {
    // Should never happen given isValidMove check above, but defensive.
    return { ok: false, code: 'illegal-move' };
  }

  room.movesUci!.push(uci);
  room.moveCount++;
  room.currentTurn = opponentOf(color);
  room.turnStartedAt = now;

  const ok: ApplyMoveOkWithFinish = {
    ok: true,
    color,
    remainingMs: clocks[color],
    moveNumber: room.moveCount,
  };

  // Auto-finish on checkmate/stalemate
  if (engine.status !== GameStatus.Playing) {
    let result: GameResult;
    if (engine.status === GameStatus.RedWin) result = 'red-win';
    else if (engine.status === GameStatus.BlackWin) result = 'black-win';
    else result = 'draw'; // not currently reachable but safe
    const reason: EndReason =
      engine.endReason === EngineEndReason.Checkmate
        ? 'checkmate'
        : engine.endReason === EngineEndReason.Stalemate
        ? 'stalemate'
        : 'resign'; // fallback — won't happen on auto path
    ok.autoFinish = { result, reason };
  }

  return ok;
}

/// Check whether the current player has run out of time. Called by interval timer.
export function isTimedOut(room: Room): boolean {
  if (room.status !== 'playing') return false;
  if (!room.currentTurn || !room.turnStartedAt || !room.clockMsByColor) return false;
  const elapsed = Date.now() - room.turnStartedAt;
  const moveLimit = room.moveTimeLimitMs ?? MOVE_TIME_LIMIT_MS;
  return (
    elapsed >= room.clockMsByColor[room.currentTurn] ||
    elapsed >= moveLimit
  );
}

/// Server-authoritative timeout check used by the room ticker. Mutates the
/// moving player's total clock to reflect the elapsed turn before finishing.
export function consumeTimeoutIfExpired(room: Room): Color | null {
  if (!isTimedOut(room) || !room.currentTurn || !room.turnStartedAt || !room.clockMsByColor) {
    return null;
  }
  const loser = room.currentTurn;
  const elapsed = Math.max(0, Date.now() - room.turnStartedAt);
  room.clockMsByColor[loser] = Math.max(
    0,
    room.clockMsByColor[loser] - elapsed,
  );
  return loser;
}

/// Transition the room to 'finished'. Returns true if THIS call performed the
/// transition, false if the room was already finished. Callers (finishGame)
/// rely on the return to avoid persisting / broadcasting a result twice when
/// two end-conditions race (e.g. resign + timeout), which would double-apply
/// ELO and emit two game-ended events.
export function endMatch(room: Room, result: GameResult, reason: EndReason): boolean {
  if (room.status === 'finished') return false;
  room.status = 'finished';
  room.result = result;
  room.endReason = reason;
  room.endedAt = Date.now();
  if (room.clockTimer) {
    clearInterval(room.clockTimer);
    room.clockTimer = undefined;
  }
  // Any pending grace timers are moot once the game is decided. If the game
  // ended while BOTH players were disconnected (double-disconnect), nobody is
  // left to tear the room down — drop it here so it doesn't leak.
  clearDisconnectGrace(room);
  deleteRoomIfEmpty(room);
  return true;
}

/// Snapshot of clock + turn for sending to clients.
export function clockSnapshot(room: Room): {
  red: number;
  black: number;
  currentTurn: Color | undefined;
  turnStartedAt: number | undefined;
  serverNow: number;
  moveTimeLimitMs: number;
  moveDeadlineAt: number | undefined;
  moveRemainingMs: number;
} {
  const serverNow = Date.now();
  const moveTimeLimitMs = room.moveTimeLimitMs ?? MOVE_TIME_LIMIT_MS;
  const moveDeadlineAt = room.turnStartedAt
    ? room.turnStartedAt + moveTimeLimitMs
    : undefined;
  const moveRemainingMs = moveDeadlineAt
    ? Math.max(0, moveDeadlineAt - serverNow)
    : moveTimeLimitMs;
  return {
    red: room.clockMsByColor?.red ?? 0,
    black: room.clockMsByColor?.black ?? 0,
    currentTurn: room.currentTurn,
    turnStartedAt: room.turnStartedAt,
    serverNow,
    moveTimeLimitMs,
    moveDeadlineAt,
    moveRemainingMs,
  };
}
