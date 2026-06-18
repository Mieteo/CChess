// Step P-C2/P-C3 (test-automation Phase C): unit tests for the persistence
// orchestration that drives test-plan cases M5 (ELO 2 chiều), G4 (delta), and
// R11 (per-game ELO). The whole read-compute-write is exercised through a fake
// in-memory PersistStore — NO Firebase, so this runs in plain `npm test`.
//
// What this covers that elo.test.ts (pure math) does not:
//   - winner +điểm / loser −điểm / draw applied to the right user docs,
//   - wins/losses/draws/totalGames counters,
//   - mirror game_records for BOTH sides (opponent, humanColor, perspective),
//   - reading each player's CURRENT rating before computing,
//   - P-C3 idempotency: a double-persist never double-applies ELO/counters.

import assert from 'node:assert/strict';
import { test } from 'node:test';

import { DEFAULT_RATING } from './elo';
import {
  buildPersistPlan,
  persistGame,
  type GameRecordData,
  type PersistPlan,
  type PersistStore,
} from './persistence';
import type { GameResult, Room } from './rooms';

// ── Fake store: an in-memory stand-in for Firestore ───────────────────────────

interface StoredUser {
  eloChess: number;
  wins: number;
  losses: number;
  draws: number;
  totalGames: number;
}

class FakeStore implements PersistStore {
  readonly users = new Map<string, StoredUser>();
  readonly records = new Map<string, GameRecordData>(); // key `${uid}/${gameId}`
  commits = 0;

  seedElo(uid: string, eloChess: number): void {
    this.users.set(uid, { ...this.blankUser(), eloChess });
  }

  user(uid: string): StoredUser {
    return this.users.get(uid) ?? this.blankUser();
  }

  record(uid: string, gameId: string): GameRecordData | undefined {
    return this.records.get(`${uid}/${gameId}`);
  }

  async commit({
    redUid,
    blackUid,
    gameId,
    plan,
  }: Parameters<PersistStore['commit']>[0]) {
    this.commits++;
    // Idempotency mirrors the Firestore adapter: already recorded → no-op.
    if (this.records.has(`${redUid}/${gameId}`)) return null;

    const redElo = this.users.get(redUid)?.eloChess ?? DEFAULT_RATING;
    const blackElo = this.users.get(blackUid)?.eloChess ?? DEFAULT_RATING;
    const p = plan(redElo, blackElo);

    this.applyStats(p.red.uid, p.red.stats);
    this.applyStats(p.black.uid, p.black.stats);
    this.records.set(`${redUid}/${gameId}`, p.red.record);
    this.records.set(`${blackUid}/${gameId}`, p.black.record);
    return p.elo;
  }

  private applyStats(uid: string, s: PersistPlan['red']['stats']): void {
    const u = this.users.get(uid) ?? this.blankUser();
    u.eloChess = s.eloChess;
    u.wins += s.winsInc;
    u.losses += s.lossesInc;
    u.draws += s.drawsInc;
    u.totalGames += s.totalGamesInc;
    this.users.set(uid, u);
  }

  private blankUser(): StoredUser {
    return { eloChess: DEFAULT_RATING, wins: 0, losses: 0, draws: 0, totalGames: 0 };
  }
}

function finishedRoom(overrides: Partial<Room> = {}): Room {
  // Only the fields persistence reads are needed; cast past the socket-heavy
  // Room shape that the realtime server fills.
  return {
    id: 'ROOMAA',
    status: 'finished',
    moveCount: 2,
    redUid: 'red-uid',
    blackUid: 'black-uid',
    result: 'red-win',
    endReason: 'checkmate',
    movesUci: ['h2e2', 'h9g7'],
    startedAt: 1_000,
    endedAt: 6_000,
    clockMsByColor: { red: 120_000, black: 90_000 },
    ...overrides,
  } as unknown as Room;
}

// ── buildPersistPlan: pure decisions ─────────────────────────────────────────

test('M5: an equal-rated red win writes +16/−16 into both records', () => {
  const plan = buildPersistPlan(finishedRoom(), 1000, 1000, 'g1');

  assert.equal(plan.red.stats.eloChess, 1016);
  assert.equal(plan.black.stats.eloChess, 984);

  assert.equal(plan.red.record.eloBefore, 1000);
  assert.equal(plan.red.record.eloAfter, 1016);
  assert.equal(plan.red.record.eloChange, 16);
  assert.equal(plan.black.record.eloBefore, 1000);
  assert.equal(plan.black.record.eloAfter, 984);
  assert.equal(plan.black.record.eloChange, -16);
});

test('the two mirror records describe the SAME game from each side', () => {
  const plan = buildPersistPlan(finishedRoom(), 1000, 1000, 'g1');

  // Same gameId, opposite perspectives.
  assert.equal(plan.red.record.gameId, 'g1');
  assert.equal(plan.black.record.gameId, 'g1');

  assert.equal(plan.red.record.humanColor, 'red');
  assert.equal(plan.red.record.opponent, 'black-uid');
  assert.equal(plan.red.record.result, 'win');

  assert.equal(plan.black.record.humanColor, 'black');
  assert.equal(plan.black.record.opponent, 'red-uid');
  assert.equal(plan.black.record.result, 'loss');

  // Shared metadata survives onto both records.
  assert.equal(plan.red.record.roomId, 'ROOMAA');
  assert.equal(plan.red.record.moveCount, 2);
  assert.deepEqual(plan.red.record.moveList, ['h2e2', 'h9g7']);
  assert.equal(plan.red.record.durationMs, 5_000); // endedAt − startedAt
  assert.equal(plan.red.record.mode, 'ranked');
});

