import { createServer, type IncomingMessage, type ServerResponse } from 'http';

import { initFirebaseAdmin, verifyIdToken, type VerifiedToken } from '../auth';
import { analyzeGame } from './analysis';
import { AnalysisCache } from './analysis_cache';
import { EnginePool, type SearchEngine } from './engine_pool';
import { bestMoveCacheKey, normalizeFen } from './fen';
import { createFirestoreVipChecker, FirestoreQuotaStore } from './firestore_quota';
import { DailyQuotaStore, type QuotaLimits, type QuotaStore } from './quota';
import { UciEngine } from './uci_engine';
import {
  EngineServiceError,
  type EngineAnalyzeRequest,
  type EngineBestMove,
  type EngineBestMoveRequest,
  type EngineFeature,
  type EngineLimit,
} from './types';

const PORT = Number(process.env.PORT ?? 8090);

export interface EngineHttpServerOptions {
  authenticate?: (token: string) => Promise<VerifiedToken>;
  isVip?: (uid: string) => Promise<boolean>;
  pool?: Pick<EnginePool, 'bestMove' | 'dispose' | 'stats'>;
  cache?: AnalysisCache<EngineBestMove>;
  quota?: QuotaStore;
  requireAuth?: boolean;
  maxRequestBytes?: number;
}

export function createEngineHttpServer(options: EngineHttpServerOptions = {}) {
  const authenticate = options.authenticate ?? verifyIdToken;
  const pool = options.pool ?? createDefaultPool();
  const cache = options.cache ?? new AnalysisCache<EngineBestMove>(envInt('ENGINE_CACHE_ENTRIES', 2000));
  const requireAuth = options.requireAuth ?? process.env.ENGINE_AUTH_DISABLED !== '1';
  const maxRequestBytes = options.maxRequestBytes ?? 128 * 1024;

  // Production (auth on) defaults to the Firestore-backed quota + VIP gate so
  // the daily cap survives Render restarts/redeploys and real VIPs bypass it.
  // Dev/tests (auth disabled) or ENGINE_QUOTA_BACKEND=memory use in-memory.
  const persistQuota = requireAuth && process.env.ENGINE_QUOTA_BACKEND !== 'memory';
  const limits: QuotaLimits = {
    bestMovePerDay: envInt('FREE_BEST_MOVE_DAILY_LIMIT', 30),
    hintPerDay: envInt('FREE_HINT_DAILY_LIMIT', 3),
    analyzePerDay: envInt('FREE_ANALYZE_DAILY_LIMIT', 3),
  };
  const quota = options.quota
    ?? (persistQuota ? new FirestoreQuotaStore(limits) : new DailyQuotaStore(limits));
  const isVip = options.isVip
    ?? (persistQuota ? createFirestoreVipChecker() : async () => false);

  const httpServer = createServer(async (req, res) => {
    setCorsHeaders(res);
    if (req.method === 'OPTIONS') {
      res.writeHead(204);
      res.end();
      return;
    }

    try {
      const url = new URL(req.url ?? '/', 'http://localhost');
      if (req.method === 'GET' && url.pathname === '/health') {
        sendJson(res, 200, {
          ok: true,
          engine: pool !== null,
          stats: pool?.stats() ?? null,
          cacheEntries: cache.size,
        });
        return;
      }

      // Read-only quota snapshot so the app can show remaining free hints/
      // analyses (and a VIP upsell) before a request is rejected with 429.
      if (req.method === 'GET' && url.pathname === '/engine/quota') {
        const user = await authenticateRequest(req, authenticate, requireAuth);
        const status = await quota.status(user.uid, await isVip(user.uid));
        sendJson(res, 200, status);
        return;
      }

      if (req.method !== 'POST') {
        throw new EngineServiceError(404, 'not-found', 'Not found');
      }
      if (!pool) {
        throw new EngineServiceError(503, 'engine-unavailable', 'PIKAFISH_PATH is not configured');
      }

      const feature = featureForPath(url.pathname);
      if (!feature) {
        throw new EngineServiceError(404, 'not-found', 'Not found');
      }
      const user = await authenticateRequest(req, authenticate, requireAuth);
      await quota.check(user.uid, feature, await isVip(user.uid));
      const body = await readJsonBody(req, maxRequestBytes);

      if (url.pathname === '/engine/best-move' || url.pathname === '/engine/hint') {
        const request = body as EngineBestMoveRequest;
        const fen = normalizeFen(request.fen);
        const limit = limitForRequest(request, feature);
        const result = await cachedBestMove(pool, cache, fen, limit);
        sendJson(res, 200, result);
        return;
      }

      const request = body as EngineAnalyzeRequest;
      const startingFen = normalizeFen(request.startingFen ?? request.fen);
      const moves = Array.isArray(request.movesUci) ? request.movesUci : request.moves;
      if (!Array.isArray(moves)) {
        throw new EngineServiceError(400, 'invalid-request', 'movesUci must be an array');
      }
      const limit = limitForRequest(request, feature);
      const result = await analyzeGame(startingFen, moves, limit, (fen, searchLimit) =>
        cachedBestMove(pool, cache, fen, searchLimit),
      );
      sendJson(res, 200, result);
    } catch (error) {
      sendError(res, error);
    }
  });

  return {
    httpServer,
    close: () => new Promise<void>((resolve) => {
      pool?.dispose();
      httpServer.close(() => resolve());
    }),
  };
}

