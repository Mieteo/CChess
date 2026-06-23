import { EngineServiceError, type EngineFeature } from './types';

export interface QuotaLimits {
  bestMovePerDay: number;
  hintPerDay: number;
  analyzePerDay: number;
}

/// Counts engine usage and enforces the free daily limit.
///
/// Abstraction so the HTTP server is agnostic about *where* usage is counted:
///   - `DailyQuotaStore` keeps counters in process memory (dev + outage fallback).
///   - `FirestoreQuotaStore` persists them so they survive Render restart/redeploy
///     (see firestore_quota.ts).
/// `check` resolves when the call is allowed (and records it), or throws
/// `EngineServiceError(429, 'quota-exceeded')` when the free daily limit for
/// `feature` is reached. VIP users are never limited.
export interface QuotaStore {
  check(uid: string, feature: EngineFeature, vip: boolean): Promise<void>;
}

interface UsageBucket {
  day: string;
  counts: Record<EngineFeature, number>;
}

/// In-memory daily quota — fast and dependency-free, but counters reset whenever
/// the process restarts. Used in dev/tests and as the fallback that keeps a cap
/// in place if the Firestore-backed store hits an infra error.
export class DailyQuotaStore implements QuotaStore {
  private readonly buckets = new Map<string, UsageBucket>();

  constructor(private readonly limits: QuotaLimits) {}

  async check(uid: string, feature: EngineFeature, vip: boolean): Promise<void> {
    if (vip) return;
    const limit = limitFor(this.limits, feature);
    const key = `${uid}:${feature}`;
    const today = dayKey(new Date());
    const bucket = this.buckets.get(key);
    if (!bucket || bucket.day !== today) {
      this.buckets.set(key, {
        day: today,
        counts: { 'best-move': 0, hint: 0, analyze: 0 },
      });
    }
    const current = this.buckets.get(key)!;
    const used = current.counts[feature];
    if (used >= limit) {
      throw new EngineServiceError(429, 'quota-exceeded', 'Daily engine quota exceeded');
    }
    current.counts[feature] = used + 1;
  }
}

export function limitFor(limits: QuotaLimits, feature: EngineFeature): number {
  switch (feature) {
    case 'best-move':
      return limits.bestMovePerDay;
    case 'hint':
      return limits.hintPerDay;
    case 'analyze':
      return limits.analyzePerDay;
  }
}

export function dayKey(date: Date): string {
  return date.toISOString().slice(0, 10);
}
