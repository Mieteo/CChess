// Storage layer for the puzzle library. The route handler talks only to the
// PuzzleStore interface, so tests inject a deterministic in-memory fake while
// production uses FirestorePuzzleStore (Admin SDK → bypasses security rules,
// which is what lets us keep server-only counters like solveRateGlobal honest).

import {
  FieldValue,
  getFirestore,
  Timestamp,
  type Firestore,
  type Query,
} from 'firebase-admin/firestore';

import {
  PuzzleError,
  type ProgressInput,
  type PuzzleDoc,
  type PuzzleInput,
  type PuzzleListQuery,
  type PuzzleListResult,
  type PuzzleProgressDoc,
} from './types';

export interface PuzzleStore {
  list(query: PuzzleListQuery): Promise<PuzzleListResult>;
  get(id: string): Promise<PuzzleDoc | null>;
  getDaily(dateKey: string): Promise<PuzzleDoc | null>;
  recordProgress(uid: string, puzzleId: string, input: ProgressInput): Promise<PuzzleProgressDoc>;
  // ── Admin ──
  upsert(input: PuzzleInput): Promise<PuzzleDoc>;
  remove(id: string): Promise<boolean>;
  setDaily(dateKey: string, puzzleId: string): Promise<void>;
}

const PUZZLES = 'puzzles';
const DAILY = 'daily_puzzles';
const USERS = 'users';
const PROGRESS = 'puzzle_progress';

/// Slug a human title into a stable-ish id when the caller didn't supply one.
/// Collisions are resolved by the store appending a short suffix.
function slugifyId(title: string): string {
  const base = title
    .normalize('NFD')
    .replace(/[̀-ͯ]/g, '') // strip Vietnamese diacritics
    .toLowerCase()
    .replace(/đ/g, 'd')
    .replace(/[^a-z0-9]+/g, '-')
    .replace(/^-+|-+$/g, '')
    .slice(0, 40);
  return base.length > 0 ? base : 'puzzle';
}

function toMillis(value: unknown): number | null {
  if (value === null || value === undefined) return null;
  if (typeof value === 'number') return value;
  if (value instanceof Date) return value.getTime();
  const maybe = value as { toMillis?: () => number };
  if (typeof maybe.toMillis === 'function') return maybe.toMillis();
  return null;
}

/// Map a Firestore document's data to the transport PuzzleDoc shape.
function mapPuzzle(id: string, data: Record<string, unknown>): PuzzleDoc {
  const totalAttempts = typeof data.totalAttempts === 'number' ? data.totalAttempts : 0;
  const solveCount = typeof data.solveCount === 'number' ? data.solveCount : 0;
  return {
    id,
    fen: String(data.fen ?? ''),
    solution: Array.isArray(data.solution) ? (data.solution as string[]) : [],
    titleVi: String(data.titleVi ?? ''),
    descriptionVi: String(data.descriptionVi ?? ''),
    difficulty: typeof data.difficulty === 'number' ? data.difficulty : 1,
    category: String(data.category ?? 'tactic'),
    theme: String(data.theme ?? ''),
    tags: Array.isArray(data.tags) ? (data.tags as string[]) : [],
    solveRateGlobal:
      typeof data.solveRateGlobal === 'number'
        ? data.solveRateGlobal
        : totalAttempts > 0
          ? solveCount / totalAttempts
          : 0,
    totalAttempts,
    solveCount,
    source: String(data.source ?? 'admin'),
    dailyDate: typeof data.dailyDate === 'string' ? data.dailyDate : null,
    publishedAtMs: toMillis(data.publishedAt),
    createdAtMs: toMillis(data.createdAt),
    updatedAtMs: toMillis(data.updatedAt),
  };
}

export interface FirestorePuzzleStoreOptions {
  getDb?: () => Firestore;
  now?: () => Date;
}

export class FirestorePuzzleStore implements PuzzleStore {
  private readonly getDb: () => Firestore;
  private readonly now: () => Date;

  constructor(opts: FirestorePuzzleStoreOptions = {}) {
    this.getDb = opts.getDb ?? (() => getFirestore());
    this.now = opts.now ?? (() => new Date());
  }

