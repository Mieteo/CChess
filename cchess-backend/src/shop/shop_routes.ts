// HTTP surface for the economy (S16 — Thương Thành / Balo), MOUNTED into the
// main cchess-backend http.Server the same way the puzzle API is: `handle()`
// returns true when it owned the request (a /shop, /wallet, /inventory or
// /admin/shop path), false otherwise so the host can fall through.
//
// Catalog reads are public. Wallet/inventory reads + purchase/equip need a
// Firebase ID token. Admin mutations need the shared `x-admin-key` secret
// (SHOP_ADMIN_KEY, falling back to PUZZLE_ADMIN_KEY); when neither env is set,
// admin routes are disabled so a misconfigured deploy can't expose writes.

import type { IncomingMessage, ServerResponse } from 'http';

import { verifyIdToken, type VerifiedToken } from '../auth';
import {
  HttpError,
  nonEmpty,
  readJsonBody,
  requireAuth,
  sendError,
  sendJson,
  setCors,
  timingSafeEqual,
} from '../http_util';
import { FirestoreShopStore, type ShopStore } from './shop_store';
import {
  validateEquipInput,
  validatePurchaseInput,
  validateShopItemInput,
  isShopItemKind,
  type ShopItemKind,
} from './types';

export interface ShopApiOptions {
  store?: ShopStore;
  authenticate?: (token: string) => Promise<VerifiedToken>;
  /// True if the request carries valid admin credentials. Default: constant-time
  /// compare of `x-admin-key` to SHOP_ADMIN_KEY || PUZZLE_ADMIN_KEY.
  isAdmin?: (req: IncomingMessage) => boolean;
  now?: () => Date;
  maxRequestBytes?: number;
}

const MAX_IMPORT_BATCH = 500;

export interface ShopApi {
  handle(req: IncomingMessage, res: ServerResponse): Promise<boolean>;
}

export function createShopApi(options: ShopApiOptions = {}): ShopApi {
  const store = options.store ?? new FirestoreShopStore({ now: options.now });
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
      await route(req, res, req.method ?? 'GET', path, url);
    } catch (error) {
      sendError(res, error, 'shop');
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
    const segments = path.split('/').filter(Boolean); // e.g. ['shop','daily']

    // ── Catalog (public reads) ────────────────────────────────────────────
    if (segments[0] === 'shop') {
      if (method === 'GET' && segments.length === 1) {
        const kindRaw = nonEmpty(url.searchParams.get('kind'));
        const kind = isShopItemKind(kindRaw) ? (kindRaw as ShopItemKind) : undefined;
        const items = await store.listItems({ kind, activeOnly: true });
        return void sendJson(res, 200, { items });
      }
      if (method === 'GET' && segments.length === 2) {
        const item = await store.getItem(decodeURIComponent(segments[1]));
        if (!item || !item.active) throw new HttpError(404, 'not-found', 'Item not found');
        return void sendJson(res, 200, item);
      }
      // POST /shop/:id/purchase  (auth)
      if (method === 'POST' && segments.length === 3 && segments[2] === 'purchase') {
        const user = await requireAuth(req, authenticate);
        const { currency } = validatePurchaseInput(await readJsonBody(req, maxRequestBytes));
        const result = await store.purchase(user.uid, decodeURIComponent(segments[1]), currency);
        return void sendJson(res, 200, result);
      }
      throw new HttpError(404, 'not-found', 'Not found');
    }

    // ── Wallet (auth) ─────────────────────────────────────────────────────
    if (segments[0] === 'wallet' && method === 'GET' && segments.length === 1) {
      const user = await requireAuth(req, authenticate);
      return void sendJson(res, 200, await store.getWallet(user.uid));
    }

    // ── Inventory (auth) ──────────────────────────────────────────────────
    if (segments[0] === 'inventory') {
      if (method === 'GET' && segments.length === 1) {
        const user = await requireAuth(req, authenticate);
        return void sendJson(res, 200, { items: await store.listInventory(user.uid) });
      }
      // POST /inventory/equip  body {kind, itemId|null}
      if (method === 'POST' && segments.length === 2 && segments[1] === 'equip') {
        const user = await requireAuth(req, authenticate);
        const { kind, itemId } = validateEquipInput(await readJsonBody(req, maxRequestBytes));
        const wallet = await store.equip(user.uid, kind, itemId);
        return void sendJson(res, 200, wallet);
      }
      throw new HttpError(404, 'not-found', 'Not found');
    }

    // ── Admin mutations ───────────────────────────────────────────────────
    if (segments[0] === 'admin' && segments[1] === 'shop') {
      if (!isAdmin(req)) {
        throw new HttpError(403, 'forbidden', 'Admin credentials required');
      }
      if (method === 'POST' && segments.length === 2) {
        const input = validateShopItemInput(await readJsonBody(req, maxRequestBytes));
        return void sendJson(res, 201, await store.upsertItem(input));
      }
      if (method === 'POST' && segments.length === 3 && segments[2] === 'import') {
        return void sendJson(res, 200, await importBatch(await readJsonBody(req, maxRequestBytes)));
      }
      if (method === 'PUT' && segments.length === 3) {
        const raw = await readJsonBody(req, maxRequestBytes);
        const input = validateShopItemInput({ ...(raw as object), id: decodeURIComponent(segments[2]) });
        return void sendJson(res, 200, await store.upsertItem(input));
      }
      if (method === 'DELETE' && segments.length === 3) {
        const removed = await store.removeItem(decodeURIComponent(segments[2]));
        if (!removed) throw new HttpError(404, 'not-found', 'Item not found');
        return void sendJson(res, 200, { removed: true });
      }
      throw new HttpError(404, 'not-found', 'Not found');
    }

    throw new HttpError(404, 'not-found', 'Not found');
  }

  async function importBatch(body: unknown) {
    const items = Array.isArray(body)
      ? body
      : Array.isArray((body as { items?: unknown })?.items)
        ? (body as { items: unknown[] }).items
        : null;
    if (!items) {
      throw new HttpError(400, 'invalid-request', 'Body must be an array or { items: [...] }');
    }
    if (items.length > MAX_IMPORT_BATCH) {
      throw new HttpError(413, 'batch-too-large', `Import at most ${MAX_IMPORT_BATCH} items per call`);
    }
    const created: string[] = [];
    const errors: { index: number; message: string }[] = [];
    for (let i = 0; i < items.length; i++) {
      try {
        const doc = await store.upsertItem(validateShopItemInput(items[i]));
        created.push(doc.id);
      } catch (e) {
        errors.push({ index: i, message: e instanceof Error ? e.message : String(e) });
      }
    }
    return { imported: created.length, ids: created, errors };
  }

  return { handle };
}

/// True for paths this API owns. Keep in sync with server.ts so unrelated routes
/// still reach their handlers.
function owns(path: string): boolean {
  return (
    path === '/shop' ||
    path.startsWith('/shop/') ||
    path === '/wallet' ||
    path === '/inventory' ||
    path.startsWith('/inventory/') ||
    path === '/admin/shop' ||
    path.startsWith('/admin/shop/')
  );
}

function defaultAdminCheck(req: IncomingMessage): boolean {
  const expected = process.env.SHOP_ADMIN_KEY ?? process.env.PUZZLE_ADMIN_KEY;
  if (!expected) return false;
  const header = req.headers['x-admin-key'];
  const provided = Array.isArray(header) ? header[0] : header;
  return typeof provided === 'string' && timingSafeEqual(provided, expected);
}
