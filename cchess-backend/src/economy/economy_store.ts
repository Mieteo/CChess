// Storage layer for the S16 economy extension (mail / events / welfare /
// crafting). Route handlers talk only to the EconomyStore interface so tests
// inject an in-memory fake; production uses FirestoreEconomyStore (Admin SDK →
// bypasses security rules, which keep all of these collections client-read-only).
//
// Money safety: every claim/craft runs inside a Firestore transaction that
// re-checks the "not yet claimed" precondition before crediting, so a
// double-tap can't double-grant, and crafting's debit + ingredient burn +
// output grant is atomic.

import {
  getFirestore,
  Timestamp,
  type Firestore,
  type Transaction,
} from 'firebase-admin/firestore';

import { mapInventory } from '../shop/shop_store';
import type { InventoryItemDoc } from '../shop/types';
import { dateKeyVN } from '../puzzles/types';
import {
  COMEBACK_GAP_DAYS,
  COMEBACK_GIFT,
  CHECKIN_REWARDS,
  EMPTY_WELFARE_STATE,
  EconomyError,
  dayGap,
  deriveWelfareStatus,
  eventLive,
  isEmptyReward,
  NEWBIE_GIFT,
  type CraftRecipeDoc,
  type CraftRecipeInput,
  type EventClaim,
  type EventDoc,
  type EventGift,
  type EventInput,
  type MailDoc,
  type RewardBundle,
  type RewardItem,
  type SendMailInput,
  type WelfareState,
  type WelfareStatus,
} from './types';

/// Wallet balance after a credit/debit (economy never touches `equipped`).
export interface BalanceDoc {
  coins: number;
  gems: number;
}

export interface ClaimResult {
  wallet: BalanceDoc;
  reward: RewardBundle;
}

export interface WelfareClaimResult extends ClaimResult {
  status: WelfareStatus;
}

export interface CraftResult {
  wallet: BalanceDoc;
  item: InventoryItemDoc;
}

export interface EconomyStore {
  // ── Mail (D4) ──
  listMail(uid: string): Promise<MailDoc[]>;
  markMailRead(uid: string, mailId: string): Promise<void>;
  claimMail(uid: string, mailId: string): Promise<ClaimResult>;
  deleteMail(uid: string, mailId: string): Promise<boolean>;
  sendMail(input: SendMailInput): Promise<number>;
  // ── Events (D5) ──
  listEvents(): Promise<EventDoc[]>;
  getEvent(eventId: string): Promise<EventDoc | null>;
  listEventClaims(uid: string): Promise<EventClaim[]>;
  claimEventGift(uid: string, eventId: string, giftId: string): Promise<ClaimResult>;
  upsertEvent(input: EventInput): Promise<EventDoc>;
  removeEvent(eventId: string): Promise<boolean>;
  // ── Welfare (D6) ──
  getWelfare(uid: string): Promise<WelfareStatus>;
  checkin(uid: string): Promise<WelfareClaimResult>;
  claimNewbie(uid: string): Promise<WelfareClaimResult>;
  claimComeback(uid: string): Promise<WelfareClaimResult>;
  // ── Crafting (D7) ──
  listRecipes(): Promise<CraftRecipeDoc[]>;
  craft(uid: string, recipeId: string): Promise<CraftResult>;
  upsertRecipe(input: CraftRecipeInput): Promise<CraftRecipeDoc>;
  removeRecipe(recipeId: string): Promise<boolean>;
}

const USERS = 'users';
const MAIL = 'mail';
const EVENTS = 'events';
const EVENT_CLAIMS = 'event_claims';
const WELFARE = 'welfare';
const WELFARE_STATE_DOC = 'state';
const CRAFT_RECIPES = 'craft_recipes';
const INVENTORY = 'inventory';
const WALLET_TX = 'wallet_tx';

export interface FirestoreEconomyOptions {
  getDb?: () => Firestore;
  now?: () => Date;
}

export class FirestoreEconomyStore implements EconomyStore {
  private readonly getDb: () => Firestore;
  private readonly now: () => Date;

  constructor(opts: FirestoreEconomyOptions = {}) {
    this.getDb = opts.getDb ?? (() => getFirestore());
    this.now = opts.now ?? (() => new Date());
  }

  // ── Mail ────────────────────────────────────────────────────────────────────

