// Step 7 + ELO update (Step A2), refactored for test-automation Phase P-C2/P-C3.
//
// On game finish:
//   1. Read both players' CURRENT eloChess.
//   2. Compute Elo delta from those ratings + result.
//   3. In a single atomic unit:
//      - Update users/{redUid}.eloChess + win/loss/draw counters
//      - Update users/{blackUid}.eloChess + win/loss/draw counters
//      - Write mirror game_records doc for each side (with eloChange recorded)
//   Admin SDK bypasses security rules, so server-only sensitive fields
//   (eloChess, wins, losses, draws, totalGames) are writable here.
//
// Design (P-C2): the read-compute-write is split so it can be unit-tested
// WITHOUT Firebase:
//   - `buildPersistPlan` is a PURE function (current ratings → all writes).
//   - `PersistStore.commit` is the atomic boundary; the Firestore impl wraps a
//     transaction, but tests inject a fake in-memory store (see persistence.test.ts).
// Idempotency (P-C3): `commit` is a no-op if this gameId was already recorded,
// so a stray double-persist can never double-apply ELO/counters.

import {
  getFirestore,
  FieldValue,
  Timestamp,
  type DocumentReference,
  type Transaction,
} from 'firebase-admin/firestore';
import { computeElo, DEFAULT_RATING, type EloUpdate } from './elo';
import type { Color, EndReason, GameVariant, Room } from './rooms';

/// The Firestore user field that holds a variant's rating. Cờ Úp keeps a
/// separate pool (eloCup) from standard Xiangqi (eloChess).
export type RatingField = 'eloChess' | 'eloCup';

export function ratingFieldFor(variant: GameVariant): RatingField {
  return variant === 'cup' ? 'eloCup' : 'eloChess';
}

export interface PersistResult {
  gameId: string;
  elo: EloUpdate | null;
}

/// Counter/rating change to apply to one user doc. Increments are plain numbers
/// (0 or 1) here; the Firestore adapter translates them to FieldValue.increment.
export interface PlayerStatsDelta {
  rating: number; // absolute new rating (written to the variant's rating field)
  winsInc: number;
  lossesInc: number;
  drawsInc: number;
  totalGamesInc: number;
}

/// One side's game_records document, as plain data (no Firestore sentinels) so
/// it can be asserted directly in unit tests. The adapter converts *AtMs fields
/// to Timestamps on write.
export interface GameRecordData {
  gameId: string;
  roomId: string;
  mode: 'ranked';
  variant: GameVariant;
  redUid: string;
  blackUid: string;
  opponent: string;
  humanColor: Color;
  result: 'win' | 'loss' | 'draw';
  eloChange: number;
  eloBefore: number;
  eloAfter: number;
  moveList: string[];
  moveCount: number;
  endReason: EndReason | null;
  durationMs: number;
  startingPosition: 'standard' | 'cup';
  startedAtMs: number | null;
  endedAtMs: number | null;
  clockRemainingMs: { red: number; black: number };
  isFavorite: boolean;
}

/// The full set of writes a finished game produces, derived purely from the two
/// players' current ratings. `elo` is what the caller broadcasts as deltas.
export interface PersistPlan {
  gameId: string;
  elo: EloUpdate;
  red: { uid: string; stats: PlayerStatsDelta; record: GameRecordData };
  black: { uid: string; stats: PlayerStatsDelta; record: GameRecordData };
}

/// Atomic persistence backend. Default is Firestore; tests inject a fake.
export interface PersistStore {
  /// Read both players' current eloChess, hand them to `plan`, then apply the
  /// returned writes as ONE atomic unit. Returns the applied EloUpdate, or
  /// `null` if `gameId` was already recorded (idempotent skip).
  commit(args: {
    redUid: string;
    blackUid: string;
    gameId: string;
    /// Which rating field to read (current ratings) and write (new ratings).
    ratingField: RatingField;
    plan: (redElo: number, blackElo: number) => PersistPlan;
  }): Promise<EloUpdate | null>;
}

