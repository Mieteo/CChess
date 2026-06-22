import assert from 'node:assert/strict';
import { createServer, type Server } from 'node:http';
import type { AddressInfo } from 'node:net';
import test from 'node:test';

import { parseUci, XiangqiGame } from '../../../src/engine';
import { EngineConcurrencyLimiter, EngineMetrics } from '../engine_metrics';
import { SeededRandom } from '../random';
import { HeuristicPolicy } from './heuristic';
import { RemoteEnginePolicy } from './remote_engine';

test('heuristic policy returns a legal move from the initial position', async () => {
  const policy = new HeuristicPolicy();
  const uci = await policy.chooseMove({
    uid: 'sim_red',
    roomId: 'ROOM01',
    color: 'red',
    movesUci: [],
    nowMs: Date.now(),
    random: new SeededRandom(11),
  });

  assert.ok(uci);
  const parsed = parseUci(uci);
  assert.ok(parsed);
  assert.equal(XiangqiGame.initial().isValidMove(parsed.from, parsed.to), true);
});

test('remote engine policy accepts a legal HTTP best move and records cache hit', async () => {
  const server = createServer((req, res) => {
    assert.equal(req.headers.authorization, 'Bearer token-1');
    res.writeHead(200, { 'content-type': 'application/json' });
    res.end(JSON.stringify({ uci: 'a3a4', scoreCp: 10, depth: 4, pv: ['a3a4'], cached: true }));
  });

  try {
    const baseUrl = await listen(server);
    const metrics = new EngineMetrics();
    const policy = new RemoteEnginePolicy({
      baseUrl,
      authToken: 'token-1',
      timeoutMs: 500,
      movetimeMs: 50,
      limiter: new EngineConcurrencyLimiter(1),
      metrics,
    });

    const uci = await policy.chooseMove({
      uid: 'sim_red',
      roomId: 'ROOM02',
      color: 'red',
      movesUci: [],
      nowMs: Date.now(),
      random: new SeededRandom(12),
    });

    assert.equal(uci, 'a3a4');
    const snapshot = metrics.snapshot();
    assert.equal(snapshot.attempts, 1);
    assert.equal(snapshot.successes, 1);
    assert.equal(snapshot.cacheHits, 1);
    assert.equal(snapshot.errors, 0);
  } finally {
    await close(server);
  }
});

test('remote engine policy falls back and reports quota errors', async () => {
  const server = createServer((_req, res) => {
    res.writeHead(429, { 'content-type': 'application/json' });
    res.end(JSON.stringify({ code: 'quota-exceeded', message: 'Daily engine quota exceeded' }));
  });

  try {
    const baseUrl = await listen(server);
    const metrics = new EngineMetrics();
    const policy = new RemoteEnginePolicy({
      baseUrl,
      timeoutMs: 500,
      movetimeMs: 50,
      limiter: new EngineConcurrencyLimiter(1),
      metrics,
    });

    const uci = await policy.chooseMove({
      uid: 'sim_red',
      roomId: 'ROOM03',
      color: 'red',
      movesUci: [],
      nowMs: Date.now(),
      random: new SeededRandom(13),
    });

    assert.ok(uci);
    const snapshot = metrics.snapshot();
    assert.equal(snapshot.attempts, 1);
    assert.equal(snapshot.errors, 1);
    assert.equal(snapshot.fallbacks, 1);
    assert.equal(snapshot.lastError?.status, 429);
    assert.equal(snapshot.lastError?.code, 'quota-exceeded');
  } finally {
    await close(server);
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

function close(server: Server): Promise<void> {
  return new Promise((resolve, reject) => {
    server.close((error) => {
      if (error) reject(error);
      else resolve();
    });
  });
}
