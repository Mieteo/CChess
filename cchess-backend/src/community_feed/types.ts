// Types + validation for C6 — Tin Tức + Tàn Cục Thách Đấu (News + Daily
// Challenge feed). The feed is admin-curated content (like shop_items /
// puzzles), NOT user-generated (that's C7 Diễn đàn — out of scope). It lives
// in Firestore `community_feed/{id}` (public read, server-only write).

export const FEED_ITEM_TYPES = ['puzzle', 'match', 'news'] as const;
export type FeedItemType = (typeof FEED_ITEM_TYPES)[number];

/// A feed card as returned to the client.
export interface CommunityFeedDoc {
  id: string;
  type: FeedItemType;
  title: string;
  subtitle: string;
  meta: string;
  /// Stable marker the client uses to decide what tapping the card does (e.g.
  /// 'daily_puzzle' → fetch+open today's daily puzzle via GET /puzzles/daily).
  /// Null means the card has no tap action.
  route: string | null;
  /// External article URL for plain news items. Null for puzzle/match cards.
  linkUrl: string | null;
  sortOrder: number;
  active: boolean;
  createdAtMs: number | null;
  updatedAtMs: number | null;
}

/// Validated, normalized feed item ready to persist.
export interface FeedItemInput {
  id?: string;
  type: FeedItemType;
  title: string;
  subtitle: string;
  meta: string;
  route: string | null;
  linkUrl: string | null;
  sortOrder: number;
  active: boolean;
}

/// HTTP-shaped error the router converts to `{ code, message }` + status.
export class FeedError extends Error {
  constructor(
    public readonly statusCode: number,
    public readonly code: string,
    message: string,
  ) {
    super(message);
    this.name = 'FeedError';
  }
}

// ── Validation ────────────────────────────────────────────────────────────────

function asTrimmedString(value: unknown): string {
  return typeof value === 'string' ? value.trim() : '';
}

function asNullableTrimmedString(value: unknown): string | null {
  if (value === null || value === undefined) return null;
  const s = asTrimmedString(value);
  return s.length > 0 ? s : null;
}

function asNonNegInt(value: unknown): number {
  const n = Number(value);
  return Number.isFinite(n) ? Math.max(0, Math.trunc(n)) : 0;
}

export function isFeedItemType(value: unknown): value is FeedItemType {
  return typeof value === 'string' && (FEED_ITEM_TYPES as readonly string[]).includes(value);
}

/// Validate + normalize a raw feed item (admin POST/PUT). Throws
/// FeedError(400, …) on the first problem. Fills sensible defaults.
export function validateFeedItemInput(raw: unknown): FeedItemInput {
  if (typeof raw !== 'object' || raw === null) {
    throw new FeedError(400, 'invalid-item', 'Item must be a JSON object');
  }
  const obj = raw as Record<string, unknown>;

  if (!isFeedItemType(obj.type)) {
    throw new FeedError(400, 'invalid-type', `type must be one of ${FEED_ITEM_TYPES.join(', ')}`);
  }
  const title = asTrimmedString(obj.title);
  if (title.length === 0) {
    throw new FeedError(400, 'invalid-title', 'title is required');
  }
  const subtitle = asTrimmedString(obj.subtitle);
  if (subtitle.length === 0) {
    throw new FeedError(400, 'invalid-subtitle', 'subtitle is required');
  }

  const idRaw = asTrimmedString(obj.id);

  return {
    id: idRaw.length > 0 ? idRaw : undefined,
    type: obj.type,
    title,
    subtitle,
    meta: asTrimmedString(obj.meta),
    route: asNullableTrimmedString(obj.route),
    linkUrl: asNullableTrimmedString(obj.linkUrl),
    sortOrder: asNonNegInt(obj.sortOrder),
    active: obj.active !== false, // default true
  };
}
