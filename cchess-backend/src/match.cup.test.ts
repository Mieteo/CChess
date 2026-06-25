// Cờ Úp wiring in the match layer: startMatch picks the cup engine for cup
// rooms, applyMove returns reveal info (the only identity data a client gets),
// and cupSnapshot exposes a cheat-safe board view for reconnect.

import assert from 'node:assert/strict';
import { afterEach, test } from 'node:test';
import type { WebSocket } from 'ws';

import { applyMove, cupSnapshot, startMatch } from './match';
import { createRoom, joinRoom, leaveRoom, type Room } from './rooms';
import { PieceColor, uciOfMove, XiangqiCupGame, XiangqiGame, type Position } from './engine';

const sockets: WebSocket[] = [];

function fakeSocket(name: string): WebSocket {
  const socket = { name } as unknown as WebSocket;
  sockets.push(socket);
  return socket;
}

/// A 2-player cup room in 'playing' state, with a SEED-pinned engine so moves
/// are deterministic (startMatch installs a random shuffle we then replace).
function startCupRoom(name: string, seed: number): {
  room: Room;
  red: WebSocket;
  black: WebSocket;
  engine: XiangqiCupGame;
} {
  const red = fakeSocket(`${name}-red`);
  const black = fakeSocket(`${name}-black`);
  const room = createRoom(red, { variant: 'cup' });
  assert.equal(joinRoom(black, room.id).ok, true);
  startMatch(room, (s) => (s === red ? `${name}-red-uid` : `${name}-black-uid`));
  const engine = XiangqiCupGame.initial(seed);
  room.engine = engine;
  return { room, red, black, engine };
}

function firstLegalCupMove(
  engine: XiangqiCupGame,
  color: PieceColor,
): { uci: string; from: Position; to: Position } {
  for (const [pos, piece] of engine.board.occupied()) {
    if (piece.color !== color) continue;
    const moves = engine.getValidMoves(pos);
    if (moves.length > 0) {
      return { uci: uciOfMove(pos, moves[0]), from: pos, to: moves[0] };
    }
  }
  throw new Error(`no legal cup move for ${color}`);
}

afterEach(() => {
  for (let i = sockets.length - 1; i >= 0; i--) leaveRoom(sockets[i]);
  sockets.length = 0;
});

test('startMatch installs a cup engine for a variant=cup room', () => {
  const { room } = startCupRoom('engine', 7);
  assert.equal(room.variant, 'cup');
  assert.ok(room.engine instanceof XiangqiCupGame, 'engine should be a cup game');
});

test('applyMove on a cup room returns reveal info (revealed + wasHidden)', () => {
  const { room, red, engine } = startCupRoom('reveal', 7);
  const mv = firstLegalCupMove(engine, PieceColor.Red);
  // The piece is face-down at the start, so we know its true identity here only
  // via the debug peek — exactly what the server reveals to clients post-move.
  const trueChar = engine.debugHiddenAt(mv.from)!.fenChar();

  const res = applyMove(room, red, mv.uci);

  assert.equal(res.ok, true);
  if (!res.ok) return;
  assert.ok(res.reveal, 'cup move carries reveal info');
  assert.equal(res.reveal!.wasHidden, true, 'a starting piece is face-down');
  assert.equal(res.reveal!.captured, null, 'first move captures nothing');
  assert.equal(res.reveal!.revealed, trueChar, 'reveals the true identity');
  assert.equal(room.movesUci?.[0], mv.uci);
});

test('applyMove on a standard room carries no reveal info', () => {
  const red = fakeSocket('std-red');
  const black = fakeSocket('std-black');
  const room = createRoom(red); // default variant: 'standard'
  assert.equal(joinRoom(black, room.id).ok, true);
  startMatch(room, (s) => (s === red ? 'std-red-uid' : 'std-black-uid'));

  // First red move. Compute it to avoid hardcoding board geometry.
  const engine = room.engine as XiangqiGame;
  let uci = '';
  for (const [pos, piece] of engine.board.occupied()) {
    if (piece.color !== PieceColor.Red) continue;
    const moves = engine.getValidMoves(pos);
    if (moves.length > 0) { uci = uciOfMove(pos, moves[0]); break; }
  }
  const res = applyMove(room, red, uci);
  assert.equal(res.ok, true);
  if (res.ok) assert.equal(res.reveal, undefined, 'standard games have no reveal');
});

test('cupSnapshot is cheat-safe and shrinks as pieces reveal', () => {
  const { room, red, engine } = startCupRoom('snap', 7);
  const before = cupSnapshot(room);
  assert.ok(before, 'cup room has a snapshot');
  assert.equal(before!.hidden.length, 30, 'all non-general pieces start face-down');

  const mv = firstLegalCupMove(engine, PieceColor.Red);
  applyMove(room, red, mv.uci);

  const after = cupSnapshot(room);
  assert.equal(after!.hidden.length, 29, 'the moved piece is now revealed');
  // The snapshot never includes hidden identities — only a FEN of covers/reveals.
  assert.equal(typeof after!.fen, 'string');
});

test('cupSnapshot returns null for a standard room', () => {
  const red = fakeSocket('snap-std-red');
  const black = fakeSocket('snap-std-black');
  const room = createRoom(red);
  assert.equal(joinRoom(black, room.id).ok, true);
  startMatch(room, (s) => (s === red ? 'a' : 'b'));
  assert.equal(cupSnapshot(room), null);
});
