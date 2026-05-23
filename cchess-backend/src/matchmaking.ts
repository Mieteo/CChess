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
}

const queue = new Map<WebSocket, QueueEntry>();

export function enqueue(
  socket: WebSocket,
  uid: string,
  clockMs?: number,
): number {
  if (queue.has(socket)) return queue.size;
  queue.set(socket, { socket, uid, joinedAt: Date.now(), clockMs });
  return queue.size;
}

export function dequeue(socket: WebSocket): boolean {
  return queue.delete(socket);
}

export function queueSize(): number {
  return queue.size;
}

/// Try to pair the 2 longest-waiting players. Removes them from queue.
/// Returns null if fewer than 2 in queue OR if it's the same uid in both
/// slots (would be solo matchmaking which is nonsense).
export function tryMatch(): [QueueEntry, QueueEntry] | null {
  if (queue.size < 2) return null;
  const entries = [...queue.values()];
  // FIFO: take oldest two (queue iteration preserves insertion order).
  const [a, b] = entries;
  if (a.uid === b.uid) {
    // Same Firebase user trying to match against themselves — keep both in
    // queue, return null. They need to either log out / use second account.
    // (Solo testing should use create-room/join-room instead.)
    return null;
  }
  queue.delete(a.socket);
  queue.delete(b.socket);
  return [a, b];
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
