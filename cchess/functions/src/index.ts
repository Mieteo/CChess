import { onCall, CallableRequest, HttpsError } from 'firebase-functions/v2/https';
import { setGlobalOptions } from 'firebase-functions/v2';
import { auth } from 'firebase-functions/v1';
import { initializeApp } from 'firebase-admin/app';
import { getFirestore, FieldValue } from 'firebase-admin/firestore';
import { logger } from 'firebase-functions';

initializeApp();
const db = getFirestore();

setGlobalOptions({ region: 'asia-southeast1' });

export const createFirestoreUser = auth.user().onCreate(async (user) => {
  const { uid, displayName, photoURL } = user;
  logger.info(`Tạo document users/${uid}`);

  const newUserDocument = {
    displayName: displayName ?? 'Người chơi ẩn danh',
    region: null,
    avatarUrl: photoURL ?? null,
    eloChess: 1000,
    eloCup: 1000,
    totalGames: 0,
    wins: 0,
    losses: 0,
    draws: 0,
    coins: 100,
    gems: 10,
    creditScore: 100,
    isVip: false,
    vipExpiresAt: null,
    createdAt: FieldValue.serverTimestamp(),
    lastActiveAt: FieldValue.serverTimestamp(),
    onboardingCompleted: false,
  };

  try {
    await db.collection('users').doc(uid).set(newUserDocument);
    logger.info(`Đã tạo users/${uid}`);
  } catch (error) {
    logger.error(`Lỗi tạo users/${uid}:`, error);
    throw error;
  }
});

interface RecordRankedGameData {
  opponentUid: string;
  result: 'win' | 'loss' | 'draw';
  moveList: string[];
  duration: number;
  startingPosition: string;
}

export const recordRankedGame = onCall<RecordRankedGameData>(async (request: CallableRequest<RecordRankedGameData>) => {
  if (!request.auth) {
    throw new HttpsError('unauthenticated', 'Cần đăng nhập để gọi function này.');
  }

  const playerUid = request.auth.uid;
  const { opponentUid, result, moveList, duration, startingPosition } = request.data;

  if (!opponentUid || !result || !moveList || duration === undefined || !startingPosition) {
    throw new HttpsError('invalid-argument', 'Thiếu trường bắt buộc.');
  }
  if (!['win', 'loss', 'draw'].includes(result)) {
    throw new HttpsError('invalid-argument', 'result phải là win/loss/draw.');
  }
  if (playerUid === opponentUid) {
    throw new HttpsError('invalid-argument', 'Không thể đấu với chính mình.');
  }

  logger.info(`Ranked: ${playerUid} vs ${opponentUid}, result=${result}`);

  const playerRef = db.collection('users').doc(playerUid);
  const opponentRef = db.collection('users').doc(opponentUid);

  return db.runTransaction(async (transaction) => {
    const playerDoc = await transaction.get(playerRef);
    const opponentDoc = await transaction.get(opponentRef);

    if (!playerDoc.exists) {
      throw new HttpsError('not-found', `Không tìm thấy users/${playerUid}.`);
    }
    if (!opponentDoc.exists) {
      throw new HttpsError('not-found', `Không tìm thấy users/${opponentUid}.`);
    }

    const playerData = playerDoc.data()!;
    const opponentData = opponentDoc.data()!;

    // TODO: tính ELO thật. Hiện tại để delta = 0, chỉ cập nhật win/loss/draw.
    const playerEloDelta = 0;
    const opponentEloDelta = 0;

    const playerUpdate: Record<string, unknown> = {
      eloChess: (playerData.eloChess as number) + playerEloDelta,
      totalGames: (playerData.totalGames as number) + 1,
      lastActiveAt: FieldValue.serverTimestamp(),
    };
    const opponentUpdate: Record<string, unknown> = {
      eloChess: (opponentData.eloChess as number) + opponentEloDelta,
      totalGames: (opponentData.totalGames as number) + 1,
      lastActiveAt: FieldValue.serverTimestamp(),
    };

    if (result === 'win') {
      playerUpdate.wins = (playerData.wins as number) + 1;
      opponentUpdate.losses = (opponentData.losses as number) + 1;
    } else if (result === 'loss') {
      playerUpdate.losses = (playerData.losses as number) + 1;
      opponentUpdate.wins = (opponentData.wins as number) + 1;
    } else {
      playerUpdate.draws = (playerData.draws as number) + 1;
      opponentUpdate.draws = (opponentData.draws as number) + 1;
    }

    transaction.update(playerRef, playerUpdate);
    transaction.update(opponentRef, opponentUpdate);

    const playerGameRef = playerRef.collection('game_records').doc();
    transaction.set(playerGameRef, {
      opponent: opponentUid,
      mode: 'ranked',
      startingPosition,
      moveList,
      result,
      duration,
      endedAt: FieldValue.serverTimestamp(),
      isFavorite: false,
    });

    const opponentResult = result === 'win' ? 'loss' : result === 'loss' ? 'win' : 'draw';
    const opponentGameRef = opponentRef.collection('game_records').doc();
    transaction.set(opponentGameRef, {
      opponent: playerUid,
      mode: 'ranked',
      startingPosition,
      moveList,
      result: opponentResult,
      duration,
      endedAt: FieldValue.serverTimestamp(),
      isFavorite: false,
    });

    return { success: true, gameId: playerGameRef.id };
  });
});
