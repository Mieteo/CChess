import { createServer, IncomingMessage } from 'http';
import { WebSocketServer, WebSocket } from 'ws';
import { initFirebaseAdmin, verifyIdToken, type VerifiedToken } from './auth';
import {
  attachReconnectingSocket,
  activeRooms,
  clearDisconnectGrace,
  createRoom,
  getRoomById,
  isSpectator,
  joinRoom,
  leaveRoom,
  membersOf,
  roomOf,
  spectateRoom,
  type EndReason,
  type GameResult,
  type Room,
} from './rooms';
import {
  applyMove,
  clockSnapshot,
  colorOfSocket,
  endMatch,
  isTimedOut,
  opponentOf,
  RECONNECT_GRACE_MS,
  startMatch,
  startRematch,
} from './match';
import { persistGame, type PersistResult } from './persistence';
import {
  dequeue as mmDequeue,
  enqueue as mmEnqueue,
  tryMatch as mmTryMatch,
} from './matchmaking';

// Step 2-3 from 08_HUONG_DAN_BACKEND_WEBSOCKET.md.
//
// Protocol summary:
//   ← welcome
//   → auth {token}
//   ← authed {uid, email, anonymous} | error {code}
//   → create-room
//   ← room-created {roomId}
//   → join-room {roomId}
//   ← room-joined {roomId, members:[uid...]}
//   ← peer-joined {uid}                            // to existing peer
//   → broadcast {payload}
//   ← peer-message {from, payload, ts}             // to other peer
//   → leave-room
//   ← left-room                                    // to leaver
//   ← peer-left {uid}                              // to remaining peer

const PORT = Number(process.env.PORT ?? 8080);
const AUTH_TIMEOUT_MS = 10_000;

// Step 6 disconnect detection: ping every 5s, terminate if no pong by next tick.
// Catches half-open TCP (mobile app killed/backgrounded without sending FIN).
// 5s = detection within 5-10s. Production may want 10-15s for less ping noise.
const HEARTBEAT_INTERVAL_MS = 5_000;

// Xiangqi UCI: 9 cols (a-i) × 10 rows (0-9). Format check only — Step 5 will
// add legality (turn, piece existence, rule compliance).
const UCI_REGEX = /^[a-i][0-9][a-i][0-9]$/;
const CHAT_MAX_CHARS = 120;
const CHAT_RATE_LIMIT_MS = 2_000;
const CHAT_HISTORY_LIMIT = 50;
const ACTIVE_ROOM_LIST_LIMIT = 30;

// A lobby-created room nobody joins is cancelled after this long, so stale
// room ids don't pile up and the creator isn't left waiting forever.
// Overridable via env so integration tests can use a short window.
const WAITING_ROOM_TTL_MS =
  Number(process.env.CCHESS_WAITING_ROOM_TTL_MS ?? '') || 60_000;

// A6 share link: room ids are 6 chars from an unambiguous alphabet.
const ROOM_ID_REGEX = /^[A-Z0-9]{6}$/;

/// Minimal HTML landing page for a shared room link (`/r/<ID>`). Opening the
/// link in a browser shows the room code + how to watch in the app; opening it
/// inside the app deep-links straight to spectate/join.
function roomLandingHtml(roomId: string, join: boolean): string {
  const title = join ? 'Lời mời vào phòng' : 'Lời mời xem ván';
  const action = join ? 'vào đấu' : 'xem ván';
  return `<!doctype html>
<html lang="vi">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>CChess — ${title} ${roomId}</title>
<style>
  :root { color-scheme: dark; }
  body { margin:0; font-family: system-ui, -apple-system, Segoe UI, Roboto, sans-serif;
    background:#1a120b; color:#f3e9d2; display:flex; min-height:100vh;
    align-items:center; justify-content:center; padding:24px; }
  .card { background:#241910; border:1px solid #4a3a28;
    border-radius:16px; padding:28px 24px; max-width:380px; width:100%; text-align:center;
    box-shadow:0 8px 32px rgba(0,0,0,.4); }
  h1 { font-size:20px; margin:0 0 4px; color:#e8b84b; }
  p { color:#c9b896; font-size:14px; line-height:1.5; }
  .code { font-size:40px; letter-spacing:8px; font-weight:700; color:#e8b84b;
    background:#1a120b; border:1px solid #4a3a28; border-radius:12px;
    padding:14px 0; margin:16px 0; user-select:all; }
  button { background:#e8b84b; color:#1a120b; border:0; border-radius:10px;
    padding:12px 20px; font-size:15px; font-weight:700; cursor:pointer; width:100%; }
  .hint { font-size:12px; color:#8c7d63; margin-top:18px; }
</style>
</head>
<body>
  <div class="card">
    <h1>CChess — Cờ Tướng Việt</h1>
    <p>${title}. Mở ứng dụng CChess để ${action} với mã phòng này:</p>
    <div class="code" id="code">${roomId}</div>
    <button onclick="navigator.clipboard&&navigator.clipboard.writeText('${roomId}').then(function(){this.textContent='Đã sao chép!'}.bind(this))">Sao chép mã phòng</button>
    <p class="hint">Trong app: Đối Đầu → Xếp Hạng Online → nhập mã phòng (hoặc quét QR).</p>
  </div>
</body>
</html>`;
}

