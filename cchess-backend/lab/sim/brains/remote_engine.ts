import type { MoveContext, MovePolicy } from '../brain';
import {
  EngineConcurrencyLimiter,
  EngineMetrics,
  type EngineFailureReason,
} from '../engine_metrics';
import { gameFromHistory, isCorrectTurn, legalMovesForTurn, legalUciSet } from './helpers';
import { HeuristicPolicy } from './heuristic';

export interface RemoteEnginePolicyOptions {
  baseUrl?: string;
  authToken?: string;
  endpoint?: '/engine/best-move' | '/engine/hint';
  timeoutMs?: number;
  movetimeMs?: number;
  level?: string;
  fallback?: MovePolicy;
  limiter?: EngineConcurrencyLimiter;
  metrics?: EngineMetrics;
}

interface EngineBestMoveResponse {
  uci?: unknown;
  cached?: unknown;
  code?: unknown;
  message?: unknown;
}

export class RemoteEnginePolicy implements MovePolicy {
  readonly name = 'remote-engine';

  private readonly baseUrl?: string;
  private readonly authToken?: string;
  private readonly endpoint: '/engine/best-move' | '/engine/hint';
  private readonly timeoutMs: number;
  private readonly movetimeMs: number;
  private readonly level?: string;
  private readonly fallback: MovePolicy;
  private readonly limiter: EngineConcurrencyLimiter;
  private readonly metrics: EngineMetrics;

  constructor(options: RemoteEnginePolicyOptions = {}) {
    this.baseUrl = normalizeBaseUrl(options.baseUrl);
    this.authToken = options.authToken;
    this.endpoint = options.endpoint ?? '/engine/best-move';
    this.timeoutMs = options.timeoutMs ?? 1200;
    this.movetimeMs = options.movetimeMs ?? 250;
    this.level = options.level;
    this.fallback = options.fallback ?? new HeuristicPolicy();
    this.limiter = options.limiter ?? new EngineConcurrencyLimiter(2);
    this.metrics = options.metrics ?? new EngineMetrics();
  }

  async chooseMove(ctx: MoveContext): Promise<string | null> {
    const game = gameFromHistory(ctx);
    if (!isCorrectTurn(game, ctx.color)) return null;
    if (legalMovesForTurn(game).length === 0) return null;

    if (!this.baseUrl) {
      this.metrics.record({
        ok: false,
        fallback: true,
        latencyMs: 0,
        reason: 'config',
        message: 'engine URL is not configured',
      });
      return this.fallback.chooseMove(ctx);
    }

    const release = this.limiter.tryAcquire();
    if (!release) {
      this.metrics.record({
        ok: false,
        fallback: true,
        latencyMs: 0,
        reason: 'concurrency',
        message: 'engine concurrency limit reached',
      });
      return this.fallback.chooseMove(ctx);
    }

    const startedAt = Date.now();
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), this.timeoutMs);

    try {
      const res = await fetch(`${this.baseUrl}${this.endpoint}`, {
        method: 'POST',
        headers: this.headers(),
        body: JSON.stringify({
          fen: game.toFen(),
          movetimeMs: this.movetimeMs,
          ...(this.level ? { level: this.level } : {}),
        }),
        signal: controller.signal,
      });
      const latencyMs = Date.now() - startedAt;
      const body = await readJsonBody(res);
      if (!res.ok) {
        this.recordFailure('http', latencyMs, body, res.status);
        return this.fallback.chooseMove(ctx);
      }

      const uci = typeof body.uci === 'string' ? body.uci : null;
      if (!uci) {
        this.recordFailure('invalid-response', latencyMs, body, res.status);
        return this.fallback.chooseMove(ctx);
      }

      const legal = legalUciSet(game);
      if (!legal.has(uci)) {
        this.recordFailure('illegal-move', latencyMs, body, res.status, `engine returned illegal move ${uci}`);
        return this.fallback.chooseMove(ctx);
      }

      this.metrics.record({
        ok: true,
        fallback: false,
        latencyMs,
        cached: typeof body.cached === 'boolean' ? body.cached : undefined,
      });
      return uci;
    } catch (error) {
      const latencyMs = Date.now() - startedAt;
      const isTimeout = controller.signal.aborted;
      this.metrics.record({
        ok: false,
        fallback: true,
        latencyMs,
        reason: isTimeout ? 'timeout' : 'network',
        message: error instanceof Error ? error.message : String(error),
      });
      return this.fallback.chooseMove(ctx);
    } finally {
      clearTimeout(timer);
      release();
    }
  }

  private headers(): Record<string, string> {
    const headers: Record<string, string> = { 'content-type': 'application/json' };
    if (this.authToken) headers.authorization = `Bearer ${this.authToken}`;
    return headers;
  }

  private recordFailure(
    reason: EngineFailureReason,
    latencyMs: number,
    body: EngineBestMoveResponse,
    status?: number,
    message?: string,
  ): void {
    this.metrics.record({
      ok: false,
      fallback: true,
      latencyMs,
      reason,
      status,
      code: typeof body.code === 'string' ? body.code : undefined,
      message: message ?? (typeof body.message === 'string' ? body.message : undefined),
    });
  }
}

function normalizeBaseUrl(baseUrl: string | undefined): string | undefined {
  const trimmed = baseUrl?.trim();
  if (!trimmed) return undefined;
  return trimmed.replace(/\/+$/, '');
}

async function readJsonBody(res: Awaited<ReturnType<typeof fetch>>): Promise<EngineBestMoveResponse> {
  try {
    const body = await res.json();
    return isRecord(body) ? body : {};
  } catch {
    return {};
  }
}

function isRecord(value: unknown): value is EngineBestMoveResponse {
  return typeof value === 'object' && value !== null;
}
