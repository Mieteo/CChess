// HTTP surface for C4 — Giải Đấu (Tournament), MOUNTED into the main
// cchess-backend http.Server the same way shop/clubs are: `handle()` returns
// true when it owned the request (a /tournaments path), false otherwise.
//
// Catalog reads are public. Register/unregister need a Firebase ID token.
// Create/start are admin-key gated (v1 ships system-organized tournaments
// only — see plan). `recordMatchResult`/`attachRoomToMatch` are NOT HTTP
// routes: server.ts calls them in-process via `tournamentsApi.store` from the
// WebSocket create-room handler and finishGame (tournament match rooms reuse
// the existing casual private-room flow instead of new matchmaking surface).

import type { IncomingMessage, ServerResponse } from 'http';

import { verifyIdToken, type VerifiedToken } from '../auth';
import { HttpError, readJsonBody, requireAuth, sendError, sendJson, setCors, timingSafeEqual } from '../http_util';
import { FirestoreTournamentStore, type TournamentStore } from './tournament_store';
import { validateCreateTournamentInput } from './types';

export interface TournamentsApiOptions {
  store?: TournamentStore;
  authenticate?: (token: string) => Promise<VerifiedToken>;
  /// True if the request carries valid admin credentials. Default: constant-time
  /// compare of `x-admin-key` to TOURNAMENT_ADMIN_KEY || SHOP_ADMIN_KEY || PUZZLE_ADMIN_KEY.
  isAdmin?: (req: IncomingMessage) => boolean;
  now?: () => Date;
  maxRequestBytes?: number;
}

export interface TournamentsApi {
  handle(req: IncomingMessage, res: ServerResponse): Promise<boolean>;
  /// Exposed so server.ts can call recordMatchResult()/attachRoomToMatch()
  /// in-process (they're not HTTP routes — see file header).
  store: TournamentStore;
}

export function createTournamentsApi(options: TournamentsApiOptions = {}): TournamentsApi {
  const store = options.store ?? new FirestoreTournamentStore({ now: options.now });
  const authenticate = options.authenticate ?? verifyIdToken;
  const isAdmin = options.isAdmin ?? defaultAdminCheck;
  const maxRequestBytes = options.maxRequestBytes ?? 64 * 1024;

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
      await route(req, res, req.method ?? 'GET', path);
    } catch (error) {
      sendError(res, error, 'tournaments');
    }
    return true;
  }

  async function route(req: IncomingMessage, res: ServerResponse, method: string, path: string): Promise<void> {
    const segments = path.split('/').filter(Boolean); // e.g. ['tournaments', 'id', 'matches']

    if (segments[0] !== 'tournaments') throw new HttpError(404, 'not-found', 'Not found');

    // GET /tournaments
    if (method === 'GET' && segments.length === 1) {
      return void sendJson(res, 200, { tournaments: await store.list({ limit: 100 }) });
    }

    // POST /tournaments (admin)
    if (method === 'POST' && segments.length === 1) {
      if (!isAdmin(req)) throw new HttpError(403, 'forbidden', 'Admin credentials required');
      const input = validateCreateTournamentInput(await readJsonBody(req, maxRequestBytes));
      return void sendJson(res, 201, await store.create('system', input));
    }

    // GET /tournaments/:id
    if (method === 'GET' && segments.length === 2) {
      const tournament = await store.get(decodeURIComponent(segments[1]));
      if (!tournament) throw new HttpError(404, 'not-found', 'Tournament not found');
      return void sendJson(res, 200, tournament);
    }

    // GET /tournaments/:id/participants
    if (method === 'GET' && segments.length === 3 && segments[2] === 'participants') {
      return void sendJson(res, 200, { participants: await store.listParticipants(decodeURIComponent(segments[1])) });
    }

    // GET /tournaments/:id/matches
    if (method === 'GET' && segments.length === 3 && segments[2] === 'matches') {
      return void sendJson(res, 200, { matches: await store.listMatches(decodeURIComponent(segments[1])) });
    }

    // POST /tournaments/:id/register
    if (method === 'POST' && segments.length === 3 && segments[2] === 'register') {
      const user = await requireAuth(req, authenticate);
      return void sendJson(res, 200, await store.register(user.uid, decodeURIComponent(segments[1])));
    }

    // POST /tournaments/:id/unregister
    if (method === 'POST' && segments.length === 3 && segments[2] === 'unregister') {
      const user = await requireAuth(req, authenticate);
      await store.unregister(user.uid, decodeURIComponent(segments[1]));
      return void sendJson(res, 200, { unregistered: true });
    }

    // POST /tournaments/:id/start (admin)
    if (method === 'POST' && segments.length === 3 && segments[2] === 'start') {
      if (!isAdmin(req)) throw new HttpError(403, 'forbidden', 'Admin credentials required');
      const matches = await store.start(decodeURIComponent(segments[1]));
      return void sendJson(res, 200, { matches });
    }

    throw new HttpError(404, 'not-found', 'Not found');
  }

  return { handle, store };
}

/// True for paths this API owns. Keep in sync with server.ts so unrelated
/// routes still reach their handlers.
function owns(path: string): boolean {
  return path === '/tournaments' || path.startsWith('/tournaments/');
}

function defaultAdminCheck(req: IncomingMessage): boolean {
  const expected =
    process.env.TOURNAMENT_ADMIN_KEY ?? process.env.SHOP_ADMIN_KEY ?? process.env.PUZZLE_ADMIN_KEY;
  if (!expected) return false;
  const header = req.headers['x-admin-key'];
  const provided = Array.isArray(header) ? header[0] : header;
  return typeof provided === 'string' && timingSafeEqual(provided, expected);
}
