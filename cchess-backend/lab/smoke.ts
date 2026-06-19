// Production smoke test: exercises the protocol against the REAL deployed
// server over a real WebSocket, authenticating with genuine Firebase ID tokens
// (minted via anonymous sign-in through the Identity Toolkit REST API). Unlike
// the in-process lab it can't introspect the server's internals, so it asserts
// only on observable protocol messages — true black-box verification of prod.
//
// Deliberately PROD-SAFE: it never lets a game START (a started game persists a
// record + ELO to Firestore when it ends), so it writes no game data. It does
// create 2 throwaway anonymous Auth users per run.
//
//   npx tsx lab/smoke.ts
//   CCHESS_BACKEND_URL=wss://staging.example npx tsx lab/smoke.ts
//   FIREBASE_ID_TOKEN=<token> npx tsx lab/smoke.ts   # bring your own token(s)
//   SMOKE_ALLOW_RANKED_WRITE=1 npx tsx lab/smoke.ts  # opt-in: starts games

import { Bot, type Msg } from './bot';
import { PieceColor, uciOfMove, XiangqiGame } from '../src/engine';

const WS_URL = process.env.CCHESS_BACKEND_URL ?? 'wss://cchess-backend.onrender.com';
const ALLOW_RANKED_WRITE = process.env.SMOKE_ALLOW_RANKED_WRITE === '1';
const GRACE_EXPIRE_TIMEOUT_MS = envInt('SMOKE_GRACE_EXPIRE_TIMEOUT_MS', 75_000);
const QUICK_TIMEOUT_MS = envInt('SMOKE_QUICK_TIMEOUT_MS', 6_000);
// Public Firebase Web API key (same one shipped in the client) — used only to
// mint anonymous ID tokens for the test users.
const API_KEY =
  process.env.FIREBASE_API_KEY ?? 'AIzaSyBIoJ-uY79BtqM8nMkd4RfhzoQ_xqdDExY';

interface AnonUser {
  idToken: string;
  uid: string;
}

async function resolveSmokeUsers(): Promise<[AnonUser, AnonUser]> {
  const tokenA = process.env.FIREBASE_ID_TOKEN_A;
  const tokenB = process.env.FIREBASE_ID_TOKEN_B;
  const singleToken = process.env.FIREBASE_ID_TOKEN;

  if (tokenA || tokenB) {
    if (!tokenA || !tokenB) {
      throw new Error(
        'FIREBASE_ID_TOKEN_A and FIREBASE_ID_TOKEN_B must be supplied together.',
      );
    }
    return [
      { idToken: tokenA, uid: 'supplied-a' },
      { idToken: tokenB, uid: 'supplied-b' },
    ];
  }

  if (singleToken) {
    return [
      { idToken: singleToken, uid: 'supplied-a' },
      { idToken: singleToken, uid: 'supplied-b' },
    ];
  }

  return Promise.all([anonSignIn(), anonSignIn()]);
}

/// Mint a real Firebase ID token via anonymous sign-in (Identity Toolkit REST).
async function anonSignIn(): Promise<AnonUser> {
  const res = await fetch(
    `https://identitytoolkit.googleapis.com/v1/accounts:signUp?key=${API_KEY}`,
    {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ returnSecureToken: true }),
    },
  );
  const data = (await res.json()) as {
    idToken?: string;
    localId?: string;
    error?: { message?: string };
  };
  if (!res.ok || !data.idToken || !data.localId) {
    const why = data.error?.message ?? JSON.stringify(data);
    throw new Error(
      `anonymous sign-in failed (${why}). Enable Anonymous auth in Firebase, ` +
        `or pass FIREBASE_ID_TOKEN env to use your own token.`,
    );
  }
  return { idToken: data.idToken, uid: data.localId };
}

function assert(cond: boolean, msg: string): void {
  if (!cond) throw new Error(msg);
}

function envInt(name: string, fallback: number): number {
  const value = Number(process.env[name]);
  return Number.isFinite(value) ? Math.trunc(value) : fallback;
}

/// First legal red move from the shared TS engine. This keeps smoke aligned
/// with the deployed server's UCI mapping instead of hard-coding a coordinate.
function firstLegalRedUci(): string {
  const game = XiangqiGame.initial();
  for (const [pos, piece] of game.board.occupied()) {
    if (piece.color !== PieceColor.Red) continue;
    const moves = game.getValidMoves(pos);
    if (moves.length > 0) return uciOfMove(pos, moves[0]);
  }
  throw new Error('no legal red move from the initial position');
}

function assertRoomId(msg: Msg, label: string): string {
  assert(
    typeof msg.roomId === 'string' && msg.roomId.length > 0,
    `${label} carries roomId`,
  );
  return msg.roomId as string;
}

function assertGameEnded(msg: Msg, reason: string, label: string): void {
  assert(
    msg.reason === reason,
    `${label}: expected reason=${reason}, got ${String(msg.reason)}`,
  );
  assert(
    msg.result === 'red-win' || msg.result === 'black-win' || msg.result === 'draw',
    `${label}: unexpected result=${String(msg.result)}`,
  );
}

