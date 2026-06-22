import { debugRooms } from '../../src/rooms';
import { checkInvariants, type InvariantViolation } from '../invariants';

export interface MonitorSnapshot {
  roomsAfterDrain: number;
  violations: InvariantViolation[];
}

export class SimMonitor {
  snapshot(): MonitorSnapshot {
    return {
      roomsAfterDrain: debugRooms().length,
      violations: checkInvariants(),
    };
  }

  assertHealthy(label: string): void {
    const violations = checkInvariants();
    if (violations.length === 0) return;
    const detail = violations.map((v) => `[${v.rule}] ${v.detail}`).join('\n');
    throw new Error(`invariant violation at ${label}:\n${detail}`);
  }
}

