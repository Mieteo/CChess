// Waiting-room TTL: a lobby-created room nobody joins is cancelled.
//
// Runs in its own process (node:test spawns one per file) with a SHORT TTL
// via CCHESS_WAITING_ROOM_TTL_MS. Both env vars must be set BEFORE server.ts
// is imported — hence the dynamic import inside startTestServer.
process.env.CCHESS_NO_LISTEN = '1';
process.env.CCHESS_WAITING_ROOM_TTL_MS = '400';

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
    reject: (e: Error) => void;
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

  waitFor(match: (m: Msg) => boolean, timeoutMs = 3000): Promise<Msg> {
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
      this.waiters.push({ match, resolve, reject, timer });
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

test('a waiting room nobody joins expires and its id becomes invalid', async () => {
  const { server, url } = await startTestServer();
  try {
    const creator = await connectAuthed(url, 'tina');
    creator.send({ type: 'create-room' });
    const created = await creator.waitType('room-created');
    const roomId = created.roomId as string;
    assert.ok((created.waitingTtlMs as number) > 0);

    // TTL (400ms) fires → the creator is told and the room is gone.
    const expired = await creator.waitType('room-expired', 2000);
    assert.equal(expired.roomId, roomId);

    const joiner = await connectAuthed(url, 'uri');
    joiner.send({ type: 'join-room', roomId });
    const err = await joiner.waitType('error');
    assert.equal(err.code, 'room-not-found');

    await Promise.all([creator.close(), joiner.close()]);
  } finally {
    await server.close();
  }
});

test('joining before the TTL cancels the expiry and the game starts', async () => {
  const { server, url } = await startTestServer();
  try {
    const red = await connectAuthed(url, 'vu');
    const black = await connectAuthed(url, 'wes');
    red.send({ type: 'create-room' });
    const created = await red.waitType('room-created');
    black.send({ type: 'join-room', roomId: created.roomId as string });
    await red.waitType('game-start');
    await black.waitType('game-start');

    // Past the 400ms TTL: no room-expired may arrive — the game is live.
    await assert.rejects(
      red.waitType('room-expired', 700),
      /timeout/,
      'room-expired must not fire once the game started',
    );

    red.send({ type: 'resign' });
    await red.waitType('game-ended');
    await Promise.all([red.close(), black.close()]);
  } finally {
    await server.close();
  }
});
