import assert from 'node:assert/strict';
import test from 'node:test';

import {
  evaluatePersistenceSnapshot,
  type GameRecordSnapshot,
  type SimGameFact,
  type UserStatsSnapshot,
} from './firebase_probe';

test('persistence probe accepts mirrored records and exact counter deltas', () => {
  const game = sampleGame();
  const before = new Map<string, UserStatsSnapshot>([
    ['red', user('red', 0, 0, 0, 0)],
    ['black', user('black', 0, 0, 0, 0)],
  ]);
  const after = new Map<string, UserStatsSnapshot>([
    ['red', user('red', 1, 0, 0, 1)],
    ['black', user('black', 0, 1, 0, 1)],
  ]);
  const records = new Map<string, GameRecordSnapshot>([
    ['red/ROOM01_1000', record('red', game, 'red')],
    ['black/ROOM01_1000', record('black', game, 'black')],
  ]);

  const summary = evaluatePersistenceSnapshot({ games: [game], before, after, records });

  assert.equal(summary.ok, true);
  assert.equal(summary.recordsChecked, 2);
  assert.deepEqual(summary.missingRecords, []);
  assert.deepEqual(summary.counterMismatches, []);
});

test('persistence probe reports missing records and double counters', () => {
  const game = sampleGame();
  const before = new Map<string, UserStatsSnapshot>([
    ['red', user('red', 0, 0, 0, 0)],
    ['black', user('black', 0, 0, 0, 0)],
  ]);
  const after = new Map<string, UserStatsSnapshot>([
    ['red', user('red', 2, 0, 0, 2)],
    ['black', user('black', 0, 1, 0, 1)],
  ]);
  const records = new Map<string, GameRecordSnapshot>([
    ['red/ROOM01_1000', record('red', game, 'red')],
  ]);

  const summary = evaluatePersistenceSnapshot({ games: [game], before, after, records });

  assert.equal(summary.ok, false);
  assert.deepEqual(summary.missingRecords, ['black/game_records/ROOM01_1000']);
  assert.ok(summary.counterMismatches.some((item) => item.includes('red.totalGames')));
  assert.ok(summary.counterMismatches.some((item) => item.includes('red.wins')));
});

function sampleGame(): SimGameFact {
  return {
    gameId: 'ROOM01_1000',
    roomId: 'ROOM01',
    redUid: 'red',
    blackUid: 'black',
    result: 'red-win',
    reason: 'resign',
    moveList: ['a3a4'],
    moveCount: 1,
    startedAt: 1000,
    endedAt: 2000,
  };
}

function user(
  uid: string,
  wins: number,
  losses: number,
  draws: number,
  totalGames: number,
): UserStatsSnapshot {
  return {
    uid,
    exists: true,
    eloChess: 1000,
    wins,
    losses,
    draws,
    totalGames,
  };
}

function record(uid: string, game: SimGameFact, color: 'red' | 'black'): GameRecordSnapshot {
  return {
    uid,
    gameId: game.gameId,
    exists: true,
    data: {
      gameId: game.gameId,
      roomId: game.roomId,
      redUid: game.redUid,
      blackUid: game.blackUid,
      humanColor: color,
      opponent: color === 'red' ? game.blackUid : game.redUid,
      result: color === 'red' ? 'win' : 'loss',
      moveCount: game.moveCount,
      moveList: game.moveList,
    },
  };
}
