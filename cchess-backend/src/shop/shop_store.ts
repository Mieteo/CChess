// Storage layer for the economy. The route handler talks only to the ShopStore
// interface, so tests inject an in-memory fake while production uses
// FirestoreShopStore (Admin SDK → bypasses security rules, which is what lets us
// debit coins/gems the client is forbidden from touching).
//
// Money safety: purchase() and equip() run inside a Firestore transaction so a
// debit + grant is atomic and a double-tap can't overdraw or double-own.

import {
  FieldValue,
  getFirestore,
  Timestamp,
  type Firestore,
} from 'firebase-admin/firestore';

import {
  EQUIPPABLE_KINDS,
  ShopError,
  type Currency,
  type InventoryItemDoc,
  type PurchaseResult,
  type ShopItemDoc,
  type ShopItemInput,
  type ShopItemKind,
  type WalletDoc,
} from './types';

export interface ShopStore {
  listItems(opts?: { kind?: ShopItemKind; activeOnly?: boolean }): Promise<ShopItemDoc[]>;
  getItem(id: string): Promise<ShopItemDoc | null>;
  getWallet(uid: string): Promise<WalletDoc>;
  listInventory(uid: string): Promise<InventoryItemDoc[]>;
  purchase(uid: string, itemId: string, currency: Currency): Promise<PurchaseResult>;
  equip(uid: string, kind: ShopItemKind, itemId: string | null): Promise<WalletDoc>;
  // ── Admin ──
  upsertItem(input: ShopItemInput): Promise<ShopItemDoc>;
  removeItem(id: string): Promise<boolean>;
}

const SHOP_ITEMS = 'shop_items';
const USERS = 'users';
const INVENTORY = 'inventory';
const WALLET_TX = 'wallet_tx';

export interface FirestoreShopOptions {
  getDb?: () => Firestore;
  now?: () => Date;
}

export class FirestoreShopStore implements ShopStore {
  private readonly getDb: () => Firestore;
  private readonly now: () => Date;

  constructor(opts: FirestoreShopOptions = {}) {
    this.getDb = opts.getDb ?? (() => getFirestore());
    this.now = opts.now ?? (() => new Date());
  }

  async listItems(opts: { kind?: ShopItemKind; activeOnly?: boolean } = {}): Promise<ShopItemDoc[]> {
    let query = this.getDb().collection(SHOP_ITEMS) as FirebaseFirestore.Query;
    if (opts.kind) query = query.where('kind', '==', opts.kind);
    const snap = await query.get();
    // Filter active + order by sortOrder in memory so we never need a composite
    // index (the catalog is small).
    const items = snap.docs
      .map((d) => mapItem(d.id, d.data()))
      .filter((it) => (opts.activeOnly === false ? true : it.active));
    items.sort((a, b) => a.sortOrder - b.sortOrder || a.id.localeCompare(b.id));
    return items;
  }

  async getItem(id: string): Promise<ShopItemDoc | null> {
    const snap = await this.getDb().collection(SHOP_ITEMS).doc(id).get();
    return snap.exists ? mapItem(snap.id, snap.data() ?? {}) : null;
  }

  async getWallet(uid: string): Promise<WalletDoc> {
    const snap = await this.getDb().collection(USERS).doc(uid).get();
    return walletFrom(snap.exists ? snap.data() ?? {} : {});
  }

  async listInventory(uid: string): Promise<InventoryItemDoc[]> {
    const snap = await this.getDb()
      .collection(USERS)
      .doc(uid)
      .collection(INVENTORY)
      .get();
    return snap.docs.map((d) => mapInventory(d.id, d.data()));
  }