  async listMail(uid: string): Promise<MailDoc[]> {
    const snap = await this.getDb().collection(USERS).doc(uid).collection(MAIL).get();
    const nowMs = this.now().getTime();
    const messages = snap.docs
      .map((d) => mapMail(d.id, d.data()))
      .filter((m) => m.expiresAtMs === null || m.expiresAtMs > nowMs);
    // Newest first.
    messages.sort((a, b) => (b.createdAtMs ?? 0) - (a.createdAtMs ?? 0));
    return messages;
  }

  async markMailRead(uid: string, mailId: string): Promise<void> {
    const ref = this.mailRef(uid, mailId);
    const snap = await ref.get();
    if (!snap.exists) throw new EconomyError(404, 'not-found', 'Mail not found');
    await ref.update({ read: true, updatedAt: this.now() });
  }

  async claimMail(uid: string, mailId: string): Promise<ClaimResult> {
    const db = this.getDb();
    const now = this.now();
    const userRef = db.collection(USERS).doc(uid);
    const mailRef = this.mailRef(uid, mailId);

    return db.runTransaction(async (tx) => {
      const mailSnap = await tx.get(mailRef);
      if (!mailSnap.exists) throw new EconomyError(404, 'not-found', 'Mail not found');
      const mail = mapMail(mailSnap.id, mailSnap.data() ?? {});
      if (mail.expiresAtMs !== null && mail.expiresAtMs <= now.getTime()) {
        throw new EconomyError(404, 'not-found', 'Mail has expired');
      }
      if (mail.claimed) throw new EconomyError(409, 'already-claimed', 'Reward already claimed');
      if (isEmptyReward(mail.reward)) {
        throw new EconomyError(400, 'no-reward', 'Mail has no reward to claim');
      }
      const reward = mail.reward as RewardBundle;

      const wallet = await creditRewardTx(tx, userRef, reward, now, {
        type: 'mail-claim',
        refId: mailId,
      });
      tx.update(mailRef, { claimed: true, read: true, updatedAt: now });
      return { wallet, reward };
    });
  }

  async deleteMail(uid: string, mailId: string): Promise<boolean> {
    const ref = this.mailRef(uid, mailId);
    const snap = await ref.get();
    if (!snap.exists) return false;
    const mail = mapMail(snap.id, snap.data() ?? {});
    if (!isEmptyReward(mail.reward) && !mail.claimed) {
      throw new EconomyError(409, 'unclaimed-reward', 'Claim the reward before deleting');
    }
    await ref.delete();
    return true;
  }

  async sendMail(input: SendMailInput): Promise<number> {
    const db = this.getDb();
    const now = this.now();
    // Batched fan-out (admin-triggered, uids list is validated + deduped).
    const batch = db.batch();
    for (const uid of input.uids) {
      const ref = db.collection(USERS).doc(uid).collection(MAIL).doc();
      batch.set(ref, {
        title: input.title,
        body: input.body,
        reward: input.reward,
        read: false,
        claimed: false,
        createdAt: now,
        expiresAt: input.expiresAtMs === null ? null : new Date(input.expiresAtMs),
      });
    }
    await batch.commit();
    return input.uids.length;
  }

  private mailRef(uid: string, mailId: string) {
    return this.getDb().collection(USERS).doc(uid).collection(MAIL).doc(mailId);
  }

  // ── Events ──────────────────────────────────────────────────────────────────

  async listEvents(): Promise<EventDoc[]> {
    const snap = await this.getDb().collection(EVENTS).get();
    const nowMs = this.now().getTime();
    const events = snap.docs
      .map((d) => mapEvent(d.id, d.data()))
      .filter((e) => eventLive(e, nowMs));
    events.sort((a, b) => a.sortOrder - b.sortOrder || a.id.localeCompare(b.id));
    return events;
  }

  async getEvent(eventId: string): Promise<EventDoc | null> {
    const snap = await this.getDb().collection(EVENTS).doc(eventId).get();
    if (!snap.exists) return null;
    const event = mapEvent(snap.id, snap.data() ?? {});
    return eventLive(event, this.now().getTime()) ? event : null;
  }

  async listEventClaims(uid: string): Promise<EventClaim[]> {
    const snap = await this.getDb()
      .collection(USERS)
      .doc(uid)
      .collection(EVENT_CLAIMS)
      .get();
    return snap.docs.map((d) => ({
      eventId: String(d.data().eventId ?? ''),
      giftId: String(d.data().giftId ?? ''),
    }));
  }

