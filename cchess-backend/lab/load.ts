// Load / leak test: stand up many concurrent games, tear them all down via a
// mix of resign + double-disconnect, then assert the server returns to a clean
// slate — zero rooms, zero invariant violations. Catches leaks that only show
// at scale (orphaned timers, rooms that never get collected, sockets stuck in
// the queue).
//
//   npx tsx lab/load.ts            # 40 concurrent games
//   npx tsx lab/load.ts 120        # heavier
//   LAB_VERBOSE=1 npx tsx lab/load.ts

import { Bot } from './bot';
import { startLabServer, sleep } from './harness';
import { checkInvariants } from './invariants';
import { debugRooms } from '../src/rooms';
import { resetState } from './run-one';

async function main(): Promise<void> {
  const print = console.log.bind(console);
  if (!process.env.LAB_VERBOSE) {
    console.warn = () => {};
    console.error = () => {};
  }

  const games = Number(process.argv[2]) || 40;
  print(`\nCChess load test — ${games} concurrent games (${games * 2} sockets)\n`);

  resetState();
  const { url, close } = await startLabServer({
    reconnectGraceMs: 600,
    waitingRoomTtlMs: 1000,
    heartbeatIntervalMs: 5000,
    livenessTimeoutMs: 60_000,
  });

  const allBots: Bot[] = [];
  let exitCode = 0;
  const fail = (msg: string): void => {
    print(`\n✘ ${msg}\n`);
    exitCode = 1;
  };

  try {
    // ── Phase 1: bring up `games` live games concurrently ──────────────────
    const t0 = Date.now();
    const made = await Promise.all(
      Array.from({ length: games }, async (_, i) => {
        const red = new Bot(url, `L${i}r`);
        const black = new Bot(url, `L${i}b`);
        allBots.push(red, black);
        await red.connectAuthed();
        await black.connectAuthed();
        red.createRoom();
        const created = await red.waitType('room-created');
        const roomId = created.roomId as string;
        black.joinRoom(roomId);
        await red.waitType('game-start');
        await black.waitType('game-start');
        return { red, black, roomId };
      }),
    );
    const upMs = Date.now() - t0;

    const playing = debugRooms().filter((r) => r.status === 'playing').length;
    print(`  brought up ${playing}/${games} games in ${upMs}ms`);
    if (playing !== games) fail(`expected ${games} playing rooms, saw ${playing}`);
    let v = checkInvariants();
    if (v.length) fail(`invariants violated at peak load:\n    ${v.map((x) => x.detail).join('\n    ')}`);

    // ── Phase 2: tear down — half by resign, half by double-disconnect ─────
    const tearStart = Date.now();
    await Promise.all(
      made.map(async (g, i) => {
        if (i % 2 === 0) {
          g.red.resign();
          await g.red.waitType('game-ended');
          await g.black.waitType('game-ended');
        } else {
          g.red.drop();
          g.black.drop();
        }
      }),
    );

    // Close every still-open socket, then wait past the grace + TTL windows so
    // forfeit timers fire and finished rooms are collected.
    for (const b of allBots) await b.close().catch(() => {});
    await sleep(1500);
    print(`  tore down in ${Date.now() - tearStart}ms`);

    // ── Phase 3: the slate must be clean ───────────────────────────────────
    const rooms = debugRooms();
    v = checkInvariants();
    if (rooms.length !== 0) {
      fail(`expected 0 rooms after drain, found ${rooms.length}: ${JSON.stringify(rooms)}`);
    }
    if (v.length) {
      fail(`invariants violated after drain:\n    ${v.map((x) => x.detail).join('\n    ')}`);
    }
    if (exitCode === 0) {
      print(`\n✔ ${games} games up + down, clean slate (0 rooms, 0 violations).\n`);
    }
  } finally {
    for (const b of allBots) await b.close().catch(() => {});
    await close();
  }
  process.exitCode = exitCode;
}

void main();
