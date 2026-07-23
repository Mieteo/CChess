// Types + validation for the S16 economy extension (Khám Phá — D4 Hộp Thư,
// D5 Sự Kiện, D6 Phúc Lợi, D7 Đúc Bàn Cờ). One module (not four) because every
// feature ends the same way: atomically crediting a RewardBundle into the
// wallet (`users/{uid}.coins/gems`) + inventory (`users/{uid}/inventory`) that
// the shop module owns. Firestore layout:
//   users/{uid}/mail/{mailId}          — personal mailbox (server-write only)
//   events/{eventId}                   — seasonal event catalog (public read)
//   users/{uid}/event_claims/{key}     — one doc per claimed event gift
//   users/{uid}/welfare/state          — check-in streak + one-time gift flags
//   craft_recipes/{recipeId}           — crafting catalog (public read)
// All writes go through the Admin SDK in transactions; security rules keep
// every one of these collections client-read-only.

import type { ShopItemKind } from '../shop/types';
import { isShopItemKind } from '../shop/types';

/// HTTP-shaped error (duck-typed by http_util.sendError).
export class EconomyError extends Error {
  constructor(
    public readonly statusCode: number,
    public readonly code: string,
    message: string,
  ) {
    super(message);
    this.name = 'EconomyError';
  }
}

// ── Rewards ───────────────────────────────────────────────────────────────────

/// A concrete item grant inside a reward. Mirrors InventoryItemDoc so claiming
/// writes straight into the same `users/{uid}/inventory/{itemId}` docs the shop
/// uses (consumables stack, cosmetics cap at qty 1).
export interface RewardItem {
  itemId: string;
  kind: ShopItemKind;
  payloadKey: string;
  qty: number;
}

export interface RewardBundle {
  coins: number;
  gems: number;
  items: RewardItem[];
}

export const EMPTY_REWARD: RewardBundle = { coins: 0, gems: 0, items: [] };

export function isEmptyReward(r: RewardBundle | null | undefined): boolean {
  return !r || (r.coins <= 0 && r.gems <= 0 && r.items.length === 0);
}

// ── Mail (D4) ────────────────────────────────────────────────────────────────

export interface MailDoc {
  id: string;
  title: string;
  body: string;
  /// null → pure notification, nothing to claim.
  reward: RewardBundle | null;
  read: boolean;
  claimed: boolean;
  createdAtMs: number | null;
  expiresAtMs: number | null;
}

/// Validated admin "send mail" request.
export interface SendMailInput {
  uids: string[];
  title: string;
  body: string;
  reward: RewardBundle | null;
  expiresAtMs: number | null;
}

// ── Events (D5) ──────────────────────────────────────────────────────────────

export interface EventGift {
  id: string;
  title: string;
  reward: RewardBundle;
}

export interface EventDoc {
  id: string;
  title: string;
  descVi: string;
  startAtMs: number;
  endAtMs: number;
  active: boolean;
  sortOrder: number;
  gifts: EventGift[];
}

export interface EventInput {
  id?: string;
  title: string;
  descVi: string;
  startAtMs: number;
  endAtMs: number;
  active: boolean;
  sortOrder: number;
  gifts: EventGift[];
}

export interface EventClaim {
  eventId: string;
  giftId: string;
}

/// True when the event should be visible/claimable at [nowMs].
export function eventLive(event: EventDoc, nowMs: number): boolean {
  return event.active && event.startAtMs <= nowMs && nowMs <= event.endAtMs;
}

// ── Welfare (D6) ─────────────────────────────────────────────────────────────

/// Escalating 7-day check-in cycle (day 7 pays gems). Positions repeat:
/// streak day 8 earns the day-1 reward again.
export const CHECKIN_REWARDS: readonly RewardBundle[] = [
  { coins: 20, gems: 0, items: [] },
  { coins: 30, gems: 0, items: [] },
  { coins: 40, gems: 0, items: [] },
  { coins: 50, gems: 0, items: [] },
  { coins: 60, gems: 0, items: [] },
  { coins: 80, gems: 0, items: [] },
  { coins: 100, gems: 5, items: [] },
];

