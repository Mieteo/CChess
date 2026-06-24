// Types + validation for the endgame puzzle library (B4 — Kho Tàn Cục).
//
// A puzzle is a stored xiangqi position the user solves move-by-move. The
// canonical record lives in Firestore `puzzles/{id}`; the app browses a
// paginated/filtered list, plays one, then reports progress. Aggregate
// counters (totalAttempts/solveCount) are server-owned so the global solve
// rate can't be inflated from a client.

/// UCI move on a 9×10 xiangqi board: file a-i, rank 0-9 (e.g. "h2e2").
export const UCI_MOVE_REGEX = /^[a-i][0-9][a-i][0-9]$/;

/// Coarse difficulty band, 1 (easiest) .. 5 (hardest).
export const MIN_DIFFICULTY = 1;
export const MAX_DIFFICULTY = 5;

/// Tactical/structural buckets used for filtering. Free-form strings are still
/// accepted on write, but the app's filter chips map to these.
export type PuzzleCategory =
  | 'checkmate_1' // chiếu hết trong 1 nước
  | 'checkmate_2' // chiếu hết trong 2 nước
  | 'checkmate_3' // chiếu hết trong 3+ nước
  | 'capture' // bắt quân / thắng vật chất
  | 'defense' // thủ hoà / gỡ thế
  | 'tactic'; // chiến thuật chung

export type PuzzleSort = 'newest' | 'hardest' | 'easiest';

/// A puzzle as returned to the client. Timestamps are epoch millis so the JSON
/// is transport-friendly (Firestore Timestamps are converted at the boundary).
export interface PuzzleDoc {
  id: string;
  fen: string;
  /// UCI moves: solver, opponent, solver, … (odd indices auto-played).
  solution: string[];
  titleVi: string;
  descriptionVi: string;
  difficulty: number;
  category: string;
  theme: string;
  tags: string[];
  /// 0..1 share of attempts that ended solved. Server-maintained.
  solveRateGlobal: number;
  totalAttempts: number;
  solveCount: number;
  source: string;
  /// "YYYY-MM-DD" if this puzzle is the featured daily for some date, else null.
  dailyDate: string | null;
  publishedAtMs: number | null;
  createdAtMs: number | null;
  updatedAtMs: number | null;
}

/// Per-user progress for one puzzle (under users/{uid}/puzzle_progress/{id}).
export interface PuzzleProgressDoc {
  puzzleId: string;
  solved: boolean;
  attempts: number;
  hintsUsed: number;
  /// Highest score the user has earned on this puzzle (0..100).
  bestScore: number;
  solvedAtMs: number | null;
  updatedAtMs: number | null;
}

/// Body of POST /puzzles/:id/progress.
export interface ProgressInput {
  solved: boolean;
  hintsUsed: number;
  score: number;
}

/// Validated, normalized puzzle ready to persist. `id` may be assigned by the
/// store on create when omitted by the caller.
export interface PuzzleInput {
  id?: string;
  fen: string;
  solution: string[];
  titleVi: string;
  descriptionVi: string;
  difficulty: number;
  category: string;
  theme: string;
  tags: string[];
  source: string;
  isDraft: boolean;
}

export interface PuzzleListQuery {
  limit: number;
  cursor?: string;
  difficulty?: number;
  category?: string;
  theme?: string;
  tag?: string;
  sort: PuzzleSort;
}

export interface PuzzleListResult {
  puzzles: PuzzleDoc[];
  hasMore: boolean;
  nextCursor: string | null;
}

/// HTTP-shaped error the router converts to `{ code, message }` + status.
export class PuzzleError extends Error {
  constructor(
    public readonly statusCode: number,
    public readonly code: string,
    message: string,
  ) {
    super(message);
    this.name = 'PuzzleError';
  }
}

// ── Validation ──────────────────────────────────────────────────────────────

