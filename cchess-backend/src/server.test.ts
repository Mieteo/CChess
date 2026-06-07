// T3 + reconnect + chat: integration tests that drive the real WebSocket
// protocol end-to-end. Unlike match.test.ts (which unit-tests the pure
// match/room helpers), this spins up an actual CChess server on an ephemeral
// port and connects real `ws` clients, so it exercises the server.ts message
// dispatch + broadcast wiring.
//
// Firebase is never touched: createCChessServer is built with a stub
// `authenticate` (the token string IS the uid) and a no-op `persist`.
//
// CCHESS_NO_LISTEN must be set BEFORE importing server.ts so the production
// entry point (initFirebaseAdmin + listen on PORT) is skipped on import.
process.env.CCHESS_NO_LISTEN = '1';

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

/// Start a fully-wired server on an ephemeral port with stubbed auth/persist.
/// server.ts is imported here (not at module top) so the CCHESS_NO_LISTEN guard
/// is already set — otherwise importing it would init Firebase + bind PORT.
/// (Dynamic import inside an async fn also sidesteps the CJS no-top-level-await
/// limitation of the tsx test transform.)
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

/// A WebSocket client that buffers incoming messages so a test can await the
/// next message matching a predicate regardless of arrival order.
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

/// Create + join a room and run it to 'playing'. First client = red.
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

/// First legal move for `color` from the initial position, as a UCI string.
function firstLegalUciFor(color: PieceColor): string {
  const game = XiangqiGame.initial();
  for (const [pos, piece] of game.board.occupied()) {
    if (piece.color !== color) continue;
    const moves = game.getValidMoves(pos);
    if (moves.length > 0) return uciOfMove(pos, moves[0]);
  }
  throw new Error(`no legal move for ${color}`);
}

// ── T3: rematch handshake over real WebSockets ───────────────────────────

test('T3: both players offer rematch → game-start{rematch:true} with swapped colors', async () => {
  const { server, url } = await startTestServer();
  try {
    const { red, black, roomId } = await startGame(url, 'alice', 'bob');

    // Finish the game so a rematch offer is allowed.
    red.send({ type: 'resign' });
    await red.waitType('game-ended');
    await black.waitType('game-ended');

    // Alice offers; Bob is notified and Alice sees her own pending state.
    red.send({ type: 'rematch-offer' });
    await red.waitType('rematch-pending');
    const offered = await black.waitType('rematch-offered');
    assert.equal(offered.from, 'alice');

    // Bob offers too → both offered → fresh game with swapped colors.
    black.send({ type: 'rematch-offer' });
    const redNew = await red.waitFor(
      (m) => m.type === 'game-start' && m.rematch === true,
    );
    const blackNew = await black.waitFor(
      (m) => m.type === 'game-start' && m.rematch === true,
    );
    assert.equal(redNew.roomId, roomId, 'rematch reuses the same room');
    assert.equal(redNew.yourColor, 'black', 'alice (was red) now plays black');
    assert.equal(blackNew.yourColor, 'red', 'bob (was black) now plays red');

    // Clean up: finish the rematch so no clock ticker lingers.
    red.send({ type: 'resign' });
    await red.waitType('game-ended');
    await Promise.all([red.close(), black.close()]);
  } finally {
    await server.close();
  }
});

test('T3: rematch-decline notifies the offerer and does not start a game', async () => {
  const { server, url } = await startTestServer();
  try {
    const { red, black } = await startGame(url, 'carol', 'dave');
    red.send({ type: 'resign' });
    await red.waitType('game-ended');
    await black.waitType('game-ended');

    red.send({ type: 'rematch-offer' });
    await red.waitType('rematch-pending');
    await black.waitType('rematch-offered');

    black.send({ type: 'rematch-decline' });
    const declined = await red.waitType('rematch-declined');
    assert.equal(declined.from, 'dave');

    await Promise.all([red.close(), black.close()]);
  } finally {
    await server.close();
  }
});