export const NEWBIE_GIFT: RewardBundle = { coins: 200, gems: 10, items: [] };
export const COMEBACK_GIFT: RewardBundle = { coins: 100, gems: 5, items: [] };
/// Days away from the last check-in before the comeback gift unlocks.
export const COMEBACK_GAP_DAYS = 7;

/// The persisted state doc (users/{uid}/welfare/state).
export interface WelfareState {
  streak: number;
  totalCheckins: number;
  /// VN-timezone "YYYY-MM-DD" of the last check-in, or null if never.
  lastCheckinDate: string | null;
  newbieClaimed: boolean;
  /// VN date the comeback gift was last claimed for (one claim per comeback).
  comebackClaimedFor: string | null;
  /// Set by check-in when it detects a ≥7-day gap, so the comeback gift stays
  /// claimable the rest of that day even though the gap has just been reset.
  comebackAvailableDate: string | null;
}

export const EMPTY_WELFARE_STATE: WelfareState = {
  streak: 0,
  totalCheckins: 0,
  lastCheckinDate: null,
  newbieClaimed: false,
  comebackClaimedFor: null,
  comebackAvailableDate: null,
};

/// The wire status the client renders (state + derived flags + reward table).
export interface WelfareStatus {
  streak: number;
  totalCheckins: number;
  lastCheckinDate: string | null;
  todayClaimed: boolean;
  /// 0-based cycle slot today's (next) check-in pays out.
  todayIndex: number;
  newbieClaimed: boolean;
  comebackAvailable: boolean;
  cycle: readonly RewardBundle[];
}

/// Difference in whole days between two "YYYY-MM-DD" keys (b - a).
export function dayGap(a: string, b: string): number {
  return Math.round((Date.parse(b) - Date.parse(a)) / 86_400_000);
}

/// Derive the client-facing status from persisted state at VN date [today].
export function deriveWelfareStatus(state: WelfareState, today: string): WelfareStatus {
  const todayClaimed = state.lastCheckinDate === today;
  let todayIndex: number;
  if (todayClaimed) {
    todayIndex = (state.streak - 1) % 7;
  } else if (state.lastCheckinDate !== null && dayGap(state.lastCheckinDate, today) === 1) {
    todayIndex = state.streak % 7;
  } else {
    todayIndex = 0; // never checked in, or the streak broke
  }
  const gap = state.lastCheckinDate === null ? 0 : dayGap(state.lastCheckinDate, today);
  const comebackAvailable =
    state.comebackClaimedFor !== today &&
    (gap >= COMEBACK_GAP_DAYS || state.comebackAvailableDate === today);
  return {
    streak: state.streak,
    totalCheckins: state.totalCheckins,
    lastCheckinDate: state.lastCheckinDate,
    todayClaimed,
    todayIndex,
    newbieClaimed: state.newbieClaimed,
    comebackAvailable,
    cycle: CHECKIN_REWARDS,
  };
}

// ── Crafting (D7) ────────────────────────────────────────────────────────────

export interface CraftIngredient {
  itemId: string;
  qty: number;
}

export interface CraftRecipeDoc {
  id: string;
  nameVi: string;
  descVi: string;
  ingredients: CraftIngredient[];
  costCoins: number;
  output: RewardItem;
  active: boolean;
  sortOrder: number;
  createdAtMs: number | null;
  updatedAtMs: number | null;
}

export interface CraftRecipeInput {
  id?: string;
  nameVi: string;
  descVi: string;
  ingredients: CraftIngredient[];
  costCoins: number;
  output: RewardItem;
  active: boolean;
  sortOrder: number;
}

// ── Validation ────────────────────────────────────────────────────────────────