test('a draw marks result=draw for both sides and no win/loss', () => {
  const plan = buildPersistPlan(
    finishedRoom({ result: 'draw', endReason: 'stalemate' }),
    1000,
    1000,
    'g1',
  );
  assert.equal(plan.red.record.result, 'draw');
  assert.equal(plan.black.record.result, 'draw');
  assert.equal(plan.red.stats.drawsInc, 1);
  assert.equal(plan.red.stats.winsInc, 0);
  assert.equal(plan.red.stats.lossesInc, 0);
});

// ── persistGame + FakeStore: end-to-end counters ─────────────────────────────

async function persistResult(result: GameResult, store = new FakeStore()) {
  const out = await persistGame(finishedRoom({ result }), store);
  return { out, store };
}

test('M5/counters: red win → red.wins+1, black.losses+1, totalGames+1 each', async () => {
  const { out, store } = await persistResult('red-win');

  assert.ok(out, 'persistGame returned a result');
  assert.deepEqual(store.user('red-uid'), {
    eloChess: 1016,
    wins: 1,
    losses: 0,
    draws: 0,
    totalGames: 1,
  });
  assert.deepEqual(store.user('black-uid'), {
    eloChess: 984,
    wins: 0,
    losses: 1,
    draws: 0,
    totalGames: 1,
  });
  // The EloUpdate surfaced to the caller (→ game-ended.elo) is consistent.
  assert.equal(out!.elo!.redDelta, 16);
  assert.equal(out!.elo!.blackDelta, -16);
});

test('counters: black win flips wins/losses to the other side', async () => {
  const { store } = await persistResult('black-win');
  assert.equal(store.user('red-uid').losses, 1);
  assert.equal(store.user('red-uid').wins, 0);
  assert.equal(store.user('black-uid').wins, 1);
  assert.equal(store.user('black-uid').losses, 0);
});

test('counters: a draw bumps draws (not wins/losses) on both sides', async () => {
  const { store } = await persistResult('draw');
  assert.deepEqual(store.user('red-uid'), {
    eloChess: 1000, // equal ratings → draw moves nothing
    wins: 0,
    losses: 0,
    draws: 1,
    totalGames: 1,
  });
  assert.equal(store.user('black-uid').draws, 1);
});

test('persistGame computes from each player CURRENT rating, not the default', async () => {
  const store = new FakeStore();
  store.seedElo('red-uid', 1400);
  store.seedElo('black-uid', 1000);

  const out = await persistGame(finishedRoom({ result: 'red-win' }), store);

  // Favourite (1400) beating an underdog (1000) gains only a little.
  assert.ok(out!.elo!.redOld === 1400, 'read the seeded rating, not DEFAULT_RATING');
  assert.ok(out!.elo!.redDelta > 0 && out!.elo!.redDelta < 16, 'small gain for the favourite');
  assert.equal(out!.elo!.redDelta + out!.elo!.blackDelta, 0, 'rating is conserved');
  assert.equal(store.user('red-uid').eloChess, 1400 + out!.elo!.redDelta);
});

// ── P-C3: idempotency ─────────────────────────────────────────────────────────

test('P-C3: persisting the SAME finished game twice does not double-apply', async () => {
  const store = new FakeStore();
  const room = finishedRoom({ result: 'red-win', startedAt: 1_000 });

  const first = await persistGame(room, store);
  const second = await persistGame(room, store); // same gameId (room.id + startedAt)

  assert.ok(first!.elo, 'first persist applies ELO');
  assert.equal(second!.elo, null, 'second persist is an idempotent skip');
  assert.equal(store.commits, 2, 'commit was attempted both times');

  // Counters reflect ONE game, not two.
  assert.equal(store.user('red-uid').wins, 1);
  assert.equal(store.user('red-uid').totalGames, 1);
  assert.equal(store.user('red-uid').eloChess, 1016);
  assert.equal(store.user('black-uid').losses, 1);
  assert.equal(store.user('black-uid').totalGames, 1);
});

// ── persistGame guards ────────────────────────────────────────────────────────

test('persistGame skips a room that is not finished', async () => {
  const store = new FakeStore();
  const out = await persistGame(finishedRoom({ status: 'playing' }), store);
  assert.equal(out, null);
  assert.equal(store.commits, 0, 'never touches the store');
});

test('persistGame skips when a player uid or the result is missing', async () => {
  const store = new FakeStore();
  assert.equal(await persistGame(finishedRoom({ redUid: undefined }), store), null);
  assert.equal(await persistGame(finishedRoom({ result: undefined }), store), null);
  assert.equal(store.commits, 0);
});
