// Types + validation for the economy / Khám Phá module (S16 — Thương Thành +
// Balo). A shop item is a purchasable cosmetic or consumable. The catalog lives
// in Firestore `shop_items/{id}` (public read); ownership lives under
// `users/{uid}/inventory/{itemId}`; the wallet (coins/gems) + active loadout
// (`equipped`) live on `users/{uid}`. ALL economy writes go through the Admin
// SDK in a transaction so balances can't be forged from a client (the security
// rules keep `coins`/`gems` client-immutable).

export const SHOP_ITEM_KINDS = [
  'boardTheme',
  'pieceSet',
  'avatarFrame',
  'chatBubble',
  'nameplate',
  'soundPack',
  'consumable',
] as const;
export type ShopItemKind = (typeof SHOP_ITEM_KINDS)[number];

/// Cosmetic slots — exactly one item may be equipped per slot. `consumable` is
/// not a slot (you can't "equip" a consumable).
export const EQUIPPABLE_KINDS: ReadonlySet<ShopItemKind> = new Set([
  'boardTheme',
  'pieceSet',
  'avatarFrame',
  'chatBubble',
  'nameplate',
  'soundPack',
]);

export const RARITIES = ['common', 'rare', 'epic', 'legendary'] as const;
export type Rarity = (typeof RARITIES)[number];

export const CURRENCIES = ['coins', 'gems'] as const;
export type Currency = (typeof CURRENCIES)[number];

/// A catalog item as returned to the client.
export interface ShopItemDoc {
  id: string;
  kind: ShopItemKind;
  nameVi: string;
  descVi: string;
  /// Price in each currency; 0 means "not purchasable with this currency".
  priceCoins: number;
  priceGems: number;
  rarity: Rarity;
  /// Key the client maps to a concrete asset/theme (e.g. a board-theme key).
  payloadKey: string;
  /// Consumables can be re-bought and stack; cosmetics are one-and-done.
  consumable: boolean;
  /// How many units a single purchase grants (consumables only; else 1).
  consumableQty: number;
  sortOrder: number;
  active: boolean;
  createdAtMs: number | null;
  updatedAtMs: number | null;
}

/// One owned item under users/{uid}/inventory/{itemId}.
export interface InventoryItemDoc {
  itemId: string;
  kind: ShopItemKind;
  payloadKey: string;
  /// Units owned (cosmetics: 1; consumables: running total).
  qty: number;
  acquiredAtMs: number | null;
}

/// The wallet + active loadout read off users/{uid}.
export interface WalletDoc {
  coins: number;
  gems: number;
  /// Active loadout: cosmetic kind -> equipped itemId.
  equipped: Record<string, string>;
}

export interface PurchaseResult {
  wallet: WalletDoc;
  item: InventoryItemDoc;
}

/// Validated, normalized catalog item ready to persist.
export interface ShopItemInput {
  id?: string;
  kind: ShopItemKind;
  nameVi: string;
  descVi: string;
  priceCoins: number;
  priceGems: number;
  rarity: Rarity;
  payloadKey: string;
  consumable: boolean;
  consumableQty: number;
  sortOrder: number;
  active: boolean;
}

/// HTTP-shaped error the router converts to `{ code, message }` + status.
export class ShopError extends Error {
  constructor(
    public readonly statusCode: number,
    public readonly code: string,
    message: string,
  ) {
    super(message);
    this.name = 'ShopError';
  }
}

// ── Validation ────────────────────────────────────────────────────────────────

function asTrimmedString(value: unknown): string {
  return typeof value === 'string' ? value.trim() : '';
}

function asNonNegInt(value: unknown): number {
  const n = Number(value);
  return Number.isFinite(n) ? Math.max(0, Math.trunc(n)) : 0;
}

export function isShopItemKind(value: unknown): value is ShopItemKind {
  return typeof value === 'string' && (SHOP_ITEM_KINDS as readonly string[]).includes(value);
}

export function isCurrency(value: unknown): value is Currency {
  return typeof value === 'string' && (CURRENCIES as readonly string[]).includes(value);
}

/// Validate + normalize a raw catalog item (from JSON import or admin POST).
/// Throws ShopError(400, …) on the first problem. Fills sensible defaults.
export function validateShopItemInput(raw: unknown): ShopItemInput {
  if (typeof raw !== 'object' || raw === null) {
    throw new ShopError(400, 'invalid-item', 'Item must be a JSON object');
  }
  const obj = raw as Record<string, unknown>;

  if (!isShopItemKind(obj.kind)) {
    throw new ShopError(400, 'invalid-kind', `kind must be one of ${SHOP_ITEM_KINDS.join(', ')}`);
  }
  const nameVi = asTrimmedString(obj.nameVi);
  if (nameVi.length === 0) {
    throw new ShopError(400, 'invalid-name', 'nameVi is required');
  }
  const payloadKey = asTrimmedString(obj.payloadKey);
  if (payloadKey.length === 0) {
    throw new ShopError(400, 'invalid-payload', 'payloadKey is required');
  }

  const priceCoins = asNonNegInt(obj.priceCoins);
  const priceGems = asNonNegInt(obj.priceGems);
  if (priceCoins === 0 && priceGems === 0) {
    throw new ShopError(400, 'invalid-price', 'Item must have a positive price in coins or gems');
  }

  const rarity: Rarity = (RARITIES as readonly string[]).includes(obj.rarity as string)
    ? (obj.rarity as Rarity)
    : 'common';

  const consumable = obj.consumable === true;
  const consumableQty = consumable ? Math.max(1, asNonNegInt(obj.consumableQty) || 1) : 1;
  const idRaw = asTrimmedString(obj.id);

  return {
    id: idRaw.length > 0 ? idRaw : undefined,
    kind: obj.kind,
    nameVi,
    descVi: asTrimmedString(obj.descVi),
    priceCoins,
    priceGems,
    rarity,
    payloadKey,
    consumable,
    consumableQty,
    sortOrder: asNonNegInt(obj.sortOrder),
    active: obj.active !== false, // default true
  };
}

/// Validate the purchase body: `{ currency: 'coins' | 'gems' }`.
export function validatePurchaseInput(raw: unknown): { currency: Currency } {
  const obj = (typeof raw === 'object' && raw !== null ? raw : {}) as Record<string, unknown>;
  if (!isCurrency(obj.currency)) {
    throw new ShopError(400, 'invalid-currency', "currency must be 'coins' or 'gems'");
  }
  return { currency: obj.currency };
}

/// Validate the equip body: `{ kind, itemId }`. `itemId: null` means unequip
/// the slot. Throws on a non-equippable kind.
export function validateEquipInput(raw: unknown): { kind: ShopItemKind; itemId: string | null } {
  const obj = (typeof raw === 'object' && raw !== null ? raw : {}) as Record<string, unknown>;
  if (!isShopItemKind(obj.kind) || !EQUIPPABLE_KINDS.has(obj.kind)) {
    throw new ShopError(400, 'invalid-kind', 'kind must be an equippable cosmetic slot');
  }
  const itemId = obj.itemId === null || obj.itemId === undefined ? null : asTrimmedString(obj.itemId);
  return { kind: obj.kind, itemId: itemId && itemId.length > 0 ? itemId : null };
}
