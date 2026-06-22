import { getAuth } from 'firebase-admin/auth';
import { getFirestore, type DocumentData } from 'firebase-admin/firestore';
import { initFirebaseAdmin } from '../../src/auth';

export type SimGameResult = 'red-win' | 'black-win' | 'draw';

export interface SimGameFact {
  gameId: string;
  roomId: string;
  redUid: string;
  blackUid: string;
  result: SimGameResult;
  reason: string;
  moveList: string[];
  moveCount: number;
  startedAt: number | null;
  endedAt: number | null;
}

export interface UserStatsSnapshot {
  uid: string;
  exists: boolean;
  eloChess: number | null;
  wins: number;
  losses: number;
  draws: number;
  totalGames: number;
}

export interface GameRecordSnapshot {
  uid: string;
  gameId: string;
  exists: boolean;
  data?: Record<string, unknown>;
}

export interface PersistenceVerificationSummary {
  enabled: boolean;
  ok: boolean;
  usersChecked: number;
  expectedGames: number;
  recordsChecked: number;
  missingRecords: string[];
  recordMismatches: string[];
  counterMismatches: string[];
  error?: string;
}

export interface FirebaseCleanupSummary {
  enabled: boolean;
  dryRun: boolean;
  recordsDeleted: number;
  userDocsDeleted: number;
  authUsersDeleted: number;
  errors: string[];
}

interface CounterExpectation {
  wins: number;
  losses: number;
  draws: number;
  totalGames: number;
}

export const DISABLED_PERSISTENCE_SUMMARY: PersistenceVerificationSummary = {
  enabled: false,
  ok: true,
  usersChecked: 0,
  expectedGames: 0,
  recordsChecked: 0,
  missingRecords: [],
  recordMismatches: [],
  counterMismatches: [],
};

export const DISABLED_CLEANUP_SUMMARY: FirebaseCleanupSummary = {
  enabled: false,
  dryRun: false,
  recordsDeleted: 0,
  userDocsDeleted: 0,
  authUsersDeleted: 0,
  errors: [],
};

export async function readUserStats(
  uids: readonly string[],
): Promise<Map<string, UserStatsSnapshot>> {
  initFirebaseAdmin();
  const db = getFirestore();
  const out = new Map<string, UserStatsSnapshot>();
  await Promise.all([...new Set(uids)].map(async (uid) => {
    const snap = await db.collection('users').doc(uid).get();
    out.set(uid, userStatsFromData(uid, snap.exists, snap.data()));
  }));
  return out;
}

export async function readGameRecords(
  games: readonly SimGameFact[],
): Promise<Map<string, GameRecordSnapshot>> {
  initFirebaseAdmin();
  const db = getFirestore();
  const keys = new Map<string, { uid: string; gameId: string }>();
  for (const game of games) {
    keys.set(recordKey(game.redUid, game.gameId), { uid: game.redUid, gameId: game.gameId });
    keys.set(recordKey(game.blackUid, game.gameId), { uid: game.blackUid, gameId: game.gameId });
  }
  const out = new Map<string, GameRecordSnapshot>();
  await Promise.all([...keys.values()].map(async ({ uid, gameId }) => {
    const snap = await db.collection('users').doc(uid).collection('game_records').doc(gameId).get();
    out.set(recordKey(uid, gameId), {
      uid,
      gameId,
      exists: snap.exists,
      data: snap.data(),
    });
  }));
  return out;
}

