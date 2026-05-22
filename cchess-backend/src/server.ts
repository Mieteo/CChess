import { createServer, IncomingMessage } from 'http';
import { WebSocketServer, WebSocket } from 'ws';
import { initFirebaseAdmin, verifyIdToken } from './auth';
import {
  createRoom,
  joinRoom,
  leaveRoom,
  membersOf,
  roomOf,
  type Room,
} from './rooms';

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

// Xiangqi UCI: 9 cols (a-i) × 10 rows (0-9). Format check only — Step 5 will
// add legality (turn, piece existence, rule compliance).
const UCI_REGEX = /^[a-i][0-9][a-i][0-9]$/;

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
  for (const s of room.members) {
    if (s === except) continue;
    send(s, payload);
  }
}

wss.on('connection', (socket: WebSocket, request: IncomingMessage) => {
  const remote = request.socket.remoteAddress;
  console.log(`[ws] connected from ${remote}`);

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
    if (msg.type === 'create-room') {
      if (roomOf(socket)) {
        send(socket, { type: 'error', code: 'already-in-room' });
        return;
      }
      const room = createRoom(socket);
      send(socket, { type: 'room-created', roomId: room.id });
      console.log(`[room] ${room.id} created by ${uid}`);
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
      return;
    }

    if (msg.type === 'leave-room') {
      const before = roomOf(socket);
      const room = leaveRoom(socket);
      if (!before || !room) {
        send(socket, { type: 'error', code: 'not-in-room' });
        return;
      }
      send(socket, { type: 'left-room', roomId: before.id });
      broadcastToRoom(room, socket, { type: 'peer-left', uid });
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

    // ── Step 4: move transport ────────────────────────────────────────
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
      room.moveCount++;
      const moveNumber = room.moveCount;
      broadcastToRoom(room, socket, {
        type: 'opponent-move',
        uci: rawUci,
        from: uid,
        moveNumber,
        ts: Date.now(),
      });
      console.log(`[room] ${room.id} move #${moveNumber} ${uid} → ${rawUci}`);
      return;
    }

    // Unknown → echo with uid
    send(socket, { type: 'echo', uid, original: msg, ts: Date.now() });
  });

  socket.on('close', (code, reason) => {
    const uid = sessions.get(socket);
    // Notify room peers if this socket was in a room
    const before = roomOf(socket);
    const room = leaveRoom(socket);
    if (before && room && uid) {
      broadcastToRoom(room, socket, { type: 'peer-left', uid });
      console.log(`[room] ${before.id} auto-left by ${uid} (disconnect)`);
    }
    sessions.delete(socket);
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