async function connectSmokeBot(label: string, user: AnonUser): Promise<Bot> {
  const bot = new Bot(WS_URL, label);
  await bot.connectAuthed(user.idToken);
  return bot;
}

async function closeAll(...bots: Array<Bot | undefined>): Promise<void> {
  await Promise.all(
    bots
      .filter((bot): bot is Bot => bot !== undefined)
      .map((bot) => bot.close().catch(() => {})),
  );
}

async function leaveFinishedRoom(bot: Bot): Promise<void> {
  bot.leaveRoom();
  await bot.waitFor(
    (m) => m.type === 'left-room' || (m.type === 'error' && m.code === 'not-in-room'),
    QUICK_TIMEOUT_MS,
  );
}

async function main(): Promise<void> {
  console.log(`\nCChess prod smoke test → ${WS_URL}\n`);

  // Two real test users (or reuse supplied tokens).
  let userA: AnonUser;
  let userB: AnonUser;
  try {
    [userA, userB] = await resolveSmokeUsers();
    if (ALLOW_RANKED_WRITE && userA.idToken === userB.idToken) {
      throw new Error(
        'SMOKE_ALLOW_RANKED_WRITE=1 requires two distinct Firebase users. ' +
          'Let the smoke script mint anonymous users, or pass FIREBASE_ID_TOKEN_A and FIREBASE_ID_TOKEN_B.',
      );
    }
  } catch (e) {
    console.error(`✘ could not obtain a token: ${(e as Error).message}\n`);
    process.exitCode = 1;
    return;
  }

  const a = new Bot(WS_URL, userA.uid);
  const b = new Bot(WS_URL, userB.uid);

  const tests: { name: string; fn: () => Promise<void> }[] = [
    {
      name: 'auth handshake with a real Firebase token',
      fn: async () => {
        await a.connectAuthed(userA.idToken);
        await b.connectAuthed(userB.idToken);
      },
    },
    {
      name: 'create then leave a private room (no game starts)',
      fn: async () => {
        a.createRoom();
        const created = await a.waitType('room-created');
        assert(typeof created.roomId === 'string', 'room-created carries an id');
        a.leaveRoom();
        await a.waitType('left-room');
      },
    },
    {
      name: 'matchmaking enqueue + cancel',
      fn: async () => {
        a.findMatch();
        await a.waitType('matching');
        a.cancelMatching();
        const r = await a.waitType('matching-canceled');
        assert(r.removed === true, 'cancel should report removed=true');
      },
    },
    {
      name: 'find→create leaves the queue (no double-booking) — THIS deploy',
      fn: async () => {
        a.findMatch();
        await a.waitType('matching');
        a.createRoom(); // the fix: entering a room must dequeue from matchmaking
        await a.waitType('room-created');

        b.findMatch();
        await b.waitType('matching');
        // If the fix is live, A is no longer queued → B can't pair with A and
        // A can't be yanked into a matchmaking game.
        await b.expectNoMessage('game-start', 1800);
        await a.expectNoMessage('match-found', 50);

        // cleanup — leave the waiting room + the queue (still no game started)
        a.leaveRoom();
        await a.waitType('left-room');
        b.cancelMatching();
        await b.waitType('matching-canceled');
      },
    },
  ];

  if (ALLOW_RANKED_WRITE) {
    tests.push(
      {
        name: 'RANKED-WRITE: matchmaking starts a real game, then resign ends it',
        fn: async () => {
          const matchA = await connectSmokeBot('ranked-m1-a', userA);
          const matchB = await connectSmokeBot('ranked-m1-b', userB);
          try {
            matchA.findMatch();
            await matchA.waitType('matching', QUICK_TIMEOUT_MS);
            matchB.findMatch();
            const foundA = await matchA.waitType('match-found', QUICK_TIMEOUT_MS);
            const foundB = await matchB.waitType('match-found', QUICK_TIMEOUT_MS);
            const startA = await matchA.waitType('game-start', QUICK_TIMEOUT_MS);
            const startB = await matchB.waitType('game-start', QUICK_TIMEOUT_MS);

            const roomId = assertRoomId(startA, 'game-start A');
            assert(foundA.roomId === roomId, 'match-found A matches game-start room');
            assert(foundB.roomId === roomId, 'match-found B matches game-start room');
            assert(startB.roomId === roomId, 'both users start in the same room');
            assert(startA.yourColor !== startB.yourColor, 'matchmaking assigns opposite colors');

            matchA.resign();
            assertGameEnded(
              await matchA.waitType('game-ended', QUICK_TIMEOUT_MS),
              'resign',
              'A game-ended',
            );
            assertGameEnded(
              await matchB.waitType('game-ended', QUICK_TIMEOUT_MS),
              'resign',
              'B game-ended',
            );
            await leaveFinishedRoom(matchA);
            await leaveFinishedRoom(matchB);
          } finally {
            await closeAll(matchA, matchB);
          }
        },
      },
      {
        name: 'RANKED-WRITE: private game reconnect restores played moves',
        fn: async () => {
          const red = await connectSmokeBot('ranked-d2-red', userA);
          const black = await connectSmokeBot('ranked-d2-black', userB);
          let red2: Bot | undefined;
          try {
            red.createRoom();
            const roomId = assertRoomId(
              await red.waitType('room-created', QUICK_TIMEOUT_MS),
              'room-created',
            );
            black.joinRoom(roomId);
            const startRed = await red.waitType('game-start', QUICK_TIMEOUT_MS);
            const startBlack = await black.waitType('game-start', QUICK_TIMEOUT_MS);
            assert(
              startRed.yourColor === 'red',
              `creator should be red, got ${String(startRed.yourColor)}`,
            );
            assert(
              startBlack.yourColor === 'black',
              `joiner should be black, got ${String(startBlack.yourColor)}`,
            );

            const uci = firstLegalRedUci();
            red.move(uci);
            await red.waitType('move-ack', QUICK_TIMEOUT_MS);
            await black.waitType('opponent-move', QUICK_TIMEOUT_MS);

            await red.close();
            const peerGone = await black.waitType('peer-disconnected', QUICK_TIMEOUT_MS);
            assert(
              typeof peerGone.graceMs === 'number' && peerGone.graceMs > 0,
              'peer-disconnected carries graceMs',
            );

            red2 = await connectSmokeBot('ranked-d2-red-reconnect', userA);
            red2.reconnectRoom(roomId);
            const snap = await red2.waitType('reconnected', QUICK_TIMEOUT_MS);
            assert(snap.roomId === roomId, 'reconnected to the original room');
            assert(
              Array.isArray(snap.moves) && snap.moves.length === 1 && snap.moves[0] === uci,
              'reconnect snapshot keeps the played move',
            );
            await black.waitType('peer-reconnected', QUICK_TIMEOUT_MS);

            red2.resign();
            assertGameEnded(
              await red2.waitType('game-ended', QUICK_TIMEOUT_MS),
              'resign',
              'reconnected red game-ended',
            );
            assertGameEnded(
              await black.waitType('game-ended', QUICK_TIMEOUT_MS),
              'resign',
              'black game-ended',
            );
            await leaveFinishedRoom(red2);
            await leaveFinishedRoom(black);
          } finally {
            await closeAll(red, red2, black);
          }
        },
      },
      {
        name: 'RANKED-WRITE: reconnect after grace expiry is rejected',
        fn: async () => {
          const red = await connectSmokeBot('ranked-d3-red', userA);
          const black = await connectSmokeBot('ranked-d3-black', userB);
          let red2: Bot | undefined;
          try {
            red.createRoom();
            const roomId = assertRoomId(
              await red.waitType('room-created', QUICK_TIMEOUT_MS),
              'room-created',
            );
            black.joinRoom(roomId);
            await red.waitType('game-start', QUICK_TIMEOUT_MS);
            await black.waitType('game-start', QUICK_TIMEOUT_MS);

            await red.close();
            const peerGone = await black.waitType('peer-disconnected', QUICK_TIMEOUT_MS);
            const graceMs = typeof peerGone.graceMs === 'number' ? peerGone.graceMs : 60_000;
            const ended = await black.waitType(
              'game-ended',
              Math.max(GRACE_EXPIRE_TIMEOUT_MS, graceMs + 10_000),
            );
            assertGameEnded(ended, 'disconnect', 'black game-ended after grace');

            red2 = await connectSmokeBot('ranked-d3-red-too-late', userA);
            red2.reconnectRoom(roomId);
            const err = await red2.waitType('error', QUICK_TIMEOUT_MS);
            assert(
              err.code === 'game-not-active' ||
                err.code === 'room-not-found' ||
                err.code === 'not-disconnected-player',
              `late reconnect should be rejected, got ${String(err.code)}`,
            );

            await leaveFinishedRoom(black);
          } finally {
            await closeAll(red, red2, black);
          }
        },
      },
    );
  } else {
    console.log(
      'Ranked-write smoke disabled. Set SMOKE_ALLOW_RANKED_WRITE=1 against staging/prod to cover D2/D3/M1/G3.\n',
    );
  }

  let passed = 0;
  const failures: { name: string; error: string }[] = [];
  for (const t of tests) {
    const t0 = Date.now();
    try {
      await t.fn();
      console.log(`  ✔ ${t.name}  (${Date.now() - t0}ms)`);
      passed++;
    } catch (e) {
      console.log(`  ✘ ${t.name}  (${Date.now() - t0}ms)`);
      failures.push({ name: t.name, error: e instanceof Error ? e.message : String(e) });
    }
  }

  await a.close().catch(() => {});
  await b.close().catch(() => {});

  console.log(`\n${passed}/${tests.length} passed`);
  if (failures.length) {
    console.log('\nFailures:');
    for (const f of failures) console.log(`  ✘ ${f.name}\n    ${f.error}`);
    process.exitCode = 1;
  }
  console.log('');
}

void main();