  async purchase(uid: string, itemId: string, currency: Currency): Promise<PurchaseResult> {
    const db = this.getDb();
    const now = this.now();
    const itemRef = db.collection(SHOP_ITEMS).doc(itemId);
    const userRef = db.collection(USERS).doc(uid);
    const invRef = userRef.collection(INVENTORY).doc(itemId);

    return db.runTransaction(async (tx) => {
      // ── All reads first (Firestore requirement) ──
      const [itemSnap, userSnap, invSnap] = await Promise.all([
        tx.get(itemRef),
        tx.get(userRef),
        tx.get(invRef),
      ]);

      if (!itemSnap.exists) throw new ShopError(404, 'not-found', 'Item not found');
      const item = mapItem(itemSnap.id, itemSnap.data() ?? {});
      if (!item.active) throw new ShopError(404, 'not-found', 'Item is not available');

      const price = currency === 'coins' ? item.priceCoins : item.priceGems;
      if (price <= 0) {
        throw new ShopError(400, 'currency-not-accepted', `Item cannot be bought with ${currency}`);
      }

      if (!item.consumable && invSnap.exists) {
        throw new ShopError(409, 'already-owned', 'You already own this item');
      }

      const wallet = walletFrom(userSnap.exists ? userSnap.data() ?? {} : {});
      const balance = currency === 'coins' ? wallet.coins : wallet.gems;
      if (balance < price) {
        throw new ShopError(402, 'insufficient-funds', `Not enough ${currency}`);
      }

      // ── Writes ──
      const grantQty = item.consumable ? item.consumableQty : 1;
      const prevQty = invSnap.exists ? mapInventory(invSnap.id, invSnap.data() ?? {}).qty : 0;
      const newQty = item.consumable ? prevQty + grantQty : 1;

      tx.update(userRef, { [currency]: balance - price, updatedAt: now });
      tx.set(
        invRef,
        {
          itemId,
          kind: item.kind,
          payloadKey: item.payloadKey,
          qty: newQty,
          acquiredAt: invSnap.exists ? (invSnap.data() ?? {}).acquiredAt ?? now : now,
          updatedAt: now,
        },
        { merge: true },
      );
      tx.set(userRef.collection(WALLET_TX).doc(), {
        type: 'purchase',
        itemId,
        currency,
        amount: price,
        balanceAfter: balance - price,
        at: now,
      });

      const nextWallet: WalletDoc = {
        coins: currency === 'coins' ? wallet.coins - price : wallet.coins,
        gems: currency === 'gems' ? wallet.gems - price : wallet.gems,
        equipped: wallet.equipped,
      };
      const grantedItem: InventoryItemDoc = {
        itemId,
        kind: item.kind,
        payloadKey: item.payloadKey,
        qty: newQty,
        acquiredAtMs: now.getTime(),
      };
      return { wallet: nextWallet, item: grantedItem };
    });
  }

  async equip(uid: string, kind: ShopItemKind, itemId: string | null): Promise<WalletDoc> {
    if (!EQUIPPABLE_KINDS.has(kind)) {
      throw new ShopError(400, 'invalid-kind', 'kind is not an equippable cosmetic slot');
    }
    const db = this.getDb();
    const now = this.now();
    const userRef = db.collection(USERS).doc(uid);

    return db.runTransaction(async (tx) => {
      const userSnap = await tx.get(userRef);
      if (!userSnap.exists) throw new ShopError(404, 'no-user', 'User profile not found');
      const wallet = walletFrom(userSnap.data() ?? {});

      if (itemId !== null) {
        const invSnap = await tx.get(userRef.collection(INVENTORY).doc(itemId));
        if (!invSnap.exists) throw new ShopError(403, 'not-owned', 'You do not own this item');
        const owned = mapInventory(invSnap.id, invSnap.data() ?? {});
        if (owned.kind !== kind) {
          throw new ShopError(400, 'kind-mismatch', 'Item does not fit this slot');
        }
      }

      const fieldPath = `equipped.${kind}`;
      tx.update(userRef, {
        [fieldPath]: itemId ?? FieldValue.delete(),
        updatedAt: now,
      });

      const equipped = { ...wallet.equipped };
      if (itemId === null) {
        delete equipped[kind];
      } else {
        equipped[kind] = itemId;
      }
      return { coins: wallet.coins, gems: wallet.gems, equipped };
    });
  }

