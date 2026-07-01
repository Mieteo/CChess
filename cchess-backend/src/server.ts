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
  type GameVariant,
  type Room,
} from './rooms';
import {
  applyMove,
  clockSnapshot,
  colorOfSocket,
  consumeTimeoutIfExpired,
  cupSnapshot,
  endMatch,
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
import { createPuzzleApi, type PuzzleApi } from './puzzles/puzzle_routes';
import { createShopApi, type ShopApi } from './shop/shop_routes';
import { createClubsApi, type ClubsApi } from './clubs/clubs_routes';
import { createCommunityFeedApi, type CommunityFeedApi } from './community_feed/community_feed_routes';
import { createTournamentsApi, type TournamentsApi } from './tournaments/tournament_routes';

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
// Sweep interval is also when the app-level liveness check below runs;
// overridable via env so integration tests can sweep fast.
const HEARTBEAT_INTERVAL_MS =
  Number(process.env.CCHESS_HEARTBEAT_INTERVAL_MS ?? '') || 5_000;

// D1 fix: application-level liveness. Clients send {type:'ping'} every ~5s and
// we reply {type:'pong'}. A socket from which we've heard NOTHING for this long
// is considered dead and terminated immediately (→ reconnect grace). Unlike the
// WS control-frame ping above, app-level JSON messages can't be auto-answered by
// a proxy/load-balancer, so this still detects half-open connections behind
// Render's router (where control-frame pong was masking ~3-min TCP timeouts).
// Overridable via env so integration tests can use a short window.
const LIVENESS_TIMEOUT_MS =
  Number(process.env.CCHESS_LIVENESS_TIMEOUT_MS ?? '') || 15_000;

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

// Minimum per-side clock a lobby may request (ms). 60s in production; the test
// lab lowers it so timeout flows can be exercised in ~1s instead of a minute.
const MIN_CLOCK_MS = Number(process.env.CCHESS_MIN_CLOCK_MS ?? '') || 60_000;
const MAX_CLOCK_MS = 3_600_000;

// Nhóm 5 abuse control. Messages are tiny JSON (a move is 4 chars, chat caps at
// 120) so a 16 KB frame cap is generous; anything larger is rejected by ws.
const MAX_PAYLOAD_BYTES = Number(process.env.CCHESS_MAX_PAYLOAD ?? '') || 16_384;
// Inbound message token bucket: burst of RL_CAPACITY, sustained RL_REFILL/sec.
// A socket that floods past RL_MAX_DROPS dropped messages is terminated.
const RL_CAPACITY = Number(process.env.CCHESS_RL_CAPACITY ?? '') || 50;
const RL_REFILL_PER_SEC = Number(process.env.CCHESS_RL_REFILL ?? '') || 25;
const RL_MAX_DROPS = 200;

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
    mode: room.mode,
    variant: room.variant,
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
  // D1 fix: timestamp of the last inbound message (any type, incl. ping). The
  // heartbeat sweep terminates sockets silent longer than LIVENESS_TIMEOUT_MS.
  lastSeenAt?: number;
  // Nhóm 5 abuse control: per-socket token bucket for inbound messages.
  rlTokens?: number;
  rlLast?: number;
  rlDrops?: number;
}

