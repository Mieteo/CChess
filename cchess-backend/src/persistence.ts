// Step 7: write game results to Firestore when a match ends.
//
// Writes 2 records (one per player) under `users/{uid}/game_records/{gameId}`
// using shared gameId so they can be linked. Admin SDK bypasses rules.

import { getFirestore, FieldValue, Timestamp } from 'firebase-admin/firestore';
import type { Room } from './rooms';

export async function persistGame(room: Room): Promise<void> {
  if (room.status !== 'finished') {
    console.warn(`[persist] skip ${room.id}: status=${room.status}`);
    return;
  }
  if (!room.redUid || !room.blackUid || !room.result) {
    console.warn(`[persist] skip ${room.id}: missing red/black/result`);
    return;
  }

  const db = getFirestore();
  const gameId = `${room.id}_${room.startedAt ?? Date.now()}`;
  const baseDoc = {
    gameId,
    roomId: room.id,
    mode: 'ranked', // server-authoritative match
    redUid: room.redUid,
    blackUid: room.blackUid,
    moveList: room.movesUci ?? [],
    moveCount: room.moveCount,
    result: room.result, // 'red-win' | 'black-win' | 'draw'
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

  // Per-player record uses their own "opponent" + "result" perspective.
  const redResult: 'win' | 'loss' | 'draw' =
    room.result === 'red-win'
      ? 'win'
      : room.result === 'black-win'
      ? 'loss'
      : 'draw';
  const blackResult: 'win' | 'loss' | 'draw' =
    room.result === 'black-win'
      ? 'win'
      : room.result === 'red-win'
      ? 'loss'
      : 'draw';

  const redDoc = {
    ...baseDoc,
    opponent: room.blackUid,
    humanColor: 'red',
    result: redResult,
  };
  const blackDoc = {
    ...baseDoc,
    opponent: room.redUid,
    humanColor: 'black',
    result: blackResult,
  };

  try {
    await Promise.all([
      db
        .collection('users')
        .doc(room.redUid)
        .collection('game_records')
        .doc(gameId)
        .set(redDoc),
      db
        .collection('users')
        .doc(room.blackUid)
        .collection('game_records')
        .doc(gameId)
        .set(blackDoc),
    ]);
    console.log(`[persist] ${room.id} → users/{${room.redUid}, ${room.blackUid}}/game_records/${gameId}`);
  } catch (e) {
    console.error(`[persist] ${room.id} failed:`, e);
  }
}
