// Types + validation for C4 — Giải Đấu (Tournament). v1 ships only
// system/admin-created, single-elimination tournaments — "Giải đấu do người
// dùng tự tổ chức" from the spec is out of scope (see plan). The catalog lives
// in Firestore `tournaments/{id}` (public read); participants and matches live
// in subcollections (public read). ALL writes go through the Admin SDK.

export const TOURNAMENT_FORMATS = ['single_elimination'] as const;
export type TournamentFormat = (typeof TOURNAMENT_FORMATS)[number];

export const TOURNAMENT_STATUSES = ['registering', 'in_progress', 'finished'] as const;
export type TournamentStatus = (typeof TOURNAMENT_STATUSES)[number];

export const PARTICIPANT_STATUSES = ['registered', 'active', 'eliminated', 'champion'] as const;
export type ParticipantStatus = (typeof PARTICIPANT_STATUSES)[number];

export const MATCH_STATUSES = ['pending', 'ready', 'in_progress', 'finished'] as const;
export type MatchStatus = (typeof MATCH_STATUSES)[number];

export type MatchSlot = 'player1' | 'player2';
export type MatchResult = 'player1' | 'player2' | 'bye';

/// A tournament as returned to the client.
export interface TournamentDoc {
  id: string;
  name: string;
  format: TournamentFormat;
  status: TournamentStatus;
  createdBy: string;
  startsAtMs: number | null;
  registrationDeadlineMs: number | null;
  minElo: number | null;
  maxElo: number | null;
  capacity: number;
  participantCount: number;
  prize: string;
  rewards: Record<string, number>;
  winnerUid: string | null;
  createdAtMs: number | null;
}

/// One registration row under tournaments/{id}/participants/{uid}.
export interface ParticipantDoc {
  uid: string;
  displayName: string;
  eloAtRegistration: number;
  status: ParticipantStatus;
  registeredAtMs: number | null;
}

/// One bracket match under tournaments/{id}/matches/{matchId}. Doubles as the
/// shape the pure bracket algorithm (bracket.ts) operates on.
export interface MatchDoc {
  id: string;
  round: number;
  slotIndex: number;
  player1Id: string | null;
  player2Id: string | null;
  result: MatchResult | null;
  roomId: string | null;
  status: MatchStatus;
  nextMatchId: string | null;
  nextMatchSlot: MatchSlot | null;
  createdAtMs: number | null;
  finishedAtMs: number | null;
}

/// Validated, normalized tournament-creation input.
export interface CreateTournamentInput {
  name: string;
  startsAtMs: number;
  registrationDeadlineMs: number;
  capacity: number;
  minElo: number | null;
  maxElo: number | null;
  prize: string;
  rewards: Record<string, number>;
}

/// HTTP-shaped error the router converts to `{ code, message }` + status.
export class TournamentError extends Error {
  constructor(
    public readonly statusCode: number,
    public readonly code: string,
    message: string,
  ) {
    super(message);
    this.name = 'TournamentError';
  }
}

// ── Validation ────────────────────────────────────────────────────────────────

function asTrimmedString(value: unknown): string {
  return typeof value === 'string' ? value.trim() : '';
}

function asPosInt(value: unknown, fallback: number): number {
  const n = Number(value);
  return Number.isFinite(n) && n > 0 ? Math.trunc(n) : fallback;
}

function asNullableElo(value: unknown): number | null {
  if (value === null || value === undefined || value === '') return null;
  const n = Number(value);
  return Number.isFinite(n) ? Math.trunc(n) : null;
}

/// Validate + normalize a raw tournament-creation body. Throws
/// TournamentError(400, …) on the first problem.
export function validateCreateTournamentInput(raw: unknown): CreateTournamentInput {
  if (typeof raw !== 'object' || raw === null) {
    throw new TournamentError(400, 'invalid-tournament', 'Body must be a JSON object');
  }
  const obj = raw as Record<string, unknown>;

  const name = asTrimmedString(obj.name);
  if (name.length === 0) {
    throw new TournamentError(400, 'invalid-name', 'name is required');
  }

  const startsAtMs = Number(obj.startsAtMs);
  if (!Number.isFinite(startsAtMs)) {
    throw new TournamentError(400, 'invalid-startsAt', 'startsAtMs must be a timestamp (ms)');
  }
  const registrationDeadlineMs = Number(obj.registrationDeadlineMs);
  if (!Number.isFinite(registrationDeadlineMs)) {
    throw new TournamentError(400, 'invalid-deadline', 'registrationDeadlineMs must be a timestamp (ms)');
  }
  if (registrationDeadlineMs > startsAtMs) {
    throw new TournamentError(400, 'invalid-deadline', 'registrationDeadlineMs must be at or before startsAtMs');
  }

  const capacity = asPosInt(obj.capacity, 32);
  const minElo = asNullableElo(obj.minElo);
  const maxElo = asNullableElo(obj.maxElo);
  if (minElo !== null && maxElo !== null && minElo > maxElo) {
    throw new TournamentError(400, 'invalid-elo-range', 'minElo must be at most maxElo');
  }

  const rewardsRaw = obj.rewards;
  const rewards: Record<string, number> = {};
  if (rewardsRaw && typeof rewardsRaw === 'object') {
    for (const [k, v] of Object.entries(rewardsRaw as Record<string, unknown>)) {
      const n = Number(v);
      if (Number.isFinite(n) && n > 0) rewards[k] = Math.trunc(n);
    }
  }

  return {
    name,
    startsAtMs,
    registrationDeadlineMs,
    capacity,
    minElo,
    maxElo,
    prize: asTrimmedString(obj.prize),
    rewards,
  };
}
