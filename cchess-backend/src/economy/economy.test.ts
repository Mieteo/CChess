import assert from 'node:assert/strict';
import { test } from 'node:test';
import { createServer, type Server } from 'node:http';
import type { AddressInfo } from 'node:net';

import type { InventoryItemDoc } from '../shop/types';
import { createEconomyApi, type EconomyApiOptions } from './economy_routes';
import {
  chunk,
  mapEvent,
  mapMail,
  mapRecipe,
  mapWelfare,
  type BalanceDoc,
  type ClaimResult,
  type CraftResult,
  type EconomyStore,
  type WelfareClaimResult,
} from './economy_store';
import {
  CHECKIN_REWARDS,
  COMEBACK_GIFT,
  EMPTY_WELFARE_STATE,
  EconomyError,
  NEWBIE_GIFT,
  dayGap,
  deriveWelfareStatus,
  eventLive,
  isEmptyReward,
  validateEventClaimInput,
  validateEventInput,
  validateRecipeInput,
  validateReward,
  validateRewardItem,
  validateSendMailInput,
  type CraftRecipeDoc,
  type CraftRecipeInput,
  type EventClaim,
  type EventDoc,
  type EventInput,
  type MailDoc,
  type RewardBundle,
  type SendMailInput,
  type WelfareState,
} from './types';

// ── In-memory store fake ─────────────────────────────────────────────────────
// Storage is faked; the business rules (streak/gap derivation, event windows,
// claim-once guards, reward crediting) reuse the real pure helpers from
// types.ts so the tests exercise production logic.

interface FakeUser {
  coins: number;
  gems: number;
  inventory: Map<string, InventoryItemDoc>;
  mail: Map<string, MailDoc>;
  eventClaims: Set<string>;
  welfare: WelfareState;
}

// Mirrors puzzles/types.ts dateKeyVN (UTC+7).
function vnDate(now: Date): string {
  return new Date(now.getTime() + 7 * 3_600_000).toISOString().slice(0, 10);
}

class FakeEconomyStore implements EconomyStore {
  readonly users = new Map<string, FakeUser>();
  readonly events = new Map<string, EventDoc>();
  readonly recipes = new Map<string, CraftRecipeDoc>();
  now: () => Date = () => new Date('2026-07-23T05:00:00Z'); // 12:00 VN time
  private seq = 0;

  user(uid: string): FakeUser {
    let u = this.users.get(uid);
    if (!u) {
      u = {
        coins: 0,
        gems: 0,
        inventory: new Map(),
        mail: new Map(),
        eventClaims: new Set(),
        welfare: { ...EMPTY_WELFARE_STATE },
      };
      this.users.set(uid, u);
    }
    return u;
  }

  seedMail(uid: string, doc: Partial<MailDoc> & { id: string }): void {
    this.user(uid).mail.set(doc.id, {
      title: 'T',
      body: '',
      reward: null,
      read: false,
      claimed: false,
      createdAtMs: ++this.seq,
      expiresAtMs: null,
      ...doc,
    });
  }

  private credit(u: FakeUser, reward: RewardBundle): BalanceDoc {
    u.coins += reward.coins;
    u.gems += reward.gems;
    for (const it of reward.items) {
      const prev = u.inventory.get(it.itemId);
      const stackable = it.kind === 'consumable';
      u.inventory.set(it.itemId, {
        itemId: it.itemId,
        kind: it.kind,
        payloadKey: it.payloadKey,
        qty: stackable ? (prev?.qty ?? 0) + it.qty : 1,
        acquiredAtMs: prev?.acquiredAtMs ?? ++this.seq,
      });
    }
    return { coins: u.coins, gems: u.gems };
  }

  // ── Mail ──
  async listMail(uid: string): Promise<MailDoc[]> {
    const nowMs = this.now().getTime();
    return [...this.user(uid).mail.values()]
      .filter((m) => m.expiresAtMs === null || m.expiresAtMs > nowMs)
      .sort((a, b) => (b.createdAtMs ?? 0) - (a.createdAtMs ?? 0));
  }

  async markMailRead(uid: string, mailId: string): Promise<void> {
    const m = this.user(uid).mail.get(mailId);
    if (!m) throw new EconomyError(404, 'not-found', 'Mail not found');
    m.read = true;
  }

  async claimMail(uid: string, mailId: string): Promise<ClaimResult> {
    const u = this.user(uid);
    const m = u.mail.get(mailId);
    if (!m) throw new EconomyError(404, 'not-found', 'Mail not found');
    if (m.expiresAtMs !== null && m.expiresAtMs <= this.now().getTime()) {
      throw new EconomyError(404, 'not-found', 'Mail has expired');
    }
    if (m.claimed) throw new EconomyError(409, 'already-claimed', 'Already claimed');
    if (isEmptyReward(m.reward)) throw new EconomyError(400, 'no-reward', 'No reward');
    const wallet = this.credit(u, m.reward as RewardBundle);
    m.claimed = true;
    m.read = true;
    return { wallet, reward: m.reward as RewardBundle };
  }

  async deleteMail(uid: string, mailId: string): Promise<boolean> {
    const u = this.user(uid);
    const m = u.mail.get(mailId);
    if (!m) return false;
    if (!isEmptyReward(m.reward) && !m.claimed) {
      throw new EconomyError(409, 'unclaimed-reward', 'Claim first');
    }
    return u.mail.delete(mailId);
  }

  async sendMail(input: SendMailInput): Promise<number> {
    let sent = 0;
    for (const uid of input.uids) {
      // Mirrors Firestore create(): a dedupe-keyed mail keeps its doc id and
      // refuses to overwrite, so re-broadcasts skip users who have it.
      const id = input.dedupeKey === null ? `m${++this.seq}` : `dk_${input.dedupeKey}`;
      if (input.dedupeKey !== null && this.user(uid).mail.has(id)) continue;
      this.seedMail(uid, {
        id,
        title: input.title,
        body: input.body,
        reward: input.reward,
        expiresAtMs: input.expiresAtMs,
      });
      sent += 1;
    }
    return sent;
  }

  // ── Events ──
  async listEvents(): Promise<EventDoc[]> {
    const nowMs = this.now().getTime();
    return [...this.events.values()]
      .filter((e) => eventLive(e, nowMs))
      .sort((a, b) => a.sortOrder - b.sortOrder || a.id.localeCompare(b.id));
  }

  async getEvent(eventId: string): Promise<EventDoc | null> {
    const e = this.events.get(eventId);
    return e && eventLive(e, this.now().getTime()) ? e : null;
  }

  async listEventClaims(uid: string): Promise<EventClaim[]> {
    return [...this.user(uid).eventClaims].map((key) => {
      const [eventId, giftId] = key.split('__');
      return { eventId, giftId };
    });
  }

