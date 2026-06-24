import assert from 'node:assert/strict';
import { test } from 'node:test';
import { createServer, type Server } from 'node:http';
import type { AddressInfo } from 'node:net';

import { createShopApi, type ShopApiOptions } from './shop_routes';
import type { ShopStore } from './shop_store';
import {
  ShopError,
  validateEquipInput,
  validatePurchaseInput,
  validateShopItemInput,
  type Currency,
  type InventoryItemDoc,
  type PurchaseResult,
  type ShopItemDoc,
  type ShopItemInput,
  type ShopItemKind,
  type WalletDoc,
} from './types';

// ── In-memory store fake ─────────────────────────────────────────────────────

interface FakeUser {
  coins: number;
  gems: number;
  equipped: Record<string, string>;
  inventory: Map<string, InventoryItemDoc>;
}

class FakeShopStore implements ShopStore {
  readonly items = new Map<string, ShopItemDoc>();
  readonly users = new Map<string, FakeUser>();
  private seq = 0;

  seedItem(doc: Partial<ShopItemDoc> & { id: string; kind: ShopItemKind; nameVi: string; payloadKey: string }): void {
    this.items.set(doc.id, {
      descVi: '',
      priceCoins: 0,
      priceGems: 0,
      rarity: 'common',
      consumable: false,
      consumableQty: 1,
      sortOrder: 0,
      active: true,
      createdAtMs: ++this.seq,
      updatedAtMs: this.seq,
      ...doc,
    });
  }

  seedUser(uid: string, user: Partial<FakeUser> = {}): FakeUser {
    const u: FakeUser = {
      coins: user.coins ?? 0,
      gems: user.gems ?? 0,
      equipped: user.equipped ?? {},
      inventory: user.inventory ?? new Map(),
    };
    this.users.set(uid, u);
    return u;
  }

  async listItems(opts: { kind?: ShopItemKind; activeOnly?: boolean } = {}): Promise<ShopItemDoc[]> {
    let all = [...this.items.values()];
    if (opts.kind) all = all.filter((i) => i.kind === opts.kind);
    if (opts.activeOnly !== false) all = all.filter((i) => i.active);
    all.sort((a, b) => a.sortOrder - b.sortOrder || a.id.localeCompare(b.id));
    return all;
  }

  async getItem(id: string): Promise<ShopItemDoc | null> {
    return this.items.get(id) ?? null;
  }

  async getWallet(uid: string): Promise<WalletDoc> {
    const u = this.users.get(uid);
    return { coins: u?.coins ?? 0, gems: u?.gems ?? 0, equipped: { ...(u?.equipped ?? {}) } };
  }

  async listInventory(uid: string): Promise<InventoryItemDoc[]> {
    return [...(this.users.get(uid)?.inventory.values() ?? [])];
  }

  async purchase(uid: string, itemId: string, currency: Currency): Promise<PurchaseResult> {
    const item = this.items.get(itemId);
    if (!item || !item.active) throw new ShopError(404, 'not-found', 'Item not found');
    const price = currency === 'coins' ? item.priceCoins : item.priceGems;
    if (price <= 0) throw new ShopError(400, 'currency-not-accepted', `Cannot buy with ${currency}`);
    const u = this.users.get(uid) ?? this.seedUser(uid);
    const owned = u.inventory.get(itemId);
    if (!item.consumable && owned) throw new ShopError(409, 'already-owned', 'Already owned');
    const balance = currency === 'coins' ? u.coins : u.gems;
    if (balance < price) throw new ShopError(402, 'insufficient-funds', `Not enough ${currency}`);

    if (currency === 'coins') u.coins -= price;
    else u.gems -= price;
    const qty = item.consumable ? (owned?.qty ?? 0) + item.consumableQty : 1;
    const invItem: InventoryItemDoc = {
      itemId,
      kind: item.kind,
      payloadKey: item.payloadKey,
      qty,
      acquiredAtMs: owned?.acquiredAtMs ?? ++this.seq,
    };
    u.inventory.set(itemId, invItem);
    return { wallet: await this.getWallet(uid), item: invItem };
  }

  async equip(uid: string, kind: ShopItemKind, itemId: string | null): Promise<WalletDoc> {
    const u = this.users.get(uid);
    if (!u) throw new ShopError(404, 'no-user', 'User not found');
    if (itemId !== null) {
      const owned = u.inventory.get(itemId);
      if (!owned) throw new ShopError(403, 'not-owned', 'Not owned');
      if (owned.kind !== kind) throw new ShopError(400, 'kind-mismatch', 'Wrong slot');
      u.equipped[kind] = itemId;
    } else {
      delete u.equipped[kind];
    }
    return this.getWallet(uid);
  }

