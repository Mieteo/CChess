import { EngineServiceError, type EngineFeature } from './types';

export interface QuotaLimits {
  bestMovePerDay: number;
  hintPerDay: number;
  analyzePerDay: number;
}

/// How much of one feature's free daily allowance is left. `limit`/`remaining`
/// are -1 for VIP users to signal "unlimited" without inventing a magic cap.
export interface FeatureUsage {
  used: number;
  limit: number;
  remaining: number;
}

/// A read-only snapshot of a user's free-tier engine usage for today, served by
/// `GET /engine/quota` so the app can show "N hints left" and a VIP upsell
/// *before* a request is rejected with 429.
export interface QuotaStatus {
  day: string;
  vip: boolean;
  features: Record<EngineFeature, FeatureUsage>;
}

const ALL_FEATURES: readonly EngineFeature[] = ['best-move', 'hint', 'analyze'];

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
  /// Reads today's usage without consuming any allowance (for GET /engine/quota).
  status(uid: string, vip: boolean): Promise<QuotaStatus>;
}

/// Build a FeatureUsage from a raw count. VIP → unlimited (-1 sentinels).
export function featureUsage(used: number, limit: number, vip: boolean): FeatureUsage {
  if (vip) return { used, limit: -1, remaining: -1 };
  return { used, limit, remaining: Math.max(0, limit - used) };
}

/// Assemble a QuotaStatus from a per-feature count lookup. Shared by both stores.
export function buildQuotaStatus(
  day: string,
  vip: boolean,
  limits: QuotaLimits,
  usedFor: (feature: EngineFeature) => number,
): QuotaStatus {
  const features = {} as Record<EngineFeature, FeatureUsage>;
  for (const feature of ALL_FEATURES) {
    features[feature] = featureUsage(usedFor(feature), limitFor(limits, feature), vip);
  }
  return { day, vip, features };
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

  async status(uid: string, vip: boolean): Promise<QuotaStatus> {
    const today = dayKey(new Date());
    return buildQuotaStatus(today, vip, this.limits, (feature) => {
      const bucket = this.buckets.get(`${uid}:${feature}`);
      return bucket && bucket.day === today ? bucket.counts[feature] : 0;
    });
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