  async claimEventGift(uid: string, eventId: string, giftId: string): Promise<ClaimResult> {
    const event = await this.getEvent(eventId);
    if (!event) throw new EconomyError(404, 'not-found', 'Event not running');
    const gift = event.gifts.find((g) => g.id === giftId);
    if (!gift) throw new EconomyError(404, 'not-found', 'Gift not found');
    const u = this.user(uid);
    const key = `${eventId}__${giftId}`;
    if (u.eventClaims.has(key)) {
      throw new EconomyError(409, 'already-claimed', 'Already claimed');
    }
    const wallet = this.credit(u, gift.reward);
    u.eventClaims.add(key);
    return { wallet, reward: gift.reward };
  }

  async upsertEvent(input: EventInput): Promise<EventDoc> {
    const id = input.id ?? `e${++this.seq}`;
    const doc: EventDoc = { ...input, id };
    this.events.set(id, doc);
    return doc;
  }

  async removeEvent(eventId: string): Promise<boolean> {
    return this.events.delete(eventId);
  }

  // ── Welfare ── (same rules as FirestoreEconomyStore.checkin/claim*)
  async getWelfare(uid: string) {
    return deriveWelfareStatus(this.user(uid).welfare, vnDate(this.now()));
  }

  async checkin(uid: string): Promise<WelfareClaimResult> {
    const u = this.user(uid);
    const today = vnDate(this.now());
    const s = u.welfare;
    if (s.lastCheckinDate === today) {
      throw new EconomyError(409, 'already-checked-in', 'Already today');
    }
    const gap = s.lastCheckinDate === null ? 0 : dayGap(s.lastCheckinDate, today);
    const streak = gap === 1 ? s.streak + 1 : 1;
    const reward = CHECKIN_REWARDS[(streak - 1) % 7];
    const wallet = this.credit(u, reward);
    u.welfare = {
      streak,
      totalCheckins: s.totalCheckins + 1,
      lastCheckinDate: today,
      newbieClaimed: s.newbieClaimed,
      comebackClaimedFor: s.comebackClaimedFor,
      comebackAvailableDate: gap >= 7 ? today : s.comebackAvailableDate,
    };
    return { wallet, reward, status: deriveWelfareStatus(u.welfare, today) };
  }

  async claimNewbie(uid: string): Promise<WelfareClaimResult> {
    const u = this.user(uid);
    const today = vnDate(this.now());
    if (u.welfare.newbieClaimed) {
      throw new EconomyError(409, 'already-claimed', 'Already claimed');
    }
    const wallet = this.credit(u, NEWBIE_GIFT);
    u.welfare = { ...u.welfare, newbieClaimed: true };
    return { wallet, reward: NEWBIE_GIFT, status: deriveWelfareStatus(u.welfare, today) };
  }

  async claimComeback(uid: string): Promise<WelfareClaimResult> {
    const u = this.user(uid);
    const today = vnDate(this.now());
    if (!deriveWelfareStatus(u.welfare, today).comebackAvailable) {
      throw new EconomyError(409, 'not-available', 'Not available');
    }
    const wallet = this.credit(u, COMEBACK_GIFT);
    u.welfare = { ...u.welfare, comebackClaimedFor: today };
    return { wallet, reward: COMEBACK_GIFT, status: deriveWelfareStatus(u.welfare, today) };
  }

  // ── Crafting ──
  async listRecipes(): Promise<CraftRecipeDoc[]> {
    return [...this.recipes.values()]
      .filter((r) => r.active)
      .sort((a, b) => a.sortOrder - b.sortOrder || a.id.localeCompare(b.id));
  }

  async craft(uid: string, recipeId: string): Promise<CraftResult> {
    const r = this.recipes.get(recipeId);
    if (!r || !r.active) throw new EconomyError(404, 'not-found', 'Recipe not found');
    const u = this.user(uid);
    if (u.coins < r.costCoins) {
      throw new EconomyError(402, 'insufficient-funds', 'Not enough coins');
    }
    for (const ing of r.ingredients) {
      const have = u.inventory.get(ing.itemId)?.qty ?? 0;
      if (have < ing.qty) {
        throw new EconomyError(400, 'missing-ingredients', `Need ${ing.qty}× ${ing.itemId}`);
      }
    }
    const stackable = r.output.kind === 'consumable';
    if (!stackable && u.inventory.has(r.output.itemId)) {
      throw new EconomyError(409, 'already-owned', 'Already owned');
    }
    u.coins -= r.costCoins;
    for (const ing of r.ingredients) {
      const have = u.inventory.get(ing.itemId)!;
      const left = have.qty - ing.qty;
      if (left <= 0) u.inventory.delete(ing.itemId);
      else u.inventory.set(ing.itemId, { ...have, qty: left });
    }
    const prev = u.inventory.get(r.output.itemId);
    const item: InventoryItemDoc = {
      itemId: r.output.itemId,
      kind: r.output.kind,
      payloadKey: r.output.payloadKey,
      qty: stackable ? (prev?.qty ?? 0) + r.output.qty : 1,
      acquiredAtMs: ++this.seq,
    };
    u.inventory.set(r.output.itemId, item);
    return { wallet: { coins: u.coins, gems: u.gems }, item };
  }

  async upsertRecipe(input: CraftRecipeInput): Promise<CraftRecipeDoc> {
    const id = input.id ?? `r${++this.seq}`;
    const doc: CraftRecipeDoc = { ...input, id, createdAtMs: ++this.seq, updatedAtMs: this.seq };
    this.recipes.set(id, doc);
    return doc;
  }

