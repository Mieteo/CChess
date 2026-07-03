import { randomUUID } from 'node:crypto';

import { analyzeGame, type BestMoveResolver } from './analysis';
import {
  EngineServiceError,
  type AnalyzeJobSnapshot,
  type AnalyzeJobStatus,
  type EngineAnalyzeMove,
  type EngineAnalyzeResult,
  type EngineLimit,
} from './types';

interface AnalyzeJob {
  jobId: string;
  uid: string;
  status: AnalyzeJobStatus;
  totalMoves: number;
  perMove: EngineAnalyzeMove[];
  summary?: EngineAnalyzeResult['summary'];
  error?: { code: string; message: string };
  createdAt: number;
  finishedAt?: number;
}

export interface AnalyzeJobStoreOptions {
  /** How long finished jobs stay pollable. */
  ttlMs?: number;
  /** Max queued+running jobs across all users (each job is a long engine
   * grind; the pool serializes the actual searches anyway). */
  maxActiveJobs?: number;
  now?: () => number;
}

/**
 * In-memory store for async analysis jobs.
 *
 * Deliberately not persisted: a job is minutes of engine work tied to one
 * process's EnginePool — after a restart the client simply resubmits (quota
 * is charged at submit, which also survives restarts via FirestoreQuotaStore).
 */
export class AnalyzeJobStore {
  constructor(private readonly options: AnalyzeJobStoreOptions = {}) {}

  private readonly jobs = new Map<string, AnalyzeJob>();

  private get ttlMs(): number {
    return this.options.ttlMs ?? 10 * 60_000;
  }

  private get maxActiveJobs(): number {
    return this.options.maxActiveJobs ?? 4;
  }

  private now(): number {
    return this.options.now ? this.options.now() : Date.now();
  }

  /** Register a new job. One live job per user; small global cap. */
  create(uid: string, totalMoves: number): AnalyzeJobSnapshot {
    this.sweep();
    const active = [...this.jobs.values()].filter(
      (job) => job.status === 'queued' || job.status === 'running',
    );
    if (active.some((job) => job.uid === uid)) {
      throw new EngineServiceError(
        409,
        'job-exists',
        'An analysis job is already running for this user',
      );
    }
    if (active.length >= this.maxActiveJobs) {
      throw new EngineServiceError(
        503,
        'jobs-busy',
        'Analysis workers are busy — try again shortly',
      );
    }
    const job: AnalyzeJob = {
      jobId: randomUUID(),
      uid,
      status: 'queued',
      totalMoves,
      perMove: [],
      createdAt: this.now(),
    };
    this.jobs.set(job.jobId, job);
    return this.snapshot(job);
  }

  /** Remove a job that never started (e.g. its quota check failed). */
  discard(jobId: string): void {
    this.jobs.delete(jobId);
  }

  /** Owner-scoped read; a foreign uid gets the same 404 as a bogus id. */
  get(jobId: string, uid: string): AnalyzeJobSnapshot {
    this.sweep();
    const job = this.jobs.get(jobId);
    if (!job || job.uid !== uid) {
      throw new EngineServiceError(404, 'job-not-found', 'Unknown analysis job');
    }
    return this.snapshot(job);
  }

  /** Execute the analysis for a created job, recording progress into it. */
  async run(
    jobId: string,
    startingFen: string,
    moveUcis: string[],
    limit: EngineLimit,
    resolveBestMove: BestMoveResolver,
  ): Promise<void> {
    const job = this.jobs.get(jobId);
    if (!job) return; // swept while queued — nothing to record into
    job.status = 'running';
    try {
      const result = await analyzeGame(
        startingFen,
        moveUcis,
        limit,
        resolveBestMove,
        (progress) => {
          job.perMove.push(progress.latest);
        },
      );
      job.perMove = result.perMove;
      job.summary = result.summary;
      job.status = 'done';
    } catch (error) {
      job.status = 'error';
      job.error =
        error instanceof EngineServiceError
          ? { code: error.code, message: error.expose ? error.message : 'Engine error' }
          : { code: 'internal-error', message: error instanceof Error ? error.message : String(error) };
    } finally {
      job.finishedAt = this.now();
    }
  }

  private snapshot(job: AnalyzeJob): AnalyzeJobSnapshot {
    return {
      jobId: job.jobId,
      status: job.status,
      totalMoves: job.totalMoves,
      completedMoves: job.perMove.length,
      progress:
        job.status === 'done'
          ? 1
          : job.totalMoves === 0
            ? 0
            : Math.min(0.99, job.perMove.length / job.totalMoves),
      perMove: [...job.perMove],
      summary: job.summary,
      error: job.error,
    };
  }

  private sweep(): void {
    const cutoff = this.now();
    for (const [jobId, job] of this.jobs) {
      const finishedExpired =
        job.finishedAt !== undefined && cutoff - job.finishedAt > this.ttlMs;
      // Safety net: no job legitimately lives longer than 30 minutes.
      const stale = cutoff - job.createdAt > 30 * 60_000;
      if (finishedExpired || stale) this.jobs.delete(jobId);
    }
  }
}
