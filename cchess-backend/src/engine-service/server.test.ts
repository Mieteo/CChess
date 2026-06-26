process.env.CCHESS_ENGINE_NO_LISTEN = '1';

import assert from 'node:assert/strict';
import { test } from 'node:test';
import type { AddressInfo } from 'node:net';
import type { Server } from 'node:http';

import { DailyQuotaStore } from './quota';
import type { EngineBestMove, EngineLimit } from './types';

class FakePool {
  calls = 0;
  lastLimit: EngineLimit | undefined;

  async bestMove(_fen: string, limit?: EngineLimit): Promise<EngineBestMove> {
    this.calls++;
    this.lastLimit = limit;
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

test('best-move forwards ELO/skill to the engine and keys the cache by them', async () => {
  const { createEngineHttpServer } = await import('./server');
  const pool = new FakePool();
  const service = createEngineHttpServer({
    pool,
    authenticate: async (token) => ({ uid: token }),
    isVip: async () => false,
    requireAuth: true,
    quota: new DailyQuotaStore({
      bestMovePerDay: 100,
      hintPerDay: 100,
      analyzePerDay: 100,
    }),
  });

  try {
    const baseUrl = await listen(service.httpServer);

    // ELO/skill reach the pool as a strength-limited EngineLimit.
    await postBestMoveBody(baseUrl, 'elo-user', {
      fen: '4k4/9/9/9/9/9/9/9/9/4K4 w - - 0 1',
      elo: 2050,
      skill: 6,
    });
    assert.equal(pool.lastLimit?.uciElo, 2050);
    assert.equal(pool.lastLimit?.skillLevel, 6);
    assert.equal(pool.calls, 1);

    // A different ELO on the SAME fen must NOT hit the cache — distinct key.
    await postBestMoveBody(baseUrl, 'elo-user', {
      fen: '4k4/9/9/9/9/9/9/9/9/4K4 w - - 0 1',
      elo: 2650,
      skill: 18,
    });
    assert.equal(pool.calls, 2);
    assert.equal(pool.lastLimit?.uciElo, 2650);

    // Repeating the first ELO serves the cached move (no new engine call).
    const cached = await postBestMoveBody(baseUrl, 'elo-user', {
      fen: '4k4/9/9/9/9/9/9/9/9/4K4 w - - 0 1',
      elo: 2050,
      skill: 6,
    });
    assert.equal(cached.cached, true);
    assert.equal(pool.calls, 2);
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

test('GET /engine/quota reports remaining free allowance', async () => {
  const { createEngineHttpServer } = await import('./server');
  const service = createEngineHttpServer({
    pool: new FakePool(),
    authenticate: async (token) => ({ uid: token }),
    isVip: async () => false,
    requireAuth: true,
    quota: new DailyQuotaStore({
      bestMovePerDay: 30,
      hintPerDay: 3,
      analyzePerDay: 3,
    }),
  });

  try {
    const baseUrl = await listen(service.httpServer);
    // Spend one hint, then read the snapshot back.
    assert.equal((await postHint(baseUrl, 'q-status')).status, 200);

    const res = await fetch(`${baseUrl}/engine/quota`, {
      headers: { authorization: 'Bearer q-status' },
    });
    assert.equal(res.status, 200);
    const body = (await res.json()) as {
      vip: boolean;
      features: Record<string, { used: number; limit: number; remaining: number }>;
    };
    assert.equal(body.vip, false);
    assert.equal(body.features.hint.used, 1);
    assert.equal(body.features.hint.limit, 3);
    assert.equal(body.features.hint.remaining, 2);
    assert.equal(body.features['best-move'].remaining, 30);
  } finally {
    await service.close();
  }
});

test('GET /engine/quota reports unlimited for VIP', async () => {
  const { createEngineHttpServer } = await import('./server');
  const service = createEngineHttpServer({
    pool: new FakePool(),
    authenticate: async (token) => ({ uid: token }),
    isVip: async () => true,
    requireAuth: true,
    quota: new DailyQuotaStore({ bestMovePerDay: 30, hintPerDay: 3, analyzePerDay: 3 }),
  });

  try {
    const baseUrl = await listen(service.httpServer);
    const res = await fetch(`${baseUrl}/engine/quota`, {
      headers: { authorization: 'Bearer vip-user' },
    });
    assert.equal(res.status, 200);
    const body = (await res.json()) as {
      vip: boolean;
      features: Record<string, { limit: number; remaining: number }>;
    };
    assert.equal(body.vip, true);
    assert.equal(body.features.hint.limit, -1);
    assert.equal(body.features.hint.remaining, -1);
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

async function postBestMoveBody(
  baseUrl: string,
  token: string,
  body: Record<string, unknown>,
): Promise<Record<string, unknown>> {
  const res = await fetch(`${baseUrl}/engine/best-move`, {
    method: 'POST',
    headers: {
      authorization: `Bearer ${token}`,
      'content-type': 'application/json',
    },
    body: JSON.stringify(body),
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
