// Types + validation for C3 — Câu Lạc Bộ (Kỳ Xã / Club). A club is a
// user-created group (friend circle or regional). The catalog lives in
// Firestore `clubs/{id}` (public read); membership lives in the subcollection
// `clubs/{id}/members/{uid}` (public read). ALL writes go through the Admin
// SDK so `memberCount` can't be forged and the 3-club-per-user cap can't be
// bypassed from a client (security rules keep the collections client-immutable).

export const MAX_CLUBS_PER_USER = 3;

export type ClubRole = 'owner' | 'member';

/// A club as returned to the client.
export interface ClubDoc {
  id: string;
  name: string;
  region: string;
  description: string;
  founderId: string;
  memberCount: number;
  weeklyScore: number;
  active: boolean;
  createdAtMs: number | null;
}

/// One membership row under clubs/{id}/members/{uid}.
export interface ClubMemberDoc {
  uid: string;
  role: ClubRole;
  displayName: string;
  eloChess: number;
  joinedAtMs: number | null;
}

/// A club id + the caller's role in it (for GET /clubs/mine).
export interface MyClubDoc {
  clubId: string;
  role: ClubRole;
  joinedAtMs: number | null;
}

/// Validated, normalized club-creation input.
export interface CreateClubInput {
  name: string;
  region: string;
  description: string;
}

/// HTTP-shaped error the router converts to `{ code, message }` + status.
export class ClubError extends Error {
  constructor(
    public readonly statusCode: number,
    public readonly code: string,
    message: string,
  ) {
    super(message);
    this.name = 'ClubError';
  }
}

// ── Validation ────────────────────────────────────────────────────────────────

function asTrimmedString(value: unknown): string {
  return typeof value === 'string' ? value.trim() : '';
}

/// Validate + normalize a raw club-creation body. Throws ClubError(400, …) on
/// the first problem.
export function validateCreateClubInput(raw: unknown): CreateClubInput {
  if (typeof raw !== 'object' || raw === null) {
    throw new ClubError(400, 'invalid-club', 'Body must be a JSON object');
  }
  const obj = raw as Record<string, unknown>;

  const name = asTrimmedString(obj.name);
  if (name.length === 0) {
    throw new ClubError(400, 'invalid-name', 'name is required');
  }
  if (name.length > 60) {
    throw new ClubError(400, 'invalid-name', 'name must be at most 60 characters');
  }

  const region = asTrimmedString(obj.region);
  if (region.length === 0) {
    throw new ClubError(400, 'invalid-region', 'region is required');
  }

  const description = asTrimmedString(obj.description);
  if (description.length > 280) {
    throw new ClubError(400, 'invalid-description', 'description must be at most 280 characters');
  }

  return { name, region, description };
}
