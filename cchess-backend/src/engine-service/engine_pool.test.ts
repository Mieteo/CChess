import assert from 'node:assert/strict';
import { test } from 'node:test';

import { EnginePool, type SearchEngine } from './engine_pool';
import type { EngineBestMove, EngineLimit } from './types';

class FakeEngine implements SearchEngine {
  constructor(
    private readonly onStart: () => void,
    private readonly onFinish: () => void,
    private readonly delayMs = 20,
  ) {}

  async bestMove(_fen: string, _limit?: EngineLimit): Promise<EngineBestMove> {
    this.onStart();
    await new Promise((resolve) => setTimeout(resolve, this.delayMs));
    this.onFinish();
    return { uci: 'h2e2', scoreCp: 12, depth: 4, pv: ['h2e2'] };
  }

  dispose(): void {
    // No process to clean up in tests.
  }
}

test('EnginePool caps concurrent searches and drains queue', async () => {
  let active = 0;
  let maxActive = 0;
  const pool = new EnginePool({
    maxConcurrency: 2,
    maxQueueSize: 8,
    taskTimeoutMs: 1000,
    createEngine: () => new FakeEngine(
      () => {
        active++;
        maxActive = Math.max(maxActive, active);
      },
      () => {
        active--;
      },
    ),
  });

  const results = await Promise.all([
    pool.bestMove('fen 1'),
    pool.bestMove('fen 2'),
    pool.bestMove('fen 3'),
    pool.bestMove('fen 4'),
  ]);

  assert.equal(results.length, 4);
  assert.equal(maxActive, 2);
  assert.equal(pool.stats().queued, 0);
  pool.dispose();
});

test('EnginePool rejects when queue is full', async () => {
  const pool = new EnginePool({
    maxConcurrency: 1,
    maxQueueSize: 0,
    taskTimeoutMs: 1000,
    createEngine: () => new FakeEngine(() => undefined, () => undefined, 50),
  });

  const first = pool.bestMove('fen 1');
  await assert.rejects(pool.bestMove('fen 2'), /Engine queue is full/);
  await first;
  pool.dispose();
});
