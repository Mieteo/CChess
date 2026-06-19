process.env.CCHESS_ENGINE_NO_LISTEN = '1';

import assert from 'node:assert/strict';
import { test } from 'node:test';
import type { AddressInfo } from 'node:net';
import type { Server } from 'node:http';

import { DailyQuotaStore } from './quota';
import type { EngineBestMove, EngineLimit } from './types';

class FakePool {
  calls = 0;

  async bestMove(_fen: string, _limit?: EngineLimit): Promise<EngineBestMove> {
    this.calls++;
    return { uci: 'h2e2', scoreCp: 20, depth: 5, pv: ['h2e2'] };
  }

  stats() {
    return { maxConcurrency: 1, busy: 0, queued: 0, maxQueueSize: 4 };
  }

  dispose(): void {
    // No process to clean up in tests.
  }
}

test('engine HTTP server requires auth then returns a cached best move', async () => {
  const { createEngineHttpServer } = await import('./server');
  const pool = new FakePool();
  const service = createEngineHttpServer({
    pool,
    authenticate: async (token) => ({ uid: token }),
    requireAuth: true,
  });

  try {
    const baseUrl = await listen(service.httpServer);
    const missingAuth = await fetch(`${baseUrl}/engine/best-move`, {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify({ fen: '4k4/9/9/9/9/9/9/9/9/4K4 w - - 0 1' }),
    });
    assert.equal(missingAuth.status, 401);

    const first = await postBestMove(baseUrl, 'alice');
    const second = await postBestMove(baseUrl, 'alice');
    assert.equal(first.uci, 'h2e2');
    assert.equal(first.cached, false);
    assert.equal(second.cached, true);
    assert.equal(pool.calls, 1);
  } finally {
    await service.close();
  }
});

test('engine HTTP server enforces free hint quota', async () => {
  const { createEngineHttpServer } = await import('./server');
  const service = createEngineHttpServer({
    pool: new FakePool(),
    authenticate: async (token) => ({ uid: token }),
    requireAuth: true,
    quota: new DailyQuotaStore({
      bestMovePerDay: 10,
      hintPerDay: 1,
      analyzePerDay: 10,
    }),
  });

  try {
    const baseUrl = await listen(service.httpServer);
    const first = await postHint(baseUrl, 'quota-user');
    assert.equal(first.status, 200);
    const second = await postHint(baseUrl, 'quota-user');
    assert.equal(second.status, 429);
    const body = await second.json() as Record<string, unknown>;
    assert.equal(body.code, 'quota-exceeded');
  } finally {
    await service.close();
  }
});

function listen(server: Server): Promise<string> {
  return new Promise((resolve) => {
    server.listen(0, '127.0.0.1', () => {
      const address = server.address() as AddressInfo;
      resolve(`http://127.0.0.1:${address.port}`);
    });
  });
}

async function postBestMove(baseUrl: string, token: string): Promise<Record<string, unknown>> {
  const res = await fetch(`${baseUrl}/engine/best-move`, {
    method: 'POST',
    headers: {
      authorization: `Bearer ${token}`,
      'content-type': 'application/json',
    },
    body: JSON.stringify({ fen: '4k4/9/9/9/9/9/9/9/9/4K4 w - - 0 1' }),
  });
  assert.equal(res.status, 200);
  return res.json() as Promise<Record<string, unknown>>;
}

async function postHint(baseUrl: string, token: string): Promise<Response> {
  return fetch(`${baseUrl}/engine/hint`, {
    method: 'POST',
    headers: {
      authorization: `Bearer ${token}`,
      'content-type': 'application/json',
    },
    body: JSON.stringify({ fen: '4k4/9/9/9/9/9/9/9/9/4K4 w - - 0 1' }),
  });
}
