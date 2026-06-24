// HTTP surface for the puzzle library, designed to be MOUNTED into an existing
// http.Server (the main cchess-backend) rather than run as its own service:
// `handle(req,res)` returns true when it owned the request (a /puzzles or
// /admin/puzzles* path), false otherwise so the host server can fall through.
//
// Public reads need no auth. Progress reporting needs a Firebase ID token.
// Admin mutations need the shared `x-admin-key` secret (PUZZLE_ADMIN_KEY); when
// that env is unset, admin routes are disabled so a misconfigured deploy can't
// expose writes.

import type { IncomingMessage, ServerResponse } from 'http';

import { verifyIdToken, type VerifiedToken } from '../auth';
import { FirestorePuzzleStore, type PuzzleStore } from './puzzle_store';
import {
  dateKeyVN,
  isValidDateKey,
  MAX_DIFFICULTY,
  MIN_DIFFICULTY,
  PuzzleError,
  validateProgressInput,
  validatePuzzleInput,
  type PuzzleSort,
} from './types';

export interface PuzzleApiOptions {
  store?: PuzzleStore;
  authenticate?: (token: string) => Promise<VerifiedToken>;
  /// Returns true if the request carries valid admin credentials. Default:
  /// constant-time compare of `x-admin-key` to PUZZLE_ADMIN_KEY (disabled when
  /// the env is unset).
  isAdmin?: (req: IncomingMessage) => boolean;
  now?: () => Date;
  maxRequestBytes?: number;
  defaultPageSize?: number;
  maxPageSize?: number;
}

const DEFAULT_PAGE_SIZE = 20;
const MAX_PAGE_SIZE = 50;
const MAX_IMPORT_BATCH = 500;

export interface PuzzleApi {
  /// Returns true if the request matched a puzzle route and a response was sent.
  handle(req: IncomingMessage, res: ServerResponse): Promise<boolean>;
}

