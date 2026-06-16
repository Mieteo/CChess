// Invariants the server's room/queue state must satisfy at every QUIESCENT
// point (after all expected messages for a step have been delivered). The
// scenario runner + fuzzer assert `checkInvariants()` is empty after each step;
// the dashboard surfaces violations live. This is the layer that turns a vague
// "state kẹt" complaint into a precise, machine-checked failure.
//
// The ghost-room bug that started all this is invariant #1 below: a 'playing'
// room with nobody connected and no grace pending is stuck forever.

import { debugRooms, debugSocketMapIssues, type RoomDebug } from '../src/rooms';
import { debugQueue } from '../src/matchmaking';

export interface InvariantViolation {
  rule: string;
  detail: string;
}

export function checkInvariants(): InvariantViolation[] {
  const v: InvariantViolation[] = [];
  const rooms = debugRooms();

  for (const r of rooms) {
    // 1. A 'playing' room with no connected players must have a grace window
    //    pending (someone can still reconnect). Otherwise nobody will ever
    //    tear it down → permanent ghost.
    if (r.status === 'playing' && r.members === 0 && r.graceUids.length === 0) {
      v.push({
        rule: 'playing-room-has-someone',
        detail: `room ${r.id} is 'playing' with 0 members and no grace — orphaned ghost`,
      });
    }

    // 2. No stale socket lingering in `members`: every counted member socket
    //    should be OPEN.
    if (r.membersOpen < r.members) {
      v.push({
        rule: 'no-stale-member-socket',
        detail: `room ${r.id} has ${r.members - r.membersOpen} non-open socket(s) in members`,
      });
    }

    // 3. A live game has both colors assigned.
    if (r.status === 'playing' && (!r.redUid || !r.blackUid)) {
      v.push({
        rule: 'playing-room-has-both-colors',
        detail: `room ${r.id} is 'playing' but redUid=${r.redUid} blackUid=${r.blackUid}`,
      });
    }

    // 4. A 'waiting' room always has its creator present (else it should have
    //    been deleted on the last leave).
    if (r.status === 'waiting' && r.members === 0) {
      v.push({
        rule: 'waiting-room-not-empty',
        detail: `room ${r.id} is 'waiting' with 0 members — should have been removed`,
      });
    }

    // 5. A 'finished' room with nobody attached must have been deleted by
    //    deleteRoomIfEmpty (endMatch calls it). Lingering == a leak.
    if (r.status === 'finished' && r.members === 0 && r.spectators === 0) {
      v.push({
        rule: 'finished-room-cleaned-up',
        detail: `room ${r.id} is 'finished' with no members/spectators — leaked`,
      });
    }

    // 6. Clock ticker only runs while playing.
    if (r.hasClockTimer && r.status !== 'playing') {
      v.push({
        rule: 'no-orphan-clock-timer',
        detail: `room ${r.id} keeps a clock timer while status='${r.status}'`,
      });
    }

    // 9. Each seat of a 'playing' room must have a live (OPEN) socket UNLESS
    //    that seat's player is currently inside the reconnect grace window.
    if (r.status === 'playing') {
      const redInGrace = r.graceColors.includes('red');
      if (r.redSocketOpen !== true && !redInGrace) {
        v.push({
          rule: 'playing-seat-live-or-grace',
          detail: `room ${r.id} red seat socket not OPEN and red not in grace`,
        });
      }
      const blackInGrace = r.graceColors.includes('black');
      if (r.blackSocketOpen !== true && !blackInGrace) {
        v.push({
          rule: 'playing-seat-live-or-grace',
          detail: `room ${r.id} black seat socket not OPEN and black not in grace`,
        });
      }
      // 10. A playing game has its clocks initialized.
      if (!r.hasClock) {
        v.push({
          rule: 'playing-room-has-clock',
          detail: `room ${r.id} is 'playing' but clockMsByColor is unset`,
        });
      }
    }

    // 11. Anyone in the grace window must actually be one of the two players.
    for (const g of r.graceUids) {
      if (g !== r.redUid && g !== r.blackUid) {
        v.push({
          rule: 'grace-uids-are-players',
          detail: `room ${r.id} has grace uid ${g} that is neither red nor black`,
        });
      }
    }

    // 12. The recorded move count must match the actual move list length.
    if (r.moveCount !== r.movesLen) {
      v.push({
        rule: 'move-count-consistent',
        detail: `room ${r.id} moveCount=${r.moveCount} but movesUci.length=${r.movesLen}`,
      });
    }
  }

  // 7. The two internal socket maps must agree.
  for (const issue of debugSocketMapIssues()) {
    v.push({ rule: 'socket-map-consistency', detail: issue });
  }

  // 8. No closed socket left stuck in the matchmaking queue.
  for (const q of debugQueue()) {
    if (!q.alive) {
      v.push({
        rule: 'no-dead-socket-in-queue',
        detail: `uid ${q.uid} is still queued but its socket is not OPEN`,
      });
    }
  }

  return v;
}

/// Compact one-object snapshot for the dashboard / logging.
export function snapshot(): {
  rooms: RoomDebug[];
  queue: ReturnType<typeof debugQueue>;
  violations: InvariantViolation[];
  ts: number;
} {
  return {
    rooms: debugRooms(),
    queue: debugQueue(),
    violations: checkInvariants(),
    ts: Date.now(),
  };
}
