// Soak/fuzz runner. Throws random lifecycle actions at a pool of bots and
// asserts the server's invariants after every (settled) step — for thousands
// of iterations. Short grace/TTL windows mean those timers fire *amid* the
// random ops, which is exactly where the races that fixed scenarios never
// imagine tend to hide.
//
// Reproducible: every run prints its seed; re-run with the same seed (and same
// --bots/--iters/--burst) to replay a failure byte-for-byte. On a violation it
// dumps the recent action history so you can see the sequence that broke it.
//
//   npx tsx lab/fuzz.ts                  # 2000 iters, random seed
//   npx tsx lab/fuzz.ts 5000 --bots=8
//   npx tsx lab/fuzz.ts --seed=123456    # replay a specific seed
//   npx tsx lab/fuzz.ts 3000 --burst     # fire 2–4 actions between checks
//   LAB_VERBOSE=1 npx tsx lab/fuzz.ts    # also show server logs

import { Bot } from './bot';
import { startLabServer, sleep } from './harness';
import { checkInvariants, type InvariantViolation } from './invariants';
import { debugRooms } from '../src/rooms';
import { resetState } from './run-one';

// ── tiny seeded PRNG (mulberry32) so runs are reproducible ────────────────
function mulberry32(seed: number): () => number {
  let a = seed >>> 0;
  return () => {
    a |= 0;
    a = (a + 0x6d2b79f5) | 0;
    let t = Math.imul(a ^ (a >>> 15), 1 | a);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

interface Args {
  iters: number;
  bots: number;
  seed: number;
  burst: boolean;
}

function parseArgs(argv: string[]): Args {
  let iters = 2000;
  let bots = 6;
  let seed = (Date.now() ^ (Math.random() * 0xffffffff)) >>> 0;
  let burst = false;
  for (const a of argv) {
    if (/^\d+$/.test(a)) iters = Number(a);
    else if (a.startsWith('--seed=')) seed = Number(a.slice(7)) >>> 0;
    else if (a.startsWith('--bots=')) bots = Number(a.slice(7));
    else if (a.startsWith('--iters=')) iters = Number(a.slice(8));
    else if (a === '--burst') burst = true;
  }
  return { iters, bots, seed, burst };
}

type Action =
  | 'spawn'
  | 'find'
  | 'cancel'
  | 'create'
  | 'join'
  | 'move'
  | 'resign'
  | 'leave'
  | 'drop'
  | 'reconnect'
  | 'spectate'
  | 'chat'
  | 'rematch'
  | 'remove';

// Weighted action bag (duplicates raise probability).
const ACTIONS: Action[] = [
  'spawn',
  'find', 'find',
  'create',
  'join', 'join',
  'move', 'move', 'move',
  'cancel',
  'resign',
  'leave',
  'drop', 'drop',
  'reconnect', 'reconnect',
  'spectate',
  'chat',
  'rematch',
  'remove',
];

// A handful of plausible UCI strings — most will be rejected (illegal / not
// your turn), which still exercises the move/turn/clock validation + the
// occasional legal one advances a real game.
const MOVES = ['b2e2', 'h2e2', 'b0c2', 'h0g2', 'a3a4', 'c3c4', 'e3e4', 'a6a5', 'b7e7'];

interface Slot {
  bot: Bot;
  dropped: boolean;
  lastRoom?: string;
}

async function persistentViolations(): Promise<InvariantViolation[]> {
  let v = checkInvariants();
  if (v.length === 0) return [];
  await sleep(120);
  v = checkInvariants();
  return v;
}

async function main(): Promise<void> {
  const print = console.log.bind(console);
  if (!process.env.LAB_VERBOSE) {
    console.warn = () => {};
    console.error = () => {};
  }

  const { iters, bots: maxBots, seed, burst } = parseArgs(process.argv.slice(2));
  const rand = mulberry32(seed);
  const pick = <T>(arr: T[]): T => arr[Math.floor(rand() * arr.length)];
  const randInt = (lo: number, hi: number): number =>
    lo + Math.floor(rand() * (hi - lo + 1));

  print(`\nCChess fuzz — seed=${seed} iters=${iters} bots≤${maxBots} burst=${burst}`);
  print(
    `(replay: npx tsx lab/fuzz.ts ${iters} --bots=${maxBots} --seed=${seed}${burst ? ' --burst' : ''})\n`,
  );

  resetState();
  const { url, close } = await startLabServer({
    reconnectGraceMs: 500,
    waitingRoomTtlMs: 700,
    heartbeatIntervalMs: 5000,
    livenessTimeoutMs: 60_000,
    minClockMs: 200,
  });

  const pool: Slot[] = [];
  let nextId = 0;
  const history: string[] = [];
  const record = (s: string): void => {
    history.push(s);
    if (history.length > 80) history.shift();
  };
  const live = (): Slot[] => pool.filter((s) => !s.dropped);
  const waitingRoomIds = (): string[] =>
    debugRooms().filter((r) => r.status === 'waiting').map((r) => r.id);
  const playingRoomIds = (): string[] =>
    debugRooms().filter((r) => r.status === 'playing').map((r) => r.id);

  async function execute(action: Action): Promise<void> {
    const ls = live();
    switch (action) {
      case 'spawn': {
        if (pool.length >= maxBots) return;
        // ~25% of the time reuse an existing uid (same-uid / multi-tab case).
        const uid =
          rand() < 0.25 && pool.length ? pick(pool).bot.uid : `f${nextId++}`;
        const bot = new Bot(url, uid);
        await bot.connectAuthed();
        pool.push({ bot, dropped: false });
        record(`spawn ${uid}`);
        return;
      }
      case 'find':
        if (ls.length) { const s = pick(ls); s.bot.findMatch(); record(`${s.bot.uid} find`); }
        return;
      case 'cancel':
        if (ls.length) { const s = pick(ls); s.bot.cancelMatching(); record(`${s.bot.uid} cancel`); }
        return;
      case 'create':
        if (ls.length) { const s = pick(ls); s.bot.createRoom(); record(`${s.bot.uid} create`); }
        return;
      case 'join': {
        const targets = waitingRoomIds();
        if (ls.length && targets.length) {
          const s = pick(ls);
          const room = pick(targets);
          s.bot.joinRoom(room);
          record(`${s.bot.uid} join ${room}`);
        }
        return;
      }
      case 'move':
        if (ls.length) { const s = pick(ls); const u = pick(MOVES); s.bot.move(u); record(`${s.bot.uid} move ${u}`); }
        return;
      case 'resign':
        if (ls.length) { const s = pick(ls); s.bot.resign(); record(`${s.bot.uid} resign`); }
        return;
      case 'leave':
        if (ls.length) { const s = pick(ls); s.bot.leaveRoom(); record(`${s.bot.uid} leave`); }
        return;
      case 'spectate': {
        const targets = playingRoomIds();
        if (ls.length && targets.length) {
          const s = pick(ls);
          const room = pick(targets);
          s.bot.spectateRoom(room);
          record(`${s.bot.uid} spectate ${room}`);
        }
        return;
      }
      case 'chat':
        if (ls.length) { const s = pick(ls); s.bot.chat('gg'); record(`${s.bot.uid} chat`); }
        return;
      case 'rematch':
        if (ls.length) { const s = pick(ls); s.bot.offerRematch(); record(`${s.bot.uid} rematch`); }
        return;
      case 'drop': {
        const ups = ls.filter((s) => !s.dropped);
        if (ups.length) {
          const s = pick(ups);
          s.lastRoom = s.bot.roomId ?? s.lastRoom;
          s.bot.drop();
          s.dropped = true;
          record(`${s.bot.uid} drop (room=${s.lastRoom ?? '—'})`);
        }
        return;
      }
      case 'reconnect': {
        const downs = pool.filter((s) => s.dropped);
        if (downs.length) {
          const s = pick(downs);
          const uid = s.bot.uid;
          const bot = new Bot(url, uid);
          await bot.connectAuthed();
          s.bot = bot;
          s.dropped = false;
          const target = s.lastRoom;
          if (target) bot.reconnectRoom(target);
          record(`${uid} reconnect ${target ?? '—'}`);
        }
        return;
      }
      case 'remove': {
        if (pool.length) {
          const i = Math.floor(rand() * pool.length);
          const [s] = pool.splice(i, 1);
          await s.bot.close().catch(() => {});
          record(`${s.bot.uid} remove`);
        }
        return;
      }
    }
  }

  function dumpAndExit(v: InvariantViolation[]): void {
    print(`\n✘ INVARIANT VIOLATED (seed=${seed})\n`);
    for (const x of v) print(`    • [${x.rule}] ${x.detail}`);
    print(`\n  Recent actions (oldest→newest):`);
    for (const h of history) print(`    ${h}`);
    print(`\n  Rooms now: ${JSON.stringify(debugRooms())}`);
    print(
      `\n  Replay: npx tsx lab/fuzz.ts ${iters} --bots=${maxBots} --seed=${seed}${burst ? ' --burst' : ''}\n`,
    );
    process.exitCode = 1;
  }

  for (let i = 1; i <= iters; i++) {
    if (pool.length < 2) await execute('spawn');
    else {
      const steps = burst ? randInt(2, 4) : 1;
      for (let k = 0; k < steps; k++) await execute(pick(ACTIONS));
    }

    await sleep(randInt(6, 35));
    const v = await persistentViolations();
    if (v.length) {
      dumpAndExit(v);
      break;
    }
    if (i % 250 === 0) {
      print(`  …${i}/${iters}  pool=${pool.length} rooms=${debugRooms().length}`);
    }
  }

  if (process.exitCode !== 1) {
    for (const s of pool) await s.bot.close().catch(() => {});
    await sleep(1200); // > grace + TTL
    const v = checkInvariants();
    const rooms = debugRooms();
    if (v.length || rooms.length) {
      print(`\n✘ Did not return to a clean slate after everyone left:`);
      for (const x of v) print(`    • [${x.rule}] ${x.detail}`);
      if (rooms.length) print(`    leftover rooms: ${JSON.stringify(rooms)}`);
      process.exitCode = 1;
    } else {
      print(`\n✔ ${iters} iterations, no invariant violations. Clean slate at the end.\n`);
    }
  }

  await close();
}

void main();