/// Per-socket inbound rate limit (token bucket). Protects the server from a
/// buggy/hostile client flooding move/find/create/etc. Normal play (a few
/// messages plus a ping every ~5s) never comes close. Returns false when the
/// message should be dropped.
function rateLimitAllows(
  sock: HeartbeatSocket,
  capacity: number,
  refillPerSec: number,
): boolean {
  const now = Date.now();
  const last = sock.rlLast ?? now;
  const refilled = Math.min(
    capacity,
    (sock.rlTokens ?? capacity) + ((now - last) / 1000) * refillPerSec,
  );
  sock.rlLast = now;
  if (refilled < 1) {
    sock.rlTokens = refilled;
    sock.rlDrops = (sock.rlDrops ?? 0) + 1;
    return false;
  }
  sock.rlTokens = refilled - 1;
  sock.rlDrops = 0;
  return true;
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
  /// REST API for the endgame puzzle library (B4), mounted on the same HTTP
  /// server. Defaults to the real Firestore-backed API. Tests that don't touch
  /// /puzzles can leave it; ones that do inject a fake-store-backed instance.
  puzzleApi?: PuzzleApi;
  /// REST API for the economy (S16 — Thương Thành / Balo), mounted on the same
  /// HTTP server. Defaults to the real Firestore-backed API; tests inject a
  /// fake-store-backed instance.
  shopApi?: ShopApi;
  /// REST API for clubs (S14 C3 — Kỳ Xã), mounted on the same HTTP server.
  /// Defaults to the real Firestore-backed API; tests inject a fake-store-backed
  /// instance.
  clubsApi?: ClubsApi;
  /// REST API for the community news/daily-challenge feed (S14 C6), mounted on
  /// the same HTTP server. Defaults to the real Firestore-backed API; tests
  /// inject a fake-store-backed instance.
  communityFeedApi?: CommunityFeedApi;
  /// REST API for tournaments (S14 C4 — Giải Đấu), mounted on the same HTTP
  /// server. Also used in-process (via `.store`) by the create-room handler
  /// and finishGame() below — tournament matches reuse the casual
  /// private-room flow instead of new matchmaking surface. Defaults to the
  /// real Firestore-backed API; tests inject a fake-store-backed instance.
  tournamentsApi?: TournamentsApi;
  /// Per-instance timing / limits. Each field defaults to its env-backed
  /// module constant, so production (no config) is unchanged. The test lab
  /// passes this PER SCENARIO — unlike env vars (read once at import), an
  /// option is honoured on every createCChessServer() call, so scenarios in one
  /// runner process can't silently inherit the first scenario's timing.
  config?: {
    reconnectGraceMs?: number;
    waitingRoomTtlMs?: number;
    heartbeatIntervalMs?: number;
    livenessTimeoutMs?: number;
    minClockMs?: number;
    maxClockMs?: number;
    maxPayloadBytes?: number;
    rlCapacity?: number;
    rlRefillPerSec?: number;
  };
}