export function evaluatePersistenceSnapshot(args: {
  games: readonly SimGameFact[];
  before: ReadonlyMap<string, UserStatsSnapshot>;
  after: ReadonlyMap<string, UserStatsSnapshot>;
  records: ReadonlyMap<string, GameRecordSnapshot>;
}): PersistenceVerificationSummary {
  const missingRecords: string[] = [];
  const recordMismatches: string[] = [];
  const counterMismatches: string[] = [];
  const expectedCounters = expectedCountersByUid(args.games);

  for (const game of args.games) {
    verifyRecord(game, game.redUid, 'red', args.records, missingRecords, recordMismatches);
    verifyRecord(game, game.blackUid, 'black', args.records, missingRecords, recordMismatches);
  }

  for (const [uid, expected] of expectedCounters) {
    const before = args.before.get(uid) ?? emptyUserStats(uid);
    const after = args.after.get(uid) ?? emptyUserStats(uid);
    checkCounter(uid, 'totalGames', before.totalGames, after.totalGames, expected.totalGames, counterMismatches);
    checkCounter(uid, 'wins', before.wins, after.wins, expected.wins, counterMismatches);
    checkCounter(uid, 'losses', before.losses, after.losses, expected.losses, counterMismatches);
    checkCounter(uid, 'draws', before.draws, after.draws, expected.draws, counterMismatches);
    if (expected.totalGames > 0 && typeof after.eloChess !== 'number') {
      counterMismatches.push(`${uid}.eloChess is missing after ${expected.totalGames} games`);
    }
  }

  return {
    enabled: true,
    ok: missingRecords.length === 0 && recordMismatches.length === 0 && counterMismatches.length === 0,
    usersChecked: expectedCounters.size,
    expectedGames: args.games.length,
    recordsChecked: args.games.length * 2,
    missingRecords,
    recordMismatches,
    counterMismatches,
  };
}

export async function verifyPersistenceWithFirestore(args: {
  games: readonly SimGameFact[];
  before: ReadonlyMap<string, UserStatsSnapshot>;
  uids: readonly string[];
}): Promise<PersistenceVerificationSummary> {
  try {
    const [after, records] = await Promise.all([
      readUserStats(args.uids),
      readGameRecords(args.games),
    ]);
    return evaluatePersistenceSnapshot({
      games: args.games,
      before: args.before,
      after,
      records,
    });
  } catch (error) {
    return {
      ...DISABLED_PERSISTENCE_SUMMARY,
      enabled: true,
      ok: false,
      expectedGames: args.games.length,
      error: error instanceof Error ? error.message : String(error),
    };
  }
}

export async function cleanupFirebaseRun(args: {
  games: readonly SimGameFact[];
  uids: readonly string[];
  deleteUserDocs: boolean;
  deleteAuthUsers: boolean;
  dryRun: boolean;
}): Promise<FirebaseCleanupSummary> {
  initFirebaseAdmin();
  const db = getFirestore();
  const uniqueUids = [...new Set(args.uids)];
  const errors: string[] = [];
  let recordsDeleted = 0;
  let userDocsDeleted = 0;
  let authUsersDeleted = 0;

  for (const game of args.games) {
    for (const uid of [game.redUid, game.blackUid]) {
      try {
        if (!args.dryRun) {
          await db.collection('users').doc(uid).collection('game_records').doc(game.gameId).delete();
        }
        recordsDeleted++;
      } catch (error) {
        errors.push(`delete record ${uid}/${game.gameId}: ${messageOf(error)}`);
      }
    }
  }

  if (args.deleteUserDocs) {
    for (const uid of uniqueUids) {
      try {
        if (!args.dryRun) await db.collection('users').doc(uid).delete();
        userDocsDeleted++;
      } catch (error) {
        errors.push(`delete user doc ${uid}: ${messageOf(error)}`);
      }
    }
  }

  if (args.deleteAuthUsers) {
    try {
      if (!args.dryRun && uniqueUids.length > 0) {
        const result = await getAuth().deleteUsers(uniqueUids);
        authUsersDeleted = result.successCount;
        for (const err of result.errors) {
          errors.push(`delete auth user ${uniqueUids[err.index]}: ${err.error.message}`);
        }
      } else {
        authUsersDeleted = uniqueUids.length;
      }
    } catch (error) {
      errors.push(`delete auth users: ${messageOf(error)}`);
    }
  }

  return {
    enabled: true,
    dryRun: args.dryRun,
    recordsDeleted,
    userDocsDeleted,
    authUsersDeleted,
    errors,
  };
}

