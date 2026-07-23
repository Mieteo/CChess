// HTTP surface for the S16 economy extension (D4 Hộp Thư / D5 Sự Kiện /
// D6 Phúc Lợi / D7 Đúc Bàn Cờ), mounted into the main cchess-backend
// http.Server like the shop API: `handle()` returns true when it owned the
// request (a /mail, /events, /welfare, /crafting or matching /admin path),
// false otherwise so the host can fall through.
//
// Event + crafting catalogs are public reads. Everything personal (mailbox,
// claims, check-in) needs a Firebase ID token. Admin mutations reuse the shop's
// `x-admin-key` scheme (SHOP_ADMIN_KEY falling back to PUZZLE_ADMIN_KEY);
// with neither env set, admin routes are disabled.

import type { IncomingMessage, ServerResponse } from 'http';

import { verifyIdToken, type VerifiedToken } from '../auth';
import {
  HttpError,
  readJsonBody,
  requireAuth,
  sendError,
  sendJson,
  setCors,
  timingSafeEqual,
} from '../http_util';
import { FirestoreEconomyStore, type EconomyStore } from './economy_store';
import {
  validateEventClaimInput,
  validateEventInput,
  validateRecipeInput,
  validateSendMailInput,
} from './types';

export interface EconomyApiOptions {
  store?: EconomyStore;
  authenticate?: (token: string) => Promise<VerifiedToken>;
  isAdmin?: (req: IncomingMessage) => boolean;
  now?: () => Date;
  maxRequestBytes?: number;
}

export interface EconomyApi {
  handle(req: IncomingMessage, res: ServerResponse): Promise<boolean>;
}

