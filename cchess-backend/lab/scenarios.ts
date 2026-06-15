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
];

// Re-export so the runner can show invariant rules in its report header.
export { checkInvariants };