  async claimEventGift(uid: string, eventId: string, giftId: string): Promise<ClaimResult> {
    const db = this.getDb();
    const now = this.now();
    const userRef = db.collection(USERS).doc(uid);
    const eventRef = db.collection(EVENTS).doc(eventId);
    const claimRef = userRef.collection(EVENT_CLAIMS).doc(`${eventId}__${giftId}`);

    return db.runTransaction(async (tx) => {
      const [eventSnap, claimSnap] = await Promise.all([tx.get(eventRef), tx.get(claimRef)]);
      if (!eventSnap.exists) throw new EconomyError(404, 'not-found', 'Event not found');
      const event = mapEvent(eventSnap.id, eventSnap.data() ?? {});
      if (!eventLive(event, now.getTime())) {
        throw new EconomyError(404, 'not-found', 'Event is not running');
      }
      const gift = event.gifts.find((g) => g.id === giftId);
      if (!gift) throw new EconomyError(404, 'not-found', 'Gift not found');
      if (claimSnap.exists) {
        throw new EconomyError(409, 'already-claimed', 'Gift already claimed');
      }

      const wallet = await creditRewardTx(tx, userRef, gift.reward, now, {
        type: 'event-claim',
        refId: `${eventId}__${giftId}`,
      });
      tx.set(claimRef, { eventId, giftId, claimedAt: now });
      return { wallet, reward: gift.reward };
    });
  }

  async upsertEvent(input: EventInput): Promise<EventDoc> {
    const db = this.getDb();
    const now = this.now();
    const id = input.id ?? db.collection(EVENTS).doc().id;
    const payload = {
      title: input.title,
      descVi: input.descVi,
      startAtMs: input.startAtMs,
      endAtMs: input.endAtMs,
      active: input.active,
      sortOrder: input.sortOrder,
      gifts: input.gifts,
      updatedAt: now,
    };
    await db.collection(EVENTS).doc(id).set(payload, { merge: true });
    return mapEvent(id, payload);
  }

  async removeEvent(eventId: string): Promise<boolean> {
    const ref = this.getDb().collection(EVENTS).doc(eventId);
    const snap = await ref.get();
    if (!snap.exists) return false;
    await ref.delete();
    return true;
  }

  // ── Welfare ─────────────────────────────────────────────────────────────────

  async getWelfare(uid: string): Promise<WelfareStatus> {
    const snap = await this.welfareRef(uid).get();
    const state = snap.exists ? mapWelfare(snap.data() ?? {}) : EMPTY_WELFARE_STATE;
    return deriveWelfareStatus(state, dateKeyVN(this.now()));
  }

  async checkin(uid: string): Promise<WelfareClaimResult> {
    const db = this.getDb();
    const now = this.now();
    const today = dateKeyVN(now);
    const userRef = db.collection(USERS).doc(uid);
    const stateRef = this.welfareRef(uid);

    return db.runTransaction(async (tx) => {
      const stateSnap = await tx.get(stateRef);
      const state = stateSnap.exists ? mapWelfare(stateSnap.data() ?? {}) : EMPTY_WELFARE_STATE;
      if (state.lastCheckinDate === today) {
        throw new EconomyError(409, 'already-checked-in', 'Already checked in today');
      }
      const gap = state.lastCheckinDate === null ? 0 : dayGap(state.lastCheckinDate, today);
      const streak = gap === 1 ? state.streak + 1 : 1;
      const reward = CHECKIN_REWARDS[(streak - 1) % 7];

      const wallet = await creditRewardTx(tx, userRef, reward, now, {
        type: 'welfare-checkin',
        refId: today,
      });
      const next: WelfareState = {
        streak,
        totalCheckins: state.totalCheckins + 1,
        lastCheckinDate: today,
        newbieClaimed: state.newbieClaimed,
        comebackClaimedFor: state.comebackClaimedFor,
        // A long gap unlocks the comeback gift for the rest of today even
        // though this check-in just reset the gap to zero.
        comebackAvailableDate:
          gap >= COMEBACK_GAP_DAYS ? today : state.comebackAvailableDate,
      };
      tx.set(stateRef, { ...next, updatedAt: now });
      return { wallet, reward, status: deriveWelfareStatus(next, today) };
    });
  }

