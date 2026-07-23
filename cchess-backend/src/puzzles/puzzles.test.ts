import assert from 'node:assert/strict';
import { test } from 'node:test';
import { createServer, type Server } from 'node:http';
import type { AddressInfo } from 'node:net';

import { createPuzzleApi } from './puzzle_routes';
import type { PuzzleStore } from './puzzle_store';
import {
  dateKeyVN,
  isValidXiangqiFen,
  PuzzleError,
  validateProgressInput,
  validatePuzzleInput,
  type ProgressInput,
  type PuzzleDoc,
  type PuzzleInput,
  type PuzzleListQuery,
  type PuzzleProgressDoc,
} from './types';

// ── In-memory store fake ─────────────────────────────────────────────────────
// Models just enough of the store contract for the route tests: a Map of
// published puzzles, a daily map, and per-uid progress with server counters.

class FakePuzzleStore implements PuzzleStore {
  readonly puzzles = new Map<string, PuzzleDoc>();
  readonly daily = new Map<string, string>();
  readonly progress = new Map<string, PuzzleProgressDoc>();
  private seq = 0;

  seed(doc: Partial<PuzzleDoc> & { id: string; fen: string; solution: string[]; titleVi: string }): void {
    this.puzzles.set(doc.id, {
      descriptionVi: '',
      difficulty: 1,
      category: 'tactic',
      theme: '',
      tags: [],
      solveRateGlobal: 0,
      totalAttempts: 0,
      solveCount: 0,
      source: 'test',
      dailyDate: null,
      publishedAtMs: ++this.seq,
      createdAtMs: this.seq,
      updatedAtMs: this.seq,
      ...doc,
    });
  }

  async list(query: PuzzleListQuery): Promise<{ puzzles: PuzzleDoc[]; hasMore: boolean; nextCursor: string | null }> {
    let all = [...this.puzzles.values()];
    if (query.difficulty !== undefined) all = all.filter((p) => p.difficulty === query.difficulty);
    if (query.category !== undefined) all = all.filter((p) => p.category === query.category);
    if (query.theme !== undefined) all = all.filter((p) => p.theme === query.theme);
    if (query.tag !== undefined) all = all.filter((p) => p.tags.includes(query.tag!));
    all.sort((a, b) => {
      if (query.sort === 'hardest') return b.difficulty - a.difficulty || (b.publishedAtMs ?? 0) - (a.publishedAtMs ?? 0);
      if (query.sort === 'easiest') return a.difficulty - b.difficulty || (b.publishedAtMs ?? 0) - (a.publishedAtMs ?? 0);
      return (b.publishedAtMs ?? 0) - (a.publishedAtMs ?? 0);
    });
    let start = 0;
    if (query.cursor) {
      const idx = all.findIndex((p) => p.id === query.cursor);
      start = idx >= 0 ? idx + 1 : 0;
    }
    const page = all.slice(start, start + query.limit);
    const hasMore = start + query.limit < all.length;
    return { puzzles: page, hasMore, nextCursor: hasMore ? page[page.length - 1].id : null };
  }

  async get(id: string): Promise<PuzzleDoc | null> {
    return this.puzzles.get(id) ?? null;
  }

  async getDaily(dateKey: string): Promise<PuzzleDoc | null> {
    const id = this.daily.get(dateKey);
    return id ? this.get(id) : null;
  }

  async recordProgress(uid: string, puzzleId: string, input: ProgressInput): Promise<PuzzleProgressDoc> {
    const puzzle = this.puzzles.get(puzzleId);
    if (!puzzle) throw new PuzzleError(404, 'not-found', 'Puzzle not found');
    const key = `${uid}/${puzzleId}`;
    const prev = this.progress.get(key);
    const prevSolved = prev?.solved ?? false;
    const solved = prevSolved || input.solved;
    const next: PuzzleProgressDoc = {
      puzzleId,
      solved,
      attempts: (prev?.attempts ?? 0) + 1,
      hintsUsed: (prev?.hintsUsed ?? 0) + input.hintsUsed,
      bestScore: Math.max(prev?.bestScore ?? 0, input.score),
      solvedAtMs: solved ? (prev?.solvedAtMs ?? Date.now()) : null,
      updatedAtMs: Date.now(),
    };
    this.progress.set(key, next);
    puzzle.totalAttempts += 1;
    if (input.solved && !prevSolved) puzzle.solveCount += 1;
    puzzle.solveRateGlobal = puzzle.totalAttempts > 0 ? puzzle.solveCount / puzzle.totalAttempts : 0;
    return next;
  }

