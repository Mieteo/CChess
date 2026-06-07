import { EngineServiceError, type EngineFeature } from './types';

export interface QuotaLimits {
  bestMovePerDay: number;
  hintPerDay: number;
  analyzePerDay: number;
}

interface UsageBucket {
  day: string;
  counts: Record<EngineFeature, number>;
}

export class DailyQuotaStore {
  private readonly buckets = new Map<string, UsageBucket>();

  constructor(private readonly limits: QuotaLimits) {}

  check(uid: string, feature: EngineFeature, vip: boolean): void {
    if (vip) return;
    const limit = this.limitFor(feature);
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

  private limitFor(feature: EngineFeature): number {
    switch (feature) {
      case 'best-move':
        return this.limits.bestMovePerDay;
      case 'hint':
        return this.limits.hintPerDay;
      case 'analyze':
        return this.limits.analyzePerDay;
    }
  }
}

function dayKey(date: Date): string {
  return date.toISOString().slice(0, 10);
}