  async upsertItem(input: ShopItemInput): Promise<ShopItemDoc> {
    const id = input.id ?? `gen-${++this.seq}`;
    const doc: ShopItemDoc = {
      id,
      kind: input.kind,
      nameVi: input.nameVi,
      descVi: input.descVi,
      priceCoins: input.priceCoins,
      priceGems: input.priceGems,
      rarity: input.rarity,
      payloadKey: input.payloadKey,
      consumable: input.consumable,
      consumableQty: input.consumableQty,
      sortOrder: input.sortOrder,
      active: input.active,
      createdAtMs: ++this.seq,
      updatedAtMs: this.seq,
    };
    this.items.set(id, doc);
    return doc;
  }

  async removeItem(id: string): Promise<boolean> {
    return this.items.delete(id);
  }
}

// ── HTTP test harness ─────────────────────────────────────────────────────────

async function getJson(res: Response): Promise<any> {
  return res.json();
}

function listen(server: Server): Promise<string> {
  return new Promise((resolve) => {
    server.listen(0, '127.0.0.1', () => {
      const addr = server.address() as AddressInfo;
      resolve(`http://127.0.0.1:${addr.port}`);
    });
  });
}

async function withServer(
  store: FakeShopStore,
  extra: ShopApiOptions,
  run: (baseUrl: string) => Promise<void>,
): Promise<void> {
  const api = createShopApi({ store, ...extra });
  const server = createServer((req, res) => {
    void api.handle(req, res).then((handled) => {
      if (!handled && !res.headersSent) {
        res.writeHead(404);
        res.end();
      }
    });
  });
  try {
    const baseUrl = await listen(server);
    await run(baseUrl);
  } finally {
    await new Promise<void>((resolve) => server.close(() => resolve()));
  }
}

// Tests treat the bearer token string as the uid.
const asUid: ShopApiOptions = { authenticate: async (t) => ({ uid: t }) };
const bearer = (uid: string) => ({ authorization: `Bearer ${uid}` });

// ── Validation ────────────────────────────────────────────────────────────────

test('validateShopItemInput normalizes and defaults', () => {
  const input = validateShopItemInput({
    kind: 'boardTheme',
    nameVi: '  Bàn Gỗ Đàn Hương  ',
    payloadKey: 'sandalwood',
    priceCoins: 500.9,
    priceGems: 0,
  });
  assert.equal(input.nameVi, 'Bàn Gỗ Đàn Hương');
  assert.equal(input.priceCoins, 500);
  assert.equal(input.rarity, 'common');
  assert.equal(input.active, true);
  assert.equal(input.consumable, false);
  assert.equal(input.consumableQty, 1);
});

const hasCode = (code: string) => (e: unknown) => (e as ShopError).code === code;

test('validateShopItemInput rejects bad kind / no price / missing fields', () => {
  assert.throws(() => validateShopItemInput({ kind: 'nope', nameVi: 'x', payloadKey: 'y', priceCoins: 1 }), hasCode('invalid-kind'));
  assert.throws(() => validateShopItemInput({ kind: 'boardTheme', nameVi: '', payloadKey: 'y', priceCoins: 1 }), hasCode('invalid-name'));
  assert.throws(() => validateShopItemInput({ kind: 'boardTheme', nameVi: 'x', payloadKey: '', priceCoins: 1 }), hasCode('invalid-payload'));
  assert.throws(() => validateShopItemInput({ kind: 'boardTheme', nameVi: 'x', payloadKey: 'y', priceCoins: 0, priceGems: 0 }), hasCode('invalid-price'));
});

test('validatePurchaseInput + validateEquipInput', () => {
  assert.deepEqual(validatePurchaseInput({ currency: 'gems' }), { currency: 'gems' });
  assert.throws(() => validatePurchaseInput({ currency: 'usd' }), hasCode('invalid-currency'));
  assert.deepEqual(validateEquipInput({ kind: 'boardTheme', itemId: 'x' }), { kind: 'boardTheme', itemId: 'x' });
  assert.deepEqual(validateEquipInput({ kind: 'boardTheme', itemId: null }), { kind: 'boardTheme', itemId: null });
  assert.throws(() => validateEquipInput({ kind: 'consumable', itemId: 'x' }), hasCode('invalid-kind'));
});

// ── Public catalog ────────────────────────────────────────────────────────────

