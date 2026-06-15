// Soak/fuzz runner. Throws random lifecycle actions (connect, find-match,
// cancel, create, join, resign, leave, drop, reconnect, remove) at a pool of
// bots and asserts the server's invariants after every step — for thousands of
// iterations. Short grace/TTL windows mean those timers fire *amid* the random
// ops, which is exactly where the races that fixed scenarios never imagine
// tend to hide.
//
// Reproducible: every run prints its seed; re-run with the same seed (and same
// --bots/--iters) to replay a failure byte-for-byte. On a violation it dumps
// the recent action history so you can see the sequence that broke it.
//
//   npx tsx lab/fuzz.ts                  # 2000 iters, random seed
//   npx tsx lab/fuzz.ts 5000             # 5000 iters
//   npx tsx lab/fuzz.ts --seed=123456    # replay a specific seed
//   npx tsx lab/fuzz.ts 3000 --bots=8 --seed=42
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
}

function parseArgs(argv: string[]): Args {
  let iters = 2000;
  let bots = 6;
  let seed = (Date.now() ^ (Math.random() * 0xffffffff)) >>> 0;
  for (const a of argv) {
    if (/^\d+$/.test(a)) iters = Number(a);
    else if (a.startsWith('--seed=')) seed = Number(a.slice(7)) >>> 0;
    else if (a.startsWith('--bots=')) bots = Number(a.slice(7));
    else if (a.startsWith('--iters=')) iters = Number(a.slice(8));
  }
  return { iters, bots, seed };
}

type Action =
  | 'spawn'
  | 'find'
  | 'cancel'
  | 'create'
  | 'join'
  | 'resign'
  | 'leave'
  | 'drop'
  | 'reconnect'
  | 'remove';

const ACTIONS: Action[] = [
  'spawn',
  'find',
  'find',
  'create',
  'join',
  'join',
  'cancel',
  'resign',
  'leave',
  'drop',
  'drop',
  'reconnect',
  'reconnect',
  'remove',
];

interface Slot {
  bot: Bot;
  dropped: boolean;
  lastRoom?: string;
}

