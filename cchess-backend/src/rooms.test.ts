import assert from 'node:assert/strict';
import { afterEach, test } from 'node:test';
import type { WebSocket } from 'ws';

import { applyMove, colorOfSocket, endMatch, startMatch } from './match';
import {
  activeRooms,
  createRoom,
  joinRoom,
  leaveRoom,
  spectateRoom,
  type Room,
} from './rooms';

const sockets: WebSocket[] = [];

function fakeSocket(name: string): WebSocket {
  const socket = { name } as unknown as WebSocket;
  sockets.push(socket);
  return socket;
}

function startPlayingRoom(name: string): Room {
  const red = fakeSocket(`${name}-red`);
  const black = fakeSocket(`${name}-black`);
  const room = createRoom(red);
  const joined = joinRoom(black, room.id);
  assert.equal(joined.ok, true);
  startMatch(room, (socket) =>
    socket === red ? `${name}-red-uid` : `${name}-black-uid`,
  );
  assert.equal(room.status, 'playing');
  return room;
}

afterEach(() => {
  for (let i = sockets.length - 1; i >= 0; i--) {
    leaveRoom(sockets[i]);
  }
  sockets.length = 0;
});

test('spectateRoom only accepts active games and keeps viewer read-only', () => {
  const waitingPlayer = fakeSocket('waiting-red');
  const waitingRoom = createRoom(waitingPlayer);
  const earlyViewer = fakeSocket('early-viewer');
  assert.deepEqual(spectateRoom(earlyViewer, waitingRoom.id), {
    ok: false,
    code: 'game-not-active',
  });

  const room = startPlayingRoom('readonly');
  const viewer = fakeSocket('viewer');
  const result = spectateRoom(viewer, room.id);

  assert.equal(result.ok, true);
  assert.equal(room.members.size, 2);
  assert.equal(room.spectators.has(viewer), true);
  assert.equal(colorOfSocket(room, viewer), null);

  const move = applyMove(room, viewer, 'a0a1');
  assert.deepEqual(move, { ok: false, code: 'not-player' });
});

test('spectator leave does not alter active player room state', () => {
  const room = startPlayingRoom('leave');
  const viewer = fakeSocket('viewer');
  assert.equal(spectateRoom(viewer, room.id).ok, true);

  const leftRoom = leaveRoom(viewer);

  assert.equal(leftRoom, room);
  assert.equal(room.status, 'playing');
  assert.equal(room.members.size, 2);
  assert.equal(room.spectators.size, 0);
  assert.equal(activeRooms().some((active) => active.id === room.id), true);
});

test('activeRooms returns playing rooms only', () => {
  const waiting = createRoom(fakeSocket('waiting'));
  const playing = startPlayingRoom('active');
  const finished = startPlayingRoom('finished');
  endMatch(finished, 'draw', 'stalemate');

  const ids = activeRooms().map((room) => room.id);

  assert.equal(ids.includes(waiting.id), false);
  assert.equal(ids.includes(playing.id), true);
  assert.equal(ids.includes(finished.id), false);
});