function asTrimmedString(value: unknown): string {
  return typeof value === 'string' ? value.trim() : '';
}

function asNonNegInt(value: unknown): number {
  const n = Number(value);
  return Number.isFinite(n) ? Math.max(0, Math.trunc(n)) : 0;
}

function asMs(value: unknown): number | null {
  const n = Number(value);
  return Number.isFinite(n) && n > 0 ? Math.trunc(n) : null;
}

/// Validate + normalize a reward bundle. Returns null for an absent/empty one.
export function validateReward(raw: unknown): RewardBundle | null {
  if (raw === null || raw === undefined) return null;
  if (typeof raw !== 'object') {
    throw new EconomyError(400, 'invalid-reward', 'reward must be an object');
  }
  const obj = raw as Record<string, unknown>;
  const coins = asNonNegInt(obj.coins);
  const gems = asNonNegInt(obj.gems);
  const items: RewardItem[] = [];
  if (obj.items !== undefined) {
    if (!Array.isArray(obj.items)) {
      throw new EconomyError(400, 'invalid-reward', 'reward.items must be an array');
    }
    for (const it of obj.items) {
      items.push(validateRewardItem(it));
    }
  }
  const bundle: RewardBundle = { coins, gems, items };
  return isEmptyReward(bundle) ? null : bundle;
}

export function validateRewardItem(raw: unknown): RewardItem {
  if (typeof raw !== 'object' || raw === null) {
    throw new EconomyError(400, 'invalid-reward-item', 'reward item must be an object');
  }
  const obj = raw as Record<string, unknown>;
  const itemId = asTrimmedString(obj.itemId);
  const payloadKey = asTrimmedString(obj.payloadKey);
  if (itemId.length === 0) {
    throw new EconomyError(400, 'invalid-reward-item', 'reward item needs itemId');
  }
  if (!isShopItemKind(obj.kind)) {
    throw new EconomyError(400, 'invalid-reward-item', `reward item ${itemId} has invalid kind`);
  }
  if (payloadKey.length === 0) {
    throw new EconomyError(400, 'invalid-reward-item', `reward item ${itemId} needs payloadKey`);
  }
  return { itemId, kind: obj.kind, payloadKey, qty: Math.max(1, asNonNegInt(obj.qty) || 1) };
}

/// Validate the admin send-mail body: `{ uid | uids[], title, body?, reward?,
/// expiresAtMs? }`.
export function validateSendMailInput(raw: unknown): SendMailInput {
  if (typeof raw !== 'object' || raw === null) {
    throw new EconomyError(400, 'invalid-request', 'Body must be a JSON object');
  }
  const obj = raw as Record<string, unknown>;
  const uids: string[] = [];
  if (Array.isArray(obj.uids)) {
    for (const u of obj.uids) {
      const uid = asTrimmedString(u);
      if (uid.length > 0) uids.push(uid);
    }
  }
  const single = asTrimmedString(obj.uid);
  if (single.length > 0) uids.push(single);
  if (uids.length === 0) {
    throw new EconomyError(400, 'invalid-uids', 'Provide uid or a non-empty uids[]');
  }
  const title = asTrimmedString(obj.title);
  if (title.length === 0) {
    throw new EconomyError(400, 'invalid-title', 'title is required');
  }
  return {
    uids: [...new Set(uids)],
    title,
    body: asTrimmedString(obj.body),
    reward: validateReward(obj.reward),
    expiresAtMs: asMs(obj.expiresAtMs),
  };
}