  async upsert(input: PuzzleInput): Promise<PuzzleDoc> {
    const id = input.id ?? `gen-${++this.seq}`;
    const existing = this.puzzles.get(id);
    const doc: PuzzleDoc = {
      id,
      fen: input.fen,
      solution: input.solution,
      titleVi: input.titleVi,
      descriptionVi: input.descriptionVi,
      difficulty: input.difficulty,
      category: input.category,
      theme: input.theme,
      tags: input.tags,
      source: input.source,
      solveRateGlobal: existing?.solveRateGlobal ?? 0,
      totalAttempts: existing?.totalAttempts ?? 0,
      solveCount: existing?.solveCount ?? 0,
      dailyDate: existing?.dailyDate ?? null,
      publishedAtMs: input.isDraft ? null : existing?.publishedAtMs ?? ++this.seq,
      createdAtMs: existing?.createdAtMs ?? this.seq,
      updatedAtMs: ++this.seq,
    };
    this.puzzles.set(id, doc);
    return doc;
  }

  async remove(id: string): Promise<boolean> {
    return this.puzzles.delete(id);
  }

  async setDaily(dateKey: string, puzzleId: string): Promise<void> {
    if (!this.puzzles.has(puzzleId)) throw new PuzzleError(404, 'not-found', 'Puzzle not found');
    this.daily.set(dateKey, puzzleId);
    const p = this.puzzles.get(puzzleId)!;
    p.dailyDate = dateKey;
  }
}

// Strict TS types fetch().json() as unknown; tests just want the parsed body.
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