/// A violation only counts if it PERSISTS after a short pause — this filters
/// the harmless transient windows (e.g. the few ms between a socket terminate
/// and the server processing its 'close', or a grace timer firing mid-check).
/// Real stuck states (orphan ghost, leaked finished room) never clear.
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

  const { iters, bots: maxBots, seed } = parseArgs(process.argv.slice(2));
  const rand = mulberry32(seed);
  const pick = <T>(arr: T[]): T => arr[Math.floor(rand() * arr.length)];
  const randInt = (lo: number, hi: number): number =>
    lo + Math.floor(rand() * (hi - lo + 1));

  print(`\nCChess fuzz — seed=${seed} iters=${iters} bots≤${maxBots}`);
  print(`(replay with: npx tsx lab/fuzz.ts ${iters} --bots=${maxBots} --seed=${seed})\n`);

  resetState();
  // Short grace/TTL → those timers fire during the storm. Heartbeat/liveness
  // kept long so the server doesn't auto-terminate idle bots (disconnects are
  // explicit, via the 'drop' action).
  const { url, close } = await startLabServer({
    reconnectGraceMs: 500,
    waitingRoomTtlMs: 700,
    heartbeatIntervalMs: 5000,
    livenessTimeoutMs: 60_000,
  });

  const pool = new Map<string, Slot>();
  let nextUid = 0;
  const history: string[] = [];
  const record = (s: string): void => {
    history.push(s);
    if (history.length > 60) history.shift();
  };

  function waitingRoomIds(): string[] {
    return debugRooms()
      .filter((r) => r.status === 'waiting')
      .map((r) => r.id);
  }
  function anyRoomIds(): string[] {
    return debugRooms().map((r) => r.id);
  }

  async function execute(action: Action): Promise<void> {
    // Actions needing an existing bot pick one at random.
    const slots = [...pool.values()];
    const live = slots.filter((s) => !s.dropped);

    switch (action) {
      case 'spawn': {
        if (pool.size >= maxBots) return;
        const uid = `f${nextUid++}`;
        const bot = new Bot(url, uid);
        await bot.connectAuthed();
        pool.set(uid, { bot, dropped: false });
        record(`spawn ${uid}`);
        return;
      }
      case 'find': {
        if (!live.length) return;
        const s = pick(live);
        s.bot.findMatch();
        record(`${s.bot.uid} find`);
        return;
      }
      case 'cancel': {
        if (!live.length) return;
        const s = pick(live);
        s.bot.cancelMatching();
        record(`${s.bot.uid} cancel`);
        return;
      }
      case 'create': {
        if (!live.length) return;
        const s = pick(live);
        s.bot.createRoom();
        record(`${s.bot.uid} create`);
        return;
      }
      case 'join': {
        if (!live.length) return;
        const targets = waitingRoomIds();
        if (!targets.length) return;
        const s = pick(live);
        const room = pick(targets);
        s.bot.joinRoom(room);
        record(`${s.bot.uid} join ${room}`);
        return;
      }
      case 'resign': {
        if (!live.length) return;
        const s = pick(live);
        s.bot.resign();
        record(`${s.bot.uid} resign`);
        return;
      }
      case 'leave': {
        if (!live.length) return;
        const s = pick(live);
        s.bot.leaveRoom();
        record(`${s.bot.uid} leave`);
        return;
      }
      case 'drop': {
        const ups = live.filter((s) => !s.dropped);
        if (!ups.length) return;
        const s = pick(ups);
        s.lastRoom = s.bot.roomId ?? s.lastRoom;
        s.bot.drop();
        s.dropped = true;
        record(`${s.bot.uid} drop (room=${s.lastRoom ?? '—'})`);
        return;
      }
      case 'reconnect': {
        const downs = slots.filter((s) => s.dropped);
        if (!downs.length) return;
        const s = pick(downs);
        const uid = s.bot.uid;
        const bot = new Bot(url, uid);
        await bot.connectAuthed();
        const target = s.lastRoom ?? pick(anyRoomIds().length ? anyRoomIds() : ['ZZZZZZ']);
        bot.reconnectRoom(target);
        pool.set(uid, { bot, dropped: false, lastRoom: target });
        record(`${uid} reconnect ${target}`);
        return;
      }
      case 'remove': {
        if (!slots.length) return;
        const s = pick(slots);
        await s.bot.close().catch(() => {});
        pool.delete(s.bot.uid);
        record(`${s.bot.uid} remove`);
        return;
      }
    }
  }

  function dumpAndExit(v: InvariantViolation[]): void {
    print(`\n✘ INVARIANT VIOLATED after ${history.length ? '' : ''}fuzzing (seed=${seed})\n`);
    for (const x of v) print(`    • [${x.rule}] ${x.detail}`);
    print(`\n  Recent actions (oldest→newest):`);
    for (const h of history) print(`    ${h}`);
    print(`\n  Rooms now: ${JSON.stringify(debugRooms(), null, 0)}`);
    print(`\n  Replay: npx tsx lab/fuzz.ts ${iters} --bots=${maxBots} --seed=${seed}\n`);
    process.exitCode = 1;
  }

  // ── the storm ───────────────────────────────────────────────────────────
  for (let i = 1; i <= iters; i++) {
    // Keep at least two bots around so games can actually form.
    if (pool.size < 2) await execute('spawn');
    else await execute(pick(ACTIONS));

    await sleep(randInt(6, 35)); // let the server (and any timer) settle a bit
    const v = await persistentViolations();
    if (v.length) {
      dumpAndExit(v);
      break;
    }
    if (i % 250 === 0) {
      const rooms = debugRooms();
      print(`  …${i}/${iters}  pool=${pool.size} rooms=${rooms.length}`);
    }
  }

  // ── final quiesce: drop everyone, let grace/TTL expire, expect a clean slate
  if (process.exitCode !== 1) {
    for (const s of pool.values()) await s.bot.close().catch(() => {});
    await sleep(1200); // > grace + TTL
    const v = checkInvariants();
    const rooms = debugRooms();
    if (v.length || rooms.length) {
      print(`\n✘ Did not return to a clean slate after everyone left:`);
      for (const x of v) print(`    • [${x.rule}] ${x.detail}`);
      if (rooms.length) print(`    leftover rooms: ${JSON.stringify(rooms)}`);
      print(`    Replay: npx tsx lab/fuzz.ts ${iters} --bots=${maxBots} --seed=${seed}\n`);
      process.exitCode = 1;
    } else {
      print(`\n✔ ${iters} iterations, no invariant violations. Clean slate at the end.\n`);
    }
  }

  await close();
}

void main();