  async removeRecipe(recipeId: string): Promise<boolean> {
    return this.recipes.delete(recipeId);
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
  store: FakeEconomyStore,
  extra: EconomyApiOptions,
  run: (baseUrl: string) => Promise<void>,
): Promise<void> {
  const api = createEconomyApi({ store, ...extra });
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

const asUid: EconomyApiOptions = { authenticate: async (t) => ({ uid: t }) };
const bearer = (uid: string) => ({ authorization: `Bearer ${uid}` });
const jsonHeaders = (uid: string) => ({ ...bearer(uid), 'content-type': 'application/json' });
const hasCode = (code: string) => (e: unknown) => (e as EconomyError).code === code;

// Fixed "now": 2026-07-23 12:00 VN. Yesterday/today VN date keys for welfare.
const NOW = new Date('2026-07-23T05:00:00Z');
const TODAY = '2026-07-23';
const YESTERDAY = '2026-07-22';

// ── Validation ────────────────────────────────────────────────────────────────

test('validateReward normalizes, empty → null, bad item rejected', () => {
  assert.equal(validateReward(undefined), null);
  assert.equal(validateReward({ coins: 0, gems: 0 }), null);
  const r = validateReward({ coins: 10.9, gems: -5, items: [{ itemId: 'x', kind: 'consumable', payloadKey: 'p', qty: 0 }] });
  assert.deepEqual(r, { coins: 10, gems: 0, items: [{ itemId: 'x', kind: 'consumable', payloadKey: 'p', qty: 1 }] });
  assert.throws(() => validateReward({ items: [{ itemId: 'x', kind: 'nope', payloadKey: 'p' }] }), hasCode('invalid-reward-item'));
});

test('validateSendMailInput merges uid + uids, dedupes, requires title', () => {
  const input = validateSendMailInput({ uid: 'a', uids: ['b', 'a', ''], title: ' Chào ', reward: { coins: 5 } });
  assert.deepEqual(input.uids.sort(), ['a', 'b']);
  assert.equal(input.title, 'Chào');
  assert.equal(input.reward?.coins, 5);
  assert.throws(() => validateSendMailInput({ title: 'x' }), hasCode('invalid-uids'));
  assert.throws(() => validateSendMailInput({ uid: 'a' }), hasCode('invalid-title'));
});

test('validateSendMailInput dedupeKey: optional, doc-id-safe, else 400', () => {
  const base = { uid: 'a', title: 'x' };
  assert.equal(validateSendMailInput(base).dedupeKey, null);
  assert.equal(validateSendMailInput({ ...base, dedupeKey: '  ' }).dedupeKey, null);
  assert.equal(
    validateSendMailInput({ ...base, dedupeKey: 'welcome_2026-07' }).dedupeKey,
    'welcome_2026-07',
  );
  assert.throws(
    () => validateSendMailInput({ ...base, dedupeKey: 'has/slash' }),
    hasCode('invalid-dedupe-key'),
  );
  assert.throws(
    () => validateSendMailInput({ ...base, dedupeKey: 'x'.repeat(65) }),
    hasCode('invalid-dedupe-key'),
  );
});

test('sendMail with dedupeKey is idempotent per user and preserves claim state', async () => {
  const store = new FakeEconomyStore();
  const input = validateSendMailInput({
    uids: ['u1', 'u2'],
    title: 'Chào mừng',
    reward: { coins: 68, gems: 1 },
    dedupeKey: 'welcome-v1',
  });
  assert.equal(await store.sendMail(input), 2);
  // Re-running the same broadcast (script fired twice) creates nothing new.
  assert.equal(await store.sendMail(input), 0);
  assert.equal((await store.listMail('u1')).length, 1);

  // u1 claims; a later re-broadcast must not resurrect the reward.
  await store.claimMail('u1', 'dk_welcome-v1');
  assert.equal(await store.sendMail(input), 0);
  const mail = (await store.listMail('u1'))[0];
  assert.equal(mail.claimed, true);

  // A NEW user joining later still receives the mail on the next run.
  const wider = validateSendMailInput({
    uids: ['u1', 'u2', 'u3'],
    title: 'Chào mừng',
    reward: { coins: 68, gems: 1 },
    dedupeKey: 'welcome-v1',
  });
  assert.equal(await store.sendMail(wider), 1);
  assert.equal((await store.listMail('u3')).length, 1);

  // No dedupeKey → legacy behaviour, every send appends.
  const legacy = validateSendMailInput({ uid: 'u1', title: 'Tin' });
  await store.sendMail(legacy);
  await store.sendMail(legacy);
  assert.equal((await store.listMail('u1')).length, 3);
});

test('validateEventInput checks window, gifts, duplicate ids', () => {
  const ok = validateEventInput({
    title: 'Tết', startAtMs: 1000, endAtMs: 2000,
    gifts: [{ id: 'g1', title: 'Lì xì', reward: { coins: 88 } }],
  });
  assert.equal(ok.gifts.length, 1);
  assert.throws(() => validateEventInput({ title: 'x', startAtMs: 2000, endAtMs: 1000, gifts: [{ id: 'g', title: 't', reward: { coins: 1 } }] }), hasCode('invalid-window'));
  assert.throws(() => validateEventInput({ title: 'x', startAtMs: 1, endAtMs: 2, gifts: [] }), hasCode('invalid-gifts'));
  assert.throws(
    () => validateEventInput({ title: 'x', startAtMs: 1, endAtMs: 2, gifts: [{ id: 'g', title: 't', reward: { coins: 1 } }, { id: 'g', title: 't2', reward: { coins: 2 } }] }),
    hasCode('invalid-gift'),
  );
  assert.throws(
    () => validateEventInput({ title: 'x', startAtMs: 1, endAtMs: 2, gifts: [{ id: 'g', title: 't', reward: {} }] }),
    hasCode('invalid-gift'),
  );
});

test('validateRecipeInput checks ingredients + output', () => {
  const ok = validateRecipeInput({
    nameVi: 'Bàn Ngọc', ingredients: [{ itemId: 'shard', qty: 3 }], costCoins: 100,
    output: { itemId: 'jade-board', kind: 'boardTheme', payloadKey: 'jade' },
  });
  assert.equal(ok.output.qty, 1);
  assert.throws(() => validateRecipeInput({ nameVi: 'x', ingredients: [], output: { itemId: 'o', kind: 'boardTheme', payloadKey: 'p' } }), hasCode('invalid-ingredients'));
  assert.throws(() => validateRecipeInput({ nameVi: 'x', ingredients: [{ itemId: 'a' }], output: { itemId: '', kind: 'boardTheme', payloadKey: 'p' } }), hasCode('invalid-reward-item'));
});

// ── Welfare pure logic ────────────────────────────────────────────────────────

test('deriveWelfareStatus: fresh, consecutive, broken streak, comeback', () => {
  const fresh = deriveWelfareStatus(EMPTY_WELFARE_STATE, TODAY);
  assert.equal(fresh.todayClaimed, false);
  assert.equal(fresh.todayIndex, 0);
  assert.equal(fresh.comebackAvailable, false);

  const consecutive = deriveWelfareStatus(
    { ...EMPTY_WELFARE_STATE, streak: 3, lastCheckinDate: YESTERDAY },
    TODAY,
  );
  assert.equal(consecutive.todayIndex, 3); // day 4 of the cycle

  const claimed = deriveWelfareStatus(
    { ...EMPTY_WELFARE_STATE, streak: 4, lastCheckinDate: TODAY },
    TODAY,
  );
  assert.equal(claimed.todayClaimed, true);
  assert.equal(claimed.todayIndex, 3);

  const broke = deriveWelfareStatus(
    { ...EMPTY_WELFARE_STATE, streak: 5, lastCheckinDate: '2026-07-20' },
    TODAY,
  );
  assert.equal(broke.todayIndex, 0); // 3-day gap resets

  const away = deriveWelfareStatus(
    { ...EMPTY_WELFARE_STATE, streak: 5, lastCheckinDate: '2026-07-10' },
    TODAY,
  );
  assert.equal(away.comebackAvailable, true); // 13-day gap ≥ 7

  const claimedComeback = deriveWelfareStatus(
    { ...EMPTY_WELFARE_STATE, streak: 5, lastCheckinDate: '2026-07-10', comebackClaimedFor: TODAY },
    TODAY,
  );
  assert.equal(claimedComeback.comebackAvailable, false);
});

test('dayGap counts whole days', () => {
  assert.equal(dayGap('2026-07-22', '2026-07-23'), 1);
  assert.equal(dayGap('2026-07-23', '2026-07-23'), 0);
  assert.equal(dayGap('2026-07-10', '2026-07-23'), 13);
});

// ── Mail HTTP flows ───────────────────────────────────────────────────────────

test('GET /mail requires auth, lists newest first, hides expired', async () => {
  const store = new FakeEconomyStore();
  store.seedMail('u1', { id: 'old', title: 'Cũ', createdAtMs: 1 });
  store.seedMail('u1', { id: 'new', title: 'Mới', createdAtMs: 2 });
  store.seedMail('u1', { id: 'gone', title: 'Hết hạn', createdAtMs: 3, expiresAtMs: 1 });
  await withServer(store, asUid, async (baseUrl) => {
    assert.equal((await fetch(`${baseUrl}/mail`)).status, 401);
    const body = await getJson(await fetch(`${baseUrl}/mail`, { headers: bearer('u1') }));
    assert.deepEqual(body.messages.map((m: MailDoc) => m.id), ['new', 'old']);
  });
});

test('claim mail credits wallet + inventory once; no-reward mail rejects', async () => {
  const store = new FakeEconomyStore();
  store.user('u1').coins = 10;
  store.seedMail('u1', {
    id: 'gift',
    reward: { coins: 50, gems: 2, items: [{ itemId: 'hint5', kind: 'consumable', payloadKey: 'hint', qty: 5 }] },
  });
  store.seedMail('u1', { id: 'note', reward: null });
  await withServer(store, asUid, async (baseUrl) => {
    const claim = await fetch(`${baseUrl}/mail/gift/claim`, { method: 'POST', headers: jsonHeaders('u1') });
    assert.equal(claim.status, 200);
    const body = await getJson(claim);
    assert.equal(body.wallet.coins, 60);
    assert.equal(body.wallet.gems, 2);
    assert.equal((await fetch(`${baseUrl}/mail/gift/claim`, { method: 'POST', headers: jsonHeaders('u1') })).status, 409);
    assert.equal((await fetch(`${baseUrl}/mail/note/claim`, { method: 'POST', headers: jsonHeaders('u1') })).status, 400);
    assert.equal(store.user('u1').inventory.get('hint5')?.qty, 5);
  });
});

test('delete mail blocks unclaimed rewards, allows after claim', async () => {
  const store = new FakeEconomyStore();
  store.seedMail('u1', { id: 'gift', reward: { coins: 5, gems: 0, items: [] } });
  await withServer(store, asUid, async (baseUrl) => {
    const blocked = await fetch(`${baseUrl}/mail/gift`, { method: 'DELETE', headers: bearer('u1') });
    assert.equal(blocked.status, 409);
    await fetch(`${baseUrl}/mail/gift/claim`, { method: 'POST', headers: jsonHeaders('u1') });
    const ok = await fetch(`${baseUrl}/mail/gift`, { method: 'DELETE', headers: bearer('u1') });
    assert.equal(ok.status, 200);
  });
});

test('POST /admin/mail fans out to uids behind the admin guard', async () => {
  const store = new FakeEconomyStore();
  await withServer(store, { ...asUid, isAdmin: () => false }, async (baseUrl) => {
    const denied = await fetch(`${baseUrl}/admin/mail`, {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify({ uids: ['a'], title: 'Hi' }),
    });
    assert.equal(denied.status, 403);
  });
  await withServer(store, { ...asUid, isAdmin: () => true }, async (baseUrl) => {
    const ok = await fetch(`${baseUrl}/admin/mail`, {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify({ uids: ['a', 'b'], title: 'Bảo trì', reward: { coins: 10 } }),
    });
    assert.equal(ok.status, 200);
    assert.equal((await getJson(ok)).sent, 2);
    assert.equal((await store.listMail('a')).length, 1);
    assert.equal((await store.listMail('b')).length, 1);
  });
});

// ── Events HTTP flows ─────────────────────────────────────────────────────────

function seedTet(store: FakeEconomyStore): void {
  const nowMs = NOW.getTime();
  store.events.set('tet', {
    id: 'tet', title: 'Tết 2026', descVi: '', sortOrder: 1, active: true,
    startAtMs: nowMs - 1000, endAtMs: nowMs + 1000,
    gifts: [{ id: 'lixi', title: 'Lì xì', reward: { coins: 88, gems: 0, items: [] } }],
  });
  store.events.set('over', {
    id: 'over', title: 'Đã xong', descVi: '', sortOrder: 2, active: true,
    startAtMs: nowMs - 5000, endAtMs: nowMs - 1000,
    gifts: [{ id: 'g', title: 'x', reward: { coins: 1, gems: 0, items: [] } }],
  });
  store.now = () => NOW;
}

test('GET /events lists only live events; claim pays once', async () => {
  const store = new FakeEconomyStore();
  seedTet(store);
  await withServer(store, asUid, async (baseUrl) => {
    const list = await getJson(await fetch(`${baseUrl}/events`));
    assert.deepEqual(list.events.map((e: EventDoc) => e.id), ['tet']);
    assert.equal((await fetch(`${baseUrl}/events/over`)).status, 404);

    const claim = await fetch(`${baseUrl}/events/tet/claim`, {
      method: 'POST', headers: jsonHeaders('u1'), body: JSON.stringify({ giftId: 'lixi' }),
    });
    assert.equal(claim.status, 200);
    assert.equal((await getJson(claim)).wallet.coins, 88);
    assert.equal(
      (await fetch(`${baseUrl}/events/tet/claim`, {
        method: 'POST', headers: jsonHeaders('u1'), body: JSON.stringify({ giftId: 'lixi' }),
      })).status,
      409,
    );
    assert.equal(
      (await fetch(`${baseUrl}/events/tet/claim`, {
        method: 'POST', headers: jsonHeaders('u1'), body: JSON.stringify({ giftId: 'nope' }),
      })).status,
      404,
    );

    const claims = await getJson(await fetch(`${baseUrl}/events/claims`, { headers: bearer('u1') }));
    assert.deepEqual(claims.claims, [{ eventId: 'tet', giftId: 'lixi' }]);
  });
});

test('admin event upsert + delete', async () => {
  const store = new FakeEconomyStore();
  store.now = () => NOW;
  await withServer(store, { ...asUid, isAdmin: () => true }, async (baseUrl) => {
    const created = await fetch(`${baseUrl}/admin/events`, {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify({
        id: 'trungthu', title: 'Trung Thu',
        startAtMs: NOW.getTime() - 1, endAtMs: NOW.getTime() + 1000,
        gifts: [{ id: 'banh', title: 'Bánh', reward: { gems: 3 } }],
      }),
    });
    assert.equal(created.status, 201);
    const del = await fetch(`${baseUrl}/admin/events/trungthu`, { method: 'DELETE' });
    assert.equal(del.status, 200);
    assert.equal((await fetch(`${baseUrl}/admin/events/trungthu`, { method: 'DELETE' })).status, 404);
  });
});

// ── Welfare HTTP flows ────────────────────────────────────────────────────────

test('check-in day 1 pays cycle[0]; same day again → 409; next day streak 2', async () => {
  const store = new FakeEconomyStore();
  store.now = () => NOW;
  await withServer(store, asUid, async (baseUrl) => {
    const first = await fetch(`${baseUrl}/welfare/checkin`, { method: 'POST', headers: jsonHeaders('u1') });
    assert.equal(first.status, 200);
    const body = await getJson(first);
    assert.equal(body.reward.coins, CHECKIN_REWARDS[0].coins);
    assert.equal(body.status.streak, 1);
    assert.equal(body.status.todayClaimed, true);

    assert.equal((await fetch(`${baseUrl}/welfare/checkin`, { method: 'POST', headers: jsonHeaders('u1') })).status, 409);

    // Next VN day → streak 2, cycle[1].
    store.now = () => new Date(NOW.getTime() + 86_400_000);
    const second = await fetch(`${baseUrl}/welfare/checkin`, { method: 'POST', headers: jsonHeaders('u1') });
    const b2 = await getJson(second);
    assert.equal(b2.status.streak, 2);
    assert.equal(b2.reward.coins, CHECKIN_REWARDS[1].coins);
  });
});

test('a ≥7-day absence resets the streak and unlocks the comeback gift', async () => {
  const store = new FakeEconomyStore();
  store.now = () => NOW;
  store.user('u1').welfare = {
    ...EMPTY_WELFARE_STATE, streak: 6, totalCheckins: 6, lastCheckinDate: '2026-07-10',
  };
  await withServer(store, asUid, async (baseUrl) => {
    // Comeback is claimable straight away (13-day gap).
    const status = await getJson(await fetch(`${baseUrl}/welfare`, { headers: bearer('u1') }));
    assert.equal(status.comebackAvailable, true);

    // Checking in first still leaves the comeback claimable today.
    const checkin = await getJson(await fetch(`${baseUrl}/welfare/checkin`, { method: 'POST', headers: jsonHeaders('u1') }));
    assert.equal(checkin.status.streak, 1); // reset
    assert.equal(checkin.status.comebackAvailable, true);

    const comeback = await fetch(`${baseUrl}/welfare/comeback`, { method: 'POST', headers: jsonHeaders('u1') });
    assert.equal(comeback.status, 200);
    assert.equal((await getJson(comeback)).reward.coins, COMEBACK_GIFT.coins);
    assert.equal(
      (await fetch(`${baseUrl}/welfare/comeback`, { method: 'POST', headers: jsonHeaders('u1') })).status,
      409,
    );
  });
});

test('newbie gift pays once', async () => {
  const store = new FakeEconomyStore();
  store.now = () => NOW;
  await withServer(store, asUid, async (baseUrl) => {
    const first = await fetch(`${baseUrl}/welfare/newbie`, { method: 'POST', headers: jsonHeaders('u1') });
    assert.equal(first.status, 200);
    assert.equal((await getJson(first)).wallet.coins, NEWBIE_GIFT.coins);
    assert.equal(
      (await fetch(`${baseUrl}/welfare/newbie`, { method: 'POST', headers: jsonHeaders('u1') })).status,
      409,
    );
  });
});

// ── Crafting HTTP flows ───────────────────────────────────────────────────────

function seedJadeRecipe(store: FakeEconomyStore): void {
  store.recipes.set('jade', {
    id: 'jade', nameVi: 'Bàn Ngọc Bích', descVi: '', sortOrder: 1, active: true,
    ingredients: [{ itemId: 'shard', qty: 3 }],
    costCoins: 100,
    output: { itemId: 'jade-board', kind: 'boardTheme', payloadKey: 'jade', qty: 1 },
    createdAtMs: 1, updatedAtMs: 1,
  });
}

test('craft burns ingredients, debits coins, grants output', async () => {
  const store = new FakeEconomyStore();
  seedJadeRecipe(store);
  const u = store.user('u1');
  u.coins = 150;
  u.inventory.set('shard', { itemId: 'shard', kind: 'consumable', payloadKey: 'shard', qty: 4, acquiredAtMs: 1 });
  await withServer(store, asUid, async (baseUrl) => {
    const list = await getJson(await fetch(`${baseUrl}/crafting`));
    assert.equal(list.recipes.length, 1);

    const res = await fetch(`${baseUrl}/crafting/jade/craft`, { method: 'POST', headers: jsonHeaders('u1') });
    assert.equal(res.status, 200);
    const body = await getJson(res);
    assert.equal(body.wallet.coins, 50);
    assert.equal(body.item.itemId, 'jade-board');
    assert.equal(u.inventory.get('shard')?.qty, 1);
    // Crafting the same cosmetic again → already owned.
    u.inventory.set('shard', { itemId: 'shard', kind: 'consumable', payloadKey: 'shard', qty: 3, acquiredAtMs: 1 });
    u.coins = 200;
    assert.equal(
      (await fetch(`${baseUrl}/crafting/jade/craft`, { method: 'POST', headers: jsonHeaders('u1') })).status,
      409,
    );
  });
});

test('craft rejects missing ingredients and insufficient coins', async () => {
  const store = new FakeEconomyStore();
  seedJadeRecipe(store);
  await withServer(store, asUid, async (baseUrl) => {
    const u = store.user('u1');
    u.coins = 100;
    u.inventory.set('shard', { itemId: 'shard', kind: 'consumable', payloadKey: 'shard', qty: 1, acquiredAtMs: 1 });
    const short = await fetch(`${baseUrl}/crafting/jade/craft`, { method: 'POST', headers: jsonHeaders('u1') });
    assert.equal(short.status, 400);
    assert.equal((await getJson(short)).code, 'missing-ingredients');

    u.inventory.set('shard', { itemId: 'shard', kind: 'consumable', payloadKey: 'shard', qty: 3, acquiredAtMs: 1 });
    u.coins = 10;
    const poor = await fetch(`${baseUrl}/crafting/jade/craft`, { method: 'POST', headers: jsonHeaders('u1') });
    assert.equal(poor.status, 402);
  });
});

test('admin recipe upsert + delete', async () => {
  const store = new FakeEconomyStore();
  await withServer(store, { ...asUid, isAdmin: () => true }, async (baseUrl) => {
    const created = await fetch(`${baseUrl}/admin/crafting`, {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify({
        id: 'ink', nameVi: 'Bàn Thủy Mặc', ingredients: [{ itemId: 'ink-drop', qty: 5 }],
        costCoins: 50, output: { itemId: 'ink-board', kind: 'boardTheme', payloadKey: 'ink' },
      }),
    });
    assert.equal(created.status, 201);
    assert.equal((await fetch(`${baseUrl}/admin/crafting/ink`, { method: 'DELETE' })).status, 200);
    assert.equal((await fetch(`${baseUrl}/admin/crafting/ink`, { method: 'DELETE' })).status, 404);
  });
});

// ── Firestore doc mapping (legacy/corrupt data hardening) ────────────────────

test('mapMail: corrupt docs → safe defaults; timestamps accept number/Date/Timestamp-like', () => {
  const empty = mapMail('m1', {});
  assert.equal(empty.title, '');
  assert.equal(empty.reward, null);
  assert.equal(empty.read, false);
  assert.equal(empty.claimed, false);
  assert.equal(empty.createdAtMs, null);
  assert.equal(empty.expiresAtMs, null);

  const doc = mapMail('m2', {
    title: 'Quà',
    reward: {
      coins: 5,
      items: [
        { itemId: 'x', kind: 'consumable', payloadKey: 'p', qty: 0 },
        'junk',
        { itemId: '' },
      ],
    },
    read: 'yes', // non-boolean → false
    claimed: true,
    createdAt: 1000,
    expiresAt: new Date(2000),
  });
  assert.equal(doc.read, false);
  assert.equal(doc.claimed, true);
  assert.equal(doc.createdAtMs, 1000);
  assert.equal(doc.expiresAtMs, 2000);
  assert.deepEqual(doc.reward, {
    coins: 5,
    gems: 0,
    items: [{ itemId: 'x', kind: 'consumable', payloadKey: 'p', qty: 1 }],
  });

  // Firestore Timestamp duck-type.
  assert.equal(mapMail('m3', { createdAt: { toMillis: () => 777 } }).createdAtMs, 777);
  // Zero reward normalizes to null (pure notification).
  assert.equal(mapMail('m4', { reward: { coins: 0, gems: 0, items: [] } }).reward, null);
});

test('mapEvent: active defaults true, invalid gifts dropped, empty gift reward → zero bundle', () => {
  const e = mapEvent('tet', {
    title: 'Tết',
    gifts: [
      { id: 'g1', title: 'Lì xì', reward: { coins: 88 } },
      { id: '', title: 'no-id', reward: { coins: 1 } }, // dropped: no id
      'junk', // dropped: not an object
      { id: 'g2', title: 'Empty', reward: {} }, // kept with a zero bundle
    ],
  });
  assert.equal(e.active, true);
  assert.equal(e.startAtMs, 0);
  assert.deepEqual(e.gifts.map((g) => g.id), ['g1', 'g2']);
  assert.deepEqual(e.gifts[1].reward, { coins: 0, gems: 0, items: [] });
  assert.equal(mapEvent('x', { active: false }).active, false);
});

test('mapWelfare tolerates corrupt fields', () => {
  const w = mapWelfare({
    streak: 'ten',
    lastCheckinDate: 42,
    newbieClaimed: 'yes',
    comebackClaimedFor: {},
  });
  assert.equal(w.streak, 0);
  assert.equal(w.lastCheckinDate, null);
  assert.equal(w.newbieClaimed, false);
  assert.equal(w.comebackClaimedFor, null);
  assert.equal(w.comebackAvailableDate, null);
});

test('mapRecipe: ingredient qty clamps to ≥1, invalid entries dropped, output kind defaults', () => {
  const r = mapRecipe('jade', {
    nameVi: 'Bàn Ngọc',
    ingredients: [{ itemId: 'shard', qty: 0 }, { itemId: '' }, 'junk'],
    output: { itemId: 'jade-board', payloadKey: 'jade' },
  });
  assert.deepEqual(r.ingredients, [{ itemId: 'shard', qty: 1 }]);
  assert.equal(r.output.kind, 'boardTheme');
  assert.equal(r.costCoins, 0);
  assert.equal(r.active, true);
  assert.equal(mapRecipe('x', { active: false }).active, false);
});

test('chunk splits large uid lists under the 500-op Firestore batch cap', () => {
  assert.deepEqual(chunk([], 500), []);
  assert.deepEqual(chunk([1, 2, 3], 2), [[1, 2], [3]]);
  assert.deepEqual(chunk([1, 2], 2), [[1, 2]]);
  const big = Array.from({ length: 1201 }, (_, i) => i);
  const parts = chunk(big, 500);
  assert.deepEqual(parts.map((p) => p.length), [500, 500, 201]);
  assert.deepEqual(parts.flat(), big); // no uid lost or duplicated
});

// ── Welfare edge cases ────────────────────────────────────────────────────────

test('deriveWelfareStatus: day-7 slot pays gems, day 8 wraps, comebackAvailableDate latch', () => {
  // Streak 6 checked in yesterday → today is slot 6 (day 7 of the cycle).
  const day7 = deriveWelfareStatus(
    { ...EMPTY_WELFARE_STATE, streak: 6, lastCheckinDate: YESTERDAY },
    TODAY,
  );
  assert.equal(day7.todayIndex, 6);
  assert.ok(CHECKIN_REWARDS[6].gems > 0);

  // Streak 7 checked in yesterday → today wraps to slot 0.
  const day8 = deriveWelfareStatus(
    { ...EMPTY_WELFARE_STATE, streak: 7, lastCheckinDate: YESTERDAY },
    TODAY,
  );
  assert.equal(day8.todayIndex, 0);

  // The check-in that reset a long gap latches the comeback for the rest of
  // that day (comebackAvailableDate === today) …
  const latched = deriveWelfareStatus(
    { ...EMPTY_WELFARE_STATE, streak: 1, lastCheckinDate: TODAY, comebackAvailableDate: TODAY },
    TODAY,
  );
  assert.equal(latched.comebackAvailable, true);
  // … and only for that day.
  const stale = deriveWelfareStatus(
    { ...EMPTY_WELFARE_STATE, streak: 1, lastCheckinDate: TODAY, comebackAvailableDate: YESTERDAY },
    TODAY,
  );
  assert.equal(stale.comebackAvailable, false);
});

test('eventLive is inclusive at both window edges and respects active', () => {
  const base: EventDoc = {
    id: 'e', title: '', descVi: '', startAtMs: 100, endAtMs: 200,
    active: true, sortOrder: 0, gifts: [],
  };
  assert.equal(eventLive(base, 99), false);
  assert.equal(eventLive(base, 100), true);
  assert.equal(eventLive(base, 200), true);
  assert.equal(eventLive(base, 201), false);
  assert.equal(eventLive({ ...base, active: false }, 150), false);
});

// ── Validation edge cases ─────────────────────────────────────────────────────

test('validateEventClaimInput requires a non-empty giftId and trims it', () => {
  assert.deepEqual(validateEventClaimInput({ giftId: ' lixi ' }), { giftId: 'lixi' });
  assert.throws(() => validateEventClaimInput({}), hasCode('invalid-gift'));
  assert.throws(() => validateEventClaimInput(null), hasCode('invalid-gift'));
  assert.throws(() => validateEventClaimInput({ giftId: '   ' }), hasCode('invalid-gift'));
});

test('validateRewardItem rejects missing itemId/payloadKey and non-objects', () => {
  assert.throws(() => validateRewardItem({ kind: 'consumable', payloadKey: 'p' }), hasCode('invalid-reward-item'));
  assert.throws(() => validateRewardItem({ itemId: 'x', kind: 'consumable' }), hasCode('invalid-reward-item'));
  assert.throws(() => validateRewardItem('junk'), hasCode('invalid-reward-item'));
});

test('validateSendMailInput normalizes expiresAtMs (absent/0/negative/NaN → null)', () => {
  const base = { uid: 'a', title: 'T' };
  assert.equal(validateSendMailInput(base).expiresAtMs, null);
  assert.equal(validateSendMailInput({ ...base, expiresAtMs: 0 }).expiresAtMs, null);
  assert.equal(validateSendMailInput({ ...base, expiresAtMs: -5 }).expiresAtMs, null);
  assert.equal(validateSendMailInput({ ...base, expiresAtMs: 'soon' }).expiresAtMs, null);
  assert.equal(validateSendMailInput({ ...base, expiresAtMs: 1234.9 }).expiresAtMs, 1234);
});

// ── Mail HTTP edge cases ──────────────────────────────────────────────────────

test('POST /mail/:id/read marks read; unknown id → 404', async () => {
  const store = new FakeEconomyStore();
  store.seedMail('u1', { id: 'm1' });
  await withServer(store, asUid, async (baseUrl) => {
    const ok = await fetch(`${baseUrl}/mail/m1/read`, { method: 'POST', headers: jsonHeaders('u1') });
    assert.equal(ok.status, 200);
    assert.equal(store.user('u1').mail.get('m1')?.read, true);
    assert.equal(
      (await fetch(`${baseUrl}/mail/nope/read`, { method: 'POST', headers: jsonHeaders('u1') })).status,
      404,
    );
  });
});

test('POST /mail/:id/delete works as the DELETE alias the Flutter transport uses', async () => {
  const store = new FakeEconomyStore();
  store.seedMail('u1', { id: 'note' }); // pure notification → deletable
  await withServer(store, asUid, async (baseUrl) => {
    const ok = await fetch(`${baseUrl}/mail/note/delete`, { method: 'POST', headers: jsonHeaders('u1') });
    assert.equal(ok.status, 200);
    assert.equal((await store.listMail('u1')).length, 0);
    assert.equal(
      (await fetch(`${baseUrl}/mail/note/delete`, { method: 'POST', headers: jsonHeaders('u1') })).status,
      404,
    );
  });
});

test('claiming expired mail → 404 and credits nothing', async () => {
  const store = new FakeEconomyStore();
  store.now = () => NOW;
  store.seedMail('u1', {
    id: 'late',
    reward: { coins: 5, gems: 0, items: [] },
    expiresAtMs: NOW.getTime() - 1,
  });
  await withServer(store, asUid, async (baseUrl) => {
    const res = await fetch(`${baseUrl}/mail/late/claim`, { method: 'POST', headers: jsonHeaders('u1') });
    assert.equal(res.status, 404);
    assert.equal(store.user('u1').coins, 0);
  });
});

// ── Auth coverage across the personal surface ─────────────────────────────────

test('personal endpoints all require a bearer token (401)', async () => {
  const store = new FakeEconomyStore();
  seedTet(store);
  seedJadeRecipe(store);
  await withServer(store, asUid, async (baseUrl) => {
    const posts = [
      '/welfare/checkin',
      '/welfare/newbie',
      '/welfare/comeback',
      '/mail/x/claim',
      '/mail/x/read',
      '/crafting/jade/craft',
      '/events/tet/claim',
    ];
    for (const path of posts) {
      const res = await fetch(`${baseUrl}${path}`, {
        method: 'POST',
        headers: { 'content-type': 'application/json' },
        body: '{}',
      });
      assert.equal(res.status, 401, `POST ${path}`);
    }
    assert.equal((await fetch(`${baseUrl}/welfare`)).status, 401);
    assert.equal((await fetch(`${baseUrl}/events/claims`)).status, 401);
    // Catalog reads stay public.
    assert.equal((await fetch(`${baseUrl}/events`)).status, 200);
    assert.equal((await fetch(`${baseUrl}/crafting`)).status, 200);
  });
});

// ── Admin guard coverage ──────────────────────────────────────────────────────

test('admin guard covers every events/crafting mutation (403)', async () => {
  const store = new FakeEconomyStore();
  await withServer(store, { ...asUid, isAdmin: () => false }, async (baseUrl) => {
    const routes: Array<[string, string]> = [
      ['POST', '/admin/events'],
      ['PUT', '/admin/events/x'],
      ['DELETE', '/admin/events/x'],
      ['POST', '/admin/crafting'],
      ['PUT', '/admin/crafting/x'],
      ['DELETE', '/admin/crafting/x'],
    ];
    for (const [method, path] of routes) {
      const res = await fetch(`${baseUrl}${path}`, {
        method,
        headers: { 'content-type': 'application/json' },
        body: method === 'DELETE' ? undefined : '{}',
      });
      assert.equal(res.status, 403, `${method} ${path}`);
    }
  });
});

test('with no admin key configured, admin routes reject any provided key', async () => {
  const prevShop = process.env.SHOP_ADMIN_KEY;
  const prevPuzzle = process.env.PUZZLE_ADMIN_KEY;
  delete process.env.SHOP_ADMIN_KEY;
  delete process.env.PUZZLE_ADMIN_KEY;
  try {
    // No isAdmin override → defaultAdminCheck reads the (absent) env keys.
    await withServer(new FakeEconomyStore(), asUid, async (baseUrl) => {
      const res = await fetch(`${baseUrl}/admin/mail`, {
        method: 'POST',
        headers: { 'content-type': 'application/json', 'x-admin-key': 'guess' },
        body: JSON.stringify({ uid: 'a', title: 'x' }),
      });
      assert.equal(res.status, 403);
    });
  } finally {
    if (prevShop !== undefined) process.env.SHOP_ADMIN_KEY = prevShop;
    if (prevPuzzle !== undefined) process.env.PUZZLE_ADMIN_KEY = prevPuzzle;
  }
});

test('PUT /admin/events/:id updates under the URL id', async () => {
  const store = new FakeEconomyStore();
  store.now = () => NOW;
  await store.upsertEvent({
    id: 'tet', title: 'Tết', descVi: '', startAtMs: 1, endAtMs: 2, active: true, sortOrder: 0,
    gifts: [{ id: 'g', title: 't', reward: { coins: 1, gems: 0, items: [] } }],
  });
  await withServer(store, { ...asUid, isAdmin: () => true }, async (baseUrl) => {
    const res = await fetch(`${baseUrl}/admin/events/tet`, {
      method: 'PUT',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify({
        title: 'Tết 2027', startAtMs: 5, endAtMs: 9,
        gifts: [{ id: 'g', title: 't', reward: { coins: 2 } }],
      }),
    });
    assert.equal(res.status, 200);
    assert.equal(store.events.get('tet')?.title, 'Tết 2027');
    assert.equal(store.events.get('tet')?.startAtMs, 5);
  });
});

test('PUT /admin/crafting/:id updates the recipe under the URL id', async () => {
  const store = new FakeEconomyStore();
  seedJadeRecipe(store);
  await withServer(store, { ...asUid, isAdmin: () => true }, async (baseUrl) => {
    const res = await fetch(`${baseUrl}/admin/crafting/jade`, {
      method: 'PUT',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify({
        nameVi: 'Bàn Ngọc v2',
        ingredients: [{ itemId: 'shard', qty: 5 }],
        costCoins: 200,
        output: { itemId: 'jade-board', kind: 'boardTheme', payloadKey: 'jade' },
      }),
    });
    assert.equal(res.status, 200);
    assert.equal(store.recipes.get('jade')?.nameVi, 'Bàn Ngọc v2');
    assert.equal(store.recipes.get('jade')?.ingredients[0].qty, 5);
  });
});

// ── Welfare HTTP edge cases ───────────────────────────────────────────────────

test('comeback without a qualifying absence → 409 not-available', async () => {
  const store = new FakeEconomyStore();
  store.now = () => NOW;
  await withServer(store, asUid, async (baseUrl) => {
    const res = await fetch(`${baseUrl}/welfare/comeback`, { method: 'POST', headers: jsonHeaders('u1') });
    assert.equal(res.status, 409);
    assert.equal((await getJson(res)).code, 'not-available');
  });
});

test('check-in streak wraps after day 7: day 8 pays cycle[0] again', async () => {
  const store = new FakeEconomyStore();
  store.now = () => NOW;
  store.user('u1').welfare = {
    ...EMPTY_WELFARE_STATE, streak: 7, totalCheckins: 7, lastCheckinDate: YESTERDAY,
  };
  await withServer(store, asUid, async (baseUrl) => {
    const res = await getJson(
      await fetch(`${baseUrl}/welfare/checkin`, { method: 'POST', headers: jsonHeaders('u1') }),
    );
    assert.equal(res.status.streak, 8);
    assert.equal(res.reward.coins, CHECKIN_REWARDS[0].coins);
  });
});

test('a 2-day gap resets the streak without unlocking the comeback', async () => {
  const store = new FakeEconomyStore();
  store.now = () => NOW;
  store.user('u1').welfare = {
    ...EMPTY_WELFARE_STATE, streak: 4, totalCheckins: 4, lastCheckinDate: '2026-07-21',
  };
  await withServer(store, asUid, async (baseUrl) => {
    const res = await getJson(
      await fetch(`${baseUrl}/welfare/checkin`, { method: 'POST', headers: jsonHeaders('u1') }),
    );
    assert.equal(res.status.streak, 1);
    assert.equal(res.reward.coins, CHECKIN_REWARDS[0].coins);
    assert.equal(res.status.comebackAvailable, false);
  });
});

// ── Events HTTP edge cases ────────────────────────────────────────────────────

test('claiming a gift from a finished event → 404; live detail returns 200', async () => {
  const store = new FakeEconomyStore();
  seedTet(store);
  await withServer(store, asUid, async (baseUrl) => {
    const dead = await fetch(`${baseUrl}/events/over/claim`, {
      method: 'POST', headers: jsonHeaders('u1'), body: JSON.stringify({ giftId: 'g' }),
    });
    assert.equal(dead.status, 404);

    const live = await fetch(`${baseUrl}/events/tet`);
    assert.equal(live.status, 200);
    assert.equal((await getJson(live)).id, 'tet');
  });
});

// ── Crafting HTTP edge cases ──────────────────────────────────────────────────

test('crafting a consumable output stacks; exact ingredient burn removes the doc', async () => {
  const store = new FakeEconomyStore();
  store.recipes.set('hintpack', {
    id: 'hintpack', nameVi: 'Gói Gợi Ý', descVi: '', sortOrder: 1, active: true,
    ingredients: [{ itemId: 'shard', qty: 1 }],
    costCoins: 10,
    output: { itemId: 'hint', kind: 'consumable', payloadKey: 'hint', qty: 3 },
    createdAtMs: 1, updatedAtMs: 1,
  });
  const u = store.user('u1');
  u.coins = 100;
  u.inventory.set('shard', {
    itemId: 'shard', kind: 'consumable', payloadKey: 'shard', qty: 2, acquiredAtMs: 1,
  });
  await withServer(store, asUid, async (baseUrl) => {
    const first = await getJson(
      await fetch(`${baseUrl}/crafting/hintpack/craft`, { method: 'POST', headers: jsonHeaders('u1') }),
    );
    assert.equal(first.item.qty, 3);
    const second = await getJson(
      await fetch(`${baseUrl}/crafting/hintpack/craft`, { method: 'POST', headers: jsonHeaders('u1') }),
    );
    assert.equal(second.item.qty, 6); // consumable output stacks
    assert.equal(store.user('u1').inventory.has('shard'), false); // 2 − 2 → doc removed
    assert.equal(second.wallet.coins, 80);
  });
});

test('inactive recipes are hidden from the list and cannot be crafted', async () => {
  const store = new FakeEconomyStore();
  seedJadeRecipe(store);
  store.recipes.get('jade')!.active = false;
  const u = store.user('u1');
  u.coins = 1000;
  u.inventory.set('shard', {
    itemId: 'shard', kind: 'consumable', payloadKey: 'shard', qty: 9, acquiredAtMs: 1,
  });
  await withServer(store, asUid, async (baseUrl) => {
    const list = await getJson(await fetch(`${baseUrl}/crafting`));
    assert.equal(list.recipes.length, 0);
    const res = await fetch(`${baseUrl}/crafting/jade/craft`, { method: 'POST', headers: jsonHeaders('u1') });
    assert.equal(res.status, 404);
  });
});

// ── Route ownership ───────────────────────────────────────────────────────────

test('economy api ignores unrelated paths', async () => {
  const api = createEconomyApi({ store: new FakeEconomyStore(), ...asUid });
  const fakeRes = {
    setHeader() {}, writeHead() {}, end() {},
    headersSent: false,
  } as unknown as import('http').ServerResponse;
  const fakeReq = (url: string) =>
    ({ url, method: 'GET', headers: {} }) as unknown as import('http').IncomingMessage;
  assert.equal(await api.handle(fakeReq('/shop'), fakeRes), false);
  assert.equal(await api.handle(fakeReq('/admin/shop'), fakeRes), false);
  assert.equal(await api.handle(fakeReq('/admin/puzzles'), fakeRes), false);
  assert.equal(await api.handle(fakeReq('/mail'), fakeRes), true);
});
