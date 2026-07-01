// HTTP surface for C3 — Câu Lạc Bộ (Club), MOUNTED into the main cchess-backend
// http.Server the same way the shop API is: `handle()` returns true when it
// owned the request (a /clubs path), false otherwise so the host can fall
// through.
//
// Catalog reads are public. Create/join/leave/mine need a Firebase ID token.
// There are no admin routes — clubs are user-created, not admin-curated.

import type { IncomingMessage, ServerResponse } from 'http';

import { verifyIdToken, type VerifiedToken } from '../auth';
import { HttpError, readJsonBody, requireAuth, sendError, sendJson, setCors } from '../http_util';
import { FirestoreClubStore, type ClubStore } from './clubs_store';
import { validateCreateClubInput } from './types';

export interface ClubsApiOptions {
  store?: ClubStore;
  authenticate?: (token: string) => Promise<VerifiedToken>;
  now?: () => Date;
  maxRequestBytes?: number;
}

export interface ClubsApi {
  handle(req: IncomingMessage, res: ServerResponse): Promise<boolean>;
}

export function createClubsApi(options: ClubsApiOptions = {}): ClubsApi {
  const store = options.store ?? new FirestoreClubStore({ now: options.now });
  const authenticate = options.authenticate ?? verifyIdToken;
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
      sendError(res, error, 'clubs');
    }
    return true;
  }

  async function route(req: IncomingMessage, res: ServerResponse, method: string, path: string): Promise<void> {
    const segments = path.split('/').filter(Boolean); // e.g. ['clubs', 'club-ha-noi', 'members']

    if (segments[0] !== 'clubs') throw new HttpError(404, 'not-found', 'Not found');

    // GET /clubs/mine (before the :id branches, since 'mine' is not an id)
    if (method === 'GET' && segments.length === 2 && segments[1] === 'mine') {
      const user = await requireAuth(req, authenticate);
      return void sendJson(res, 200, { clubs: await store.listMyClubs(user.uid) });
    }

    // GET /clubs
    if (method === 'GET' && segments.length === 1) {
      return void sendJson(res, 200, { clubs: await store.listClubs({ limit: 100 }) });
    }

    // POST /clubs
    if (method === 'POST' && segments.length === 1) {
      const user = await requireAuth(req, authenticate);
      const input = validateCreateClubInput(await readJsonBody(req, maxRequestBytes));
      return void sendJson(res, 201, await store.createClub(user.uid, input));
    }

    // GET /clubs/:id
    if (method === 'GET' && segments.length === 2) {
      const club = await store.getClub(decodeURIComponent(segments[1]));
      if (!club) throw new HttpError(404, 'not-found', 'Club not found');
      return void sendJson(res, 200, club);
    }

    // GET /clubs/:id/members
    if (method === 'GET' && segments.length === 3 && segments[2] === 'members') {
      const members = await store.listMembers(decodeURIComponent(segments[1]));
      return void sendJson(res, 200, { members });
    }

    // POST /clubs/:id/join
    if (method === 'POST' && segments.length === 3 && segments[2] === 'join') {
      const user = await requireAuth(req, authenticate);
      return void sendJson(res, 200, await store.joinClub(user.uid, decodeURIComponent(segments[1])));
    }

    // POST /clubs/:id/leave
    if (method === 'POST' && segments.length === 3 && segments[2] === 'leave') {
      const user = await requireAuth(req, authenticate);
      await store.leaveClub(user.uid, decodeURIComponent(segments[1]));
      return void sendJson(res, 200, { left: true });
    }

    throw new HttpError(404, 'not-found', 'Not found');
  }

  return { handle };
}

/// True for paths this API owns. Keep in sync with server.ts so unrelated
/// routes still reach their handlers.
function owns(path: string): boolean {
  return path === '/clubs' || path.startsWith('/clubs/');
}