function send(socket: WebSocket, payload: Record<string, unknown>) {
  if (socket.readyState === WebSocket.OPEN) {
    socket.send(JSON.stringify(payload));
  }
}

function socketsOf(room: Room): WebSocket[] {
  return [...room.members, ...room.spectators];
}

function broadcastToRoom(
  room: Room,
  except: WebSocket | null,
  payload: Record<string, unknown>,
) {
  for (const s of socketsOf(room)) {
    if (s === except) continue;
    send(s, payload);
  }
}

/// Send a payload to ALL members in the room.
function broadcastAll(room: Room, payload: Record<string, unknown>) {
  for (const s of socketsOf(room)) send(s, payload);
}

function normalizeChatText(raw: unknown): string | null {
  if (typeof raw !== 'string') return null;
  const text = raw.replace(/\s+/g, ' ').trim();
  if (text.length === 0 || text.length > CHAT_MAX_CHARS) return null;
  return text;
}

function pushChatMessage(room: Room, uid: string, text: string) {
  const ts = Date.now();
  const history = room.chatMessages ?? [];
  const message = {
    id: `${room.id}_${ts}_${history.length}`,
    from: uid,
    text,
    ts,
  };
  history.push(message);
  if (history.length > CHAT_HISTORY_LIMIT) {
    history.splice(0, history.length - CHAT_HISTORY_LIMIT);
  }
  room.chatMessages = history;
  return message;
}

function activeRoomSummary(room: Room) {
  return {
    roomId: room.id,
    redUid: room.redUid,
    blackUid: room.blackUid,
    moveCount: room.movesUci?.length ?? room.moveCount,
    spectatorCount: room.spectators.size,
    startedAt: room.startedAt,
    currentTurn: room.currentTurn,
    clock: clockSnapshot(room),
  };
}

interface HeartbeatSocket extends WebSocket {
  isAlive?: boolean;
}

export interface CChessServer {
  httpServer: ReturnType<typeof createServer>;
  wss: WebSocketServer;
  /// Stop accepting connections, drop existing clients, clear timers. Resolves
  /// once the HTTP listener is fully closed. Used by tests + graceful shutdown.
  close: () => Promise<void>;
}

export interface CChessServerOptions {
  /// Verify a Firebase ID token. Defaults to the real Firebase Admin check.
  /// Tests inject a stub (e.g. treat the token string as the uid).
  authenticate?: (token: string) => Promise<VerifiedToken>;
  /// Persist a finished game + update ELO. Defaults to the real Firestore
  /// transaction. Tests inject a no-op so no Firebase is required.
  persist?: (room: Room) => Promise<PersistResult | null>;
}

