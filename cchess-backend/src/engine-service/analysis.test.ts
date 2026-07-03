import assert from 'node:assert/strict';
import { test } from 'node:test';

import { analyzeGame } from './analysis';
import type { EngineBestMove, EngineLimit } from './types';
import { EngineServiceError } from './types';

const INITIAL_FEN =
  'rnbakabnr/9/1c5c1/p1p1p1p1p/9/9/P1P1P1P1P/1C5C1/9/RNBAKABNR w - - 0 1';

/** Scripted resolver: returns queued responses in order and counts calls. */
function scriptedResolver(responses: EngineBestMove[]) {
  let calls = 0;
  const resolver = async (_fen: string, _limit: EngineLimit): Promise<EngineBestMove> => {
    const response = responses[Math.min(calls, responses.length - 1)];
    calls++;
    return response;
  };
  return { resolver, callCount: () => calls };
}

test('analyzeGame searches once per position (N+1 for N moves)', async () => {
  const { resolver, callCount } = scriptedResolver([
    { uci: 'b2e2', scoreCp: 30, depth: 12, pv: ['b2e2'] },
    { uci: 'b7e7', scoreCp: -28, depth: 12, pv: ['b7e7'] },
    { uci: 'h0g2', scoreCp: 55, depth: 12, pv: ['h0g2'] },
  ]);

  const result = await analyzeGame(INITIAL_FEN, ['b2e2', 'h7e7'], {}, resolver);

  assert.equal(callCount(), 3); // 3 positions, not 4 searches
  assert.equal(result.perMove.length, 2);

  // Red played the engine's own best move → 'best'.
  assert.equal(result.perMove[0].classification, 'best');
  // Eval after red's move comes from position 1 (black to move, −28 for
  // black) → +28 red-perspective.
  assert.equal(result.perMove[0].evalAfterCp, 28);

  // Black best was −28 (mover view) but played into +55 for red → actual
  // −55 → loss 27 → 'good'; evalAfterCp stays red-positive (+55).
  assert.equal(result.perMove[1].centipawnLoss, 27);
  assert.equal(result.perMove[1].classification, 'good');
  assert.equal(result.perMove[1].evalAfterCp, 55);
});

test('analyzeGame scores a game-ending move without an extra search', async () => {
  // Lone black king d9; red rook e4 → e8 stalemates black (stalemate = loss
  // in xiangqi), so the game ends on red's move.
  const fen = '3k5/9/9/9/9/4R4/9/9/9/4K4 w - - 0 1';
  const { resolver, callCount } = scriptedResolver([
    { uci: 'e4e8', scoreCp: 2500, depth: 15, pv: ['e4e8'] },
  ]);

  const result = await analyzeGame(fen, ['e4e8'], {}, resolver);

  assert.equal(callCount(), 1); // terminal position never searched
  assert.equal(result.perMove.length, 1);
  assert.equal(result.perMove[0].actualScoreCp, 29_999);
  assert.equal(result.perMove[0].evalAfterCp, 29_999);
  assert.equal(result.perMove[0].classification, 'best');
});

test('analyzeGame reports progress per graded move', async () => {
  const { resolver } = scriptedResolver([
    { uci: 'b2e2', scoreCp: 10, depth: 10, pv: ['b2e2'] },
  ]);
  const seen: Array<{ completed: number; total: number }> = [];

  await analyzeGame(INITIAL_FEN, ['b2e2', 'b7e7'], {}, resolver, (p) => {
    seen.push({ completed: p.completedMoves, total: p.totalMoves });
    assert.ok(p.latest.uci.length === 4);
  });

  assert.deepEqual(seen, [
    { completed: 1, total: 2 },
    { completed: 2, total: 2 },
  ]);
});

test('analyzeGame rejects an illegal recorded move', async () => {
  const { resolver } = scriptedResolver([
    { uci: 'b2e2', scoreCp: 10, depth: 10, pv: ['b2e2'] },
  ]);
  await assert.rejects(
    analyzeGame(INITIAL_FEN, ['a0a9'], {}, resolver),
    (error: unknown) =>
      error instanceof EngineServiceError && error.code === 'illegal-move',
  );
});