test('GET /shop returns active items sorted, filterable by kind', async () => {
  const store = new FakeShopStore();
  store.seedItem({ id: 'b1', kind: 'boardTheme', nameVi: 'Bàn 1', payloadKey: 'classic', priceCoins: 0, priceGems: 0, sortOrder: 2 });
  store.seedItem({ id: 'b2', kind: 'boardTheme', nameVi: 'Bàn 2', payloadKey: 'jade', priceCoins: 300, sortOrder: 1 });
  store.seedItem({ id: 'p1', kind: 'pieceSet', nameVi: 'Bộ 1', payloadKey: 'ink', priceGems: 50, sortOrder: 3 });
  store.seedItem({ id: 'hidden', kind: 'boardTheme', nameVi: 'Ẩn', payloadKey: 'x', priceCoins: 1, active: false });
  await withServer(store, {}, async (baseUrl) => {
    const all = await getJson(await fetch(`${baseUrl}/shop`));
    assert.deepEqual(all.items.map((i: ShopItemDoc) => i.id), ['b2', 'b1', 'p1']);
    const boards = await getJson(await fetch(`${baseUrl}/shop?kind=boardTheme`));
    assert.deepEqual(boards.items.map((i: ShopItemDoc) => i.id), ['b2', 'b1']);
  });
});

test('GET /shop/:id 404 for missing or inactive', async () => {
  const store = new FakeShopStore();
  store.seedItem({ id: 'hidden', kind: 'boardTheme', nameVi: 'Ẩn', payloadKey: 'x', priceCoins: 1, active: false });
  await withServer(store, {}, async (baseUrl) => {
    assert.equal((await fetch(`${baseUrl}/shop/nope`)).status, 404);
    assert.equal((await fetch(`${baseUrl}/shop/hidden`)).status, 404);
  });
});

// ── Wallet / inventory auth ───────────────────────────────────────────────────

test('GET /wallet requires a token', async () => {
  const store = new FakeShopStore();
  store.seedUser('u1', { coins: 120, gems: 5 });
  await withServer(store, asUid, async (baseUrl) => {
    assert.equal((await fetch(`${baseUrl}/wallet`)).status, 401);
    const w = await getJson(await fetch(`${baseUrl}/wallet`, { headers: bearer('u1') }));
    assert.equal(w.coins, 120);
    assert.equal(w.gems, 5);
  });
});

// ── Purchase ──────────────────────────────────────────────────────────────────

test('purchase debits coins and grants the item', async () => {
  const store = new FakeShopStore();
  store.seedItem({ id: 'jade', kind: 'boardTheme', nameVi: 'Ngọc Bích', payloadKey: 'jade', priceCoins: 300 });
  store.seedUser('u1', { coins: 500 });
  await withServer(store, asUid, async (baseUrl) => {
    const res = await fetch(`${baseUrl}/shop/jade/purchase`, {
      method: 'POST',
      headers: { ...bearer('u1'), 'content-type': 'application/json' },
      body: JSON.stringify({ currency: 'coins' }),
    });
    assert.equal(res.status, 200);
    const body = await getJson(res);
    assert.equal(body.wallet.coins, 200);
    assert.equal(body.item.itemId, 'jade');
    assert.equal(body.item.qty, 1);
    const inv = await getJson(await fetch(`${baseUrl}/inventory`, { headers: bearer('u1') }));
    assert.equal(inv.items.length, 1);
    assert.equal(inv.items[0].payloadKey, 'jade');
  });
});

test('purchase with insufficient funds → 402', async () => {
  const store = new FakeShopStore();
  store.seedItem({ id: 'jade', kind: 'boardTheme', nameVi: 'Ngọc Bích', payloadKey: 'jade', priceCoins: 300 });
  store.seedUser('u1', { coins: 100 });
  await withServer(store, asUid, async (baseUrl) => {
    const res = await fetch(`${baseUrl}/shop/jade/purchase`, {
      method: 'POST',
      headers: { ...bearer('u1'), 'content-type': 'application/json' },
      body: JSON.stringify({ currency: 'coins' }),
    });
    assert.equal(res.status, 402);
    assert.equal((await getJson(res)).code, 'insufficient-funds');
  });
});

test('buying an owned cosmetic twice → 409', async () => {
  const store = new FakeShopStore();
  store.seedItem({ id: 'jade', kind: 'boardTheme', nameVi: 'Ngọc Bích', payloadKey: 'jade', priceCoins: 100 });
  store.seedUser('u1', { coins: 500 });
  await withServer(store, asUid, async (baseUrl) => {
    const buy = () =>
      fetch(`${baseUrl}/shop/jade/purchase`, {
        method: 'POST',
        headers: { ...bearer('u1'), 'content-type': 'application/json' },
        body: JSON.stringify({ currency: 'coins' }),
      });
    assert.equal((await buy()).status, 200);
    assert.equal((await buy()).status, 409);
  });
});

