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

test('best-move forwards blunderRate to the engine and never caches blunder rolls', async () => {
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

    // blunderRate reaches the pool as part of EngineLimit.
    await postBestMoveBody(baseUrl, 'blunder-user', {
      fen: '4k4/9/9/9/9/9/9/9/9/4K4 w - - 0 1',
      blunderRate: 0.12,
    });
    assert.equal(pool.lastLimit?.blunderRate, 0.12);
    assert.equal(pool.calls, 1);

    // A blunder-enabled request must NEVER hit the cache, even repeating the
    // exact same fen+blunderRate — every call needs its own fresh roll.
    const second = await postBestMoveBody(baseUrl, 'blunder-user', {
      fen: '4k4/9/9/9/9/9/9/9/9/4K4 w - - 0 1',
      blunderRate: 0.12,
    });
    assert.equal(second.cached, false);
    assert.equal(pool.calls, 2);
  } finally {
    await service.close();
  }
});

test('best-move without blunderRate still caches as before', async () => {
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
    await postBestMoveBody(baseUrl, 'plain-user', {
      fen: '4k4/9/9/9/9/9/9/9/9/4K4 w - - 0 1',
    });
    assert.equal(pool.calls, 1);
    const cached = await postBestMoveBody(baseUrl, 'plain-user', {
      fen: '4k4/9/9/9/9/9/9/9/9/4K4 w - - 0 1',
    });
    assert.equal(cached.cached, true);
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

test('GET /engine/nnue streams the network file to signed-in users', async () => {
  const { createEngineHttpServer } = await import('./server');
  const { mkdtempSync, writeFileSync, rmSync } = await import('node:fs');
  const { tmpdir } = await import('node:os');
  const { join } = await import('node:path');

  const dir = mkdtempSync(join(tmpdir(), 'nnue-test-'));
  const nnuePath = join(dir, 'pikafish.nnue');
  const payload = Buffer.from('fake-nnue-bytes-for-testing');
  writeFileSync(nnuePath, payload);

  const service = createEngineHttpServer({
    pool: new FakePool(),
    authenticate: async (token) => ({ uid: token }),
    requireAuth: true,
    nnuePath,
  });

  try {
    const baseUrl = await listen(service.httpServer);

    const anonymous = await fetch(`${baseUrl}/engine/nnue`);
    assert.equal(anonymous.status, 401);

    const res = await fetch(`${baseUrl}/engine/nnue`, {
      headers: { authorization: 'Bearer alice' },
    });
    assert.equal(res.status, 200);
    assert.equal(res.headers.get('content-type'), 'application/octet-stream');
    assert.equal(Number(res.headers.get('content-length')), payload.length);
    const body = Buffer.from(await res.arrayBuffer());
    assert.deepEqual(body, payload);
  } finally {
    await service.close();
    rmSync(dir, { recursive: true, force: true });
  }
});

test('GET /engine/nnue returns 503 when no network file is configured', async () => {
  const previous = process.env.EVAL_FILE;
  delete process.env.EVAL_FILE;
  const { createEngineHttpServer } = await import('./server');
  const service = createEngineHttpServer({
    pool: new FakePool(),
    authenticate: async (token) => ({ uid: token }),
    requireAuth: true,
  });

  try {
    const baseUrl = await listen(service.httpServer);
    const res = await fetch(`${baseUrl}/engine/nnue`, {
      headers: { authorization: 'Bearer alice' },
    });
    assert.equal(res.status, 503);
  } finally {
    await service.close();
    if (previous !== undefined) process.env.EVAL_FILE = previous;
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
