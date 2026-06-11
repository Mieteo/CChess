// D5 hardening: double-disconnect (BOTH players drop mid-game).
//
// Runs in its own process (node:test spawns one per file) with a SHORT
// reconnect grace via CCHESS_RECONNECT_GRACE_MS so the forfeit path can be
// exercised without waiting 60s. Both env vars must be set BEFORE server.ts
// (and transitively match.ts) is imported — hence the dynamic import inside
// startTestServer, mirroring server.test.ts.
process.env.CCHESS_NO_LISTEN = '1';
process.env.CCHESS_RECONNECT_GRACE_MS = '1500';

import assert from 'node:assert/strict';
import { test } from 'node:test';
import type { AddressInfo } from 'node:net';
import { WebSocket } from 'ws';

import type { CChessServer } from './server';

interface Msg {
  type: string;
  [k: string]: unknown;
}

async function startTestServer(): Promise<{ server: CChessServer; url: string }> {
  const { createCChessServer } = await import('./server');
  const server = createCChessServer({
    authenticate: async (token: string) => ({ uid: token }),
    persist: async () => null,
  });
  return new Promise((resolve) => {
    server.httpServer.listen(0, '127.0.0.1', () => {
      const { port } = server.httpServer.address() as AddressInfo;
      resolve({ server, url: `ws://127.0.0.1:${port}` });
    });
  });
}

class TestClient {
  readonly ws: WebSocket;
  private readonly queue: Msg[] = [];
  private readonly waiters: Array<{
    match: (m: Msg) => boolean;
    resolve: (m: Msg) => void;
    timer: NodeJS.Timeout;
  }> = [];

  constructor(url: string) {
    this.ws = new WebSocket(url);
    this.ws.on('message', (data) => {
      const msg = JSON.parse(data.toString()) as Msg;
      const i = this.waiters.findIndex((w) => w.match(msg));
      if (i >= 0) {
        const [w] = this.waiters.splice(i, 1);
        clearTimeout(w.timer);
        w.resolve(msg);
      } else {
        this.queue.push(msg);
      }
    });
  }

  open(): Promise<void> {
    if (this.ws.readyState === WebSocket.OPEN) return Promise.resolve();
    return new Promise((resolve, reject) => {
      this.ws.once('open', () => resolve());
      this.ws.once('error', reject);
    });
  }

  send(obj: Record<string, unknown>): void {
    this.ws.send(JSON.stringify(obj));
  }

  waitFor(match: (m: Msg) => boolean, timeoutMs = 4000): Promise<Msg> {
    const i = this.queue.findIndex(match);
    if (i >= 0) return Promise.resolve(this.queue.splice(i, 1)[0]);
    return new Promise((resolve, reject) => {
      const timer = setTimeout(() => {
        const j = this.waiters.findIndex((w) => w.resolve === resolve);
        if (j >= 0) this.waiters.splice(j, 1);
        reject(
          new Error(
            `timeout waiting for message; queued=${JSON.stringify(this.queue)}`,
          ),
        );
      }, timeoutMs);
      this.waiters.push({ match, resolve, timer });
    });
  }

  waitType(type: string, timeoutMs?: number): Promise<Msg> {
    return this.waitFor((m) => m.type === type, timeoutMs);
  }

  close(): Promise<void> {
    if (this.ws.readyState === WebSocket.CLOSED) return Promise.resolve();
    return new Promise((resolve) => {
      this.ws.once('close', () => resolve());
      this.ws.close();
    });
  }
}

async function connectAuthed(url: string, uid: string): Promise<TestClient> {
  const c = new TestClient(url);
  await c.open();
  await c.waitType('welcome');
  c.send({ type: 'auth', token: uid });
  const authed = await c.waitType('authed');
  assert.equal(authed.uid, uid);
  return c;
}

async function startGame(
  url: string,
  redUid: string,
  blackUid: string,
): Promise<{ red: TestClient; black: TestClient; roomId: string }> {
  const red = await connectAuthed(url, redUid);
  const black = await connectAuthed(url, blackUid);
  red.send({ type: 'create-room' });
  const created = await red.waitType('room-created');
  const roomId = created.roomId as string;
  black.send({ type: 'join-room', roomId });
  const redStart = await red.waitType('game-start');
  const blackStart = await black.waitType('game-start');
  assert.equal(redStart.yourColor, 'red');
  assert.equal(blackStart.yourColor, 'black');
  return { red, black, roomId };
}

// ── D5a: both drop, both reconnect within grace ──────────────────────────
// Regression for the single-slot disconnect marker: the second drop used to
// OVERWRITE the first player's grace entry, so the first player got
// 'not-disconnected-player' on reconnect and could never resume.

test('double-disconnect: both players can reconnect within grace', async () => {
  const { server, url } = await startTestServer();
  try {
    const { red, black, roomId } = await startGame(url, 'mara', 'nico');

    // Red drops first (their grace entry must survive black's drop)…
    await red.close();
    await black.waitType('peer-disconnected');
    // …then black drops too.
    await black.close();

    // Red reconnects → snapshot + a peerInGrace marker for black.
    const red2 = await connectAuthed(url, 'mara');
    red2.send({ type: 'reconnect-room', roomId });
    const redSnap = await red2.waitType('reconnected');
    assert.equal(redSnap.yourColor, 'red');
    const peerInGrace = redSnap.peerInGrace as { uid: string; remainingMs: number };
    assert.equal(peerInGrace.uid, 'nico');
    assert.ok(peerInGrace.remainingMs > 0);

    // Black reconnects too → snapshot, and red sees peer-reconnected.
    const black2 = await connectAuthed(url, 'nico');
    black2.send({ type: 'reconnect-room', roomId });
    const blackSnap = await black2.waitType('reconnected');
    assert.equal(blackSnap.yourColor, 'black');
    assert.equal(blackSnap.peerInGrace, null);
    const peerBack = await red2.waitType('peer-reconnected');
    assert.equal(peerBack.uid, 'nico');

    // The game is still alive: finish it cleanly.
    red2.send({ type: 'resign' });
    await red2.waitType('game-ended');
    await black2.waitType('game-ended');
    await Promise.all([red2.close(), black2.close()]);
  } finally {
    await server.close();
  }
});

// ── D5b: both drop, nobody returns → first dropper forfeits on expiry ────

test('double-disconnect: grace expiry forfeits the first player to drop', async () => {
  const { server, url } = await startTestServer();
  try {
    const { red, black, roomId } = await startGame(url, 'olga', 'pete');

    // A spectator stays connected to observe the outcome.
    const watcher = await connectAuthed(url, 'quinn');
    watcher.send({ type: 'spectate-room', roomId });
    await watcher.waitType('spectate-started');

    // Red drops first, then black — both are now in grace.
    await red.close();
    await watcher.waitType('peer-disconnected');
    await black.close();
    await watcher.waitType('peer-disconnected');

    // Red's grace expires first → red forfeits, black wins by disconnect.
    const ended = await watcher.waitType('game-ended', 5000);
    assert.equal(ended.result, 'black-win');
    assert.equal(ended.reason, 'disconnect');

    await watcher.close();
  } finally {
    await server.close();
  }
});