test('purchase rejects a currency the item does not accept', async () => {
  const store = new FakeShopStore();
  store.seedItem({ id: 'jade', kind: 'boardTheme', nameVi: 'Ngọc Bích', payloadKey: 'jade', priceCoins: 100, priceGems: 0 });
  store.seedUser('u1', { gems: 999 });
  await withServer(store, asUid, async (baseUrl) => {
    const res = await fetch(`${baseUrl}/shop/jade/purchase`, {
      method: 'POST',
      headers: { ...bearer('u1'), 'content-type': 'application/json' },
      body: JSON.stringify({ currency: 'gems' }),
    });
    assert.equal(res.status, 400);
    assert.equal((await getJson(res)).code, 'currency-not-accepted');
  });
});

test('consumables can be re-bought and stack', async () => {
  const store = new FakeShopStore();
  store.seedItem({ id: 'hint5', kind: 'consumable', nameVi: 'Gói Gợi Ý', payloadKey: 'hint_pack', priceCoins: 50, consumable: true, consumableQty: 5 });
  store.seedUser('u1', { coins: 500 });
  await withServer(store, asUid, async (baseUrl) => {
    const buy = () =>
      fetch(`${baseUrl}/shop/hint5/purchase`, {
        method: 'POST',
        headers: { ...bearer('u1'), 'content-type': 'application/json' },
        body: JSON.stringify({ currency: 'coins' }),
      });
    await buy();
    const second = await getJson(await buy());
    assert.equal(second.item.qty, 10);
    assert.equal(second.wallet.coins, 400);
  });
});

// ── Equip ─────────────────────────────────────────────────────────────────────

test('equip an owned item then unequip', async () => {
  const store = new FakeShopStore();
  store.seedItem({ id: 'jade', kind: 'boardTheme', nameVi: 'Ngọc Bích', payloadKey: 'jade', priceCoins: 100 });
  store.seedUser('u1', { coins: 500 });
  await withServer(store, asUid, async (baseUrl) => {
    await fetch(`${baseUrl}/shop/jade/purchase`, {
      method: 'POST',
      headers: { ...bearer('u1'), 'content-type': 'application/json' },
      body: JSON.stringify({ currency: 'coins' }),
    });
    const equip = await getJson(
      await fetch(`${baseUrl}/inventory/equip`, {
        method: 'POST',
        headers: { ...bearer('u1'), 'content-type': 'application/json' },
        body: JSON.stringify({ kind: 'boardTheme', itemId: 'jade' }),
      }),
    );
    assert.equal(equip.equipped.boardTheme, 'jade');
    const un = await getJson(
      await fetch(`${baseUrl}/inventory/equip`, {
        method: 'POST',
        headers: { ...bearer('u1'), 'content-type': 'application/json' },
        body: JSON.stringify({ kind: 'boardTheme', itemId: null }),
      }),
    );
    assert.equal(un.equipped.boardTheme, undefined);
  });
});

test('equipping an unowned item → 403', async () => {
  const store = new FakeShopStore();
  store.seedItem({ id: 'jade', kind: 'boardTheme', nameVi: 'Ngọc Bích', payloadKey: 'jade', priceCoins: 100 });
  store.seedUser('u1', { coins: 0 });
  await withServer(store, asUid, async (baseUrl) => {
    const res = await fetch(`${baseUrl}/inventory/equip`, {
      method: 'POST',
      headers: { ...bearer('u1'), 'content-type': 'application/json' },
      body: JSON.stringify({ kind: 'boardTheme', itemId: 'jade' }),
    });
    assert.equal(res.status, 403);
    assert.equal((await getJson(res)).code, 'not-owned');
  });
});

// ── Admin guard ───────────────────────────────────────────────────────────────

test('admin write requires credentials', async () => {
  const store = new FakeShopStore();
  await withServer(store, { isAdmin: () => false }, async (baseUrl) => {
    const denied = await fetch(`${baseUrl}/admin/shop`, {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify({ kind: 'boardTheme', nameVi: 'X', payloadKey: 'x', priceCoins: 1 }),
    });
    assert.equal(denied.status, 403);
  });
  await withServer(store, { isAdmin: () => true }, async (baseUrl) => {
    const ok = await fetch(`${baseUrl}/admin/shop`, {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify({ kind: 'boardTheme', nameVi: 'X', payloadKey: 'x', priceCoins: 1 }),
    });
    assert.equal(ok.status, 201);
  });
});
