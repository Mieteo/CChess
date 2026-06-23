import assert from 'node:assert/strict';
import { test } from 'node:test';

import type { Firestore } from 'firebase-admin/firestore';

import { createFirestoreVipChecker, FirestoreQuotaStore } from './firestore_quota';
import { DailyQuotaStore } from './quota';
import { EngineServiceError } from './types';

// ── Minimal in-memory Firestore fake ────────────────────────────────────────
// Only the surface FirestoreQuotaStore / the VIP checker actually touch:
// collection().doc() chaining, runTransaction(get/set), and doc().get().
// Docs are stored by their full slash path so a fresh store instance reading the
// same fake sees prior writes — i.e. it models persistence across a restart.

class FakeSnap {
  constructor(private readonly _data: Record<string, unknown> | undefined) {}
  get exists(): boolean {
    return this._data !== undefined;
  }
  data(): Record<string, unknown> | undefined {
    return this._data;
  }
}

class FakeDocRef {
  constructor(
    readonly path: string,
    private readonly store: Map<string, Record<string, unknown>>,
  ) {}
  collection(name: string): FakeCollectionRef {
    return new FakeCollectionRef(`${this.path}/${name}`, this.store);
  }
  async get(): Promise<FakeSnap> {
    return new FakeSnap(this.store.get(this.path));
  }
}

class FakeCollectionRef {
  constructor(
    readonly path: string,
    private readonly store: Map<string, Record<string, unknown>>,
  ) {}
  doc(id: string): FakeDocRef {
    return new FakeDocRef(`${this.path}/${id}`, this.store);
  }
}

class FakeTransaction {
  constructor(private readonly store: Map<string, Record<string, unknown>>) {}
  async get(ref: FakeDocRef): Promise<FakeSnap> {
    return new FakeSnap(this.store.get(ref.path));
  }
  set(
    ref: FakeDocRef,
    data: Record<string, unknown>,
    options?: { merge?: boolean },
  ): FakeTransaction {
    const base = options?.merge ? (this.store.get(ref.path) ?? {}) : {};
    this.store.set(ref.path, { ...base, ...data });
    return this;
  }
}

class FakeFirestore {
  readonly store = new Map<string, Record<string, unknown>>();
  collection(name: string): FakeCollectionRef {
    return new FakeCollectionRef(name, this.store);
  }
  async runTransaction<T>(fn: (tx: FakeTransaction) => Promise<T>): Promise<T> {
    return fn(new FakeTransaction(this.store));
  }
  seedUser(uid: string, data: Record<string, unknown>): void {
    this.store.set(`users/${uid}`, data);
  }
}

function asDb(fake: FakeFirestore): () => Firestore {
  return () => fake as unknown as Firestore;
}

const isQuotaExceeded = (e: unknown): boolean =>
  e instanceof EngineServiceError && e.code === 'quota-exceeded' && e.statusCode === 429;

// ── FirestoreQuotaStore ─────────────────────────────────────────────────────

test('FirestoreQuotaStore enforces the daily limit and survives a "restart"', async () => {
  const db = new FakeFirestore();
  const getDb = asDb(db);
  const limits = { bestMovePerDay: 5, hintPerDay: 2, analyzePerDay: 5 };

  const before = new FirestoreQuotaStore(limits, { getDb });
  await before.check('u1', 'hint', false); // 1
  await before.check('u1', 'hint', false); // 2
  await assert.rejects(() => before.check('u1', 'hint', false), isQuotaExceeded);

  // A brand-new store instance (process restarted) reading the same Firestore
  // still sees the exhausted quota — this is the whole point of persisting it.
  const afterRestart = new FirestoreQuotaStore(limits, { getDb });
  await assert.rejects(() => afterRestart.check('u1', 'hint', false), isQuotaExceeded);

  // A different feature keeps its own counter.
  await afterRestart.check('u1', 'best-move', false);
});

test('FirestoreQuotaStore resets per UTC day', async () => {
  const db = new FakeFirestore();
  const getDb = asDb(db);
  const limits = { bestMovePerDay: 1, hintPerDay: 1, analyzePerDay: 1 };

  let now = new Date('2026-06-23T10:00:00.000Z');
  const store = new FirestoreQuotaStore(limits, { getDb, now: () => now });
  await store.check('u1', 'hint', false);
  await assert.rejects(() => store.check('u1', 'hint', false), isQuotaExceeded);

  now = new Date('2026-06-24T00:01:00.000Z'); // next day → fresh bucket doc
  await store.check('u1', 'hint', false);
});

test('FirestoreQuotaStore never limits VIPs and writes nothing for them', async () => {
  const db = new FakeFirestore();
  const store = new FirestoreQuotaStore(
    { bestMovePerDay: 1, hintPerDay: 1, analyzePerDay: 1 },
    { getDb: asDb(db) },
  );
  for (let i = 0; i < 5; i++) await store.check('vip', 'hint', true);
  assert.equal(db.store.size, 0);
});

test('FirestoreQuotaStore falls back to an in-memory cap on Firestore error', async () => {
  const fallback = new DailyQuotaStore({ bestMovePerDay: 1, hintPerDay: 1, analyzePerDay: 1 });
  const store = new FirestoreQuotaStore(
    { bestMovePerDay: 1, hintPerDay: 1, analyzePerDay: 1 },
    {
      getDb: () => {
        throw new Error('firestore unavailable');
      },
      fallback,
    },
  );
  await store.check('u1', 'hint', false); // counted by the fallback
  await assert.rejects(() => store.check('u1', 'hint', false), isQuotaExceeded);
});

// ── createFirestoreVipChecker ───────────────────────────────────────────────

test('createFirestoreVipChecker reads isVip, honors expiry, and caches', async () => {
  const db = new FakeFirestore();
  db.seedUser('vipUser', { isVip: true, vipExpiresAt: null });
  db.seedUser('freeUser', { isVip: false });
  db.seedUser('expired', { isVip: true, vipExpiresAt: new Date(1000) });

  let nowMs = 5000;
  const isVip = createFirestoreVipChecker({
    getDb: asDb(db),
    now: () => nowMs,
    cacheTtlMs: 100,
  });

  assert.equal(await isVip('vipUser'), true);
  assert.equal(await isVip('freeUser'), false);
  assert.equal(await isVip('expired'), false); // expiry 1000ms < now 5000ms

  // Within the cache TTL, a doc change is not yet observed.
  db.seedUser('freeUser', { isVip: true, vipExpiresAt: null });
  assert.equal(await isVip('freeUser'), false);

  // Past the TTL, the next read refreshes.
  nowMs += 200;
  assert.equal(await isVip('freeUser'), true);
});

test('createFirestoreVipChecker degrades to non-VIP on Firestore error', async () => {
  const isVip = createFirestoreVipChecker({
    getDb: () => {
      throw new Error('firestore unavailable');
    },
  });
  assert.equal(await isVip('whoever'), false);
});
