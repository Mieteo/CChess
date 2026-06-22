import assert from 'node:assert/strict';
import test from 'node:test';
import { SimMonitor, type ProtocolViolation } from './monitor';
import type { Msg } from '../bot';

function server(
  monitor: SimMonitor,
  agentId: string,
  uid: string,
  message: Msg,
): ProtocolViolation | undefined {
  return monitor.observeServerMessage({
    agentId,
    uid,
    roomId: typeof message.roomId === 'string' ? message.roomId : undefined,
    message,
  });
}

test('monitor detects a spectator being promoted to player', () => {
  const monitor = new SimMonitor();
  monitor.registerAgent({ id: 'watcher', uid: 'watcher_uid' });

  assert.equal(
    monitor.observeCommand({
      type: 'spectate-room',
      agentId: 'watcher',
      uid: 'watcher_uid',
      roomId: 'ROOM01',
    }),
    undefined,
  );
  assert.equal(
    server(monitor, 'watcher', 'watcher_uid', {
      type: 'spectate-started',
      roomId: 'ROOM01',
      redUid: 'red_uid',
      blackUid: 'black_uid',
      moves: [],
    }),
    undefined,
  );

  const violation = server(monitor, 'watcher', 'watcher_uid', {
    type: 'game-start',
    roomId: 'ROOM01',
    redUid: 'watcher_uid',
    blackUid: 'black_uid',
    yourColor: 'red',
  });
  assert.equal(violation?.rule, 'spectator-became-player');
});

test('monitor detects game-ended move list mismatch', () => {
  const monitor = new SimMonitor();
  monitor.registerAgent({ id: 'red', uid: 'red_uid' });
  monitor.registerAgent({ id: 'black', uid: 'black_uid' });
  server(monitor, 'red', 'red_uid', {
    type: 'game-start',
    roomId: 'ROOM02',
    redUid: 'red_uid',
    blackUid: 'black_uid',
    yourColor: 'red',
  });
  server(monitor, 'black', 'black_uid', {
    type: 'game-start',
    roomId: 'ROOM02',
    redUid: 'red_uid',
    blackUid: 'black_uid',
    yourColor: 'black',
  });
  server(monitor, 'red', 'red_uid', {
    type: 'move-ack',
    roomId: 'ROOM02',
    uci: 'a3a4',
    moveNumber: 1,
  });

  const violation = server(monitor, 'red', 'red_uid', {
    type: 'game-ended',
    roomId: 'ROOM02',
    result: 'black-win',
    reason: 'resign',
    moves: [],
  });
  assert.equal(violation?.rule, 'game-ended-move-mismatch');
});

test('monitor detects reconnect snapshot mismatch', () => {
  const monitor = new SimMonitor();
  monitor.registerAgent({ id: 'red', uid: 'red_uid' });
  monitor.registerAgent({ id: 'black', uid: 'black_uid' });
  server(monitor, 'red', 'red_uid', {
    type: 'game-start',
    roomId: 'ROOM03',
    redUid: 'red_uid',
    blackUid: 'black_uid',
    yourColor: 'red',
  });
  server(monitor, 'black', 'black_uid', {
    type: 'game-start',
    roomId: 'ROOM03',
    redUid: 'red_uid',
    blackUid: 'black_uid',
    yourColor: 'black',
  });
  server(monitor, 'red', 'red_uid', {
    type: 'move-ack',
    roomId: 'ROOM03',
    uci: 'a3a4',
    moveNumber: 1,
  });
  monitor.observeCommand({ type: 'drop', agentId: 'red', uid: 'red_uid', roomId: 'ROOM03' });
  monitor.observeCommand({
    type: 'reconnect-room',
    agentId: 'red',
    uid: 'red_uid',
    roomId: 'ROOM03',
  });

  const violation = server(monitor, 'red', 'red_uid', {
    type: 'reconnected',
    roomId: 'ROOM03',
    redUid: 'red_uid',
    blackUid: 'black_uid',
    yourColor: 'red',
    moves: [],
    currentTurn: 'black',
  });
  assert.equal(violation?.rule, 'reconnect-snapshot-mismatch');
});

test('monitor detects duplicate game-ended for one agent', () => {
  const monitor = new SimMonitor();
  monitor.registerAgent({ id: 'red', uid: 'red_uid' });
  server(monitor, 'red', 'red_uid', {
    type: 'game-start',
    roomId: 'ROOM04',
    redUid: 'red_uid',
    blackUid: 'black_uid',
    yourColor: 'red',
  });
  assert.equal(
    server(monitor, 'red', 'red_uid', {
      type: 'game-ended',
      roomId: 'ROOM04',
      result: 'black-win',
      reason: 'resign',
      moves: [],
    }),
    undefined,
  );

  const violation = server(monitor, 'red', 'red_uid', {
    type: 'game-ended',
    roomId: 'ROOM04',
    result: 'black-win',
    reason: 'resign',
    moves: [],
  });
  assert.equal(violation?.rule, 'game-ended-duplicate');
});

test('monitor detects command phase mistakes', () => {
  const monitor = new SimMonitor();
  monitor.registerAgent({ id: 'red', uid: 'red_uid' });

  const violation = monitor.observeCommand({
    type: 'move',
    agentId: 'red',
    uid: 'red_uid',
    roomId: 'ROOM05',
    data: { uci: 'a3a4' },
  });
  assert.equal(violation?.rule, 'protocol-phase');
});