export function createPuzzleApi(options: PuzzleApiOptions = {}): PuzzleApi {
  const store = options.store ?? new FirestorePuzzleStore({ now: options.now });
  const authenticate = options.authenticate ?? verifyIdToken;
  const isAdmin = options.isAdmin ?? defaultAdminCheck;
  const now = options.now ?? (() => new Date());
  const maxRequestBytes = options.maxRequestBytes ?? 256 * 1024;
  const defaultPageSize = options.defaultPageSize ?? DEFAULT_PAGE_SIZE;
  const maxPageSize = options.maxPageSize ?? MAX_PAGE_SIZE;

  async function handle(req: IncomingMessage, res: ServerResponse): Promise<boolean> {
    const url = new URL(req.url ?? '/', 'http://localhost');
    const path = url.pathname.replace(/\/+$/, '') || '/';
    if (!owns(path)) return false;

    setCors(res);
    if (req.method === 'OPTIONS') {
      res.writeHead(204);
      res.end();
      return true;
    }

    try {
      await route(req, res, req.method ?? 'GET', path, url);
    } catch (error) {
      sendError(res, error);
    }
    return true;
  }

  async function route(
    req: IncomingMessage,
    res: ServerResponse,
    method: string,
    path: string,
    url: URL,
  ): Promise<void> {
    const segments = path.split('/').filter(Boolean); // e.g. ['puzzles','daily']

    // ── Public reads ──────────────────────────────────────────────────────
    if (segments[0] === 'puzzles') {
      if (method === 'GET' && segments.length === 1) {
        return void sendJson(res, 200, await listPuzzles(url));
      }
      if (method === 'GET' && segments.length === 2 && segments[1] === 'daily') {
        const dateKey = url.searchParams.get('date') ?? dateKeyVN(now());
        if (!isValidDateKey(dateKey)) {
          throw new PuzzleError(400, 'invalid-date', 'date must be YYYY-MM-DD');
        }
        const puzzle = await store.getDaily(dateKey);
        return void sendJson(res, 200, { date: dateKey, puzzle });
      }
      if (method === 'GET' && segments.length === 2) {
        const puzzle = await store.get(decodeURIComponent(segments[1]));
        if (!puzzle) throw new PuzzleError(404, 'not-found', 'Puzzle not found');
        return void sendJson(res, 200, puzzle);
      }
      // ── User progress (auth required) ───────────────────────────────────
      if (method === 'POST' && segments.length === 3 && segments[2] === 'progress') {
        const user = await requireAuth(req, authenticate);
        const body = await readJsonBody(req, maxRequestBytes);
        const input = validateProgressInput(body);
        const progress = await store.recordProgress(
          user.uid,
          decodeURIComponent(segments[1]),
          input,
        );
        return void sendJson(res, 200, progress);
      }
      throw new PuzzleError(404, 'not-found', 'Not found');
    }

    // ── Admin mutations ───────────────────────────────────────────────────
    if (segments[0] === 'admin') {
      if (!isAdmin(req)) {
        throw new PuzzleError(403, 'forbidden', 'Admin credentials required');
      }
      // /admin/puzzles[...]
      if (segments[1] === 'puzzles') {
        if (method === 'POST' && segments.length === 2) {
          const input = validatePuzzleInput(await readJsonBody(req, maxRequestBytes));
          return void sendJson(res, 201, await store.upsert(input));
        }
        if (method === 'POST' && segments.length === 3 && segments[2] === 'import') {
          return void sendJson(res, 200, await importBatch(await readJsonBody(req, maxRequestBytes)));
        }
        if (method === 'PUT' && segments.length === 3) {
          const raw = await readJsonBody(req, maxRequestBytes);
          const input = validatePuzzleInput({ ...(raw as object), id: decodeURIComponent(segments[2]) });
          return void sendJson(res, 200, await store.upsert(input));
        }
        if (method === 'DELETE' && segments.length === 3) {
          const removed = await store.remove(decodeURIComponent(segments[2]));
          if (!removed) throw new PuzzleError(404, 'not-found', 'Puzzle not found');
          return void sendJson(res, 200, { removed: true });
        }
      }
      // /admin/daily  body {date, puzzleId}
      if (segments[1] === 'daily' && method === 'POST' && segments.length === 2) {
        const body = (await readJsonBody(req, maxRequestBytes)) as Record<string, unknown>;
        const date = String(body.date ?? '');
        const puzzleId = String(body.puzzleId ?? '');
        if (!isValidDateKey(date)) throw new PuzzleError(400, 'invalid-date', 'date must be YYYY-MM-DD');
        if (!puzzleId) throw new PuzzleError(400, 'invalid-request', 'puzzleId is required');
        await store.setDaily(date, puzzleId);
        return void sendJson(res, 200, { date, puzzleId });
      }
      throw new PuzzleError(404, 'not-found', 'Not found');
    }

    throw new PuzzleError(404, 'not-found', 'Not found');
  }

  async function listPuzzles(url: URL) {
    const params = url.searchParams;
    const limit = clampInt(params.get('limit'), 1, maxPageSize) ?? defaultPageSize;
    const difficulty = clampInt(params.get('difficulty'), MIN_DIFFICULTY, MAX_DIFFICULTY);
    const sortRaw = params.get('sort');
    const sort: PuzzleSort =
      sortRaw === 'hardest' || sortRaw === 'easiest' ? sortRaw : 'newest';
    return store.list({
      limit,
      cursor: params.get('cursor') ?? undefined,
      difficulty: difficulty ?? undefined,
      category: nonEmpty(params.get('category')),
      theme: nonEmpty(params.get('theme')),
      tag: nonEmpty(params.get('tag')),
      sort,
    });
  }

  async function importBatch(body: unknown) {
    const items = Array.isArray(body)
      ? body
      : Array.isArray((body as { puzzles?: unknown })?.puzzles)
        ? (body as { puzzles: unknown[] }).puzzles
        : null;
    if (!items) {
      throw new PuzzleError(400, 'invalid-request', 'Body must be an array or { puzzles: [...] }');
    }
    if (items.length > MAX_IMPORT_BATCH) {
      throw new PuzzleError(413, 'batch-too-large', `Import at most ${MAX_IMPORT_BATCH} puzzles per call`);
    }
    const created: string[] = [];
    const errors: { index: number; message: string }[] = [];
    for (let i = 0; i < items.length; i++) {
      try {
        const doc = await store.upsert(validatePuzzleInput(items[i]));
        created.push(doc.id);
      } catch (e) {
        errors.push({ index: i, message: e instanceof Error ? e.message : String(e) });
      }
    }
    return { imported: created.length, ids: created, errors };
  }

  return { handle };
}

