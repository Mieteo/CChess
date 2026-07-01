// HTTP surface for C6 — the community news/daily-challenge feed, MOUNTED into
// the main cchess-backend http.Server the same way shop/clubs are:
// `handle()` returns true when it owned the request, false otherwise so the
// host can fall through.
//
// Reads are public. Admin mutations need the shared `x-admin-key` secret
// (COMMUNITY_ADMIN_KEY, falling back to SHOP_ADMIN_KEY/PUZZLE_ADMIN_KEY); when
// none of those env vars are set, admin routes are disabled so a
// misconfigured deploy can't expose writes.

import type { IncomingMessage, ServerResponse } from 'http';

import { HttpError, readJsonBody, sendError, sendJson, setCors, timingSafeEqual } from '../http_util';
import { FirestoreCommunityFeedStore, type CommunityFeedStore } from './community_feed_store';
import { validateFeedItemInput } from './types';

export interface CommunityFeedApiOptions {
  store?: CommunityFeedStore;
  /// True if the request carries valid admin credentials. Default: constant-time
  /// compare of `x-admin-key` to COMMUNITY_ADMIN_KEY || SHOP_ADMIN_KEY || PUZZLE_ADMIN_KEY.
  isAdmin?: (req: IncomingMessage) => boolean;
  now?: () => Date;
  maxRequestBytes?: number;
}

export interface CommunityFeedApi {
  handle(req: IncomingMessage, res: ServerResponse): Promise<boolean>;
}

export function createCommunityFeedApi(options: CommunityFeedApiOptions = {}): CommunityFeedApi {
  const store = options.store ?? new FirestoreCommunityFeedStore({ now: options.now });
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
      sendError(res, error, 'community_feed');
    }
    return true;
  }

  async function route(req: IncomingMessage, res: ServerResponse, method: string, path: string): Promise<void> {
    const segments = path.split('/').filter(Boolean); // e.g. ['community','feed'] or ['admin','community','feed','id']

    // GET /community/feed — public
    if (method === 'GET' && segments.length === 2 && segments[0] === 'community' && segments[1] === 'feed') {
      return void sendJson(res, 200, { items: await store.listItems({ activeOnly: true }) });
    }

    // /admin/community/feed[...] — admin-key gated
    if (segments[0] === 'admin' && segments[1] === 'community' && segments[2] === 'feed') {
      if (!isAdmin(req)) {
        throw new HttpError(403, 'forbidden', 'Admin credentials required');
      }
      if (method === 'POST' && segments.length === 3) {
        const input = validateFeedItemInput(await readJsonBody(req, maxRequestBytes));
        return void sendJson(res, 201, await store.upsertItem(input));
      }
      if (method === 'PUT' && segments.length === 4) {
        const raw = await readJsonBody(req, maxRequestBytes);
        const input = validateFeedItemInput({ ...(raw as object), id: decodeURIComponent(segments[3]) });
        return void sendJson(res, 200, await store.upsertItem(input));
      }
      if (method === 'DELETE' && segments.length === 4) {
        const removed = await store.removeItem(decodeURIComponent(segments[3]));
        if (!removed) throw new HttpError(404, 'not-found', 'Feed item not found');
        return void sendJson(res, 200, { removed: true });
      }
      throw new HttpError(404, 'not-found', 'Not found');
    }

    throw new HttpError(404, 'not-found', 'Not found');
  }

  return { handle };
}

/// True for paths this API owns. Keep in sync with server.ts so unrelated
/// routes still reach their handlers.
function owns(path: string): boolean {
  return (
    path === '/community/feed' ||
    path === '/admin/community/feed' ||
    path.startsWith('/admin/community/feed/')
  );
}

function defaultAdminCheck(req: IncomingMessage): boolean {
  const expected = process.env.COMMUNITY_ADMIN_KEY ?? process.env.SHOP_ADMIN_KEY ?? process.env.PUZZLE_ADMIN_KEY;
  if (!expected) return false;
  const header = req.headers['x-admin-key'];
  const provided = Array.isArray(header) ? header[0] : header;
  return typeof provided === 'string' && timingSafeEqual(provided, expected);
}