/// Validate an admin event upsert.
export function validateEventInput(raw: unknown): EventInput {
  if (typeof raw !== 'object' || raw === null) {
    throw new EconomyError(400, 'invalid-request', 'Body must be a JSON object');
  }
  const obj = raw as Record<string, unknown>;
  const title = asTrimmedString(obj.title);
  if (title.length === 0) {
    throw new EconomyError(400, 'invalid-title', 'title is required');
  }
  const startAtMs = asMs(obj.startAtMs);
  const endAtMs = asMs(obj.endAtMs);
  if (startAtMs === null || endAtMs === null || endAtMs <= startAtMs) {
    throw new EconomyError(400, 'invalid-window', 'startAtMs/endAtMs must form a valid window');
  }
  if (!Array.isArray(obj.gifts) || obj.gifts.length === 0) {
    throw new EconomyError(400, 'invalid-gifts', 'gifts[] must be non-empty');
  }
  const gifts: EventGift[] = [];
  const seen = new Set<string>();
  for (const g of obj.gifts) {
    const go = (typeof g === 'object' && g !== null ? g : {}) as Record<string, unknown>;
    const id = asTrimmedString(go.id);
    const gtitle = asTrimmedString(go.title);
    if (id.length === 0 || gtitle.length === 0) {
      throw new EconomyError(400, 'invalid-gift', 'each gift needs id + title');
    }
    if (seen.has(id)) {
      throw new EconomyError(400, 'invalid-gift', `duplicate gift id ${id}`);
    }
    seen.add(id);
    const reward = validateReward(go.reward);
    if (reward === null) {
      throw new EconomyError(400, 'invalid-gift', `gift ${id} needs a non-empty reward`);
    }
    gifts.push({ id, title: gtitle, reward });
  }
  const idRaw = asTrimmedString(obj.id);
  return {
    id: idRaw.length > 0 ? idRaw : undefined,
    title,
    descVi: asTrimmedString(obj.descVi),
    startAtMs,
    endAtMs,
    active: obj.active !== false,
    sortOrder: asNonNegInt(obj.sortOrder),
    gifts,
  };
}

/// Validate an admin craft-recipe upsert.
export function validateRecipeInput(raw: unknown): CraftRecipeInput {
  if (typeof raw !== 'object' || raw === null) {
    throw new EconomyError(400, 'invalid-request', 'Body must be a JSON object');
  }
  const obj = raw as Record<string, unknown>;
  const nameVi = asTrimmedString(obj.nameVi);
  if (nameVi.length === 0) {
    throw new EconomyError(400, 'invalid-name', 'nameVi is required');
  }
  if (!Array.isArray(obj.ingredients) || obj.ingredients.length === 0) {
    throw new EconomyError(400, 'invalid-ingredients', 'ingredients[] must be non-empty');
  }
  const ingredients: CraftIngredient[] = [];
  const seen = new Set<string>();
  for (const ing of obj.ingredients) {
    const io = (typeof ing === 'object' && ing !== null ? ing : {}) as Record<string, unknown>;
    const itemId = asTrimmedString(io.itemId);
    if (itemId.length === 0) {
      throw new EconomyError(400, 'invalid-ingredient', 'each ingredient needs itemId');
    }
    if (seen.has(itemId)) {
      throw new EconomyError(400, 'invalid-ingredient', `duplicate ingredient ${itemId}`);
    }
    seen.add(itemId);
    ingredients.push({ itemId, qty: Math.max(1, asNonNegInt(io.qty) || 1) });
  }
  const output = validateRewardItem(obj.output);
  const idRaw = asTrimmedString(obj.id);
  return {
    id: idRaw.length > 0 ? idRaw : undefined,
    nameVi,
    descVi: asTrimmedString(obj.descVi),
    ingredients,
    costCoins: asNonNegInt(obj.costCoins),
    output,
    active: obj.active !== false,
    sortOrder: asNonNegInt(obj.sortOrder),
  };
}

/// Validate the event-claim body `{ giftId }`.
export function validateEventClaimInput(raw: unknown): { giftId: string } {
  const obj = (typeof raw === 'object' && raw !== null ? raw : {}) as Record<string, unknown>;
  const giftId = asTrimmedString(obj.giftId);
  if (giftId.length === 0) {
    throw new EconomyError(400, 'invalid-gift', 'giftId is required');
  }
  return { giftId };
}