  async list(query: PuzzleListQuery): Promise<PuzzleListResult> {
    const db = this.getDb();
    let q: Query = db.collection(PUZZLES).where('isDraft', '==', false);

    // One optional equality/array filter. Combining a filter with a difficulty
    // sort would need extra composite indexes, so when a filter is present we
    // pin the sort to publishedAt (newest) — see firestore.indexes.json.
    const filtered =
      query.difficulty !== undefined ||
      query.category !== undefined ||
      query.theme !== undefined ||
      query.tag !== undefined;

    if (query.difficulty !== undefined) q = q.where('difficulty', '==', query.difficulty);
    else if (query.category !== undefined) q = q.where('category', '==', query.category);
    else if (query.theme !== undefined) q = q.where('theme', '==', query.theme);
    else if (query.tag !== undefined) q = q.where('tags', 'array-contains', query.tag);

    if (!filtered && query.sort === 'hardest') {
      q = q.orderBy('difficulty', 'desc').orderBy('publishedAt', 'desc');
    } else if (!filtered && query.sort === 'easiest') {
      q = q.orderBy('difficulty', 'asc').orderBy('publishedAt', 'desc');
    } else {
      q = q.orderBy('publishedAt', 'desc');
    }

    if (query.cursor) {
      const curSnap = await db.collection(PUZZLES).doc(query.cursor).get();
      if (curSnap.exists) q = q.startAfter(curSnap);
    }

    // Fetch one extra to detect whether another page exists.
    const snap = await q.limit(query.limit + 1).get();
    const docs = snap.docs.slice(0, query.limit);
    const hasMore = snap.docs.length > query.limit;
    const puzzles = docs.map((d) => mapPuzzle(d.id, d.data()));
    return {
      puzzles,
      hasMore,
      nextCursor: hasMore && puzzles.length > 0 ? puzzles[puzzles.length - 1].id : null,
    };
  }

  async get(id: string): Promise<PuzzleDoc | null> {
    const snap = await this.getDb().collection(PUZZLES).doc(id).get();
    if (!snap.exists || snap.data()?.isDraft === true) return null;
    return mapPuzzle(snap.id, snap.data() as Record<string, unknown>);
  }

  async getDaily(dateKey: string): Promise<PuzzleDoc | null> {
    const dailySnap = await this.getDb().collection(DAILY).doc(dateKey).get();
    const puzzleId = dailySnap.exists ? (dailySnap.data()?.puzzleId as string | undefined) : undefined;
    if (!puzzleId) return null;
    return this.get(puzzleId);
  }

