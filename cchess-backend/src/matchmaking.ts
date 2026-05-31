// Step A3: simple FIFO matchmaking queue.
//
// MVP: pair the 2 longest-waiting players regardless of ELO. Production
// would bucket by rating band and widen tolerance over wait time.

import type { WebSocket } from 'ws';

export interface QueueEntry {
  socket: WebSocket;
  uid: string;
  joinedAt: number;
  /// Preferred initial clock per side (ms). The PAIRED room uses the
  /// first matched player's preference (or default if both absent).
  clockMs?: number;
  /// Current ELO rating for bucket matchmaking (fetched from Firestore).
  /// Defaults to 1000 if user doc is missing eloChess field.
  elo: number;
}

const queue = new Map<WebSocket, QueueEntry>();

/// ELO bucket pairing constants.
/// Base tolerance ±100 widens by 50 per 30s of waiting. So:
///   waited 0s   → tolerance 100
///   waited 30s  → tolerance 150
///   waited 60s  → tolerance 200
///   waited 5min → tolerance 600 (almost anyone)
const BASE_TOLERANCE = 100;
const TOLERANCE_STEP = 50;
const STEP_INTERVAL_MS = 30_000;

export function enqueue(
  socket: WebSocket,
  uid: string,
  elo: number,
  clockMs?: number,
): number {
  if (queue.has(socket)) return queue.size;
  queue.set(socket, { socket, uid, joinedAt: Date.now(), clockMs, elo });
  return queue.size;
}

export function dequeue(socket: WebSocket): boolean {
  return queue.delete(socket);
}

export function queueSize(): number {
  return queue.size;
}

/// Try to pair 2 players whose ELO falls within an expanding tolerance window.
/// The tolerance grows with wait time so very long-waiting players will
/// eventually match against almost anyone.
///
/// Algorithm: O(N²) over current queue — fine for prototype (queue rarely
/// > 100). Production should bucket by rating band.
export function tryMatch(): [QueueEntry, QueueEntry] | null {
  if (queue.size < 2) return null;
  const now = Date.now();
  const entries = [...queue.values()];

  // Sort by joinedAt ASC so longest-waiting player is checked first.
  entries.sort((a, b) => a.joinedAt - b.joinedAt);

  for (let i = 0; i < entries.length; i++) {
    const a = entries[i];
    const waitA = now - a.joinedAt;
    const toleranceA =
      BASE_TOLERANCE + Math.floor(waitA / STEP_INTERVAL_MS) * TOLERANCE_STEP;
    let best: { entry: QueueEntry; diff: number } | null = null;
    for (let j = 0; j < entries.length; j++) {
      if (i === j) continue;
      const b = entries[j];
      if (a.uid === b.uid) continue; // can't match against yourself
      const waitB = now - b.joinedAt;
      const toleranceB =
        BASE_TOLERANCE + Math.floor(waitB / STEP_INTERVAL_MS) * TOLERANCE_STEP;
      // Use the tighter constraint — both sides must agree they're a fair match.
      const tolerance = Math.min(toleranceA, toleranceB);
      const diff = Math.abs(a.elo - b.elo);
      if (diff <= tolerance && (best === null || diff < best.diff)) {
        best = { entry: b, diff };
      }
    }
    if (best !== null) {
      queue.delete(a.socket);
      queue.delete(best.entry.socket);
      return [a, best.entry];
    }
  }
  return null;
}

/// Compute the current tolerance for a given wait duration. Exported for
/// telemetry / logging.
export function toleranceForWait(waitedMs: number): number {
  return BASE_TOLERANCE + Math.floor(waitedMs / STEP_INTERVAL_MS) * TOLERANCE_STEP;
}

/// Snapshot for debugging.
export function queueSnapshot(): { uid: string; waitedMs: number; clockMs?: number }[] {
  const now = Date.now();
  return [...queue.values()].map((e) => ({
    uid: e.uid,
    waitedMs: now - e.joinedAt,
    clockMs: e.clockMs,
  }));
}