/// True for paths this API is responsible for. Keep this in sync with the host
/// server so unrelated routes (/health, /r/<id>) still reach their handlers.
function owns(path: string): boolean {
  return (
    path === '/puzzles' ||
    path.startsWith('/puzzles/') ||
    path === '/admin' ||
    path.startsWith('/admin/')
  );
}

function defaultAdminCheck(req: IncomingMessage): boolean {
  const expected = process.env.PUZZLE_ADMIN_KEY;
  if (!expected) return false;
  const header = req.headers['x-admin-key'];
  const provided = Array.isArray(header) ? header[0] : header;
  return typeof provided === 'string' && timingSafeEqual(provided, expected);
}

/// Length-independent constant-time string compare (avoids leaking the key
/// length / prefix via early-exit timing).
function timingSafeEqual(a: string, b: string): boolean {
  let mismatch = a.length === b.length ? 0 : 1;
  const len = Math.max(a.length, b.length);
  for (let i = 0; i < len; i++) {
    mismatch |= a.charCodeAt(i) ^ b.charCodeAt(i);
  }
  return mismatch === 0;
}

async function requireAuth(
  req: IncomingMessage,
  authenticate: (token: string) => Promise<VerifiedToken>,
): Promise<VerifiedToken> {
  const auth = req.headers.authorization ?? '';
  const match = /^Bearer\s+(.+)$/i.exec(Array.isArray(auth) ? auth[0] : auth);
  if (!match) throw new PuzzleError(401, 'missing-token', 'Missing Bearer token');
  try {
    return await authenticate(match[1]);
  } catch {
    throw new PuzzleError(401, 'invalid-token', 'Invalid Firebase ID token');
  }
}

function readJsonBody(req: IncomingMessage, maxBytes: number): Promise<unknown> {
  return new Promise((resolve, reject) => {
    const chunks: Buffer[] = [];
    let size = 0;
    req.on('data', (chunk: Buffer) => {
      size += chunk.length;
      if (size > maxBytes) {
        reject(new PuzzleError(413, 'request-too-large', 'Request body is too large'));
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
        reject(new PuzzleError(400, 'invalid-json', 'Request body must be valid JSON'));
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
  if (error instanceof PuzzleError) {
    sendJson(res, error.statusCode, { code: error.code, message: error.message });
    return;
  }
  const message = error instanceof Error ? error.message : String(error);
  console.error('[puzzles] internal error:', message);
  sendJson(res, 500, { code: 'internal-error', message: 'Internal error' });
}

function setCors(res: ServerResponse): void {
  res.setHeader('Access-Control-Allow-Origin', process.env.CORS_ORIGIN ?? '*');
  res.setHeader('Access-Control-Allow-Headers', 'authorization, content-type, x-admin-key');
  res.setHeader('Access-Control-Allow-Methods', 'GET, POST, PUT, DELETE, OPTIONS');
}

function clampInt(raw: string | null, min: number, max: number): number | undefined {
  if (raw === null || raw.trim() === '') return undefined;
  const value = Number(raw);
  if (!Number.isFinite(value)) return undefined;
  return Math.min(max, Math.max(min, Math.trunc(value)));
}

function nonEmpty(raw: string | null): string | undefined {
  const v = raw?.trim();
  return v && v.length > 0 ? v : undefined;
}