/// Light FEN shape check: 10 ranks separated by '/', a side-to-move token, and
/// only legal piece/rank characters. Not a full legality check — the engine
/// smoke / app already vet positions; this just rejects obvious garbage.
export function isValidXiangqiFen(fen: unknown): fen is string {
  if (typeof fen !== 'string' || fen.trim().length === 0) return false;
  const parts = fen.trim().split(/\s+/);
  const ranks = parts[0].split('/');
  if (ranks.length !== 10) return false;
  for (const rank of ranks) {
    if (!/^[rnbakcpRNBAKCP1-9]+$/.test(rank)) return false;
    let count = 0;
    for (const ch of rank) {
      count += /[1-9]/.test(ch) ? Number(ch) : 1;
    }
    if (count !== 9) return false;
  }
  // Side-to-move is optional in some stores but we want it for the solver turn.
  if (parts.length >= 2 && parts[1] !== 'w' && parts[1] !== 'b') return false;
  return true;
}

function asTrimmedString(value: unknown): string {
  return typeof value === 'string' ? value.trim() : '';
}

/// Validate + normalize a raw puzzle object (from JSON import or admin POST).
/// Throws PuzzleError(400, …) on the first problem so the caller gets a precise
/// message. Returns a clean PuzzleInput with defaults filled in.
export function validatePuzzleInput(raw: unknown): PuzzleInput {
  if (typeof raw !== 'object' || raw === null) {
    throw new PuzzleError(400, 'invalid-puzzle', 'Puzzle must be a JSON object');
  }
  const obj = raw as Record<string, unknown>;

  const fen = asTrimmedString(obj.fen);
  if (!isValidXiangqiFen(fen)) {
    throw new PuzzleError(400, 'invalid-fen', `Invalid FEN: ${JSON.stringify(obj.fen)}`);
  }

  const solution = Array.isArray(obj.solution) ? obj.solution : [];
  if (solution.length === 0) {
    throw new PuzzleError(400, 'invalid-solution', 'solution must be a non-empty array of UCI moves');
  }
  for (const mv of solution) {
    if (typeof mv !== 'string' || !UCI_MOVE_REGEX.test(mv)) {
      throw new PuzzleError(400, 'invalid-solution', `Invalid UCI move in solution: ${JSON.stringify(mv)}`);
    }
  }

  const titleVi = asTrimmedString(obj.titleVi);
  if (titleVi.length === 0) {
    throw new PuzzleError(400, 'invalid-title', 'titleVi is required');
  }

  const difficultyRaw = Number(obj.difficulty);
  const difficulty = Number.isFinite(difficultyRaw)
    ? Math.min(MAX_DIFFICULTY, Math.max(MIN_DIFFICULTY, Math.trunc(difficultyRaw)))
    : 1;

  const tags = Array.isArray(obj.tags)
    ? obj.tags.filter((t): t is string => typeof t === 'string' && t.trim().length > 0).map((t) => t.trim())
    : [];

  const idRaw = asTrimmedString(obj.id);

  return {
    id: idRaw.length > 0 ? idRaw : undefined,
    fen,
    solution: solution as string[],
    titleVi,
    descriptionVi: asTrimmedString(obj.descriptionVi),
    difficulty,
    category: asTrimmedString(obj.category) || 'tactic',
    theme: asTrimmedString(obj.theme),
    tags,
    source: asTrimmedString(obj.source) || 'admin',
    isDraft: obj.isDraft === true,
  };
}

/// Validate the progress report body. Clamps score to 0..100 and hintsUsed ≥ 0.
export function validateProgressInput(raw: unknown): ProgressInput {
  const obj = (typeof raw === 'object' && raw !== null ? raw : {}) as Record<string, unknown>;
  const score = Number(obj.score);
  const hintsUsed = Number(obj.hintsUsed);
  return {
    solved: obj.solved === true,
    hintsUsed: Number.isFinite(hintsUsed) ? Math.max(0, Math.trunc(hintsUsed)) : 0,
    score: Number.isFinite(score) ? Math.min(100, Math.max(0, Math.trunc(score))) : 0,
  };
}

/// "YYYY-MM-DD" for a Date in a given IANA offset. Daily puzzles roll over at
/// local midnight; default tz is Vietnam (UTC+7, no DST).
export function dateKeyVN(now: Date = new Date(), offsetHours = 7): string {
  const shifted = new Date(now.getTime() + offsetHours * 3_600_000);
  return shifted.toISOString().slice(0, 10);
}

/// Whether a "YYYY-MM-DD" string is well-formed.
export function isValidDateKey(value: unknown): value is string {
  return typeof value === 'string' && /^\d{4}-\d{2}-\d{2}$/.test(value);
}
