import { createServer, IncomingMessage } from 'http';
import { WebSocketServer, WebSocket } from 'ws';
import { initFirebaseAdmin, verifyIdToken } from './auth';
import {
  attachReconnectingSocket,
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
} from './match';
import { persistGame } from './persistence';
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
const CHAT_RATE_LIMIT_MS = 1_500;
const CHAT_HISTORY_LIMIT = 50;

initFirebaseAdmin();

// socket -> uid (only after successful auth)
const sessions = new Map<WebSocket, string>();

const httpServer = createServer((req, res) => {
  if (req.url === '/health') {
    res.writeHead(200, { 'Content-Type': 'text/plain' });
    res.end('ok');
    return;
  }
  res.writeHead(404);
  res.end();
});

const wss = new WebSocketServer({ server: httpServer });

function send(socket: WebSocket, payload: Record<string, unknown>) {
  if (socket.readyState === WebSocket.OPEN) {
    socket.send(JSON.stringify(payload));
  }
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

function socketsOf(room: Room): WebSocket[] {
  return [...room.members, ...room.spectators];
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

/// Step 6 + matchmaking shared: start the game once a room has 2 players.
/// Sets status='playing', initializes engine + clocks, broadcasts per-socket
/// game-start with yourColor field.
function startGameForRoom(room: Room): void {
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
    const persisted = await persistGame(room).catch((e) => {
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

interface HeartbeatSocket extends WebSocket {
  isAlive?: boolean;
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

wss.on('close', () => clearInterval(heartbeatInterval));

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
wss.on('close', () => clearInterval(matchmakingInterval));

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
        const decoded = await verifyIdToken(msg.token);
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
      send(socket, {
        type: 'room-created',
        roomId: room.id,
        initialClockMs: room.initialClockMs,
      });
      console.log(
        `[room] ${room.id} created by ${uid} (clock=${clockMs ?? 'default'}ms)`,
      );
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
      if (room.disconnectedUid !== uid) {
        send(socket, { type: 'error', code: 'not-disconnected-player' });
        return;
      }
      // Swap socket into room (replaces dead socket reference)
      attachReconnectingSocket(socket, room, uid);
      // Cancel grace timer + clear disconnect marker
      if (room.disconnectTimer) {
        clearTimeout(room.disconnectTimer);
        room.disconnectTimer = undefined;
      }
      room.disconnectedUid = undefined;

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
        beforeRoom.disconnectedUid = uid;
        if (beforeRoom.disconnectTimer) {
          clearTimeout(beforeRoom.disconnectTimer);
        }
        beforeRoom.disconnectTimer = setTimeout(() => {
          const stillDisconnected = beforeRoom.disconnectedUid === uid;
          const stillPlaying = beforeRoom.status === 'playing';
          console.log(
            `[match] ${beforeRoom.id} grace timer fired: stillDisconnected=${stillDisconnected} stillPlaying=${stillPlaying} status=${beforeRoom.status}`,
          );
          if (stillDisconnected && stillPlaying) {
            const winner: GameResult =
              opponentOf(color) === 'red' ? 'red-win' : 'black-win';
            finishGame(beforeRoom, winner, 'disconnect');
          }
        }, RECONNECT_GRACE_MS);
        broadcastToRoom(beforeRoom, socket, {
          type: 'peer-disconnected',
          uid,
          graceMs: RECONNECT_GRACE_MS,
        });
        console.log(
          `[match] ${beforeRoom.id} ${color} (${uid}) disconnected, grace ${RECONNECT_GRACE_MS}ms`,
        );
      }
    }

    // Remove socket from maps. Preserve room status when grace is in progress
    // so the reconnect-room handler + grace timer can still operate on a
    // 'playing' room.
    const room = leaveRoom(socket, { preserveStatus: wasPlaying });
    if (beforeRoom && room && uid && !wasPlaying && !wasSpectator) {
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

httpServer.listen(PORT, () => {
  console.log(`[server] HTTP+WS listening on http://localhost:${PORT}`);
  console.log(`[server] WS endpoint: ws://localhost:${PORT}`);
  console.log(`[server] Health check: http://localhost:${PORT}/health`);
});

function shutdown() {
  console.log('[server] shutting down...');
  wss.close(() => {
    httpServer.close(() => {
      process.exit(0);
    });
  });
}

process.on('SIGINT', shutdown);
process.on('SIGTERM', shutdown);