export function createEconomyApi(options: EconomyApiOptions = {}): EconomyApi {
  const store = options.store ?? new FirestoreEconomyStore({ now: options.now });
  const authenticate = options.authenticate ?? verifyIdToken;
  const isAdmin = options.isAdmin ?? defaultAdminCheck;
  const maxRequestBytes = options.maxRequestBytes ?? 256 * 1024;

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
      sendError(res, error, 'economy');
    }
    return true;
  }

  async function route(
    req: IncomingMessage,
    res: ServerResponse,
    method: string,
    path: string,
  ): Promise<void> {
    const segments = path.split('/').filter(Boolean);

    // ── Mail (D4, all auth) ───────────────────────────────────────────────
    if (segments[0] === 'mail') {
      const user = await requireAuth(req, authenticate);
      if (method === 'GET' && segments.length === 1) {
        return void sendJson(res, 200, { messages: await store.listMail(user.uid) });
      }
      if (method === 'POST' && segments.length === 3 && segments[2] === 'read') {
        await store.markMailRead(user.uid, decodeURIComponent(segments[1]));
        return void sendJson(res, 200, { ok: true });
      }
      if (method === 'POST' && segments.length === 3 && segments[2] === 'claim') {
        const result = await store.claimMail(user.uid, decodeURIComponent(segments[1]));
        return void sendJson(res, 200, result);
      }
      if (method === 'DELETE' && segments.length === 2) {
        const removed = await store.deleteMail(user.uid, decodeURIComponent(segments[1]));
        if (!removed) throw new HttpError(404, 'not-found', 'Mail not found');
        return void sendJson(res, 200, { removed: true });
      }
      throw new HttpError(404, 'not-found', 'Not found');
    }

    // ── Events (D5) ───────────────────────────────────────────────────────
    if (segments[0] === 'events') {
      if (method === 'GET' && segments.length === 1) {
        return void sendJson(res, 200, { events: await store.listEvents() });
      }
      // NOTE: must match before the /events/:id detail route.
      if (method === 'GET' && segments.length === 2 && segments[1] === 'claims') {
        const user = await requireAuth(req, authenticate);
        return void sendJson(res, 200, { claims: await store.listEventClaims(user.uid) });
      }
      if (method === 'GET' && segments.length === 2) {
        const event = await store.getEvent(decodeURIComponent(segments[1]));
        if (!event) throw new HttpError(404, 'not-found', 'Event not found');
        return void sendJson(res, 200, event);
      }
      if (method === 'POST' && segments.length === 3 && segments[2] === 'claim') {
        const user = await requireAuth(req, authenticate);
        const { giftId } = validateEventClaimInput(await readJsonBody(req, maxRequestBytes));
        const result = await store.claimEventGift(
          user.uid,
          decodeURIComponent(segments[1]),
          giftId,
        );
        return void sendJson(res, 200, result);
      }
      throw new HttpError(404, 'not-found', 'Not found');
    }

    // ── Welfare (D6, all auth) ────────────────────────────────────────────
    if (segments[0] === 'welfare') {
      const user = await requireAuth(req, authenticate);
      if (method === 'GET' && segments.length === 1) {
        return void sendJson(res, 200, await store.getWelfare(user.uid));
      }
      if (method === 'POST' && segments.length === 2 && segments[1] === 'checkin') {
        return void sendJson(res, 200, await store.checkin(user.uid));
      }
      if (method === 'POST' && segments.length === 2 && segments[1] === 'newbie') {
        return void sendJson(res, 200, await store.claimNewbie(user.uid));
      }
      if (method === 'POST' && segments.length === 2 && segments[1] === 'comeback') {
        return void sendJson(res, 200, await store.claimComeback(user.uid));
      }
      throw new HttpError(404, 'not-found', 'Not found');
    }

    // ── Crafting (D7) ─────────────────────────────────────────────────────
    if (segments[0] === 'crafting') {
      if (method === 'GET' && segments.length === 1) {
        return void sendJson(res, 200, { recipes: await store.listRecipes() });
      }
      if (method === 'POST' && segments.length === 3 && segments[2] === 'craft') {
        const user = await requireAuth(req, authenticate);
        const result = await store.craft(user.uid, decodeURIComponent(segments[1]));
        return void sendJson(res, 200, result);
      }
      throw new HttpError(404, 'not-found', 'Not found');
    }

    // ── Admin mutations ───────────────────────────────────────────────────
    if (segments[0] === 'admin') {
      if (!isAdmin(req)) {
        throw new HttpError(403, 'forbidden', 'Admin credentials required');
      }
      if (segments[1] === 'mail' && method === 'POST' && segments.length === 2) {
        const input = validateSendMailInput(await readJsonBody(req, maxRequestBytes));
        const sent = await store.sendMail(input);
        return void sendJson(res, 200, { sent });
      }
      if (segments[1] === 'events') {
        if (method === 'POST' && segments.length === 2) {
          const input = validateEventInput(await readJsonBody(req, maxRequestBytes));
          return void sendJson(res, 201, await store.upsertEvent(input));
        }
        if (method === 'PUT' && segments.length === 3) {
          const raw = await readJsonBody(req, maxRequestBytes);
          const input = validateEventInput({
            ...(raw as object),
            id: decodeURIComponent(segments[2]),
          });
          return void sendJson(res, 200, await store.upsertEvent(input));
        }
        if (method === 'DELETE' && segments.length === 3) {
          const removed = await store.removeEvent(decodeURIComponent(segments[2]));
          if (!removed) throw new HttpError(404, 'not-found', 'Event not found');
          return void sendJson(res, 200, { removed: true });
        }
      }
      if (segments[1] === 'crafting') {
        if (method === 'POST' && segments.length === 2) {
          const input = validateRecipeInput(await readJsonBody(req, maxRequestBytes));
          return void sendJson(res, 201, await store.upsertRecipe(input));
        }
        if (method === 'PUT' && segments.length === 3) {
          const raw = await readJsonBody(req, maxRequestBytes);
          const input = validateRecipeInput({
            ...(raw as object),
            id: decodeURIComponent(segments[2]),
          });
          return void sendJson(res, 200, await store.upsertRecipe(input));
        }
        if (method === 'DELETE' && segments.length === 3) {
          const removed = await store.removeRecipe(decodeURIComponent(segments[2]));
          if (!removed) throw new HttpError(404, 'not-found', 'Recipe not found');
          return void sendJson(res, 200, { removed: true });
        }
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
    path === '/mail' ||
    path.startsWith('/mail/') ||
    path === '/events' ||
    path.startsWith('/events/') ||
    path === '/welfare' ||
    path.startsWith('/welfare/') ||
    path === '/crafting' ||
    path.startsWith('/crafting/') ||
    path === '/admin/mail' ||
    path === '/admin/events' ||
    path.startsWith('/admin/events/') ||
    path === '/admin/crafting' ||
    path.startsWith('/admin/crafting/')
  );
}

function defaultAdminCheck(req: IncomingMessage): boolean {
  const expected = process.env.SHOP_ADMIN_KEY ?? process.env.PUZZLE_ADMIN_KEY;
  if (!expected) return false;
  const header = req.headers['x-admin-key'];
  const provided = Array.isArray(header) ? header[0] : header;
  return typeof provided === 'string' && timingSafeEqual(provided, expected);
}
