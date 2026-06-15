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

import { Bot } from './bot';

const WS_URL = process.env.CCHESS_BACKEND_URL ?? 'wss://cchess-backend.onrender.com';
// Public Firebase Web API key (same one shipped in the client) — used only to
// mint anonymous ID tokens for the test users.
const API_KEY =
  process.env.FIREBASE_API_KEY ?? 'AIzaSyBIoJ-uY79BtqM8nMkd4RfhzoQ_xqdDExY';

interface AnonUser {
  idToken: string;
  uid: string;
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

async function main(): Promise<void> {
  console.log(`\nCChess prod smoke test → ${WS_URL}\n`);

  // Two real test users (or reuse a supplied token for both seats).
  let userA: AnonUser;
  let userB: AnonUser;
  try {
    const supplied = process.env.FIREBASE_ID_TOKEN;
    if (supplied) {
      userA = { idToken: supplied, uid: 'supplied-a' };
      userB = { idToken: supplied, uid: 'supplied-b' };
    } else {
      [userA, userB] = await Promise.all([anonSignIn(), anonSignIn()]);
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