async function cachedBestMove(
  pool: Pick<EnginePool, 'bestMove'>,
  cache: AnalysisCache<EngineBestMove>,
  fen: string,
  limit: EngineLimit,
): Promise<EngineBestMove> {
  // A blunder roll makes the result non-deterministic for a given fen+limit —
  // caching it would freeze whichever move the first roll happened to pick,
  // serving it forever after. Always search fresh when blunderRate is active.
  if (limit.blunderRate !== undefined && limit.blunderRate > 0) {
    const result = await pool.bestMove(fen, limit);
    return { ...result, cached: false };
  }
  const key = bestMoveCacheKey(fen, limit);
  const cached = cache.get(key);
  if (cached) return { ...cached, cached: true };
  const result = await pool.bestMove(fen, limit);
  cache.set(key, result);
  return { ...result, cached: false };
}

function createDefaultPool(): EnginePool | null {
  const binaryPath = process.env.PIKAFISH_PATH;
  if (!binaryPath) return null;
  return new EnginePool({
    maxConcurrency: envInt('MAX_CONCURRENCY', envInt('ENGINE_WORKERS', 1)),
    maxQueueSize: envInt('MAX_QUEUE_SIZE', 32),
    taskTimeoutMs: envInt('ENGINE_TASK_TIMEOUT_MS', 10_000),
    createEngine: (): SearchEngine => new UciEngine({
      binaryPath,
      evalFile: process.env.EVAL_FILE,
      threads: envInt('ENGINE_THREADS', 1),
      hashMb: envInt('ENGINE_HASH_MB', 128),
      defaultMovetimeMs: envInt('DEFAULT_MOVETIME_MS', 600),
      initTimeoutMs: envInt('ENGINE_INIT_TIMEOUT_MS', 10_000),
      searchTimeoutMs: envInt('ENGINE_SEARCH_TIMEOUT_MS', 10_000),
    }),
  });
}

function featureForPath(pathname: string): EngineFeature | null {
  if (pathname === '/engine/best-move') return 'best-move';
  if (pathname === '/engine/hint') return 'hint';
  if (pathname === '/engine/analyze') return 'analyze';
  return null;
}

function limitForRequest(
  request: EngineBestMoveRequest | EngineAnalyzeRequest,
  feature: EngineFeature,
): EngineLimit {
  // ELO-ladder blunder dial only applies to bot play; hints + analysis stay
  // at full strength.
  const strength: Pick<EngineLimit, 'blunderRate'> =
    feature === 'best-move'
      ? {
          blunderRate: clampOptionalFloat(
            'blunderRate' in request ? request.blunderRate : undefined,
            0,
            1,
          ),
        }
      : {};

  const depth = clampOptionalInt(request.depth, 1, envInt('MAX_DEPTH', 20));
  if (depth !== undefined) return { depth, ...strength };
  const level = 'level' in request ? request.level : undefined;
  const defaultMovetime = defaultMovetimeFor(level, feature);
  return {
    movetimeMs: clampOptionalInt(
      request.movetimeMs,
      50,
      envInt('MAX_MOVETIME_MS', 3000),
    ) ?? defaultMovetime,
    ...strength,
  };
}

