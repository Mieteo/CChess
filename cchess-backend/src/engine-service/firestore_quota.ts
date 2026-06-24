// Persistent quota + VIP gating for the engine service.
//
// Why this exists: the in-memory DailyQuotaStore (quota.ts) loses every counter
// when the Render process restarts/redeploys, so a free user could reset their
// daily allowance just by waiting for a cold start. FirestoreQuotaStore counts
// usage in Firestore (`users/{uid}/engine_usage/{YYYY-MM-DD}`) inside a
// transaction, so the cap survives restarts and is shared across instances.
//
// VIP is read from the same `users/{uid}` doc the app/Cloud Functions already
// maintain (`isVip` + `vipExpiresAt`). createFirestoreVipChecker caches results
// briefly so we don't hit Firestore on every engine call.
//
// Both are fail-safe: a Firestore outage must not break the AI features. The
// quota store falls back to an in-memory cap; the VIP checker degrades to the
// free tier. Neither ever hands out unlimited free usage on error.

import { getFirestore, type Firestore } from 'firebase-admin/firestore';

import {
  buildQuotaStatus,
  DailyQuotaStore,
  dayKey,
  limitFor,
  type QuotaLimits,
  type QuotaStatus,
  type QuotaStore,
} from './quota';
import { EngineServiceError, type EngineFeature } from './types';

export interface FirestoreQuotaOptions {
  /// Lazily resolves the Firestore handle (default: firebase-admin getFirestore).
  /// Injected in tests with a fake.
  getDb?: () => Firestore;
  /// Used when Firestore itself errors (network/permission). Default: an
  /// in-memory DailyQuotaStore so a cap stays in place during an outage.
  fallback?: QuotaStore;
  /// Clock seam for deterministic tests.
  now?: () => Date;
  /// Daily usage docs are stamped with `expireAt = now + ttlDays` so a Firestore
  /// TTL policy can garbage-collect old days. Default 3 days.
  ttlDays?: number;
}

export class FirestoreQuotaStore implements QuotaStore {
  private readonly getDb: () => Firestore;
  private readonly fallback: QuotaStore;
  private readonly now: () => Date;
  private readonly ttlMs: number;

  constructor(private readonly limits: QuotaLimits, opts: FirestoreQuotaOptions = {}) {
    this.getDb = opts.getDb ?? (() => getFirestore());
    this.fallback = opts.fallback ?? new DailyQuotaStore(limits);
    this.now = opts.now ?? (() => new Date());
    this.ttlMs = (opts.ttlDays ?? 3) * 86_400_000;
  }

  async check(uid: string, feature: EngineFeature, vip: boolean): Promise<void> {
    if (vip) return;
    const limit = limitFor(this.limits, feature);
    const now = this.now();
    const day = dayKey(now);
    try {
      await this.consume(uid, feature, day, limit, now);
    } catch (error) {
      // A genuine over-limit is a quota-exceeded EngineServiceError — propagate it.
      if (error instanceof EngineServiceError) throw error;
      // Anything else is an infra problem. Fail open onto the in-memory cap so a
      // transient Firestore outage doesn't break hints/analysis for everyone,
      // while still preventing unbounded free usage.
      console.error(`[quota] firestore error for ${uid}/${feature}, using memory fallback:`, error);
      await this.fallback.check(uid, feature, vip);
    }
  }

  async status(uid: string, vip: boolean): Promise<QuotaStatus> {
    const day = dayKey(this.now());
    try {
      const ref = this.getDb()
        .collection('users')
        .doc(uid)
        .collection('engine_usage')
        .doc(day);
      const snap = await ref.get();
      const data = (snap.exists ? snap.data() : undefined) ?? {};
      return buildQuotaStatus(day, vip, this.limits, (feature) => {
        const raw = data[feature];
        return typeof raw === 'number' ? raw : 0;
      });
    } catch (error) {
      // A read failure must not break the screen — degrade to the in-memory
      // counter (which on a cold instance just reports a full allowance).
      console.error(`[quota] firestore status read failed for ${uid}, using fallback:`, error);
      return this.fallback.status(uid, vip);
    }
  }

  private async consume(
    uid: string,
    feature: EngineFeature,
    day: string,
    limit: number,
    now: Date,
  ): Promise<void> {
    const ref = this.getDb()
      .collection('users')
      .doc(uid)
      .collection('engine_usage')
      .doc(day);

    await this.getDb().runTransaction(async (tx) => {
      const snap = await tx.get(ref);
      const data = (snap.exists ? snap.data() : undefined) ?? {};
      const raw = data[feature];
      const used = typeof raw === 'number' ? raw : 0;
      if (used >= limit) {
        throw new EngineServiceError(429, 'quota-exceeded', 'Daily engine quota exceeded');
      }
      tx.set(
        ref,
        {
          day,
          [feature]: used + 1,
          updatedAt: now,
          expireAt: new Date(now.getTime() + this.ttlMs),
        },
        { merge: true },
      );
    });
  }
}

export interface VipCheckerOptions {
  getDb?: () => Firestore;
  /// How long a VIP lookup is cached per uid. Default 60s.
  cacheTtlMs?: number;
  now?: () => number;
}

/// Returns an `isVip(uid)` reader backed by `users/{uid}.isVip` + `vipExpiresAt`,
/// with a short per-uid cache to avoid a Firestore read on every engine call.
/// On a Firestore error it degrades to the free tier (returns the last cached
/// value or false) rather than throwing.
export function createFirestoreVipChecker(
  opts: VipCheckerOptions = {},
): (uid: string) => Promise<boolean> {
  const getDb = opts.getDb ?? (() => getFirestore());
  const cacheTtlMs = opts.cacheTtlMs ?? 60_000;
  const now = opts.now ?? (() => Date.now());
  const cache = new Map<string, { value: boolean; at: number }>();

  return async (uid: string): Promise<boolean> => {
    const t = now();
    const cached = cache.get(uid);
    if (cached && t - cached.at < cacheTtlMs) return cached.value;
    try {
      const snap = await getDb().collection('users').doc(uid).get();
      const data = (snap.exists ? snap.data() : undefined) ?? {};
      const value = isVipData(data, t);
      cache.set(uid, { value, at: t });
      return value;
    } catch (error) {
      console.error(`[vip] firestore error for ${uid}, defaulting to non-VIP:`, error);
      return cached?.value ?? false;
    }
  };
}

function isVipData(data: Record<string, unknown>, nowMs: number): boolean {
  if (data.isVip !== true) return false;
  const expires = toMillis(data.vipExpiresAt);
  // No expiry recorded → treat the flag as authoritative; otherwise honor it.
  return expires === null || expires > nowMs;
}

function toMillis(value: unknown): number | null {
  if (value === null || value === undefined) return null;
  if (typeof value === 'number') return value;
  if (value instanceof Date) return value.getTime();
  if (typeof (value as { toMillis?: unknown }).toMillis === 'function') {
    return (value as { toMillis: () => number }).toMillis();
  }
  return null;
}
