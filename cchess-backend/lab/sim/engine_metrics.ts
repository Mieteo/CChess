export type EngineFailureReason =
  | 'config'
  | 'concurrency'
  | 'http'
  | 'invalid-response'
  | 'illegal-move'
  | 'network'
  | 'timeout';

export interface EngineMetricRecord {
  ok: boolean;
  fallback: boolean;
  latencyMs: number;
  cached?: boolean;
  reason?: EngineFailureReason;
  status?: number;
  code?: string;
  message?: string;
}

export interface EngineLatencySummary {
  avgMs: number;
  p50Ms: number;
  p95Ms: number;
  maxMs: number;
}

export interface EngineMetricsSummary {
  attempts: number;
  httpCalls: number;
  successes: number;
  errors: number;
  timeouts: number;
  fallbacks: number;
  cacheHits: number;
  cacheMisses: number;
  concurrencyFallbacks: number;
  illegalMoves: number;
  errorRate: number;
  latency: EngineLatencySummary;
  lastError?: EngineMetricRecord;
}

export class EngineMetrics {
  private readonly records: EngineMetricRecord[] = [];

  constructor(private readonly onRecord?: (record: EngineMetricRecord) => void) {}

  record(record: EngineMetricRecord): void {
    this.records.push(record);
    this.onRecord?.(record);
  }

  snapshot(): EngineMetricsSummary {
    const attempts = this.records.length;
    const httpRecords = this.records.filter((record) => record.reason !== 'concurrency' && record.reason !== 'config');
    const latencies = httpRecords.map((record) => record.latencyMs).sort((a, b) => a - b);
    const errors = this.records.filter((record) => !record.ok).length;
    const lastError = [...this.records].reverse().find((record) => !record.ok);
    return {
      attempts,
      httpCalls: httpRecords.length,
      successes: this.records.filter((record) => record.ok).length,
      errors,
      timeouts: this.records.filter((record) => record.reason === 'timeout').length,
      fallbacks: this.records.filter((record) => record.fallback).length,
      cacheHits: this.records.filter((record) => record.cached === true).length,
      cacheMisses: this.records.filter((record) => record.cached === false).length,
      concurrencyFallbacks: this.records.filter((record) => record.reason === 'concurrency').length,
      illegalMoves: this.records.filter((record) => record.reason === 'illegal-move').length,
      errorRate: attempts === 0 ? 0 : errors / attempts,
      latency: summarizeLatency(latencies),
      lastError,
    };
  }
}

export class EngineConcurrencyLimiter {
  private active = 0;

  constructor(private readonly maxConcurrency: number) {}

  tryAcquire(): (() => void) | null {
    if (this.active >= this.maxConcurrency) return null;
    this.active++;
    let released = false;
    return () => {
      if (released) return;
      released = true;
      this.active--;
    };
  }
}

function summarizeLatency(latencies: number[]): EngineLatencySummary {
  if (latencies.length === 0) return { avgMs: 0, p50Ms: 0, p95Ms: 0, maxMs: 0 };
  const sum = latencies.reduce((acc, value) => acc + value, 0);
  return {
    avgMs: Math.round(sum / latencies.length),
    p50Ms: percentile(latencies, 0.5),
    p95Ms: percentile(latencies, 0.95),
    maxMs: latencies[latencies.length - 1],
  };
}

function percentile(sorted: number[], p: number): number {
  const index = Math.min(sorted.length - 1, Math.max(0, Math.ceil(sorted.length * p) - 1));
  return sorted[index];
}