  async recordProgress(
    uid: string,
    puzzleId: string,
    input: ProgressInput,
  ): Promise<PuzzleProgressDoc> {
    const db = this.getDb();
    const now = this.now();
    const puzzleRef = db.collection(PUZZLES).doc(puzzleId);
    const progressRef = db
      .collection(USERS)
      .doc(uid)
      .collection(PROGRESS)
      .doc(puzzleId);

    return db.runTransaction(async (tx) => {
      const puzzleSnap = await tx.get(puzzleRef);
      if (!puzzleSnap.exists) {
        throw new PuzzleError(404, 'not-found', 'Puzzle not found');
      }
      const prevSnap = await tx.get(progressRef);
      const prev = prevSnap.exists ? (prevSnap.data() as Record<string, unknown>) : {};
      const prevSolved = prev.solved === true;
      const prevAttempts = typeof prev.attempts === 'number' ? prev.attempts : 0;
      const prevHints = typeof prev.hintsUsed === 'number' ? prev.hintsUsed : 0;
      const prevBest = typeof prev.bestScore === 'number' ? prev.bestScore : 0;

      const solved = prevSolved || input.solved;
      const bestScore = Math.max(prevBest, input.score);
      const next: PuzzleProgressDoc = {
        puzzleId,
        solved,
        attempts: prevAttempts + 1,
        hintsUsed: prevHints + input.hintsUsed,
        bestScore,
        solvedAtMs: solved ? (typeof prev.solvedAt !== 'undefined' && prevSolved ? toMillis(prev.solvedAt) : now.getTime()) : null,
        updatedAtMs: now.getTime(),
      };

      tx.set(
        progressRef,
        {
          puzzleId,
          solved,
          attempts: next.attempts,
          hintsUsed: next.hintsUsed,
          bestScore,
          solvedAt: solved ? (prevSolved ? prev.solvedAt ?? Timestamp.fromMillis(now.getTime()) : Timestamp.fromMillis(now.getTime())) : null,
          updatedAt: Timestamp.fromMillis(now.getTime()),
        },
        { merge: true },
      );

      // Global aggregates: every report is one more attempt; only the FIRST
      // solve by this user counts toward solveCount (so the rate isn't gamed by
      // re-solving). solveRateGlobal is recomputed from the new totals.
      const firstSolveByUser = input.solved && !prevSolved;
      const newTotal = (typeof puzzleSnap.data()?.totalAttempts === 'number' ? puzzleSnap.data()!.totalAttempts as number : 0) + 1;
      const newSolves = (typeof puzzleSnap.data()?.solveCount === 'number' ? puzzleSnap.data()!.solveCount as number : 0) + (firstSolveByUser ? 1 : 0);
      tx.set(
        puzzleRef,
        {
          totalAttempts: FieldValue.increment(1),
          solveCount: firstSolveByUser ? FieldValue.increment(1) : FieldValue.increment(0),
          solveRateGlobal: newTotal > 0 ? newSolves / newTotal : 0,
        },
        { merge: true },
      );

      return next;
    });
  }

  async upsert(input: PuzzleInput): Promise<PuzzleDoc> {
    const db = this.getDb();
    const now = Timestamp.fromMillis(this.now().getTime());
    const id = input.id ?? (await this.uniqueId(slugifyId(input.titleVi)));
    const ref = db.collection(PUZZLES).doc(id);
    const existing = await ref.get();

    const base = {
      fen: input.fen,
      solution: input.solution,
      titleVi: input.titleVi,
      descriptionVi: input.descriptionVi,
      difficulty: input.difficulty,
      category: input.category,
      theme: input.theme,
      tags: input.tags,
      source: input.source,
      isDraft: input.isDraft,
      updatedAt: now,
    };
    if (existing.exists) {
      await ref.set(base, { merge: true });
    } else {
      await ref.set({
        ...base,
        totalAttempts: 0,
        solveCount: 0,
        solveRateGlobal: 0,
        dailyDate: null,
        createdAt: now,
        publishedAt: input.isDraft ? null : now,
      });
    }
    const fresh = await ref.get();
    return mapPuzzle(id, fresh.data() as Record<string, unknown>);
  }

  async remove(id: string): Promise<boolean> {
    const ref = this.getDb().collection(PUZZLES).doc(id);
    const snap = await ref.get();
    if (!snap.exists) return false;
    await ref.delete();
    return true;
  }

  async setDaily(dateKey: string, puzzleId: string): Promise<void> {
    const db = this.getDb();
    const puzzleRef = db.collection(PUZZLES).doc(puzzleId);
    const snap = await puzzleRef.get();
    if (!snap.exists) {
      throw new PuzzleError(404, 'not-found', `Puzzle ${puzzleId} not found`);
    }
    const now = Timestamp.fromMillis(this.now().getTime());
    await db.collection(DAILY).doc(dateKey).set({ puzzleId, date: dateKey, setAt: now });
    await puzzleRef.set({ dailyDate: dateKey }, { merge: true });
  }

  /// Find a free document id derived from `base`, appending -2, -3, … on clash.
  private async uniqueId(base: string): Promise<string> {
    const col = this.getDb().collection(PUZZLES);
    if (!(await col.doc(base).get()).exists) return base;
    for (let i = 2; i < 1000; i++) {
      const candidate = `${base}-${i}`;
      if (!(await col.doc(candidate).get()).exists) return candidate;
    }
    return `${base}-${Date.now()}`;
  }
}
