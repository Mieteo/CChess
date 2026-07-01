// Storage layer for C6 — the community news/daily-challenge feed. Simple CRUD
// over Firestore `community_feed/{id}`, no transactions needed (no cross-doc
// consistency requirement, unlike shop purchases or club membership).

import { getFirestore, Timestamp, type Firestore } from 'firebase-admin/firestore';

import type { CommunityFeedDoc, FeedItemInput } from './types';

export interface CommunityFeedStore {
  listItems(opts?: { activeOnly?: boolean }): Promise<CommunityFeedDoc[]>;
  // ── Admin ──
  upsertItem(input: FeedItemInput): Promise<CommunityFeedDoc>;
  removeItem(id: string): Promise<boolean>;
}

const COMMUNITY_FEED = 'community_feed';

export interface FirestoreCommunityFeedStoreOptions {
  getDb?: () => Firestore;
  now?: () => Date;
}

export class FirestoreCommunityFeedStore implements CommunityFeedStore {
  private readonly getDb: () => Firestore;
  private readonly now: () => Date;

  constructor(opts: FirestoreCommunityFeedStoreOptions = {}) {
    this.getDb = opts.getDb ?? (() => getFirestore());
    this.now = opts.now ?? (() => new Date());
  }

  async listItems(opts: { activeOnly?: boolean } = {}): Promise<CommunityFeedDoc[]> {
    // Filter + sort in memory (same trick as the shop catalog) so this never
    // needs a composite index — the feed is small and admin-curated.
    const snap = await this.getDb().collection(COMMUNITY_FEED).get();
    const items = snap.docs
      .map((d) => mapItem(d.id, d.data()))
      .filter((it) => (opts.activeOnly === false ? true : it.active));
    items.sort((a, b) => a.sortOrder - b.sortOrder || a.id.localeCompare(b.id));
    return items;
  }

  async upsertItem(input: FeedItemInput): Promise<CommunityFeedDoc> {
    const db = this.getDb();
    const now = this.now();
    const col = db.collection(COMMUNITY_FEED);
    const id = input.id ?? col.doc().id;
    const ref = col.doc(id);
    const existing = await ref.get();
    const payload = {
      type: input.type,
      title: input.title,
      subtitle: input.subtitle,
      meta: input.meta,
      route: input.route,
      linkUrl: input.linkUrl,
      sortOrder: input.sortOrder,
      active: input.active,
      createdAt: existing.exists ? (existing.data() ?? {}).createdAt ?? now : now,
      updatedAt: now,
    };
    await ref.set(payload, { merge: true });
    return mapItem(id, payload);
  }

  async removeItem(id: string): Promise<boolean> {
    const ref = this.getDb().collection(COMMUNITY_FEED).doc(id);
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

function str(value: unknown, fallback = ''): string {
  return typeof value === 'string' ? value : fallback;
}

function nullableStr(value: unknown): string | null {
  return typeof value === 'string' && value.length > 0 ? value : null;
}

export function mapItem(id: string, data: Record<string, unknown>): CommunityFeedDoc {
  return {
    id,
    type: (data.type as CommunityFeedDoc['type']) ?? 'news',
    title: str(data.title),
    subtitle: str(data.subtitle),
    meta: str(data.meta),
    route: nullableStr(data.route),
    linkUrl: nullableStr(data.linkUrl),
    sortOrder: num(data.sortOrder),
    active: data.active !== false,
    createdAtMs: toMillis(data.createdAt),
    updatedAtMs: toMillis(data.updatedAt),
  };
}
