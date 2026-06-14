// D1 fix: application-level liveness heartbeat.
//
// Clients send {type:'ping'} every ~5s; the server replies {type:'pong'} and
// terminates any socket it hasn't heard from for LIVENESS_TIMEOUT_MS. Unlike
// WS control-frame ping/pong (which the `ws` client auto-answers, and which a
// proxy can mask), app-level silence reliably detects a half-open connection —
// so a peer learns about a wifi drop in seconds, not minutes.
//
// Short windows via env, set BEFORE server.ts is imported (dynamic import in
// startTestServer). HEARTBEAT_INTERVAL is the sweep granularity.
process.env.CCHESS_NO_LISTEN = '1';
process.env.CCHESS_HEARTBEAT_INTERVAL_MS = '150';
process.env.CCHESS_LIVENESS_TIMEOUT_MS = '400';

import assert from 'node:assert/strict';
import { test } from 'node:test';
import type { AddressInfo } from 'node:net';
import { WebSocket } from 'ws';

import type { CChessServer } from './server';
import { PieceColor, uciOfMove, XiangqiGame } from './engine';

interface Msg {
  type: string;
  [k: string]: unknown;
}

/// First legal move for a colour from the initial position (UCI string).
function firstLegalUciFor(color: PieceColor): string {
  const game = XiangqiGame.initial();
  for (const [pos, piece] of game.board.occupied()) {
    if (piece.color !== color) continue;
    const moves = game.getValidMoves(pos);
    if (moves.length > 0) return uciOfMove(pos, moves[0]);
  }
  throw new Error(`no legal move for ${color}`);
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
  private keepalive?: NodeJS.Timeout;

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

  /// Simulate a real client's heartbeat so the server keeps this socket alive.
  startPinging(everyMs = 100): void {
    this.keepalive = setInterval(() => {
      if (this.ws.readyState === WebSocket.OPEN) this.send({ type: 'ping' });
    }, everyMs);
  }

  stopPinging(): void {
    if (this.keepalive) clearInterval(this.keepalive);
    this.keepalive = undefined;
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
    this.stopPinging();
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

test('app-level ping is answered with pong and keeps the socket alive', async () => {
  const { server, url } = await startTestServer();
  try {
    const c = await connectAuthed(url, 'pia');
    c.send({ type: 'ping' });
    const pong = await c.waitType('pong');
    assert.equal(typeof pong.ts, 'number');

    // Keep pinging across more than one LIVENESS_TIMEOUT_MS (400ms) window:
    // the liveness sweep must NOT terminate a socket that keeps talking.
    c.startPinging(100);
    await new Promise((r) => setTimeout(r, 900));
    assert.equal(c.ws.readyState, WebSocket.OPEN, 'pinging socket stays open');

    await c.close();
  } finally {
    await server.close();
  }
});

test('a player who goes app-level silent is dropped fast → peer-disconnected', async () => {
  const { server, url } = await startTestServer();
  try {
    const red = await connectAuthed(url, 'rui');
    const black = await connectAuthed(url, 'sam');
    red.send({ type: 'create-room' });
    const created = await red.waitType('room-created');
    black.send({ type: 'join-room', roomId: created.roomId as string });
    await red.waitType('game-start');
    await black.waitType('game-start');

    // black behaves like a real client (keeps pinging); red goes silent. The
    // `ws` runtime still auto-answers WS control-frame pings for red, so ONLY
    // the app-level liveness check can notice red is gone.
    black.startPinging(100);

    const started = Date.now();
    const peerGone = await black.waitType('peer-disconnected', 2500);
    const elapsed = Date.now() - started;
    assert.equal(peerGone.uid, 'rui');
    // Detection must be fast — far under the old multi-minute TCP timeout.
    assert.ok(elapsed < 2000, `peer-disconnected took ${elapsed}ms (want < 2000)`);

    await Promise.all([red.close(), black.close()]);
  } finally {
    await server.close();
  }
});

// D2 regression: a player who drops mid-game and reconnects must get the FULL
// move list back, so the client replays to the live position (not the start).
test('reconnect after a liveness drop replays the moves played so far', async () => {
  const { server, url } = await startTestServer();
  try {
    const red = await connectAuthed(url, 'rod');
    const black = await connectAuthed(url, 'sia');
    red.send({ type: 'create-room' });
    const created = await red.waitType('room-created');
    const roomId = created.roomId as string;
    black.send({ type: 'join-room', roomId });
    await red.waitType('game-start');
    await black.waitType('game-start');

    // Red plays one legal move → server records it in movesUci.
    const uci = firstLegalUciFor(PieceColor.Red);
    red.send({ type: 'move', uci });
    await red.waitType('move-ack');

    // black stays alive; red goes app-level silent → liveness drops red.
    black.startPinging(100);
    await black.waitType('peer-disconnected', 2500);

    // Red reconnects → snapshot MUST still contain the move (board not reset).
    const red2 = await connectAuthed(url, 'rod');
    red2.send({ type: 'reconnect-room', roomId });
    const snap = await red2.waitType('reconnected');
    assert.deepEqual(
      snap.moves,
      [uci],
      'reconnect snapshot must replay the played move, not reset to the start',
    );

    await Promise.all([black.close(), red2.close()]);
  } finally {
    await server.close();
  }
});
