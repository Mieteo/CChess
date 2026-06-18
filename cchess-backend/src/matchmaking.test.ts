// Step A3a (test-automation Phase A): unit tests for the ELO-aware matchmaking
// queue. Covers test-plan cases M1 (cùng tầm ELO được ghép) and M2 (nới
// tolerance theo thời gian chờ). Pure logic — no WebSocket server needed; we
// stub Date.now() to control each entry's wait time deterministically.

import assert from 'node:assert/strict';
import { afterEach, test } from 'node:test';
import type { WebSocket } from 'ws';

import {
  __resetQueueForLab,
  dequeue,
  enqueue,
  queueSize,
  toleranceForWait,
  tryMatch,
} from './matchmaking';

// Minimal fake socket — matchmaking only stores it and (for debugQueue) reads
// readyState, which tryMatch/enqueue/dequeue never touch.
let socketSeq = 0;
function fakeSocket(): WebSocket {
  return { __mm: ++socketSeq } as unknown as WebSocket;
}

const realNow = Date.now;
/// Pin the clock so enqueue() stamps a known joinedAt; advance via setNow().
function setNow(ms: number): void {
  Date.now = () => ms;
}

afterEach(() => {
  Date.now = realNow;
  __resetQueueForLab();
});

test('toleranceForWait widens by 50 every 30s on top of a 100 base', () => {
  assert.equal(toleranceForWait(0), 100);
  assert.equal(toleranceForWait(29_999), 100); // still in the first window
  assert.equal(toleranceForWait(30_000), 150);
  assert.equal(toleranceForWait(60_000), 200);
  assert.equal(toleranceForWait(5 * 60_000), 600); // ~anyone after 5 min
});

test('enqueue is idempotent per socket and dequeue removes it', () => {
  const s = fakeSocket();
  assert.equal(enqueue(s, 'u1', 1000), 1);
  assert.equal(enqueue(s, 'u1', 1000), 1, 're-enqueue same socket is a no-op');
  assert.equal(queueSize(), 1);
  assert.equal(dequeue(s), true);
  assert.equal(queueSize(), 0);
  assert.equal(dequeue(s), false, 'dequeue of an absent socket returns false');
});

test('M1: two players within base tolerance pair immediately', () => {
  setNow(1_000_000);
  enqueue(fakeSocket(), 'a', 1000);
  enqueue(fakeSocket(), 'b', 1050); // diff 50 <= 100

  const pair = tryMatch();
  assert.ok(pair, 'should pair');
  assert.deepEqual([pair![0].uid, pair![1].uid].sort(), ['a', 'b']);
  assert.equal(queueSize(), 0, 'both paired players leave the queue');
});

test('players outside the current tolerance do NOT pair', () => {
  setNow(1_000_000);
  enqueue(fakeSocket(), 'a', 1000);
  enqueue(fakeSocket(), 'b', 1400); // diff 400 > 100 at wait 0

  assert.equal(tryMatch(), null);
  assert.equal(queueSize(), 2, 'unmatched players stay queued');
});

test('M2: a wide-ELO pair becomes matchable once both have waited long enough', () => {
  // Enqueue both at t0 with a 400-point gap (needs tolerance >= 400 → 3 min).
  setNow(1_000_000);
  enqueue(fakeSocket(), 'a', 1000);
  enqueue(fakeSocket(), 'b', 1400);
  assert.equal(tryMatch(), null, 'no match before tolerance grows');

  // Advance just shy of the 3-min boundary: floor(179999/30000)*50+100 = 350.
  setNow(1_000_000 + 179_999);
  assert.equal(tryMatch(), null, 'tolerance 350 still < 400');

  // At 3 min: floor(180000/30000)=6 → tolerance 100+300 = 400 >= 400.
  setNow(1_000_000 + 180_000);
  const pair = tryMatch();
  assert.ok(pair, 'should pair once tolerance reaches the gap');
  assert.deepEqual([pair![0].uid, pair![1].uid].sort(), ['a', 'b']);
});

test('a player is never matched against another socket sharing its uid', () => {
  setNow(1_000_000);
  enqueue(fakeSocket(), 'same', 1000);
  enqueue(fakeSocket(), 'same', 1000); // same uid (two devices / two sockets)

  assert.equal(tryMatch(), null, 'cannot self-match across two sockets');
  assert.equal(queueSize(), 2);
});

test('the longest-waiting player is paired with the closest-ELO opponent', () => {
  // 'a' waits longest; both 'b' (diff 100) and 'c' (diff 50) are in range.
  setNow(1_000_000);
  enqueue(fakeSocket(), 'a', 1000);
  setNow(1_000_500);
  enqueue(fakeSocket(), 'b', 1100); // diff 100
  setNow(1_001_000);
  enqueue(fakeSocket(), 'c', 1050); // diff 50 — closer

  setNow(1_001_500);
  const pair = tryMatch();
  assert.ok(pair);
  const uids = [pair![0].uid, pair![1].uid];
  assert.ok(uids.includes('a'), 'longest-waiting player is matched first');
  assert.ok(uids.includes('c'), 'paired with the closest-ELO opponent, not b');
  assert.equal(queueSize(), 1, 'b remains queued');
});