function verifyRecord(
  game: SimGameFact,
  uid: string,
  color: 'red' | 'black',
  records: ReadonlyMap<string, GameRecordSnapshot>,
  missingRecords: string[],
  recordMismatches: string[],
): void {
  const snapshot = records.get(recordKey(uid, game.gameId));
  if (!snapshot || !snapshot.exists || !snapshot.data) {
    missingRecords.push(`${uid}/game_records/${game.gameId}`);
    return;
  }
  const data = snapshot.data;
  expectField(data, 'gameId', game.gameId, uid, game.gameId, recordMismatches);
  expectField(data, 'roomId', game.roomId, uid, game.gameId, recordMismatches);
  expectField(data, 'redUid', game.redUid, uid, game.gameId, recordMismatches);
  expectField(data, 'blackUid', game.blackUid, uid, game.gameId, recordMismatches);
  expectField(data, 'humanColor', color, uid, game.gameId, recordMismatches);
  expectField(data, 'opponent', color === 'red' ? game.blackUid : game.redUid, uid, game.gameId, recordMismatches);
  expectField(data, 'result', perspective(game.result, color), uid, game.gameId, recordMismatches);
  expectField(data, 'moveCount', game.moveCount, uid, game.gameId, recordMismatches);
  const moveList = Array.isArray(data.moveList) ? data.moveList.filter((item): item is string => typeof item === 'string') : [];
  if (!sameMoves(moveList, game.moveList)) {
    recordMismatches.push(`${uid}/${game.gameId}.moveList mismatch`);
  }
}

function expectField(
  data: Record<string, unknown>,
  field: string,
  expected: unknown,
  uid: string,
  gameId: string,
  mismatches: string[],
): void {
  if (data[field] !== expected) {
    mismatches.push(`${uid}/${gameId}.${field}: expected ${String(expected)}, got ${String(data[field])}`);
  }
}

function expectedCountersByUid(games: readonly SimGameFact[]): Map<string, CounterExpectation> {
  const out = new Map<string, CounterExpectation>();
  for (const game of games) {
    addCounter(out, game.redUid, game.result === 'red-win' ? 'win' : game.result === 'black-win' ? 'loss' : 'draw');
    addCounter(out, game.blackUid, game.result === 'black-win' ? 'win' : game.result === 'red-win' ? 'loss' : 'draw');
  }
  return out;
}

function addCounter(
  counters: Map<string, CounterExpectation>,
  uid: string,
  result: 'win' | 'loss' | 'draw',
): void {
  const current = counters.get(uid) ?? { wins: 0, losses: 0, draws: 0, totalGames: 0 };
  current.totalGames++;
  if (result === 'win') current.wins++;
  else if (result === 'loss') current.losses++;
  else current.draws++;
  counters.set(uid, current);
}

function checkCounter(
  uid: string,
  field: keyof CounterExpectation,
  before: number,
  after: number,
  expectedDelta: number,
  mismatches: string[],
): void {
  const actualDelta = after - before;
  if (actualDelta !== expectedDelta) {
    mismatches.push(`${uid}.${field}: expected delta ${expectedDelta}, got ${actualDelta}`);
  }
}

function userStatsFromData(
  uid: string,
  exists: boolean,
  data: DocumentData | undefined,
): UserStatsSnapshot {
  return {
    uid,
    exists,
    eloChess: typeof data?.eloChess === 'number' ? data.eloChess : null,
    wins: intField(data, 'wins'),
    losses: intField(data, 'losses'),
    draws: intField(data, 'draws'),
    totalGames: intField(data, 'totalGames'),
  };
}

function emptyUserStats(uid: string): UserStatsSnapshot {
  return {
    uid,
    exists: false,
    eloChess: null,
    wins: 0,
    losses: 0,
    draws: 0,
    totalGames: 0,
  };
}

function intField(data: DocumentData | undefined, field: string): number {
  const value = data?.[field];
  return typeof value === 'number' && Number.isFinite(value) ? Math.trunc(value) : 0;
}

function perspective(result: SimGameResult, color: 'red' | 'black'): 'win' | 'loss' | 'draw' {
  if (result === 'draw') return 'draw';
  return (result === 'red-win' && color === 'red') || (result === 'black-win' && color === 'black')
    ? 'win'
    : 'loss';
}

function sameMoves(a: readonly string[], b: readonly string[]): boolean {
  return a.length === b.length && a.every((move, index) => move === b[index]);
}

function recordKey(uid: string, gameId: string): string {
  return `${uid}/${gameId}`;
}

function messageOf(error: unknown): string {
  return error instanceof Error ? error.message : String(error);
}