  async claimNewbie(uid: string): Promise<WelfareClaimResult> {
    const db = this.getDb();
    const now = this.now();
    const today = dateKeyVN(now);
    const userRef = db.collection(USERS).doc(uid);
    const stateRef = this.welfareRef(uid);

    return db.runTransaction(async (tx) => {
      const stateSnap = await tx.get(stateRef);
      const state = stateSnap.exists ? mapWelfare(stateSnap.data() ?? {}) : EMPTY_WELFARE_STATE;
      if (state.newbieClaimed) {
        throw new EconomyError(409, 'already-claimed', 'Newbie gift already claimed');
      }
      const wallet = await creditRewardTx(tx, userRef, NEWBIE_GIFT, now, {
        type: 'welfare-newbie',
        refId: 'newbie',
      });
      const next: WelfareState = { ...state, newbieClaimed: true };
      tx.set(stateRef, { ...next, updatedAt: now }, { merge: true });
      return { wallet, reward: NEWBIE_GIFT, status: deriveWelfareStatus(next, today) };
    });
  }

  async claimComeback(uid: string): Promise<WelfareClaimResult> {
    const db = this.getDb();
    const now = this.now();
    const today = dateKeyVN(now);
    const userRef = db.collection(USERS).doc(uid);
    const stateRef = this.welfareRef(uid);

    return db.runTransaction(async (tx) => {
      const stateSnap = await tx.get(stateRef);
      const state = stateSnap.exists ? mapWelfare(stateSnap.data() ?? {}) : EMPTY_WELFARE_STATE;
      const status = deriveWelfareStatus(state, today);
      if (!status.comebackAvailable) {
        throw new EconomyError(409, 'not-available', 'Comeback gift is not available');
      }
      const wallet = await creditRewardTx(tx, userRef, COMEBACK_GIFT, now, {
        type: 'welfare-comeback',
        refId: today,
      });
      const next: WelfareState = { ...state, comebackClaimedFor: today };
      tx.set(stateRef, { ...next, updatedAt: now }, { merge: true });
      return { wallet, reward: COMEBACK_GIFT, status: deriveWelfareStatus(next, today) };
    });
  }

  private welfareRef(uid: string) {
    return this.getDb()
      .collection(USERS)
      .doc(uid)
      .collection(WELFARE)
      .doc(WELFARE_STATE_DOC);
  }

  // ── Crafting ────────────────────────────────────────────────────────────────

  async listRecipes(): Promise<CraftRecipeDoc[]> {
    const snap = await this.getDb().collection(CRAFT_RECIPES).get();
    const recipes = snap.docs
      .map((d) => mapRecipe(d.id, d.data()))
      .filter((r) => r.active);
    recipes.sort((a, b) => a.sortOrder - b.sortOrder || a.id.localeCompare(b.id));
    return recipes;
  }

  async craft(uid: string, recipeId: string): Promise<CraftResult> {
    const db = this.getDb();
    const now = this.now();
    const userRef = db.collection(USERS).doc(uid);
    const recipeRef = db.collection(CRAFT_RECIPES).doc(recipeId);

    return db.runTransaction(async (tx) => {
      // ── All reads first (Firestore requirement) ──
      const [recipeSnap, userSnap] = await Promise.all([tx.get(recipeRef), tx.get(userRef)]);
      if (!recipeSnap.exists) throw new EconomyError(404, 'not-found', 'Recipe not found');
      const recipe = mapRecipe(recipeSnap.id, recipeSnap.data() ?? {});
      if (!recipe.active) throw new EconomyError(404, 'not-found', 'Recipe is not available');

      const userData = userSnap.exists ? userSnap.data() ?? {} : {};
      const coins = num(userData.coins);
      if (coins < recipe.costCoins) {
        throw new EconomyError(402, 'insufficient-funds', 'Not enough coins');
      }

      const ingredientRefs = recipe.ingredients.map((ing) =>
        userRef.collection(INVENTORY).doc(ing.itemId),
      );
      const outputRef = userRef.collection(INVENTORY).doc(recipe.output.itemId);
      const [outputSnap, ...ingredientSnaps] = await Promise.all([
        tx.get(outputRef),
        ...ingredientRefs.map((r) => tx.get(r)),
      ]);

      for (let i = 0; i < recipe.ingredients.length; i++) {
        const need = recipe.ingredients[i];
        const snap = ingredientSnaps[i];
        const have = snap.exists ? mapInventory(snap.id, snap.data() ?? {}).qty : 0;
        if (have < need.qty) {
          throw new EconomyError(
            400,
            'missing-ingredients',
            `Need ${need.qty}× ${need.itemId}, have ${have}`,
          );
        }
      }

      const output = recipe.output;
      const stackable = output.kind === 'consumable';
      if (!stackable && outputSnap.exists) {
        throw new EconomyError(409, 'already-owned', 'You already own this item');
      }

      // ── Writes ──
      tx.update(userRef, { coins: coins - recipe.costCoins, updatedAt: now });
      for (let i = 0; i < recipe.ingredients.length; i++) {
        const need = recipe.ingredients[i];
        const snap = ingredientSnaps[i];
        const have = mapInventory(snap.id, snap.data() ?? {}).qty;
        const left = have - need.qty;
        if (left <= 0) {
          tx.delete(ingredientRefs[i]);
        } else {
          tx.update(ingredientRefs[i], { qty: left, updatedAt: now });
        }
      }
      const prevOutQty = outputSnap.exists
        ? mapInventory(outputSnap.id, outputSnap.data() ?? {}).qty
        : 0;
      const newQty = stackable ? prevOutQty + output.qty : 1;
      tx.set(
        outputRef,
        {
          itemId: output.itemId,
          kind: output.kind,
          payloadKey: output.payloadKey,
          qty: newQty,
          acquiredAt: outputSnap.exists
            ? (outputSnap.data() ?? {}).acquiredAt ?? now
            : now,
          updatedAt: now,
        },
        { merge: true },
      );
      tx.set(userRef.collection(WALLET_TX).doc(), {
        type: 'craft',
        refId: recipeId,
        coinsDelta: -recipe.costCoins,
        gemsDelta: 0,
        balanceCoinsAfter: coins - recipe.costCoins,
        balanceGemsAfter: num(userData.gems),
        at: now,
      });

      return {
        wallet: { coins: coins - recipe.costCoins, gems: num(userData.gems) },
        item: {
          itemId: output.itemId,
          kind: output.kind,
          payloadKey: output.payloadKey,
          qty: newQty,
          acquiredAtMs: now.getTime(),
        },
      };
    });
  }

