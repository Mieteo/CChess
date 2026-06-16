// Named, scripted scenarios over the in-process server. Each one drives the
// protocol entirely through Bot method calls (no manual UI) and the runner
// asserts invariants after every step. Adding coverage = adding an entry here.

import { Bot } from './bot';
import { activeRooms } from '../src/rooms';
import type { LabTiming } from './harness';
import { checkInvariants } from './invariants';

export interface Lab {
  url: string;
  /// Create + auth a bot, registering it for automatic teardown.
  bot: (uid: string) => Promise<Bot>;
  /// Create (but don't connect) a bot — for reconnect scenarios.
  rawBot: (uid: string) => Bot;
  /// Throw if any invariant is currently violated.
  assertHealthy: (label?: string) => void;
  sleep: (ms: number) => Promise<void>;
}

export interface Scenario {
  name: string;
  /// What this scenario protects against, shown in the dashboard.
  why: string;
  timing?: LabTiming;
  run: (lab: Lab) => Promise<void>;
}

function assert(cond: boolean, msg: string): void {
  if (!cond) throw new Error(msg);
}

export const scenarios: Scenario[] = [
  {
    name: 'matchmaking-pairs-two',
    why: 'Two queued players get paired into one game with opposite colors.',
    async run(lab) {
      const a = await lab.bot('alice');
      const b = await lab.bot('bob');
      a.findMatch();
      await a.waitType('matching');
      b.findMatch();
      const sa = await a.waitType('game-start');
      const sb = await b.waitType('game-start');
      assert(sa.roomId === sb.roomId, 'both should land in the same room');
      assert(
        sa.yourColor !== sb.yourColor,
        `colors must differ, got ${sa.yourColor}/${sb.yourColor}`,
      );
      lab.assertHealthy('after pairing');
    },
  },

  {
    name: 'cancel-matching-clears-queue',
    why: 'Cancelling matchmaking must remove the player from the queue.',
    async run(lab) {
      const a = await lab.bot('cara');
      a.findMatch();
      await a.waitType('matching');
      a.cancelMatching();
      const res = await a.waitType('matching-canceled');
      assert(res.removed === true, 'cancel should report removed=true');
      await a.expectNoMessage('game-start');
      lab.assertHealthy('after cancel'); // invariant #8: no dead socket queued
    },
  },

  {
    name: 'create-join-starts-game',
    why: 'Private room: creator waits, joiner triggers game-start for both.',
    async run(lab) {
      const a = await lab.bot('dan');
      const b = await lab.bot('eve');
      a.createRoom();
      const created = await a.waitType('room-created');
      b.joinRoom(created.roomId as string);
      await a.waitType('game-start');
      await b.waitType('game-start');
      lab.assertHealthy('mid-game');
    },
  },

  {
    name: 'both-leave-after-end-no-ghost',
    why: 'After a finished game both players leaving must remove the room — the original "đang đánh" ghost bug.',
    async run(lab) {
      const a = await lab.bot('finn');
      const b = await lab.bot('gwen');
      a.createRoom();
      const created = await a.waitType('room-created');
      const roomId = created.roomId as string;
      b.joinRoom(roomId);
      await a.waitType('game-start');
      await b.waitType('game-start');

      a.resign();
      await a.waitType('game-ended');
      await b.waitType('game-ended');

      // Mirror the client's leave(): leave-room then close, for both.
      a.leaveRoom();
      a.drop();
      b.leaveRoom();
      b.drop();
      await lab.sleep(150);

      assert(activeRooms().length === 0, 'no room should remain after both left');
      lab.assertHealthy('after both left');
    },
  },

  {
    name: 'ghost-room-not-listed-during-grace',
    why: 'While both players are in grace the room is hidden from active-rooms and stays invariant-clean.',
    timing: { reconnectGraceMs: 800 },
    async run(lab) {
      const a = await lab.bot('hugo');
      const b = await lab.bot('iris');
      a.createRoom();
      const created = await a.waitType('room-created');
      b.joinRoom(created.roomId as string);
      await a.waitType('game-start');
      await b.waitType('game-start');

      a.drop();
      await b.waitType('peer-disconnected');
      // One still connected → still a live game.
      assert(activeRooms().length === 1, 'single-disconnect game stays listed');
      lab.assertHealthy('one player in grace');

      b.drop();
      await lab.sleep(150); // within the 800ms grace
      assert(
        activeRooms().length === 0,
        'a room with nobody connected must NOT be advertised as active',
      );
      lab.assertHealthy('both in grace'); // playing+0 members is OK *with* grace

      await lab.sleep(900); // let grace expire → forfeit + cleanup
      assert(activeRooms().length === 0, 'room should be gone after grace expiry');
      lab.assertHealthy('after grace expiry');
    },
  },

  {
    name: 'find-then-create-no-double-booking',
    why: 'Searching for a match then creating a private room must leave the queue — otherwise matchmaking later pairs you into a 2nd game (found by the fuzzer).',
    async run(lab) {
      const a = await lab.bot('quinn');
      a.findMatch();
      await a.waitType('matching');
      a.createRoom(); // enters a private room → must cancel the search
      await a.waitType('room-created');

      // A second searcher must NOT get paired with `a` (a is no longer queued).
      const b = await lab.bot('rosa');
      b.findMatch();
      await b.waitType('matching');
      await b.expectNoMessage('game-start', 800);
      // `a` must not have been yanked into a matchmaking game either.
      await a.expectNoMessage('match-found', 50);
      lab.assertHealthy('after find+create');
    },
  },

  {
    name: 'find-then-immediately-drop leaves no dead socket queued',
    why: 'find-match fetches ELO async; if the socket drops during that await the enqueue must not resurrect a dead socket in the queue (found by the burst fuzzer).',
    async run(lab) {
      // Hammer the race: each bot enqueues then drops before the handler's
      // async ELO fetch resolves. With the bug, dead sockets pile up in the queue.
      for (let i = 0; i < 15; i++) {
        const bot = lab.rawBot(`race${i}`);
        await bot.connectAuthed();
        bot.findMatch();
        bot.drop();
      }
      await lab.sleep(400);
      lab.assertHealthy('after find→drop hammering');
    },
  },

  {
    name: 'reconnect-resumes-mid-game',
    why: 'A dropped player can reconnect within grace and resume the same game.',
    timing: { reconnectGraceMs: 1500 },
    async run(lab) {
      const a = await lab.bot('jay');
      const b = await lab.bot('kim');
      a.createRoom();
      const created = await a.waitType('room-created');
      const roomId = created.roomId as string;
      b.joinRoom(roomId);
      await a.waitType('game-start');
      await b.waitType('game-start');

      a.drop();
      await b.waitType('peer-disconnected');

      const a2 = lab.rawBot('jay'); // same uid, fresh socket
      await a2.connectAuthed();
      a2.reconnectRoom(roomId);
      const snap = await a2.waitType('reconnected');
      assert(snap.roomId === roomId, 'reconnected into the same room');
      await b.waitType('peer-reconnected');
      lab.assertHealthy('after reconnect');
    },
  },

  {
    name: 'waiting-room-ttl-expires',
    why: 'A private room nobody joins is cancelled and removed after its TTL.',
    timing: { waitingRoomTtlMs: 400 },
    async run(lab) {
      const a = await lab.bot('lee');
      a.createRoom();
      await a.waitType('room-created');
      const expired = await a.waitType('room-expired', 2000);
      assert(typeof expired.roomId === 'string', 'room-expired carries the id');
      await lab.sleep(50);
      assert(activeRooms().length === 0, 'expired room must be gone');
      lab.assertHealthy('after ttl');
    },
  },

  {
    name: 'resign-race-close-still-cleans',
    why: 'Client back-button resigns then immediately drops; the room must still end + clean up.',
    async run(lab) {
      const a = await lab.bot('mara');
      const b = await lab.bot('ned');
      a.createRoom();
      const created = await a.waitType('room-created');
      b.joinRoom(created.roomId as string);
      await a.waitType('game-start');
      await b.waitType('game-start');

      a.resign();
      a.drop(); // race the resign frame against the close
      await b.waitType('game-ended');
      b.leaveRoom();
      b.drop();
      await lab.sleep(150);
      assert(activeRooms().length === 0, 'no leftover room after resign+drop');
      lab.assertHealthy('after resign race');
    },
  },

  // ── Batch 1 regressions: the rare bugs found by code review ──────────────
  {
    name: 'join-an-in-progress-room-is-rejected (no hijack)',
    why: 'Joining by ID into a playing room (e.g. a seat mid-reconnect) must be refused, not reset the game and steal the seat.',
    timing: { reconnectGraceMs: 2500 },
    async run(lab) {
      const a = await lab.bot('host');
      const b = await lab.bot('guest');
      a.createRoom();
      const created = await a.waitType('room-created');
      const roomId = created.roomId as string;
      b.joinRoom(roomId);
      await a.waitType('game-start');
      await b.waitType('game-start');

      // a drops → the room is still 'playing' with one seat in grace.
      a.drop();
      await b.waitType('peer-disconnected');

      // A stranger tries to join the in-progress room by id → must be rejected.
      const c = await lab.bot('stranger');
      c.joinRoom(roomId);
      const err = await c.waitType('error');
      assert(
        err.code === 'room-in-progress',
        `expected room-in-progress, got ${err.code}`,
      );

      // The original game is untouched: the dropped player can still resume it.
      const a2 = lab.rawBot('host');
      await a2.connectAuthed();
      a2.reconnectRoom(roomId);
      const snap = await a2.waitType('reconnected');
      assert(snap.roomId === roomId, 'original player resumes the untouched game');
      lab.assertHealthy('after blocked hijack');
    },
  },

  {
    name: 'exactly-one-game-ended-per-game',
    why: 'Redundant end triggers (resign then leave) must not emit a second game-ended / double-apply ELO.',
    async run(lab) {
      const a = await lab.bot('aa');
      const b = await lab.bot('bb');
      a.createRoom();
      const created = await a.waitType('room-created');
      b.joinRoom(created.roomId as string);
      await a.waitType('game-start');
      await b.waitType('game-start');

      a.resign();
      await a.waitType('game-ended');
      await b.waitType('game-ended');
      // Pile on more end-ish actions; the opponent must see NO second result.
      a.resign();
      a.leaveRoom();
      await b.expectNoMessage('game-ended', 500);
      lab.assertHealthy('after redundant end triggers');
    },
  },

  {
    name: 'same-uid reconnect reclaims the dropped seat',
    why: 'When both seats share one Firebase uid (solo testing), a reconnect must fill the seat that actually dropped, not always red.',
    timing: { reconnectGraceMs: 2500 },
    async run(lab) {
      const red = await lab.bot('solo');
      const black = await lab.bot('solo'); // same uid, second socket
      red.createRoom();
      const created = await red.waitType('room-created');
      const roomId = created.roomId as string;
      black.joinRoom(roomId);
      const rs = await red.waitType('game-start');
      const bs = await black.waitType('game-start');
      assert(rs.yourColor === 'red' && bs.yourColor === 'black', 'seats assigned');

      black.drop(); // the BLACK seat drops
      await red.waitType('peer-disconnected');

      const back = lab.rawBot('solo');
      await back.connectAuthed();
      back.reconnectRoom(roomId);
      const snap = await back.waitType('reconnected');
      assert(
        snap.yourColor === 'black',
        `same-uid reconnect should reclaim black, got ${snap.yourColor}`,
      );
      lab.assertHealthy('after same-uid reconnect');
    },
  },

  // ── Batch 2 edge cases: player behaviour ─────────────────────────────────
  {
    name: 'spectator cannot move or resign',
    why: 'A watcher is read-only: move/resign must be refused with not-player.',
    async run(lab) {
      const a = await lab.bot('p1');
      const b = await lab.bot('p2');
      a.createRoom();
      const created = await a.waitType('room-created');
      const roomId = created.roomId as string;
      b.joinRoom(roomId);
      await a.waitType('game-start');
      await b.waitType('game-start');

      const c = await lab.bot('watch');
      c.spectateRoom(roomId);
      await c.waitType('spectate-started');

      c.move('a0a1');
      const e1 = await c.waitType('error');
      assert(e1.code === 'not-player', `move: expected not-player, got ${e1.code}`);
      c.resign();
      const e2 = await c.waitType('error');
      assert(e2.code === 'not-player', `resign: expected not-player, got ${e2.code}`);
      lab.assertHealthy('after spectator abuse');
    },
  },

  {
    name: 'move out of turn is rejected',
    why: 'Black moving before red (or any wrong-turn move) must be refused with not-your-turn.',
    async run(lab) {
      const red = await lab.bot('r');
      const black = await lab.bot('k');
      red.createRoom();
      const created = await red.waitType('room-created');
      black.joinRoom(created.roomId as string);
      await red.waitType('game-start');
      await black.waitType('game-start');

      black.move('a9a8'); // red moves first
      const e = await black.waitType('error');
      assert(e.code === 'not-your-turn', `expected not-your-turn, got ${e.code}`);
      lab.assertHealthy('after out-of-turn move');
    },
  },

  {
    name: 'join errors: not-found and in-progress',
    why: 'Joining a missing room → room-not-found; joining a full/active room → room-in-progress.',
    async run(lab) {
      const a = await lab.bot('j1');
      a.joinRoom('ZZZZZZ');
      const e1 = await a.waitType('error');
      assert(e1.code === 'room-not-found', `expected room-not-found, got ${e1.code}`);

      const b = await lab.bot('j2');
      const c = await lab.bot('j3');
      b.createRoom();
      const created = await b.waitType('room-created');
      const roomId = created.roomId as string;
      c.joinRoom(roomId);
      await b.waitType('game-start'); // now full + playing
      await c.waitType('game-start');
      a.joinRoom(roomId);
      const e2 = await a.waitType('error');
      assert(e2.code === 'room-in-progress', `expected room-in-progress, got ${e2.code}`);
      lab.assertHealthy('after join errors');
    },
  },

  {
    name: 'running out of time forfeits the player on the clock',
    why: 'When a side hits 0 the opponent wins by timeout (uses a sub-second clock via the min-clock override).',
    timing: { minClockMs: 200, livenessTimeoutMs: 60_000 },
    async run(lab) {
      const red = await lab.bot('tr');
      const black = await lab.bot('tk');
      red.createRoom(600); // 600ms each — red is on move and will time out
      const created = await red.waitType('room-created');
      black.joinRoom(created.roomId as string);
      await red.waitType('game-start');
      await black.waitType('game-start');

      const ended = await red.waitType('game-ended', 3000);
      assert(ended.reason === 'timeout', `expected timeout, got ${ended.reason}`);
      assert(ended.result === 'black-win', `red on clock loses, got ${ended.result}`);
      lab.assertHealthy('after timeout');
    },
  },

  {
    name: 'rematch: decline then a fresh mutual offer restarts',
    why: 'Declining clears offers; a later mutual offer must still start a new game with rematch=true.',
    async run(lab) {
      const a = await lab.bot('ra');
      const b = await lab.bot('rb');
      a.createRoom();
      const created = await a.waitType('room-created');
      b.joinRoom(created.roomId as string);
      await a.waitType('game-start');
      await b.waitType('game-start');

      a.resign();
      await a.waitType('game-ended');
      await b.waitType('game-ended');

      a.offerRematch();
      await b.waitType('rematch-offered');
      b.declineRematch();
      await a.waitType('rematch-declined');

      // Fresh mutual offer → restart.
      a.offerRematch();
      await b.waitType('rematch-offered');
      b.offerRematch();
      const rs = await a.waitType('game-start');
      assert(rs.rematch === true, 'rematch game-start carries rematch=true');
      await b.waitType('game-start');
      lab.assertHealthy('after rematch restart');
    },
  },
];

// Re-export so the runner can show invariant rules in its report header.
export { checkInvariants };