  async upsertItem(input: ShopItemInput): Promise<ShopItemDoc> {
    const db = this.getDb();
    const now = this.now();
    const col = db.collection(SHOP_ITEMS);
    const id = input.id ?? (await uniqueId(col, slugifyId(input.nameVi)));
    const ref = col.doc(id);
    const existing = await ref.get();
    const payload = {
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
      createdAt: existing.exists ? (existing.data() ?? {}).createdAt ?? now : now,
      updatedAt: now,
    };
    await ref.set(payload, { merge: true });
    return mapItem(id, payload);
  }

  async removeItem(id: string): Promise<boolean> {
    const ref = this.getDb().collection(SHOP_ITEMS).doc(id);
    const snap = await ref.get();
    if (!snap.exists) return false;
    await ref.delete();
    return true;
  }
}

// ── Mapping helpers ───────────────────────────────────────────────────────────

function toMillis(value: unknown): number | null {
  if (value === null || value === undefined) return null;
  if (typeof value === 'number') return value;
  if (value instanceof Date) return value.getTime();
  if (value instanceof Timestamp) return value.toMillis();
  const maybe = value as { toMillis?: () => number };
  if (typeof maybe.toMillis === 'function') return maybe.toMillis();
  return null;
}

function num(value: unknown, fallback = 0): number {
  return typeof value === 'number' && Number.isFinite(value) ? value : fallback;
}

export function mapItem(id: string, data: Record<string, unknown>): ShopItemDoc {
  return {
    id,
    kind: (data.kind as ShopItemKind) ?? 'consumable',
    nameVi: String(data.nameVi ?? ''),
    descVi: String(data.descVi ?? ''),
    priceCoins: num(data.priceCoins),
    priceGems: num(data.priceGems),
    rarity: (data.rarity as ShopItemDoc['rarity']) ?? 'common',
    payloadKey: String(data.payloadKey ?? ''),
    consumable: data.consumable === true,
    consumableQty: num(data.consumableQty, 1),
    sortOrder: num(data.sortOrder),
    active: data.active !== false,
    createdAtMs: toMillis(data.createdAt),
    updatedAtMs: toMillis(data.updatedAt),
  };
}

export function mapInventory(itemId: string, data: Record<string, unknown>): InventoryItemDoc {
  return {
    itemId,
    kind: (data.kind as ShopItemKind) ?? 'consumable',
    payloadKey: String(data.payloadKey ?? ''),
    qty: num(data.qty, 1),
    acquiredAtMs: toMillis(data.acquiredAt),
  };
}

function walletFrom(data: Record<string, unknown>): WalletDoc {
  const equippedRaw = data.equipped;
  const equipped: Record<string, string> = {};
  if (equippedRaw && typeof equippedRaw === 'object') {
    for (const [k, v] of Object.entries(equippedRaw as Record<string, unknown>)) {
      if (typeof v === 'string' && v.length > 0) equipped[k] = v;
    }
  }
  return { coins: num(data.coins), gems: num(data.gems), equipped };
}

/// Slug a human name into a stable-ish id when the caller didn't supply one.
function slugifyId(name: string): string {
  const base = name
    .normalize('NFD')
    .replace(/[̀-ͯ]/g, '') // strip diacritics
    .toLowerCase()
    .replace(/đ/g, 'd')
    .replace(/[^a-z0-9]+/g, '-')
    .replace(/^-+|-+$/g, '')
    .slice(0, 40);
  return base.length > 0 ? base : 'item';
}

async function uniqueId(col: FirebaseFirestore.CollectionReference, base: string): Promise<string> {
  if (!(await col.doc(base).get()).exists) return base;
  for (let i = 2; i < 1000; i++) {
    const candidate = `${base}-${i}`;
    if (!(await col.doc(candidate).get()).exists) return candidate;
  }
  return `${base}-${Date.now()}`;
}