  async upsertRecipe(input: CraftRecipeInput): Promise<CraftRecipeDoc> {
    const db = this.getDb();
    const now = this.now();
    const id = input.id ?? db.collection(CRAFT_RECIPES).doc().id;
    const ref = db.collection(CRAFT_RECIPES).doc(id);
    const existing = await ref.get();
    const payload = {
      nameVi: input.nameVi,
      descVi: input.descVi,
      ingredients: input.ingredients,
      costCoins: input.costCoins,
      output: input.output,
      active: input.active,
      sortOrder: input.sortOrder,
      createdAt: existing.exists ? (existing.data() ?? {}).createdAt ?? now : now,
      updatedAt: now,
    };
    await ref.set(payload, { merge: true });
    return mapRecipe(id, payload);
  }

  async removeRecipe(recipeId: string): Promise<boolean> {
    const ref = this.getDb().collection(CRAFT_RECIPES).doc(recipeId);
    const snap = await ref.get();
    if (!snap.exists) return false;
    await ref.delete();
    return true;
  }
}

// ── Shared reward crediting ───────────────────────────────────────────────────

/// Credit [reward] to `users/{uid}` inside [tx]: bump coins/gems, merge item
/// grants into the inventory subcollection, and append a wallet_tx entry.
/// Performs its own reads via the transaction (allowed: Admin SDK transactions
/// interleave reads before the first write — callers must not have written yet).
async function creditRewardTx(
  tx: Transaction,
  userRef: FirebaseFirestore.DocumentReference,
  reward: RewardBundle,
  now: Date,
  meta: { type: string; refId: string },
): Promise<BalanceDoc> {
  const userSnap = await tx.get(userRef);
  const data = userSnap.exists ? userSnap.data() ?? {} : {};
  const coins = num(data.coins) + reward.coins;
  const gems = num(data.gems) + reward.gems;

  const itemSnaps = await Promise.all(
    reward.items.map((it) => tx.get(userRef.collection(INVENTORY).doc(it.itemId))),
  );

  tx.set(userRef, { coins, gems, updatedAt: now }, { merge: true });
  for (let i = 0; i < reward.items.length; i++) {
    const it = reward.items[i];
    const snap = itemSnaps[i];
    const prevQty = snap.exists ? mapInventory(snap.id, snap.data() ?? {}).qty : 0;
    const stackable = it.kind === 'consumable';
    const qty = stackable ? prevQty + it.qty : 1;
    tx.set(
      userRef.collection(INVENTORY).doc(it.itemId),
      {
        itemId: it.itemId,
        kind: it.kind,
        payloadKey: it.payloadKey,
        qty,
        acquiredAt: snap.exists ? (snap.data() ?? {}).acquiredAt ?? now : now,
        updatedAt: now,
      },
      { merge: true },
    );
  }
  tx.set(userRef.collection(WALLET_TX).doc(), {
    type: meta.type,
    refId: meta.refId,
    coinsDelta: reward.coins,
    gemsDelta: reward.gems,
    items: reward.items.map((it) => ({ itemId: it.itemId, qty: it.qty })),
    balanceCoinsAfter: coins,
    balanceGemsAfter: gems,
    at: now,
  });
  return { coins, gems };
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

function str(value: unknown): string {
  return typeof value === 'string' ? value : '';
}

function mapReward(raw: unknown): RewardBundle | null {
  if (typeof raw !== 'object' || raw === null) return null;
  const obj = raw as Record<string, unknown>;
  const items: RewardItem[] = Array.isArray(obj.items)
    ? obj.items
        .filter((it): it is Record<string, unknown> => typeof it === 'object' && it !== null)
        .map((it) => ({
          itemId: str(it.itemId),
          kind: (it.kind as RewardItem['kind']) ?? 'consumable',
          payloadKey: str(it.payloadKey),
          qty: Math.max(1, num(it.qty, 1)),
        }))
        .filter((it) => it.itemId.length > 0)
    : [];
  const bundle: RewardBundle = { coins: num(obj.coins), gems: num(obj.gems), items };
  return isEmptyReward(bundle) ? null : bundle;
}

export function mapMail(id: string, data: Record<string, unknown>): MailDoc {
  return {
    id,
    title: str(data.title),
    body: str(data.body),
    reward: mapReward(data.reward),
    read: data.read === true,
    claimed: data.claimed === true,
    createdAtMs: toMillis(data.createdAt),
    expiresAtMs: toMillis(data.expiresAt),
  };
}

export function mapEvent(id: string, data: Record<string, unknown>): EventDoc {
  const gifts: EventGift[] = Array.isArray(data.gifts)
    ? data.gifts
        .filter((g): g is Record<string, unknown> => typeof g === 'object' && g !== null)
        .map((g) => ({
          id: str(g.id),
          title: str(g.title),
          reward: mapReward(g.reward) ?? { coins: 0, gems: 0, items: [] },
        }))
        .filter((g) => g.id.length > 0)
    : [];
  return {
    id,
    title: str(data.title),
    descVi: str(data.descVi),
    startAtMs: num(data.startAtMs),
    endAtMs: num(data.endAtMs),
    active: data.active !== false,
    sortOrder: num(data.sortOrder),
    gifts,
  };
}

export function mapWelfare(data: Record<string, unknown>): WelfareState {
  return {
    streak: num(data.streak),
    totalCheckins: num(data.totalCheckins),
    lastCheckinDate: typeof data.lastCheckinDate === 'string' ? data.lastCheckinDate : null,
    newbieClaimed: data.newbieClaimed === true,
    comebackClaimedFor:
      typeof data.comebackClaimedFor === 'string' ? data.comebackClaimedFor : null,
    comebackAvailableDate:
      typeof data.comebackAvailableDate === 'string' ? data.comebackAvailableDate : null,
  };
}

export function mapRecipe(id: string, data: Record<string, unknown>): CraftRecipeDoc {
  const ingredients = Array.isArray(data.ingredients)
    ? data.ingredients
        .filter((g): g is Record<string, unknown> => typeof g === 'object' && g !== null)
        .map((g) => ({ itemId: str(g.itemId), qty: Math.max(1, num(g.qty, 1)) }))
        .filter((g) => g.itemId.length > 0)
    : [];
  const outRaw = (typeof data.output === 'object' && data.output !== null
    ? data.output
    : {}) as Record<string, unknown>;
  return {
    id,
    nameVi: str(data.nameVi),
    descVi: str(data.descVi),
    ingredients,
    costCoins: num(data.costCoins),
    output: {
      itemId: str(outRaw.itemId),
      kind: (outRaw.kind as RewardItem['kind']) ?? 'boardTheme',
      payloadKey: str(outRaw.payloadKey),
      qty: Math.max(1, num(outRaw.qty, 1)),
    },
    active: data.active !== false,
    sortOrder: num(data.sortOrder),
    createdAtMs: toMillis(data.createdAt),
    updatedAtMs: toMillis(data.updatedAt),
  };
}
