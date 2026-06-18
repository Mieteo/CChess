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
type PersistFn = NonNullable<
  Parameters<typeof import('./server').createCChessServer>[0]
>['persist'];

async function startTestServer(
  opts: { persist?: PersistFn } = {},
): Promise<{ server: CChessServer; url: string }> {
  const { createCChessServer } = await import('./server');
  const server = createCChessServer({
    authenticate: async (token: string) => ({ uid: token }),
    persist: opts.persist ?? (async () => null),
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

test('R9: leave-room after game end broadcasts peer-left and rematch fails fast', async () => {
  const { server, url } = await startTestServer();
  try {
    const { red, black } = await startGame(url, 'rita', 'sam');
    red.send({ type: 'resign' });
    await red.waitType('game-ended');
    await black.waitType('game-ended');

    // Rita exits the result screen ("Về Đối Đầu") → explicit leave-room.
    red.send({ type: 'leave-room' });
    await red.waitType('left-room');
    // Sam is told IMMEDIATELY — this is what drives the R9 dialog update.
    const left = await black.waitType('peer-left');
    assert.equal(left.uid, 'rita');

    // Any rematch offer now fails fast with no-opponent (no 10s heartbeat wait).
    black.send({ type: 'rematch-offer' });
    const err = await black.waitType('error');
    assert.equal(err.code, 'no-opponent');

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

// ── G3 lifecycle: resign result/reason + idempotency ─────────────────────

test('G3: resign ends the game with reason=resign and the opponent winning', async () => {
  const { server, url } = await startTestServer();
  try {
    const { red, black } = await startGame(url, 'gina', 'hugo');

    // Red resigns → both sides see the same result: black wins by resignation.
    red.send({ type: 'resign' });
    const redEnd = await red.waitType('game-ended');
    const blackEnd = await black.waitType('game-ended');

    assert.equal(redEnd.reason, 'resign');
    assert.equal(redEnd.result, 'black-win', 'the resigner (red) loses');
    assert.equal(blackEnd.reason, 'resign');
    assert.equal(blackEnd.result, 'black-win');

    await Promise.all([red.close(), black.close()]);
  } finally {
    await server.close();
  }
});

test('resign is idempotent: a second resign does not emit a second game-ended', async () => {
  const { server, url } = await startTestServer();
  try {
    const { red, black } = await startGame(url, 'ivy', 'jack');

    red.send({ type: 'resign' });
    await red.waitType('game-ended');
    await black.waitType('game-ended');

    // Resign again on the already-finished game. endMatch() must guard the
    // playing→finished transition, so NO new game-ended should arrive.
    red.send({ type: 'resign' });
    await assert.rejects(
      red.waitFor((m) => m.type === 'game-ended', 400),
      /timeout/,
      'a duplicate game-ended would be a double-persist / double-ELO bug',
    );

    await Promise.all([red.close(), black.close()]);
  } finally {
    await server.close();
  }
});

// ── P-C1: ELO deltas from persist are wired into game-ended (M5/G4/R11) ───

test('P-C1: injected persist ELO is mapped into game-ended for both sides', async () => {
  // Fake persist returns a known EloUpdate so we assert the server's mapping
  // PersistResult.elo → game-ended.elo (the shape the Flutter dialog reads)
  // WITHOUT needing Firebase. Red won by resignation below, so red gains.
  const fakePersist: PersistFn = async () => ({
    gameId: 'test-game',
    elo: {
      redOld: 1000,
      redNew: 1016,
      redDelta: 16,
      blackOld: 1000,
      blackNew: 984,
      blackDelta: -16,
    },
  });

  const { server, url } = await startTestServer({ persist: fakePersist });
  try {
    const { red, black } = await startGame(url, 'kara', 'liam');

    // Black resigns → red wins, matching the +16/-16 fake above.
    black.send({ type: 'resign' });
    const end = await red.waitType('game-ended');

    assert.equal(end.result, 'red-win');
    assert.deepEqual(end.elo, {
      red: { old: 1000, new: 1016, delta: 16 },
      black: { old: 1000, new: 984, delta: -16 },
    });

    await Promise.all([red.close(), black.close()]);
  } finally {
    await server.close();
  }
});

test('game-ended carries elo:null when persistence yields nothing', async () => {
  // Default persist returns null (Firebase unavailable in tests). The game
  // must still end cleanly — just without ELO numbers.
  const { server, url } = await startTestServer();
  try {
    const { red, black } = await startGame(url, 'mia', 'noah');
    red.send({ type: 'resign' });
    const end = await red.waitType('game-ended');
    assert.equal(end.elo, null);
    await Promise.all([red.close(), black.close()]);
  } finally {
    await server.close();
  }
});

// ── M4: per-room clock chosen at create-room reaches both players ─────────

test('M4: the creator\'s clock choice initialises both sides equally', async () => {
  const { server, url } = await startTestServer();
  try {
    const FIVE_MIN = 5 * 60_000;
    const red = await connectAuthed(url, 'olive');
    const black = await connectAuthed(url, 'pete');

    red.send({ type: 'create-room', clockMs: FIVE_MIN });
    const roomId = (await red.waitType('room-created')).roomId as string;
    black.send({ type: 'join-room', roomId });

    const redStart = await red.waitType('game-start');
    const blackStart = await black.waitType('game-start');

    // Both clocks start full at the chosen budget; turn is red's.
    for (const start of [redStart, blackStart]) {
      const clock = start.clock as { red: number; black: number; currentTurn: string };
      assert.equal(clock.red, FIVE_MIN, 'red clock = chosen budget');
      assert.equal(clock.black, FIVE_MIN, 'black clock = chosen budget');
      assert.equal(clock.currentTurn, 'red');
    }

    red.send({ type: 'resign' });
    await red.waitType('game-ended');
    await Promise.all([red.close(), black.close()]);
  } finally {
    await server.close();
  }
});

// ── A1: spectator chat + chat history in snapshots (C5/C6) ────────────────

test('A1/C5: a spectator gets chat history on join and can chat to players', async () => {
  const { server, url } = await startTestServer();
  try {
    const { red, black, roomId } = await startGame(url, 'ivy', 'jack');

    // A player chats BEFORE anyone is watching → it lands in room history.
    red.send({ type: 'chat-message', text: 'gg hf' });
    await red.waitType('chat-message');
    await black.waitType('chat-message');

    // A watcher joins and is handed the existing history in spectate-started.
    const watcher = await connectAuthed(url, 'mona');
    watcher.send({ type: 'spectate-room', roomId });
    const started = await watcher.waitType('spectate-started');
    const history = started.chat as Array<{ from: string; text: string }>;
    assert.equal(history.length, 1);
    assert.equal(history[0].from, 'ivy');
    assert.equal(history[0].text, 'gg hf');

    // The watcher chats → BOTH players AND the watcher receive it.
    watcher.send({ type: 'chat-message', text: 'nice game' });
    for (const c of [red, black, watcher]) {
      const m = await c.waitType('chat-message');
      assert.equal(m.text, 'nice game');
      assert.equal(m.from, 'mona', 'chat is attributed to the spectator');
    }

    red.send({ type: 'resign' });
    await red.waitType('game-ended');
    await Promise.all([red.close(), black.close(), watcher.close()]);
  } finally {
    await server.close();
  }
});

test('A1/C6: the reconnect snapshot restores chat history in order', async () => {
  const { server, url } = await startTestServer();
  try {
    const { red, black, roomId } = await startGame(url, 'kim', 'leo');

    // Two messages from distinct uids (distinct uids dodge the rate limit).
    red.send({ type: 'chat-message', text: 'hello' });
    await red.waitType('chat-message');
    await black.waitType('chat-message');
    black.send({ type: 'chat-message', text: 'hi back' });
    await black.waitType('chat-message');
    await red.waitType('chat-message');

    // Red drops and reconnects within grace → snapshot carries the history.
    await red.close();
    await black.waitType('peer-disconnected');
    const red2 = await connectAuthed(url, 'kim');
    red2.send({ type: 'reconnect-room', roomId });
    const snap = await red2.waitType('reconnected');
    const chat = snap.chat as Array<{ from: string; text: string }>;
    assert.deepEqual(
      chat.map((c) => [c.from, c.text]),
      [
        ['kim', 'hello'],
        ['leo', 'hi back'],
      ],
    );

    red2.send({ type: 'resign' });
    await red2.waitType('game-ended');
    await Promise.all([red2.close(), black.close()]);
  } finally {
    await server.close();
  }
});