function defaultMovetimeFor(level: string | undefined, feature: EngineFeature): number {
  if (feature === 'analyze') return envInt('ANALYZE_MOVETIME_MS', 300);
  if (feature === 'hint') return envInt('HINT_MOVETIME_MS', 500);
  switch (level) {
    case 'grandmaster':
    case 'daiSuPlus':
      return envInt('GRANDMASTER_MOVETIME_MS', 1200);
    case 'hard':
    case 'veryHard':
      return envInt('STRONG_BOT_MOVETIME_MS', 800);
    default:
      return envInt('DEFAULT_MOVETIME_MS', 600);
  }
}

async function authenticateRequest(
  req: IncomingMessage,
  authenticate: (token: string) => Promise<VerifiedToken>,
  requireAuth: boolean,
): Promise<VerifiedToken> {
  if (!requireAuth) return { uid: 'dev' };
  const auth = req.headers.authorization ?? '';
  const match = /^Bearer\s+(.+)$/i.exec(Array.isArray(auth) ? auth[0] : auth);
  if (!match) {
    throw new EngineServiceError(401, 'missing-token', 'Missing Bearer token');
  }
  return authenticate(match[1]);
}

function readJsonBody(req: IncomingMessage, maxBytes: number): Promise<unknown> {
  return new Promise((resolve, reject) => {
    const chunks: Buffer[] = [];
    let size = 0;
    req.on('data', (chunk: Buffer) => {
      size += chunk.length;
      if (size > maxBytes) {
        reject(new EngineServiceError(413, 'request-too-large', 'Request body is too large'));
        req.destroy();
        return;
      }
      chunks.push(chunk);
    });
    req.on('end', () => {
      try {
        const text = Buffer.concat(chunks).toString('utf8');
        resolve(text.length === 0 ? {} : JSON.parse(text));
      } catch {
        reject(new EngineServiceError(400, 'invalid-json', 'Request body must be valid JSON'));
      }
    });
    req.on('error', (error) => reject(error));
  });
}

function sendJson(res: ServerResponse, statusCode: number, body: unknown): void {
  res.writeHead(statusCode, { 'Content-Type': 'application/json; charset=utf-8' });
  res.end(JSON.stringify(body));
}

function sendError(res: ServerResponse, error: unknown): void {
  if (error instanceof EngineServiceError) {
    sendJson(res, error.statusCode, { code: error.code, message: error.expose ? error.message : 'Engine error' });
    return;
  }
  const message = error instanceof Error ? error.message : String(error);
  sendJson(res, 500, { code: 'internal-error', message });
}

function setCorsHeaders(res: ServerResponse): void {
  res.setHeader('Access-Control-Allow-Origin', process.env.CORS_ORIGIN ?? '*');
  res.setHeader('Access-Control-Allow-Headers', 'authorization, content-type');
  res.setHeader('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
}

function clampOptionalInt(raw: unknown, min: number, max: number): number | undefined {
  if (raw === undefined || raw === null) return undefined;
  const value = Number(raw);
  if (!Number.isFinite(value)) return undefined;
  return Math.min(max, Math.max(min, Math.trunc(value)));
}

function clampOptionalFloat(raw: unknown, min: number, max: number): number | undefined {
  if (raw === undefined || raw === null) return undefined;
  const value = Number(raw);
  if (!Number.isFinite(value)) return undefined;
  return Math.min(max, Math.max(min, value));
}

function envInt(name: string, fallback: number): number {
  const value = Number(process.env[name]);
  return Number.isFinite(value) ? Math.trunc(value) : fallback;
}

if (process.env.CCHESS_ENGINE_NO_LISTEN !== '1') {
  if (process.env.ENGINE_AUTH_DISABLED !== '1') initFirebaseAdmin();
  const { httpServer, close } = createEngineHttpServer();
  httpServer.listen(PORT, () => {
    console.log(`[engine] HTTP listening on http://localhost:${PORT}`);
  });
  const shutdown = () => {
    console.log('[engine] shutting down...');
    void close().then(() => process.exit(0));
  };
  process.on('SIGINT', shutdown);
  process.on('SIGTERM', shutdown);
}
