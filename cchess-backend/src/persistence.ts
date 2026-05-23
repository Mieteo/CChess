// Step 7 + ELO update (Step A2).
//
// On game finish:
//   1. Compute Elo delta from both players' current ratings + result
//   2. In a single Firestore transaction:
//      - Update users/{redUid}.eloChess + win/loss/draw counters
//      - Update users/{blackUid}.eloChess + win/loss/draw counters
//      - Write mirror game_records doc for each side (with eloChange recorded)
//   Admin SDK bypasses security rules, so server-only sensitive fields
//   (eloChess, wins, losses, draws, totalGames) are writable here.

import {
  getFirestore,
  FieldValue,
  Timestamp,
  type DocumentReference,
  type Transaction,
} from 'firebase-admin/firestore';
import { computeElo, DEFAULT_RATING, type EloUpdate } from './elo';
import type { Room } from './rooms';

export interface PersistResult {
  gameId: string;
  elo: EloUpdate | null;
}

export async function persistGame(room: Room): Promise<PersistResult | null> {
  if (room.status !== 'finished') {
    console.warn(`[persist] skip ${room.id}: status=${room.status}`);
    return null;
  }
  if (!room.redUid || !room.blackUid || !room.result) {
    console.warn(`[persist] skip ${room.id}: missing red/black/result`);
    return null;
  }

  const db = getFirestore();
  const gameId = `${room.id}_${room.startedAt ?? Date.now()}`;
  const redRef = db.collection('users').doc(room.redUid);
  const blackRef = db.collection('users').doc(room.blackUid);
  const redGameRef = redRef.collection('game_records').doc(gameId);
  const blackGameRef = blackRef.collection('game_records').doc(gameId);

  try {
    const elo = await db.runTransaction<EloUpdate>(async (tx) => {
      const redSnap = await tx.get(redRef);
      const blackSnap = await tx.get(blackRef);
      const redCurrentElo =
        (redSnap.data()?.eloChess as number | undefined) ?? DEFAULT_RATING;
      const blackCurrentElo =
        (blackSnap.data()?.eloChess as number | undefined) ?? DEFAULT_RATING;

      const eloUpdate = computeElo(redCurrentElo, blackCurrentElo, room.result!);

      // ── Update user ratings + counters ──
      writePlayerUpdate(tx, redRef, room.result!, 'red', eloUpdate.redNew);
      writePlayerUpdate(tx, blackRef, room.result!, 'black', eloUpdate.blackNew);

      // ── Write mirror game records ──
      const baseDoc = buildBaseRecord(room, gameId, eloUpdate);
      tx.set(redGameRef, {
        ...baseDoc,
        opponent: room.blackUid,
        humanColor: 'red',
        result: perspective(room.result!, 'red'),
        eloChange: eloUpdate.redDelta,
        eloBefore: eloUpdate.redOld,
        eloAfter: eloUpdate.redNew,
      });
      tx.set(blackGameRef, {
        ...baseDoc,
        opponent: room.redUid,
        humanColor: 'black',
        result: perspective(room.result!, 'black'),
        eloChange: eloUpdate.blackDelta,
        eloBefore: eloUpdate.blackOld,
        eloAfter: eloUpdate.blackNew,
      });

      return eloUpdate;
    });

    console.log(
      `[persist] ${room.id} → game_records/${gameId} | ELO: red ${elo.redOld}→${elo.redNew} (${signed(elo.redDelta)}) black ${elo.blackOld}→${elo.blackNew} (${signed(elo.blackDelta)})`,
    );
    return { gameId, elo };
  } catch (e) {
    console.error(`[persist] ${room.id} failed:`, e);
    return null;
  }
}

function writePlayerUpdate(
  tx: Transaction,
  userRef: DocumentReference,
  result: 'red-win' | 'black-win' | 'draw',
  color: 'red' | 'black',
  newElo: number,
): void {
  const update: Record<string, unknown> = {
    eloChess: newElo,
    totalGames: FieldValue.increment(1),
    lastActiveAt: FieldValue.serverTimestamp(),
  };
  if (result === 'draw') {
    update.draws = FieldValue.increment(1);
  } else {
    const won =
      (result === 'red-win' && color === 'red') ||
      (result === 'black-win' && color === 'black');
    if (won) update.wins = FieldValue.increment(1);
    else update.losses = FieldValue.increment(1);
  }
  tx.set(userRef, update, { merge: true });
}

function buildBaseRecord(
  room: Room,
  gameId: string,
  _elo: EloUpdate,
): Record<string, unknown> {
  return {
    gameId,
    roomId: room.id,
    mode: 'ranked',
    redUid: room.redUid,
    blackUid: room.blackUid,
    moveList: room.movesUci ?? [],
    moveCount: room.moveCount,
    endReason: room.endReason ?? null,
    duration:
      room.endedAt && room.startedAt ? room.endedAt - room.startedAt : 0,
    startingPosition: 'standard',
    startedAt: room.startedAt ? Timestamp.fromMillis(room.startedAt) : null,
    endedAt: room.endedAt
      ? Timestamp.fromMillis(room.endedAt)
      : FieldValue.serverTimestamp(),
    clockRemainingMs: {
      red: room.clockMsByColor?.red ?? 0,
      black: room.clockMsByColor?.black ?? 0,
    },
    isFavorite: false,
  };
}

function perspective(
  result: 'red-win' | 'black-win' | 'draw',
  color: 'red' | 'black',
): 'win' | 'loss' | 'draw' {
  if (result === 'draw') return 'draw';
  return (result === 'red-win' && color === 'red') ||
    (result === 'black-win' && color === 'black')
    ? 'win'
    : 'loss';
}

function signed(n: number): string {
  return n >= 0 ? `+${n}` : `${n}`;
}