export async function persistGame(
  room: Room,
  store: PersistStore = firestoreStore(),
): Promise<PersistResult | null> {
  if (room.status !== 'finished') {
    console.warn(`[persist] skip ${room.id}: status=${room.status}`);
    return null;
  }
  if (!room.redUid || !room.blackUid || !room.result) {
    console.warn(`[persist] skip ${room.id}: missing red/black/result`);
    return null;
  }

  const gameId = `${room.id}_${room.startedAt ?? Date.now()}`;
  const ratingField = ratingFieldFor(room.variant);

  try {
    const elo = await store.commit({
      redUid: room.redUid,
      blackUid: room.blackUid,
      gameId,
      ratingField,
      plan: (redElo, blackElo) => buildPersistPlan(room, redElo, blackElo, gameId),
    });

    if (!elo) {
      // Idempotent skip: the game was already recorded (P-C3). The first
      // persist already broadcast the deltas; nothing more to do.
      console.log(`[persist] ${room.id} already recorded as ${gameId} — skipped`);
      return { gameId, elo: null };
    }

    console.log(
      `[persist] ${room.id} → game_records/${gameId} | ELO: red ${elo.redOld}→${elo.redNew} (${signed(elo.redDelta)}) black ${elo.blackOld}→${elo.blackNew} (${signed(elo.blackDelta)})`,
    );
    return { gameId, elo };
  } catch (e) {
    console.error(`[persist] ${room.id} failed:`, e);
    return null;
  }
}

/// PURE: given a finished room + both players' CURRENT ratings, produce every
/// write the game finish entails. No I/O — unit-tested directly and via a fake
/// store (see persistence.test.ts). Assumes redUid/blackUid/result are set
/// (persistGame guards this before calling).
export function buildPersistPlan(
  room: Room,
  redElo: number,
  blackElo: number,
  gameId: string,
): PersistPlan {
  const redUid = room.redUid!;
  const blackUid = room.blackUid!;
  const result = room.result!;
  const elo = computeElo(redElo, blackElo, result);

  const base = buildBaseRecord(room, gameId);
  const redRecord: GameRecordData = {
    ...base,
    opponent: blackUid,
    humanColor: 'red',
    result: perspective(result, 'red'),
    eloChange: elo.redDelta,
    eloBefore: elo.redOld,
    eloAfter: elo.redNew,
  };
  const blackRecord: GameRecordData = {
    ...base,
    opponent: redUid,
    humanColor: 'black',
    result: perspective(result, 'black'),
    eloChange: elo.blackDelta,
    eloBefore: elo.blackOld,
    eloAfter: elo.blackNew,
  };

  return {
    gameId,
    elo,
    red: { uid: redUid, stats: statsDeltaFor(result, 'red', elo.redNew), record: redRecord },
    black: {
      uid: blackUid,
      stats: statsDeltaFor(result, 'black', elo.blackNew),
      record: blackRecord,
    },
  };
}

function statsDeltaFor(
  result: 'red-win' | 'black-win' | 'draw',
  color: Color,
  newElo: number,
): PlayerStatsDelta {
  const isDraw = result === 'draw';
  const won =
    (result === 'red-win' && color === 'red') ||
    (result === 'black-win' && color === 'black');
  return {
    rating: newElo,
    winsInc: !isDraw && won ? 1 : 0,
    lossesInc: !isDraw && !won ? 1 : 0,
    drawsInc: isDraw ? 1 : 0,
    totalGamesInc: 1,
  };
}

function buildBaseRecord(
  room: Room,
  gameId: string,
): Omit<
  GameRecordData,
  'opponent' | 'humanColor' | 'result' | 'eloChange' | 'eloBefore' | 'eloAfter'
