import assert from 'node:assert/strict';
import { afterEach, test } from 'node:test';
import type { WebSocket } from 'ws';

import {
  applyMove,
  colorOfSocket,
  endMatch,
  INITIAL_CLOCK_MS,
  startMatch,
  startRematch,
} from './match';
import { createRoom, joinRoom, leaveRoom, type Room } from './rooms';
import { PieceColor, uciOfMove, XiangqiGame } from './engine';

const sockets: WebSocket[] = [];

function fakeSocket(name: string): WebSocket {
  const socket = { name } as unknown as WebSocket;
  sockets.push(socket);
  return socket;
}

/// Build a 2-player room already in 'playing' state. First member = red.
function startPlayingRoom(name: string): {
  room: Room;
  red: WebSocket;
  black: WebSocket;
} {
  const red = fakeSocket(`${name}-red`);
  const black = fakeSocket(`${name}-black`);
  const room = createRoom(red);
  assert.equal(joinRoom(black, room.id).ok, true);
  startMatch(room, (s) =>
    s === red ? `${name}-red-uid` : `${name}-black-uid`,
  );
  assert.equal(room.status, 'playing');
  return { room, red, black };
}

/// First legal move for `color` from the initial position, as a UCI string.
/// Computed dynamically so the test never hardcodes board geometry.
function firstLegalUciFor(color: PieceColor): string {
  const game = XiangqiGame.initial();
  for (const [pos, piece] of game.board.occupied()) {
    if (piece.color !== color) continue;
    const moves = game.getValidMoves(pos);
    if (moves.length > 0) return uciOfMove(pos, moves[0]);
  }
  throw new Error(`no legal move for ${color}`);
}

afterEach(() => {
  for (let i = sockets.length - 1; i >= 0; i--) leaveRoom(sockets[i]);
  sockets.length = 0;
});

test('startMatch assigns colors by insertion order + initial clock/turn/engine', () => {
  const { room, red, black } = startPlayingRoom('start');

  assert.equal(room.redSocket, red);
  assert.equal(room.blackSocket, black);
  assert.equal(room.redUid, 'start-red-uid');
  assert.equal(room.blackUid, 'start-black-uid');
  assert.equal(room.currentTurn, 'red');
  assert.equal(room.clockMsByColor?.red, INITIAL_CLOCK_MS);
  assert.equal(room.clockMsByColor?.black, INITIAL_CLOCK_MS);
  assert.deepEqual(room.movesUci, []);
  assert.ok(room.engine, 'engine should be initialised');
  assert.equal(colorOfSocket(room, red), 'red');
  assert.equal(colorOfSocket(room, black), 'black');
});

test('applyMove: legal red move advances turn, records move, deducts clock', () => {
  const { room, red } = startPlayingRoom('apply');
  const uci = firstLegalUciFor(PieceColor.Red);
  const before = room.clockMsByColor!.red;

  const res = applyMove(room, red, uci);

  assert.equal(res.ok, true);
  if (res.ok) {
    assert.equal(res.color, 'red');
    assert.equal(res.moveNumber, 1);
  }
  assert.equal(room.currentTurn, 'black');
  assert.equal(room.movesUci?.length, 1);
  assert.equal(room.movesUci?.[0], uci);
  assert.ok(room.clockMsByColor!.red <= before);
});

test('applyMove rejects a move when it is not that player\'s turn', () => {
  const { room, black } = startPlayingRoom('wrong-turn');
  // Red moves first. The turn check fires before legality, so the exact UCI
  // doesn't matter — black simply isn't allowed to move yet.
  const res = applyMove(room, black, firstLegalUciFor(PieceColor.Red));
  assert.deepEqual(res, { ok: false, code: 'not-your-turn' });
  assert.equal(room.movesUci?.length, 0);
});

test('applyMove rejects an illegal move (diagonal chariot)', () => {
  const { room, red } = startPlayingRoom('illegal');
  // a0b1: red corner chariot moving diagonally — never legal.
  const res = applyMove(room, red, 'a0b1');
  assert.deepEqual(res, { ok: false, code: 'illegal-move' });
  assert.equal(room.movesUci?.length, 0);
});

test('applyMove rejects a socket that is not a player', () => {
  const { room } = startPlayingRoom('non-player');
  const stranger = fakeSocket('stranger');
  const res = applyMove(room, stranger, firstLegalUciFor(PieceColor.Red));
  assert.deepEqual(res, { ok: false, code: 'not-player' });
});

test('applyMove returns time-out when the mover has no clock left', () => {
  const { room, red } = startPlayingRoom('timeout');
  room.clockMsByColor!.red = 50;
  room.turnStartedAt = Date.now() - 5_000; // 5s elapsed >> 50ms budget

  const res = applyMove(room, red, firstLegalUciFor(PieceColor.Red));

  assert.deepEqual(res, { ok: false, code: 'time-out' });
  assert.equal(room.clockMsByColor!.red, 0);
  assert.equal(room.movesUci?.length, 0, 'a timed-out move must not be recorded');
});

test('startRematch swaps colors and resets all game state', () => {
  const { room, red, black } = startPlayingRoom('rematch');
  // Play one move + finish so there is dirty state to reset.
  applyMove(room, red, firstLegalUciFor(PieceColor.Red));
  endMatch(room, 'red-win', 'checkmate');
  room.rematchOfferedBy = new Set([room.redUid!, room.blackUid!]);
  const prevRedUid = room.redUid;
  const prevBlackUid = room.blackUid;

  const ok = startRematch(room);

  assert.equal(ok, true);
  // Colors swapped (chess etiquette: alternate first-move advantage).
  assert.equal(room.redUid, prevBlackUid);
  assert.equal(room.blackUid, prevRedUid);
  assert.equal(room.redSocket, black);
  assert.equal(room.blackSocket, red);
  // Fresh game state.
  assert.equal(room.status, 'playing');
  assert.equal(room.currentTurn, 'red');
  assert.deepEqual(room.movesUci, []);
  assert.equal(room.moveCount, 0);
  assert.equal(room.result, undefined);
  assert.equal(room.endReason, undefined);
  assert.equal(room.rematchOfferedBy, undefined);
  assert.equal(room.clockMsByColor?.red, INITIAL_CLOCK_MS);
  assert.equal(room.clockMsByColor?.black, INITIAL_CLOCK_MS);
  assert.ok(room.engine, 'engine should be re-initialised');
});

test('startRematch fails when the room no longer has two players', () => {
  const red = fakeSocket('solo-red');
  const room = createRoom(red); // only one member
  assert.equal(startRematch(room), false);
});