/// Build a fully-wired CChess WebSocket server WITHOUT starting to listen.
/// The caller decides the port (`httpServer.listen(...)`). Auth + persistence
/// are injectable so the protocol can be integration-tested over real sockets
/// without Firebase. Production behaviour is unchanged: the defaults are the
/// real `verifyIdToken` + `persistGame`.
export function createCChessServer(options: CChessServerOptions = {}): CChessServer {
  const authenticate = options.authenticate ?? verifyIdToken;
  const persist = options.persist ?? persistGame;

  // socket -> uid (only after successful auth)
  const sessions = new Map<WebSocket, string>();

  const httpServer = createServer((req, res) => {
    const url = new URL(req.url ?? '/', 'http://localhost');
    const pathname = url.pathname;

    if (pathname === '/health') {
      res.writeHead(200, { 'Content-Type': 'text/plain' });
      res.end('ok');
      return;
    }

    // A6 share link landing page: /r/<ROOMID>?mode=join
    const roomMatch = pathname.match(/^\/r\/([^/]+)\/?$/);
    if (roomMatch) {
      const roomId = decodeURIComponent(roomMatch[1]).toUpperCase();
      if (!ROOM_ID_REGEX.test(roomId)) {
        res.writeHead(400, { 'Content-Type': 'text/plain; charset=utf-8' });
        res.end('Mã phòng không hợp lệ');
        return;
      }
      const join = url.searchParams.get('mode') === 'join';
      res.writeHead(200, { 'Content-Type': 'text/html; charset=utf-8' });
      res.end(roomLandingHtml(roomId, join));
      return;
    }

    res.writeHead(404);
    res.end();
  });

  const wss = new WebSocketServer({ server: httpServer });

  /// Step 6 + matchmaking shared: start the game once a room has 2 players.
  /// Sets status='playing', initializes engine + clocks, broadcasts per-socket
  /// game-start with yourColor field.
  function startGameForRoom(room: Room): void {
    if (room.waitingTimer) {
      clearTimeout(room.waitingTimer);
      room.waitingTimer = undefined;
    }
    room.status = 'playing';
    startMatch(room, (s) => sessions.get(s));
    startClockTicker(room);
    const baseStartEvent = {
      type: 'game-start',
      roomId: room.id,
      redUid: room.redUid,
      blackUid: room.blackUid,
      clock: clockSnapshot(room),
      startedAt: room.startedAt,
    };
    for (const s of room.members) {
      const yourColor = s === room.redSocket ? 'red' : 'black';
      send(s, { ...baseStartEvent, yourColor });
    }
    console.log(
      `[match] ${room.id} started: red=${room.redUid} black=${room.blackUid} clock=${room.clockMsByColor?.red ?? '?'}ms`,
    );
  }

  /// Sprint 12 rematch: restart the SAME room with swapped colors. Both player
  /// sockets must still be connected. Broadcasts a fresh per-socket game-start
  /// (with new yourColor) plus a generic update to any spectators.
  function startRematchForRoom(room: Room): void {
    if (!startRematch(room)) {
      // Couldn't rematch (a socket missing) — tell whoever is left.
      broadcastAll(room, { type: 'error', code: 'rematch-failed' });
      return;
    }
    startClockTicker(room);
    const baseStartEvent = {
      type: 'game-start',
      roomId: room.id,
      redUid: room.redUid,
      blackUid: room.blackUid,
      clock: clockSnapshot(room),
      startedAt: room.startedAt,
      rematch: true,
    };
    for (const s of room.members) {
      const yourColor = s === room.redSocket ? 'red' : 'black';
      send(s, { ...baseStartEvent, yourColor });
    }
    for (const s of room.spectators) {
      send(s, { ...baseStartEvent, yourColor: null });
    }
    console.log(
      `[rematch] ${room.id} restarted: red=${room.redUid} black=${room.blackUid}`,
    );
  }

  /// Step A3 matchmaking: when 2 sockets are paired, set up a room then call
  /// startGameForRoom. Sends explicit `match-found` to both first so they know
  /// matchmaking succeeded.
  function pairAndStartMatch(
    a: { socket: WebSocket; uid: string; clockMs?: number },
    b: { socket: WebSocket; uid: string; clockMs?: number },
  ): void {
    const clockMs = a.clockMs ?? b.clockMs;
    const room = createRoom(a.socket, { initialClockMs: clockMs });
    // Attach B as 2nd member. attachReconnectingSocket also registers B in
    // socketToRoom; the redSocket/blackSocket fields it sets are overwritten
    // by startMatch a moment later (based on members iteration order).
    attachReconnectingSocket(b.socket, room, b.uid);
    send(a.socket, { type: 'match-found', roomId: room.id, opponent: b.uid });
    send(b.socket, { type: 'match-found', roomId: room.id, opponent: a.uid });
    console.log(
      `[matchmaking] paired ${a.uid} ↔ ${b.uid} → room ${room.id}`,
    );
    startGameForRoom(room);
  }

  /// Step 6 ticker: check every 1s if current player has run out of time.
  function startClockTicker(room: Room) {
    if (room.clockTimer) clearInterval(room.clockTimer);
    room.clockTimer = setInterval(() => {
      if (room.status !== 'playing') {
        if (room.clockTimer) clearInterval(room.clockTimer);
        room.clockTimer = undefined;
        return;
      }
      if (isTimedOut(room)) {
        const loser = room.currentTurn;
        const winner: GameResult = loser === 'red' ? 'black-win' : 'red-win';
        finishGame(room, winner, 'timeout');
      }
    }, 1000);
  }

  /// End the game cleanly: stop ticker, mark room finished, persist + ELO,
  /// then broadcast game-ended (with ELO deltas included when available).
  function finishGame(room: Room, result: GameResult, reason: EndReason): void {
    endMatch(room, result, reason);

    // Run persistence + ELO update, then broadcast. Even if persistence fails,
    // we still broadcast (game IS ended) — just without ELO numbers.
    void (async () => {
      const persisted = await persist(room).catch((e) => {
        console.error('[persist] error:', e);
        return null;
      });
      const elo = persisted?.elo
        ? {
            red: {
              old: persisted.elo.redOld,
              new: persisted.elo.redNew,
              delta: persisted.elo.redDelta,
            },
            black: {
              old: persisted.elo.blackOld,
              new: persisted.elo.blackNew,
              delta: persisted.elo.blackDelta,
            },
          }
        : null;
      const payload = {
        type: 'game-ended',
        roomId: room.id,
        result,
        reason,
        moves: room.movesUci ?? [],
        startedAt: room.startedAt,
        endedAt: room.endedAt,
        durationMs:
          room.endedAt && room.startedAt ? room.endedAt - room.startedAt : null,
        clock: clockSnapshot(room),
        redUid: room.redUid,
        blackUid: room.blackUid,
        elo,
      };
      broadcastAll(room, payload);
      console.log(
        `[match] ${room.id} ended result=${result} reason=${reason} moves=${room.movesUci?.length ?? 0}${elo ? ` | elo red ${elo.red.old}→${elo.red.new} black ${elo.black.old}→${elo.black.new}` : ''}`,
      );
    })();
  }

  const heartbeatInterval = setInterval(() => {
    wss.clients.forEach((s) => {
      const sock = s as HeartbeatSocket;
      if (sock.isAlive === false) {
        console.log('[ws] heartbeat timeout → terminate');
        sock.terminate(); // fires 'close' event → finishGame path
        return;
      }
      sock.isAlive = false;
      try {
        sock.ping();
      } catch {
        // ignore — terminate will be called next tick
      }
    });
  }, HEARTBEAT_INTERVAL_MS);

  // Step A3 polish: re-check matchmaking queue every 5s so waiting players
  // get paired when their tolerance grows (no new enqueue needed).
  const matchmakingInterval = setInterval(() => {
    let pair = mmTryMatch();
    while (pair) {
      const [a, b] = pair;
      pairAndStartMatch(a, b);
      pair = mmTryMatch();
    }
  }, 5_000);

  wss.on('connection', (socket: WebSocket, request: IncomingMessage) => {
    const remote = request.socket.remoteAddress;
    console.log(`[ws] connected from ${remote}`);

    // Heartbeat: client must respond to ping within ~HEARTBEAT_INTERVAL_MS.
    const hbSock = socket as HeartbeatSocket;
    hbSock.isAlive = true;
    socket.on('pong', () => {
      hbSock.isAlive = true;
    });

    send(socket, {
      type: 'welcome',
      message: 'Send {"type":"auth","token":"<firebase id token>"} within 10s.',
      ts: Date.now(),
    });

    const authTimer = setTimeout(() => {
      if (!sessions.has(socket)) {
        console.log(`[ws] auth timeout for ${remote}`);
        send(socket, { type: 'error', code: 'auth-timeout' });
        socket.close(4001, 'auth timeout');
      }
    }, AUTH_TIMEOUT_MS);

    socket.on('message', async (data, isBinary) => {
      if (isBinary) {
        send(socket, { type: 'error', code: 'binary-not-supported' });
        return;
      }

      let msg: {
        type?: string;
        token?: string;
        roomId?: string;
        payload?: unknown;
        uci?: string;
        [k: string]: unknown;
      };
      try {
        msg = JSON.parse(data.toString());
      } catch {
        send(socket, { type: 'error', code: 'invalid-json' });
        return;
      }

      // ── Auth handshake ────────────────────────────────────────────────
      if (msg.type === 'auth') {
        if (typeof msg.token !== 'string' || msg.token.length === 0) {
          send(socket, { type: 'error', code: 'missing-token' });
          return;
        }
        try {
          const decoded = await authenticate(msg.token);
          sessions.set(socket, decoded.uid);
          clearTimeout(authTimer);
          send(socket, {
            type: 'authed',
            uid: decoded.uid,
            email: decoded.email ?? null,
            anonymous: decoded.firebase?.sign_in_provider === 'anonymous',
          });
          console.log(`[ws] authed uid=${decoded.uid} email=${decoded.email ?? '—'}`);
        } catch (e) {
          const message = e instanceof Error ? e.message : String(e);
          console.warn(`[ws] auth failed: ${message}`);
          send(socket, { type: 'error', code: 'invalid-token', message });
          socket.close(4002, 'invalid token');
        }
        return;
      }

      // ── Require auth for everything below ─────────────────────────────
      const uid = sessions.get(socket);
      if (!uid) {
        send(socket, { type: 'error', code: 'not-authed' });
        return;
      }

      // ── Room operations ───────────────────────────────────────────────
      // ── Step A3 matchmaking ──────────────────────────────────────────
      if (msg.type === 'find-match') {
        if (roomOf(socket)) {
          send(socket, { type: 'error', code: 'already-in-room' });
          return;
        }
        const rawClock = (msg as { clockMs?: number }).clockMs;
        const clockMs =
          typeof rawClock === 'number' && rawClock >= 60_000 && rawClock <= 3_600_000
            ? rawClock
            : undefined;
        // Fetch current ELO from Firestore so bucket matchmaking can pair fairly
        let elo = 1000;
        try {
          const { getFirestore } = await import('firebase-admin/firestore');
          const snap = await getFirestore().collection('users').doc(uid).get();
          const e = snap.data()?.eloChess as number | undefined;
          if (typeof e === 'number') elo = e;
        } catch (e) {
          console.warn(`[matchmaking] failed to fetch ELO for ${uid}, using default 1000:`, e);
        }
        const size = mmEnqueue(socket, uid, elo, clockMs);
        send(socket, { type: 'matching', queueSize: size, elo });
        console.log(`[matchmaking] ${uid} enqueued (queue size=${size}, elo=${elo})`);
        const pair = mmTryMatch();
        if (pair) {
          const [a, b] = pair;
          pairAndStartMatch(a, b);
        }
        return;
      }

      if (msg.type === 'cancel-matching') {
        const removed = mmDequeue(socket);
        send(socket, { type: 'matching-canceled', removed });
        console.log(`[matchmaking] ${uid} canceled (was queued=${removed})`);
        return;
      }

      if (msg.type === 'create-room') {
        if (roomOf(socket)) {
          send(socket, { type: 'error', code: 'already-in-room' });
          return;
        }
        // Step A5: optional initial clock from lobby (clamp to sane range)
        const rawClock = (msg as { clockMs?: number }).clockMs;
        const clockMs =
          typeof rawClock === 'number' && rawClock >= 60_000 && rawClock <= 3_600_000
            ? rawClock
            : undefined;
        const room = createRoom(socket, { initialClockMs: clockMs });
        // Waiting-room TTL: cancel the room if nobody joins in time.
        room.waitingTimer = setTimeout(() => {
          room.waitingTimer = undefined;
          if (room.status !== 'waiting') return;
          console.log(
            `[room] ${room.id} expired — no opponent joined within ${WAITING_ROOM_TTL_MS}ms`,
          );
          for (const s of [...room.members]) {
            send(s, { type: 'room-expired', roomId: room.id });
            leaveRoom(s); // last leaver deletes the room
          }
        }, WAITING_ROOM_TTL_MS);
        send(socket, {
          type: 'room-created',
          roomId: room.id,
          initialClockMs: room.initialClockMs,
          waitingTtlMs: WAITING_ROOM_TTL_MS,
        });
        console.log(
          `[room] ${room.id} created by ${uid} (clock=${clockMs ?? 'default'}ms)`,
        );
        return;
      }

      if (msg.type === 'list-active-rooms') {
        const allRooms = activeRooms().sort(
          (a, b) => (b.startedAt ?? b.createdAt) - (a.startedAt ?? a.createdAt),
        );
        const rooms = allRooms
          .slice(0, ACTIVE_ROOM_LIST_LIMIT)
          .map(activeRoomSummary);
        send(socket, {
          type: 'active-rooms',
          rooms,
          total: allRooms.length,
          limit: ACTIVE_ROOM_LIST_LIMIT,
          ts: Date.now(),
        });
        return;
      }

      // ── Step 8: reconnect to in-progress room ────────────────────────
      if (msg.type === 'reconnect-room') {
        const roomId =
          typeof msg.roomId === 'string' ? msg.roomId.toUpperCase() : '';
        if (!roomId) {
          send(socket, { type: 'error', code: 'missing-room-id' });
          return;
        }
        const room = getRoomById(roomId);
        if (!room) {
          send(socket, { type: 'error', code: 'room-not-found' });
          return;
        }
        if (room.status !== 'playing') {
          send(socket, { type: 'error', code: 'game-not-active' });
          return;
        }
        if (!uid || !room.disconnectGrace?.has(uid)) {
          send(socket, { type: 'error', code: 'not-disconnected-player' });
          return;
        }
        // Swap socket into room (replaces dead socket reference)
        attachReconnectingSocket(socket, room, uid);
        // Cancel this player's grace timer. The OTHER player may still be in
        // grace (double-disconnect) — leave their entry untouched.
        clearDisconnectGrace(room, uid);
        const peerGraceEntry = [...(room.disconnectGrace ?? new Map())][0] as
          | [string, { deadline: number }]
          | undefined;

        const yourColor = uid === room.redUid ? 'red' : 'black';
        send(socket, {
          type: 'reconnected',
          roomId: room.id,
          yourColor,
          redUid: room.redUid,
          blackUid: room.blackUid,
          moves: room.movesUci ?? [],
          chat: room.chatMessages ?? [],
          currentTurn: room.currentTurn,
          clock: clockSnapshot(room),
          startedAt: room.startedAt,
          // Double-disconnect: tell the reconnecting client when the peer is
          // ALSO in grace so it can show the countdown banner right away.
          peerInGrace: peerGraceEntry
            ? {
                uid: peerGraceEntry[0],
                remainingMs: Math.max(0, peerGraceEntry[1].deadline - Date.now()),
              }
            : null,
        });
        broadcastToRoom(room, socket, { type: 'peer-reconnected', uid });
        console.log(`[match] ${room.id} ${yourColor} (${uid}) reconnected`);
        return;
      }

      if (msg.type === 'spectate-room') {
        const roomId =
          typeof msg.roomId === 'string' ? msg.roomId.toUpperCase() : '';
        if (!roomId) {
          send(socket, { type: 'error', code: 'missing-room-id' });
          return;
        }
        const result = spectateRoom(socket, roomId);
        if (!result.ok) {
          send(socket, { type: 'error', code: result.code });
          return;
        }
        const room = result.room;
        send(socket, {
          type: 'spectate-started',
          roomId: room.id,
          redUid: room.redUid,
          blackUid: room.blackUid,
          moves: room.movesUci ?? [],
          chat: room.chatMessages ?? [],
          currentTurn: room.currentTurn,
          clock: clockSnapshot(room),
          startedAt: room.startedAt,
          spectatorCount: room.spectators.size,
        });
        broadcastToRoom(room, socket, {
          type: 'spectator-joined',
          uid,
          spectatorCount: room.spectators.size,
        });
        console.log(`[spectate] ${uid} watching ${room.id}`);
        return;
      }

      if (msg.type === 'stop-spectating') {
        const room = roomOf(socket);
        if (!room) {
          send(socket, { type: 'error', code: 'not-in-room' });
          return;
        }
        if (!isSpectator(room, socket)) {
          send(socket, { type: 'error', code: 'not-spectator' });
          return;
        }
        leaveRoom(socket);
        send(socket, { type: 'spectate-stopped', roomId: room.id });
        broadcastToRoom(room, socket, {
          type: 'spectator-left',
          uid,
          spectatorCount: room.spectators.size,
        });
        console.log(`[spectate] ${uid} stopped watching ${room.id}`);
        return;
      }

      if (msg.type === 'join-room') {
        const roomId = typeof msg.roomId === 'string' ? msg.roomId : '';
        if (!roomId) {
          send(socket, { type: 'error', code: 'missing-room-id' });
          return;
        }
        const result = joinRoom(socket, roomId.toUpperCase());
        if (!result.ok) {
          send(socket, { type: 'error', code: result.code });
          return;
        }
        const room = result.room;
        const members = membersOf(room, (s) => sessions.get(s));
        send(socket, {
          type: 'room-joined',
          roomId: room.id,
          members,
          status: room.status,
        });
        broadcastToRoom(room, socket, { type: 'peer-joined', uid });
        console.log(`[room] ${room.id} joined by ${uid} (${room.members.size}/2)`);

        // Step 6: when 2 players are in, start the match
        if (room.members.size === 2 && room.status === 'playing') {
          startGameForRoom(room);
        }
        return;
      }

      if (msg.type === 'leave-room') {
        const before = roomOf(socket);
        if (!before) {
          send(socket, { type: 'error', code: 'not-in-room' });
          return;
        }
        const wasSpectator = isSpectator(before, socket);
        // If game was playing, treat client-initiated leave as a disconnect:
        // ends the game with the OTHER side winning + persists + notifies peer.
        if (before.status === 'playing' && !wasSpectator) {
          const color = colorOfSocket(before, socket);
          if (color) {
            const winner: GameResult =
              opponentOf(color) === 'red' ? 'red-win' : 'black-win';
            finishGame(before, winner, 'disconnect');
          }
        }
        const room = leaveRoom(socket);
        // A leaver's pending rematch offer is void (R9 hygiene).
        if (uid) before.rematchOfferedBy?.delete(uid);
        send(socket, { type: 'left-room', roomId: before.id });
        if (room && !wasSpectator) {
          broadcastToRoom(room, socket, { type: 'peer-left', uid });
        }
        if (room && wasSpectator) {
          broadcastToRoom(room, socket, {
            type: 'spectator-left',
            uid,
            spectatorCount: room.spectators.size,
          });
        }
        console.log(`[room] ${before.id} left by ${uid}`);
        return;
      }

      if (msg.type === 'broadcast') {
        const room = roomOf(socket);
        if (!room) {
          send(socket, { type: 'error', code: 'not-in-room' });
          return;
        }
        broadcastToRoom(room, socket, {
          type: 'peer-message',
          from: uid,
          payload: msg.payload,
          ts: Date.now(),
        });
        return;
      }

      if (msg.type === 'chat-message') {
        const room = roomOf(socket);
        if (!room) {
          send(socket, { type: 'error', code: 'not-in-room' });
          return;
        }
        if (room.status === 'finished') {
          send(socket, { type: 'error', code: 'not-playing' });
          return;
        }
        const text = normalizeChatText(msg.text);
        if (!text) {
          send(socket, {
            type: 'error',
            code: 'invalid-chat',
            maxChars: CHAT_MAX_CHARS,
          });
          return;
        }
        const now = Date.now();
        const lastByUid = room.lastChatAtByUid ?? {};
        const last = lastByUid[uid] ?? 0;
        const retryMs = CHAT_RATE_LIMIT_MS - (now - last);
        if (retryMs > 0) {
          send(socket, {
            type: 'error',
            code: 'chat-rate-limited',
            retryMs,
          });
          return;
        }
        lastByUid[uid] = now;
        room.lastChatAtByUid = lastByUid;

        const chat = pushChatMessage(room, uid, text);
        broadcastAll(room, {
          type: 'chat-message',
          roomId: room.id,
          ...chat,
        });
        return;
      }

      // ── Sprint 12 rematch ─────────────────────────────────────────────
      if (msg.type === 'rematch-offer') {
        const room = roomOf(socket);
        if (!room) {
          send(socket, { type: 'error', code: 'not-in-room' });
          return;
        }
        if (room.status !== 'finished') {
          send(socket, { type: 'error', code: 'not-finished' });
          return;
        }
        const color = colorOfSocket(room, socket);
        if (!color) {
          send(socket, { type: 'error', code: 'not-player' });
          return;
        }
        if (room.members.size < 2) {
          send(socket, { type: 'error', code: 'no-opponent' });
          return;
        }
        room.rematchOfferedBy ??= new Set<string>();
        room.rematchOfferedBy.add(uid);
        // Notify the opponent that a rematch was offered.
        broadcastToRoom(room, socket, { type: 'rematch-offered', from: uid });
        send(socket, { type: 'rematch-pending' });
        console.log(`[rematch] ${room.id} offered by ${uid} (${room.rematchOfferedBy.size}/2)`);

        // If BOTH players have offered → start rematch.
        const bothOffered =
          room.redUid != null &&
          room.blackUid != null &&
          room.rematchOfferedBy.has(room.redUid) &&
          room.rematchOfferedBy.has(room.blackUid);
        if (bothOffered) {
          startRematchForRoom(room);
        }
        return;
      }

      if (msg.type === 'rematch-decline') {
        const room = roomOf(socket);
        if (!room) {
          send(socket, { type: 'error', code: 'not-in-room' });
          return;
        }
        room.rematchOfferedBy?.clear();
        broadcastToRoom(room, socket, { type: 'rematch-declined', from: uid });
        console.log(`[rematch] ${room.id} declined by ${uid}`);
        return;
      }

      // ── Step 4+6: move transport with turn + clock validation ─────────
      if (msg.type === 'move') {
        const room = roomOf(socket);
        if (!room) {
          send(socket, { type: 'error', code: 'not-in-room' });
          return;
        }
        if (room.members.size < 2) {
          send(socket, { type: 'error', code: 'no-opponent' });
          return;
        }
        const rawUci = typeof msg.uci === 'string' ? msg.uci.trim().toLowerCase() : '';
        if (!UCI_REGEX.test(rawUci)) {
          send(socket, { type: 'error', code: 'invalid-uci', uci: rawUci });
          return;
        }
        const result = applyMove(room, socket, rawUci);
        if (!result.ok) {
          if (result.code === 'time-out') {
            const winner: GameResult =
              room.currentTurn === 'red' ? 'black-win' : 'red-win';
            finishGame(room, winner, 'timeout');
          } else {
            send(socket, { type: 'error', code: result.code, uci: rawUci });
          }
          return;
        }
        const movePayload = {
          type: 'opponent-move',
          uci: rawUci,
          from: uid,
          color: result.color,
          moveNumber: result.moveNumber,
          clock: clockSnapshot(room),
          ts: Date.now(),
        };
        broadcastToRoom(room, socket, movePayload);
        send(socket, {
          type: 'move-ack',
          uci: rawUci,
          moveNumber: result.moveNumber,
          clock: clockSnapshot(room),
        });
        console.log(`[match] ${room.id} #${result.moveNumber} ${result.color} ${rawUci} (red=${room.clockMsByColor!.red}ms black=${room.clockMsByColor!.black}ms)`);

        // Step 5: auto-finish on checkmate / stalemate
        if (result.autoFinish) {
          finishGame(room, result.autoFinish.result, result.autoFinish.reason);
        }
        return;
      }

      // ── Step 6: resign ────────────────────────────────────────────────
      if (msg.type === 'resign') {
        const room = roomOf(socket);
        if (!room) {
          send(socket, { type: 'error', code: 'not-in-room' });
          return;
        }
        if (room.status !== 'playing') {
          send(socket, { type: 'error', code: 'not-playing' });
          return;
        }
        const color = colorOfSocket(room, socket);
        if (!color) {
          send(socket, { type: 'error', code: 'not-player' });
          return;
        }
        const winner: GameResult = opponentOf(color) === 'red' ? 'red-win' : 'black-win';
        finishGame(room, winner, 'resign');
        return;
      }

      // Unknown → echo with uid
      send(socket, { type: 'echo', uid, original: msg, ts: Date.now() });
    });

    socket.on('close', (code, reason) => {
      const uid = sessions.get(socket);
      const beforeRoom = roomOf(socket);
      const wasPlaying = beforeRoom?.status === 'playing';
      const wasSpectator = beforeRoom ? isSpectator(beforeRoom, socket) : false;

      // Step 8: enter reconnect grace instead of immediate finishGame.
      // If same uid reconnects via reconnect-room within RECONNECT_GRACE_MS,
      // the room resumes; otherwise the grace timer fires finishGame(disconnect).
      if (beforeRoom && wasPlaying && uid && !wasSpectator) {
        const color = colorOfSocket(beforeRoom, socket);
        if (color) {
          // Per-uid grace entries so a double-disconnect (both players drop)
          // keeps BOTH forfeit timers alive — the second drop must not
          // overwrite the first player's pending reconnect window.
          const grace = (beforeRoom.disconnectGrace ??= new Map());
          const prior = grace.get(uid);
          if (prior) clearTimeout(prior.timer);
          const timer = setTimeout(() => {
            const stillDisconnected = beforeRoom.disconnectGrace?.has(uid) ?? false;
            const stillPlaying = beforeRoom.status === 'playing';
            console.log(
              `[match] ${beforeRoom.id} grace timer fired for ${uid}: stillDisconnected=${stillDisconnected} stillPlaying=${stillPlaying} status=${beforeRoom.status}`,
            );
            beforeRoom.disconnectGrace?.delete(uid);
            if (stillDisconnected && stillPlaying) {
              const winner: GameResult =
                opponentOf(color) === 'red' ? 'red-win' : 'black-win';
              finishGame(beforeRoom, winner, 'disconnect');
            }
          }, RECONNECT_GRACE_MS);
          grace.set(uid, { timer, deadline: Date.now() + RECONNECT_GRACE_MS });
          broadcastToRoom(beforeRoom, socket, {
            type: 'peer-disconnected',
            uid,
            graceMs: RECONNECT_GRACE_MS,
          });
          console.log(
            `[match] ${beforeRoom.id} ${color} (${uid}) disconnected, grace ${RECONNECT_GRACE_MS}ms (inGrace=${grace.size})`,
          );
        }
      }

      // Remove socket from maps. Preserve room status when grace is in progress
      // so the reconnect-room handler + grace timer can still operate on a
      // 'playing' room.
      const room = leaveRoom(socket, { preserveStatus: wasPlaying });
      if (beforeRoom && room && uid && !wasPlaying && !wasSpectator) {
        beforeRoom.rematchOfferedBy?.delete(uid);
        broadcastToRoom(room, socket, { type: 'peer-left', uid });
        console.log(`[room] ${beforeRoom.id} auto-left by ${uid} (disconnect)`);
      }
      if (beforeRoom && room && uid && wasSpectator) {
        broadcastToRoom(room, socket, {
          type: 'spectator-left',
          uid,
          spectatorCount: room.spectators.size,
        });
        console.log(`[spectate] ${uid} auto-left ${beforeRoom.id}`);
      }
      sessions.delete(socket);
      mmDequeue(socket); // remove from matchmaking queue if present
      clearTimeout(authTimer);
      console.log(
        `[ws] closed code=${code} reason=${reason.toString()} uid=${uid ?? 'unauthed'}`,
      );
    });

    socket.on('error', (err) => {
      console.error('[ws] error:', err);
    });
  });

  function close(): Promise<void> {
    clearInterval(heartbeatInterval);
    clearInterval(matchmakingInterval);
    for (const client of wss.clients) {
      try {
        client.terminate();
      } catch {
        // ignore — already gone
      }
    }
    return new Promise((resolve) => {
      wss.close(() => {
        httpServer.close(() => resolve());
      });
    });
  }

  return { httpServer, wss, close };
}

// ── Production entry point ───────────────────────────────────────────────
// Skipped when imported for tests (CCHESS_NO_LISTEN=1): tests build their own
// instance via createCChessServer() with stubbed auth/persist on an ephemeral
// port, so importing this module must not init Firebase or bind PORT.
if (process.env.CCHESS_NO_LISTEN !== '1') {
  initFirebaseAdmin();
  const { httpServer, close } = createCChessServer();

  httpServer.listen(PORT, () => {
    console.log(`[server] HTTP+WS listening on http://localhost:${PORT}`);
    console.log(`[server] WS endpoint: ws://localhost:${PORT}`);
    console.log(`[server] Health check: http://localhost:${PORT}/health`);
  });

  const shutdown = () => {
    console.log('[server] shutting down...');
    void close().then(() => process.exit(0));
  };

  process.on('SIGINT', shutdown);
  process.on('SIGTERM', shutdown);
}