/// Mount a puzzle API on a throwaway http server; the 404 fallthrough mirrors
/// how the real cchess-backend hosts it.
async function withServer(
  store: FakePuzzleStore,
  extra: Parameters<typeof createPuzzleApi>[0],
  run: (baseUrl: string) => Promise<void>,
): Promise<void> {
  const api = createPuzzleApi({ store, ...extra });
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

const VALID_FEN = '4k4/9/9/9/R3c4/9/9/9/9/4K4 w - - 0 1';

// ── Validation ───────────────────────────────────────────────────────────────

test('isValidXiangqiFen accepts a real position and rejects garbage', () => {
  assert.equal(isValidXiangqiFen(VALID_FEN), true);
  assert.equal(isValidXiangqiFen('4k4/9/9/9/9/9/9/9/9/4K4 w - - 0 1'), true);
  assert.equal(isValidXiangqiFen('not a fen'), false);
  assert.equal(isValidXiangqiFen('4k4/9/9/9/9/9/9/9/4K4 w'), false); // only 9 ranks
  assert.equal(isValidXiangqiFen('9/9/9/9/9/9/9/9/9/8 w'), false); // rank sums to 8
  assert.equal(isValidXiangqiFen('4k4/9/9/9/9/9/9/9/9/4K4 x'), false); // bad side
});

test('validatePuzzleInput normalizes and clamps', () => {
  const input = validatePuzzleInput({
    fen: VALID_FEN,
    solution: ['a5e5'],
    titleVi: '  Bắt Pháo Hớ  ',
    difficulty: 9,
    tags: ['Tàn cục', '', 'Xe'],
  });
  assert.equal(input.titleVi, 'Bắt Pháo Hớ');
  assert.equal(input.difficulty, 5); // clamped to MAX
  assert.deepEqual(input.tags, ['Tàn cục', 'Xe']);
  assert.equal(input.category, 'tactic'); // default
  assert.equal(input.source, 'admin'); // default
  assert.equal(input.isDraft, false);
});

test('validatePuzzleInput rejects bad fen / empty solution / missing title', () => {
  assert.throws(() => validatePuzzleInput({ fen: 'x', solution: ['a5e5'], titleVi: 'T' }), /invalid-fen|Invalid FEN/);
  assert.throws(() => validatePuzzleInput({ fen: VALID_FEN, solution: [], titleVi: 'T' }), /solution/);
  assert.throws(() => validatePuzzleInput({ fen: VALID_FEN, solution: ['zz99'], titleVi: 'T' }), /UCI/);
  assert.throws(() => validatePuzzleInput({ fen: VALID_FEN, solution: ['a5e5'], titleVi: '' }), /titleVi/);
});

test('validateProgressInput clamps score and hints', () => {
  assert.deepEqual(validateProgressInput({ solved: true, score: 250, hintsUsed: -3 }), {
    solved: true,
    score: 100,
    hintsUsed: 0,
  });
  assert.deepEqual(validateProgressInput(null), { solved: false, score: 0, hintsUsed: 0 });
});

test('dateKeyVN rolls over at Vietnam midnight, not UTC', () => {
  // 2026-06-23T18:00:00Z is 2026-06-24 01:00 in UTC+7.
  assert.equal(dateKeyVN(new Date('2026-06-23T18:00:00.000Z')), '2026-06-24');
  assert.equal(dateKeyVN(new Date('2026-06-23T16:59:00.000Z')), '2026-06-23');
});

// ── Public read routes ───────────────────────────────────────────────────────

test('GET /puzzles paginates with a cursor', async () => {
  const store = new FakePuzzleStore();
  for (let i = 1; i <= 5; i++) {
    store.seed({ id: `p00${i}`, fen: VALID_FEN, solution: ['a5e5'], titleVi: `Bài ${i}` });
  }
  await withServer(store, {}, async (baseUrl) => {
    const r1 = await getJson(await fetch(`${baseUrl}/puzzles?limit=2`));
    assert.equal(r1.puzzles.length, 2);
    assert.equal(r1.hasMore, true);
    assert.ok(r1.nextCursor);

    const r2 = await getJson(await fetch(`${baseUrl}/puzzles?limit=2&cursor=${r1.nextCursor}`));
    assert.equal(r2.puzzles.length, 2);
    // No overlap between pages.
    const ids1 = r1.puzzles.map((p: PuzzleDoc) => p.id);
    const ids2 = r2.puzzles.map((p: PuzzleDoc) => p.id);
    assert.equal(ids1.some((id: string) => ids2.includes(id)), false);
  });
});

test('GET /puzzles filters by difficulty', async () => {
  const store = new FakePuzzleStore();
  store.seed({ id: 'easy', fen: VALID_FEN, solution: ['a5e5'], titleVi: 'Dễ', difficulty: 1 });
  store.seed({ id: 'hard', fen: VALID_FEN, solution: ['a5e5'], titleVi: 'Khó', difficulty: 5 });
  await withServer(store, {}, async (baseUrl) => {
    const res = await getJson(await fetch(`${baseUrl}/puzzles?difficulty=5`));
    assert.equal(res.puzzles.length, 1);
    assert.equal(res.puzzles[0].id, 'hard');
  });
});

test('GET /puzzles/:id returns one or 404', async () => {
  const store = new FakePuzzleStore();
  store.seed({ id: 'p001', fen: VALID_FEN, solution: ['a5e5'], titleVi: 'Bài 1' });
  await withServer(store, {}, async (baseUrl) => {
    const ok = await fetch(`${baseUrl}/puzzles/p001`);
    assert.equal(ok.status, 200);
    assert.equal((await getJson(ok)).titleVi, 'Bài 1');

    const missing = await fetch(`${baseUrl}/puzzles/nope`);
    assert.equal(missing.status, 404);
  });
});

test('GET /puzzles/daily returns the configured daily for a date', async () => {
  const store = new FakePuzzleStore();
  store.seed({ id: 'p007', fen: VALID_FEN, solution: ['a5e5'], titleVi: 'Daily' });
  store.daily.set('2026-06-24', 'p007');
  await withServer(store, {}, async (baseUrl) => {
    const res = await getJson(await fetch(`${baseUrl}/puzzles/daily?date=2026-06-24`));
    assert.equal(res.date, '2026-06-24');
    assert.equal(res.puzzle.id, 'p007');

    const empty = await getJson(await fetch(`${baseUrl}/puzzles/daily?date=2030-01-01`));
    assert.equal(empty.puzzle, null);
  });
});

test('unmatched non-puzzle path falls through to 404', async () => {
  const store = new FakePuzzleStore();
  await withServer(store, {}, async (baseUrl) => {
    const res = await fetch(`${baseUrl}/health`);
    assert.equal(res.status, 404); // host server would handle this; api didn't own it
  });
});

// ── Progress route (auth) ────────────────────────────────────────────────────

test('POST /puzzles/:id/progress requires auth then records + aggregates', async () => {
  const store = new FakePuzzleStore();
  store.seed({ id: 'p001', fen: VALID_FEN, solution: ['a5e5'], titleVi: 'Bài 1' });
  await withServer(store, { authenticate: async (token) => ({ uid: token }) }, async (baseUrl) => {
    const noAuth = await fetch(`${baseUrl}/puzzles/p001/progress`, {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify({ solved: true, score: 100, hintsUsed: 0 }),
    });
    assert.equal(noAuth.status, 401);

    const ok = await fetch(`${baseUrl}/puzzles/p001/progress`, {
      method: 'POST',
      headers: { 'content-type': 'application/json', authorization: 'Bearer alice' },
      body: JSON.stringify({ solved: true, score: 100, hintsUsed: 1 }),
    });
    assert.equal(ok.status, 200);
    const body = await getJson(ok);
    assert.equal(body.solved, true);
    assert.equal(body.bestScore, 100);
    assert.equal(body.attempts, 1);

    // Global counters updated; first solve counted once.
    assert.equal(store.puzzles.get('p001')!.totalAttempts, 1);
    assert.equal(store.puzzles.get('p001')!.solveCount, 1);
  });
});

// ── Admin routes ─────────────────────────────────────────────────────────────

test('admin routes are gated by the admin check', async () => {
  const store = new FakePuzzleStore();
  const isAdmin = (req: { headers: Record<string, unknown> }) => req.headers['x-admin-key'] === 'secret';
  await withServer(store, { isAdmin: isAdmin as never }, async (baseUrl) => {
    const denied = await fetch(`${baseUrl}/admin/puzzles`, {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify({ fen: VALID_FEN, solution: ['a5e5'], titleVi: 'X' }),
    });
    assert.equal(denied.status, 403);

    const created = await fetch(`${baseUrl}/admin/puzzles`, {
      method: 'POST',
      headers: { 'content-type': 'application/json', 'x-admin-key': 'secret' },
      body: JSON.stringify({ fen: VALID_FEN, solution: ['a5e5'], titleVi: 'Bài Admin', difficulty: 3 }),
    });
    assert.equal(created.status, 201);
    const doc = await getJson(created);
    assert.equal(doc.titleVi, 'Bài Admin');
    assert.equal(doc.difficulty, 3);
    assert.equal(store.puzzles.size, 1);
  });
});

test('POST /admin/puzzles/import reports created + per-item errors', async () => {
  const store = new FakePuzzleStore();
  const isAdmin = () => true;
  await withServer(store, { isAdmin: isAdmin as never }, async (baseUrl) => {
    const res = await fetch(`${baseUrl}/admin/puzzles/import`, {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify([
        { id: 'a', fen: VALID_FEN, solution: ['a5e5'], titleVi: 'Hợp lệ' },
        { id: 'b', fen: 'broken', solution: ['a5e5'], titleVi: 'Lỗi FEN' },
      ]),
    });
    assert.equal(res.status, 200);
    const body = await getJson(res);
    assert.equal(body.imported, 1);
    assert.deepEqual(body.ids, ['a']);
    assert.equal(body.errors.length, 1);
    assert.equal(body.errors[0].index, 1);
  });
});

test('POST /admin/daily wires a date to a puzzle', async () => {
  const store = new FakePuzzleStore();
  store.seed({ id: 'p010', fen: VALID_FEN, solution: ['a5e5'], titleVi: 'Daily' });
  await withServer(store, { isAdmin: (() => true) as never }, async (baseUrl) => {
    const res = await fetch(`${baseUrl}/admin/daily`, {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify({ date: '2026-07-01', puzzleId: 'p010' }),
    });
    assert.equal(res.status, 200);
    assert.equal(store.daily.get('2026-07-01'), 'p010');
  });
});

test('puzzle api only owns its own /admin namespace (regression: it used to shadow /admin/shop)', async () => {
  const api = createPuzzleApi({ store: new FakePuzzleStore() });
  const fakeRes = {
    setHeader() {}, writeHead() {}, end() {},
    headersSent: false,
  } as unknown as import('http').ServerResponse;
  const fakeReq = (url: string) =>
    ({ url, method: 'GET', headers: {} }) as unknown as import('http').IncomingMessage;
  assert.equal(await api.handle(fakeReq('/admin/shop'), fakeRes), false);
  assert.equal(await api.handle(fakeReq('/admin/community/feed'), fakeRes), false);
  assert.equal(await api.handle(fakeReq('/admin/mail'), fakeRes), false);
  assert.equal(await api.handle(fakeReq('/admin/puzzles'), fakeRes), true);
  assert.equal(await api.handle(fakeReq('/admin/daily'), fakeRes), true);
  assert.equal(await api.handle(fakeReq('/puzzles'), fakeRes), true);
});