/// Build a fully-wired CChess WebSocket server WITHOUT starting to listen.
/// The caller decides the port (`httpServer.listen(...)`). Auth + persistence
/// are injectable so the protocol can be integration-tested over real sockets
/// without Firebase. Production behaviour is unchanged: the defaults are the
/// real `verifyIdToken` + `persistGame`.
export function createCChessServer(options: CChessServerOptions = {}): CChessServer {
  const authenticate = options.authenticate ?? verifyIdToken;
  const persist = options.persist ?? persistGame;

  // Resolve per-instance config; each field defaults to its env-backed const.
  const c = options.config ?? {};
  const cfg = {
    reconnectGraceMs: c.reconnectGraceMs ?? RECONNECT_GRACE_MS,
    waitingRoomTtlMs: c.waitingRoomTtlMs ?? WAITING_ROOM_TTL_MS,
    heartbeatIntervalMs: c.heartbeatIntervalMs ?? HEARTBEAT_INTERVAL_MS,
    livenessTimeoutMs: c.livenessTimeoutMs ?? LIVENESS_TIMEOUT_MS,
    minClockMs: c.minClockMs ?? MIN_CLOCK_MS,
    maxClockMs: c.maxClockMs ?? MAX_CLOCK_MS,
    maxPayloadBytes: c.maxPayloadBytes ?? MAX_PAYLOAD_BYTES,
    rlCapacity: c.rlCapacity ?? RL_CAPACITY,
    rlRefillPerSec: c.rlRefillPerSec ?? RL_REFILL_PER_SEC,
  };

  // socket -> uid (only after successful auth)
  const sessions = new Map<WebSocket, string>();

  // B4 puzzle library REST API, mounted on this same HTTP server (no separate
  // Render service). It owns /puzzles* and /admin/puzzles*; everything else
  // falls through to the routes below.
  const puzzleApi = options.puzzleApi ?? createPuzzleApi();
  // S16 economy REST API, mounted on the same HTTP server. It owns /shop*,
  // /wallet, /inventory* and /admin/shop*; everything else falls through.
  const shopApi = options.shopApi ?? createShopApi();
  // S14 C3 clubs REST API, mounted on the same HTTP server. It owns /clubs*;
  // everything else falls through.
  const clubsApi = options.clubsApi ?? createClubsApi();
  // S14 C6 community feed REST API, mounted on the same HTTP server. It owns
  // /community/feed and /admin/community/feed*; everything else falls through.
  const communityFeedApi = options.communityFeedApi ?? createCommunityFeedApi();
  // S14 C4 tournaments REST API, mounted on the same HTTP server. It owns
  // /tournaments*; everything else falls through. Also called in-process
  // (`.store`) below for room attachment + match result recording.
  const tournamentsApi = options.tournamentsApi ?? createTournamentsApi();

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

    // Mounted REST APIs. Each handle() resolves true if it owned the request
    // (and already sent a response); we try the puzzle API, then the shop API,
    // then the clubs API, then the community feed API, then the tournaments
    // API, and 404 only if none claimed the path.
    void puzzleApi
      .handle(req, res)
      .then((handled) => (handled ? true : shopApi.handle(req, res)))
      .then((handled) => (handled ? true : clubsApi.handle(req, res)))
      .then((handled) => (handled ? true : communityFeedApi.handle(req, res)))
      .then((handled) => (handled ? true : tournamentsApi.handle(req, res)))
      .then((handled) => {
        if (!handled && !res.headersSent) {
          res.writeHead(404);
          res.end();
        }
      })
      .catch((err) => {
        console.error('[rest] unhandled route error:', err);
        if (!res.headersSent) {
          res.writeHead(500);
          res.end();
        }
      });
  });

  const wss = new WebSocketServer({ server: httpServer, maxPayload: cfg.maxPayloadBytes });

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
      mode: room.mode,
      variant: room.variant,
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
      mode: room.mode,
      variant: room.variant,
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
    a: { socket: WebSocket; uid: string; clockMs?: number; variant?: GameVariant },
    b: { socket: WebSocket; uid: string; clockMs?: number; variant?: GameVariant },
  ): void {
    const clockMs = a.clockMs ?? b.clockMs;
    // tryMatch only pairs equal variants, so a.variant === b.variant here.
    const variant: GameVariant = a.variant ?? 'standard';
    const room = createRoom(a.socket, {
      initialClockMs: clockMs,
      mode: 'ranked',
      variant,
    });
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
      const loser = consumeTimeoutIfExpired(room);
      if (loser) {
        const winner: GameResult = loser === 'red' ? 'black-win' : 'red-win';
        finishGame(room, winner, 'timeout');
      }
    }, 1000);
  }

  /// End the game cleanly: stop ticker, mark room finished, persist + ELO,
  /// then broadcast game-ended (with ELO deltas included when available).
  function finishGame(room: Room, result: GameResult, reason: EndReason): void {
    // endMatch is the single source of truth for the playing→finished
    // transition. If it returns false the game was ALREADY finished (a second
    // end-condition raced in) — bail so we don't persist/ELO/broadcast twice.
    if (!endMatch(room, result, reason)) return;

    // Run persistence + ELO update, then broadcast. Even if persistence fails,
    // we still broadcast (game IS ended) — just without ELO numbers.
    void (async () => {
      const persisted = room.mode === 'casual'
        ? null
        : await persist(room).catch((e) => {
            console.error('[persist] error:', e);
            return null;
          });
      // S14 C4: if this room was a tournament bracket match, record the
      // result and advance the bracket — independent of (and in addition to)
      // the ranked persist above, which tournament rooms always skip
      // (mode:'casual'). A draw resets the match for a replay instead of
      // advancing anyone (single-elimination has no draws).
      if (room.tournamentTag && room.result) {
        const { tournamentId, matchId } = room.tournamentTag;
        const outcome: { winnerUid: string } | { draw: true } =
          room.result === 'draw'
            ? { draw: true }
            : { winnerUid: room.result === 'red-win' ? room.redUid! : room.blackUid! };
        await tournamentsApi.store
          .recordMatchResult({ tournamentId, matchId, outcome, roomId: room.id })
          .catch((e) => console.error('[tournament] recordMatchResult failed:', e));
      }
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
        mode: room.mode,
        variant: room.variant,
      };
      broadcastAll(room, payload);
      console.log(
        `[match] ${room.id} ended result=${result} reason=${reason} moves=${room.movesUci?.length ?? 0}${elo ? ` | elo red ${elo.red.old}→${elo.red.new} black ${elo.black.old}→${elo.black.new}` : ''}`,
      );
    })();
  }

  const heartbeatInterval = setInterval(() => {
    const now = Date.now();
    wss.clients.forEach((s) => {
      const sock = s as HeartbeatSocket;
      // D1 fix: app-level liveness first — if the client has gone silent (no
      // ping/message) past the timeout, treat it as dead right away. This is
      // what catches mobile wifi drops behind Render's proxy, where the WS
      // control-frame heartbeat below was masked for ~3 min by TCP timeouts.
      if (
        sock.lastSeenAt !== undefined &&
        now - sock.lastSeenAt > cfg.livenessTimeoutMs
      ) {
        console.log('[ws] liveness timeout → terminate');
        sock.terminate(); // fires 'close' event → grace/finishGame path
        return;
      }
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
  }, cfg.heartbeatIntervalMs);

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
    hbSock.lastSeenAt = Date.now();
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
      // D1 fix: any inbound frame proves the socket is alive (drives the
      // app-level liveness sweep, independent of WS control-frame pong).
      (socket as HeartbeatSocket).lastSeenAt = Date.now();
      if (isBinary) {
        send(socket, { type: 'error', code: 'binary-not-supported' });
        return;
      }

      // Nhóm 5: per-socket flood control. Drop the message when the bucket is
      // empty; report once per burst (no per-message amplification); terminate
      // a socket that keeps hammering far past the limit.
      const hb = socket as HeartbeatSocket;
      if (!rateLimitAllows(hb, cfg.rlCapacity, cfg.rlRefillPerSec)) {
        if ((hb.rlDrops ?? 0) > RL_MAX_DROPS) {
          console.warn('[ws] rate-limit flood → terminate');
          socket.terminate();
          return;
        }
        if (hb.rlDrops === 1) send(socket, { type: 'error', code: 'rate-limited' });
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

      // D1 fix: app-level heartbeat. lastSeenAt was bumped above; just echo a
      // pong so the client's own watchdog stays satisfied. Allowed pre-auth.
      if (msg.type === 'ping') {
        send(socket, { type: 'pong', ts: Date.now() });
        return;
      }

      // ── Auth handshake ────────────────────────────────────────────────
      if (msg.type === 'auth') {
        // A socket authenticates ONCE. Re-auth (especially changing uid mid-
        // session) would desync the seat/uid bookkeeping for an in-progress
        // game, so refuse it outright.
        if (sessions.has(socket)) {
          send(socket, { type: 'error', code: 'already-authed' });
          return;
        }
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
          typeof rawClock === 'number' && rawClock >= cfg.minClockMs && rawClock <= cfg.maxClockMs
            ? rawClock
            : undefined;
        // Cờ Úp has its own rating pool — bucket on eloCup, not eloChess.
        const variant: GameVariant = msg.variant === 'cup' ? 'cup' : 'standard';
        const eloField = variant === 'cup' ? 'eloCup' : 'eloChess';
        // Fetch current ELO from Firestore so bucket matchmaking can pair fairly
        let elo = 1000;
        try {
          const { getFirestore } = await import('firebase-admin/firestore');
          const snap = await getFirestore().collection('users').doc(uid).get();
          const e = snap.data()?.[eloField] as number | undefined;
          if (typeof e === 'number') elo = e;
        } catch (e) {
          console.warn(`[matchmaking] failed to fetch ELO for ${uid}, using default 1000:`, e);
        }
        // The ELO fetch above is async — the socket may have disconnected (or
        // joined a room) DURING that await. The close handler's mmDequeue would
        // then have run BEFORE this enqueue, leaving a dead socket stuck in the
        // queue forever (and liable to be "paired" into a ghost game). Re-check
        // liveness before enqueuing. This window is wider against real Firestore.
        if (!sessions.has(socket) || socket.readyState !== WebSocket.OPEN) {
          mmDequeue(socket);
          return;
        }
        if (roomOf(socket)) {
          send(socket, { type: 'error', code: 'already-in-room' });
          return;
        }
        const size = mmEnqueue(socket, uid, elo, clockMs, variant);
        send(socket, { type: 'matching', queueSize: size, elo, variant });
        console.log(`[matchmaking] ${uid} enqueued (queue size=${size}, elo=${elo} variant=${variant})`);
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
        // A socket must never be in the matchmaking queue AND in a room at the
        // same time: a stale queue entry would later get paired into a SECOND
        // game, double-booking the socket and corrupting room/socket maps.
        // Entering a private room implicitly cancels any pending search.
        mmDequeue(socket);
        // Step A5: optional initial clock from lobby (clamp to sane range)
        const rawClock = (msg as { clockMs?: number }).clockMs;
        const clockMs =
          typeof rawClock === 'number' && rawClock >= cfg.minClockMs && rawClock <= cfg.maxClockMs
            ? rawClock
            : undefined;
        // S14 C4: an optional tag linking this room to a tournament bracket
        // match (see tournaments/tournament_routes.ts + the create-room WS
        // protocol doc). Tournament rooms always run as 'casual' — ladder
        // ELO is untouched; standings are tracked via TournamentStore
        // instead.
        const rawTag = (msg as { tournamentTag?: unknown }).tournamentTag as
          | { tournamentId?: unknown; matchId?: unknown }
          | undefined;
        const tournamentTag =
          rawTag &&
          typeof rawTag.tournamentId === 'string' &&
          rawTag.tournamentId.length > 0 &&
          typeof rawTag.matchId === 'string' &&
          rawTag.matchId.length > 0
            ? { tournamentId: rawTag.tournamentId, matchId: rawTag.matchId }
            : undefined;
        const roomMode = tournamentTag
          ? 'casual'
          : msg.mode === 'casual' || msg.casual === true
            ? 'casual'
            : 'ranked';
        const variant = msg.variant === 'cup' ? 'cup' : 'standard';
        const room = createRoom(socket, {
          initialClockMs: clockMs,
          mode: roomMode,
          variant,
          tournamentTag,
        });
        // Waiting-room TTL: cancel the room if nobody joins in time.
        room.waitingTimer = setTimeout(() => {
          room.waitingTimer = undefined;
          if (room.status !== 'waiting') return;
          console.log(
            `[room] ${room.id} expired — no opponent joined within ${cfg.waitingRoomTtlMs}ms`,
          );
          for (const s of [...room.members]) {
            send(s, { type: 'room-expired', roomId: room.id });
            leaveRoom(s); // last leaver deletes the room
          }
        }, cfg.waitingRoomTtlMs);
        send(socket, {
          type: 'room-created',
          roomId: room.id,
          mode: room.mode,
          variant: room.variant,
          initialClockMs: room.initialClockMs,
          waitingTtlMs: cfg.waitingRoomTtlMs,
        });
        console.log(
          `[room] ${room.id} created by ${uid} (mode=${room.mode} variant=${room.variant} clock=${clockMs ?? 'default'}ms)`,
        );
        if (tournamentTag) {
          // Fire-and-forget: lets the OTHER player's match-detail screen
          // discover this room id (via GET /tournaments/:id/matches) instead
          // of needing a new "who's hosting" protocol message. No-ops if
          // `uid` isn't actually one of this match's two players.
          void tournamentsApi.store
            .attachRoomToMatch(tournamentTag.tournamentId, tournamentTag.matchId, room.id, uid)
            .catch((e) => console.error('[tournament] attachRoomToMatch failed:', e));
        }
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
        // Eligible only if this uid owns a SEAT currently in grace. (Grace is
        // keyed by seat now, so check the entry uids, not the map key.)
        const graceEntries = room.disconnectGrace
          ? [...room.disconnectGrace.values()]
          : [];
        if (!uid || !graceEntries.some((e) => e.uid === uid)) {
          send(socket, { type: 'error', code: 'not-disconnected-player' });
          return;
        }
        // Swap socket into room (replaces dead socket reference). The returned
        // seat is authoritative — it handles the same-uid case where redUid ===
        // blackUid and the seat can't be inferred from uid alone.
        const yourColor = attachReconnectingSocket(socket, room, uid);
        // Cancel THIS seat's grace timer. The other seat may still be in grace
        // (double-disconnect) — leave its entry untouched.
        clearDisconnectGrace(room, yourColor);
        const peerEntry = room.disconnectGrace
          ? [...room.disconnectGrace.values()][0]
          : undefined;
        // Cờ Úp: a UCI replay can't reconstruct revealed identities, so ship the
        // cheat-safe board snapshot (covers + revealed + hidden squares).
        const cupState = cupSnapshot(room);
        send(socket, {
          type: 'reconnected',
          roomId: room.id,
          yourColor,
          redUid: room.redUid,
          blackUid: room.blackUid,
          mode: room.mode,
          variant: room.variant,
          moves: room.movesUci ?? [],
          ...(cupState ? { cup: cupState } : {}),
          chat: room.chatMessages ?? [],
          currentTurn: room.currentTurn,
          clock: clockSnapshot(room),
          startedAt: room.startedAt,
          // Double-disconnect: tell the reconnecting client when the peer is
          // ALSO in grace so it can show the countdown banner right away.
          peerInGrace: peerEntry
            ? {
                uid: peerEntry.uid,
                remainingMs: Math.max(0, peerEntry.deadline - Date.now()),
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
        // Becoming a spectator also leaves any pending matchmaking search.
        mmDequeue(socket);
        const room = result.room;
        // Cờ Úp: a UCI replay can't reconstruct revealed identities, so ship the
        // cheat-safe board snapshot (covers + revealed + hidden squares) just
        // like reconnect — otherwise a fresh watcher can't rebuild the board.
        const spectateCup = cupSnapshot(room);
        send(socket, {
          type: 'spectate-started',
          roomId: room.id,
          redUid: room.redUid,
          blackUid: room.blackUid,
          mode: room.mode,
          variant: room.variant,
          moves: room.movesUci ?? [],
          ...(spectateCup ? { cup: spectateCup } : {}),
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
        // Joining a room implicitly leaves the matchmaking queue (see
        // create-room) so a stale queue entry can't pair us into a 2nd game.
        mmDequeue(socket);
        const room = result.room;
        const members = membersOf(room, (s) => sessions.get(s));
        send(socket, {
          type: 'room-joined',
          roomId: room.id,
          mode: room.mode,
          variant: room.variant,
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
          // Cờ Úp: the revealed identity + captured piece so peers/spectators can
          // flip the cover. Absent for standard games.
          ...(result.reveal ? { reveal: result.reveal } : {}),
        };
        broadcastToRoom(room, socket, movePayload);
        send(socket, {
          type: 'move-ack',
          uci: rawUci,
          moveNumber: result.moveNumber,
          clock: clockSnapshot(room),
          ...(result.reveal ? { reveal: result.reveal } : {}),
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
          // Per-SEAT grace entries (keyed by color). A double-disconnect keeps
          // BOTH forfeit timers alive, and — unlike the old per-uid keying — a
          // same-uid game (one account on both seats) still tracks each seat
          // independently, so reconnecting one seat doesn't wipe the other's.
          const grace = (beforeRoom.disconnectGrace ??= new Map());
          const prior = grace.get(color);
          if (prior) clearTimeout(prior.timer);
          const timer = setTimeout(() => {
            const stillDisconnected = beforeRoom.disconnectGrace?.has(color) ?? false;
            const stillPlaying = beforeRoom.status === 'playing';
            console.log(
              `[match] ${beforeRoom.id} grace timer fired for ${color} (${uid}): stillDisconnected=${stillDisconnected} stillPlaying=${stillPlaying} status=${beforeRoom.status}`,
            );
            beforeRoom.disconnectGrace?.delete(color);
            if (stillDisconnected && stillPlaying) {
              const winner: GameResult =
                opponentOf(color) === 'red' ? 'red-win' : 'black-win';
              finishGame(beforeRoom, winner, 'disconnect');
            }
          }, cfg.reconnectGraceMs);
          grace.set(color, { timer, deadline: Date.now() + cfg.reconnectGraceMs, uid });
          broadcastToRoom(beforeRoom, socket, {
            type: 'peer-disconnected',
            uid,
            graceMs: cfg.reconnectGraceMs,
          });
          console.log(
            `[match] ${beforeRoom.id} ${color} (${uid}) disconnected, grace ${cfg.reconnectGraceMs}ms (inGrace=${grace.size})`,
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