test('T3: rematch-offer is rejected while the game is still playing', async () => {
  const { server, url } = await startTestServer();
  try {
    const { red, black } = await startGame(url, 'erin', 'frank');
    red.send({ type: 'rematch-offer' });
    const err = await red.waitType('error');
    assert.equal(err.code, 'not-finished');

    red.send({ type: 'resign' });
    await red.waitType('game-ended');
    await Promise.all([red.close(), black.close()]);
  } finally {
    await server.close();
  }
});

// ── Reconnect: snapshot restore within the grace window ──────────────────

test('reconnect-room restores a mid-game snapshot after a disconnect', async () => {
  const { server, url } = await startTestServer();
  try {
    const { red, black, roomId } = await startGame(url, 'gina', 'hank');

    // Red plays one legal move so the snapshot has something to restore.
    const uci = firstLegalUciFor(PieceColor.Red);
    red.send({ type: 'move', uci });
    await red.waitType('move-ack');
    await black.waitType('opponent-move');

    // Red drops; the opponent sees the grace banner event.
    await red.close();
    const dc = await black.waitType('peer-disconnected');
    assert.equal(dc.uid, 'gina');
    assert.ok((dc.graceMs as number) > 0);

    // Red reconnects within grace → gets the full snapshot back.
    const red2 = await connectAuthed(url, 'gina');
    red2.send({ type: 'reconnect-room', roomId });
    const snap = await red2.waitType('reconnected');
    assert.equal(snap.yourColor, 'red');
    assert.deepEqual(snap.moves, [uci]);
    assert.equal(snap.currentTurn, 'black');
    const peerBack = await black.waitType('peer-reconnected');
    assert.equal(peerBack.uid, 'gina');

    // Clean up.
    red2.send({ type: 'resign' });
    await red2.waitType('game-ended');
    await Promise.all([red2.close(), black.close()]);
  } finally {
    await server.close();
  }
});

// ── Chat: broadcast + rate limit + length cap + finished-game block ──────

test('chat-message broadcasts to both players with sender uid', async () => {
  const { server, url } = await startTestServer();
  try {
    const { red, black } = await startGame(url, 'ivy', 'jack');
    red.send({ type: 'chat-message', text: 'gg hf' });
    const onRed = await red.waitType('chat-message');
    const onBlack = await black.waitType('chat-message');
    assert.equal(onRed.text, 'gg hf');
    assert.equal(onRed.from, 'ivy');
    assert.equal(onBlack.text, 'gg hf');
    assert.equal(onBlack.from, 'ivy');

    red.send({ type: 'resign' });
    await red.waitType('game-ended');
    await Promise.all([red.close(), black.close()]);
  } finally {
    await server.close();
  }
});

test('chat enforces rate limit, length cap, and finished-game block', async () => {
  const { server, url } = await startTestServer();
  try {
    const { red, black } = await startGame(url, 'kim', 'leo');

    // First message is fine.
    red.send({ type: 'chat-message', text: 'hi' });
    await red.waitType('chat-message');
    // Immediate second message from the same uid → rate limited.
    red.send({ type: 'chat-message', text: 'spam' });
    const rl = await red.waitType('error');
    assert.equal(rl.code, 'chat-rate-limited');

    // Over the 120-char cap → invalid-chat (black has its own rate window).
    black.send({ type: 'chat-message', text: 'x'.repeat(121) });
    const bad = await black.waitType('error');
    assert.equal(bad.code, 'invalid-chat');

    // After the game ends, chat is blocked.
    red.send({ type: 'resign' });
    await red.waitType('game-ended');
    await black.waitType('game-ended');
    black.send({ type: 'chat-message', text: 'later' });
    const np = await black.waitType('error');
    assert.equal(np.code, 'not-playing');

    await Promise.all([red.close(), black.close()]);
  } finally {
    await server.close();
  }
});