> {
  return {
    gameId,
    roomId: room.id,
    mode: 'ranked',
    variant: room.variant,
    redUid: room.redUid!,
    blackUid: room.blackUid!,
    moveList: room.movesUci ?? [],
    moveCount: room.moveCount,
    endReason: room.endReason ?? null,
    durationMs:
      room.endedAt && room.startedAt ? room.endedAt - room.startedAt : 0,
    startingPosition: room.variant === 'cup' ? 'cup' : 'standard',
    startedAtMs: room.startedAt ?? null,
    endedAtMs: room.endedAt ?? null,
    clockRemainingMs: {
      red: room.clockMsByColor?.red ?? 0,
      black: room.clockMsByColor?.black ?? 0,
    },
    isFavorite: false,
  };
}

function perspective(
  result: 'red-win' | 'black-win' | 'draw',
  color: Color,
): 'win' | 'loss' | 'draw' {
  if (result === 'draw') return 'draw';
  return (result === 'red-win' && color === 'red') ||
    (result === 'black-win' && color === 'black')
    ? 'win'
    : 'loss';
}

// ── Firestore adapter ──────────────────────────────────────────────────────

function firestoreStore(): PersistStore {
  return {
    async commit({ redUid, blackUid, gameId, ratingField, plan }) {
      const db = getFirestore();
      const redRef = db.collection('users').doc(redUid);
      const blackRef = db.collection('users').doc(blackUid);
      const redGameRef = redRef.collection('game_records').doc(gameId);
      const blackGameRef = blackRef.collection('game_records').doc(gameId);

      return db.runTransaction<EloUpdate | null>(async (tx) => {
        // All reads MUST precede writes in a Firestore transaction.
        // Idempotency (P-C3): if this game was already recorded, bail.
        const existing = await tx.get(redGameRef);
        if (existing.exists) return null;
        const redSnap = await tx.get(redRef);
        const blackSnap = await tx.get(blackRef);
        const redElo =
          (redSnap.data()?.[ratingField] as number | undefined) ?? DEFAULT_RATING;
        const blackElo =
          (blackSnap.data()?.[ratingField] as number | undefined) ?? DEFAULT_RATING;

        const p = plan(redElo, blackElo);
        applyStats(tx, redRef, p.red.stats, ratingField);
        applyStats(tx, blackRef, p.black.stats, ratingField);
        tx.set(redGameRef, toFirestoreRecord(p.red.record));
        tx.set(blackGameRef, toFirestoreRecord(p.black.record));
        return p.elo;
      });
    },
  };
}

function applyStats(
  tx: Transaction,
  userRef: DocumentReference,
  s: PlayerStatsDelta,
  ratingField: RatingField,
): void {
  const update: Record<string, unknown> = {
    [ratingField]: s.rating,
    totalGames: FieldValue.increment(s.totalGamesInc),
    lastActiveAt: FieldValue.serverTimestamp(),
  };
  if (s.winsInc) update.wins = FieldValue.increment(s.winsInc);
  if (s.lossesInc) update.losses = FieldValue.increment(s.lossesInc);
  if (s.drawsInc) update.draws = FieldValue.increment(s.drawsInc);
  tx.set(userRef, update, { merge: true });
}

function toFirestoreRecord(r: GameRecordData): Record<string, unknown> {
  return {
    gameId: r.gameId,
    roomId: r.roomId,
    mode: r.mode,
    variant: r.variant,
    redUid: r.redUid,
    blackUid: r.blackUid,
    opponent: r.opponent,
    humanColor: r.humanColor,
    result: r.result,
    eloChange: r.eloChange,
    eloBefore: r.eloBefore,
    eloAfter: r.eloAfter,
    moveList: r.moveList,
    moveCount: r.moveCount,
    endReason: r.endReason,
    duration: r.durationMs,
    startingPosition: r.startingPosition,
    startedAt:
      r.startedAtMs !== null ? Timestamp.fromMillis(r.startedAtMs) : null,
    endedAt:
      r.endedAtMs !== null
        ? Timestamp.fromMillis(r.endedAtMs)
        : FieldValue.serverTimestamp(),
    clockRemainingMs: r.clockRemainingMs,
    isFavorite: r.isFavorite,
  };
}

function signed(n: number): string {
  return n >= 0 ? `+${n}` : `${n}`;
}
