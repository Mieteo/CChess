import { createServer, IncomingMessage } from 'http';
import { WebSocketServer, WebSocket } from 'ws';
import { initFirebaseAdmin, verifyIdToken } from './auth';

// Step 2 from 08_HUONG_DAN_BACKEND_WEBSOCKET.md: auth handshake.
//
// Protocol:
//   1. Client connects.
//   2. Server sends `{type:"welcome"}` and waits up to AUTH_TIMEOUT_MS.
//   3. Client sends `{type:"auth", token: "<firebase id token>"}`.
//   4. Server verifies via Firebase Admin → sends `{type:"authed", uid}`.
//   5. From now on every message is tagged with that uid (echo for now).
//
// If client doesn't auth in time, or token invalid, socket is closed.

const PORT = Number(process.env.PORT ?? 8080);
const AUTH_TIMEOUT_MS = 10_000;

// Initialize Firebase Admin once.
initFirebaseAdmin();

// Map socket -> uid (only set after successful auth).
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

    let msg: { type?: string; token?: string; [k: string]: unknown };
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

    // ── Post-auth messages ────────────────────────────────────────────
    const uid = sessions.get(socket);
    if (!uid) {
      send(socket, { type: 'error', code: 'not-authed' });
      return;
    }

    // Echo with uid attached, for now.
    send(socket, {
      type: 'echo',
      uid,
      original: msg,
      ts: Date.now(),
    });
  });

  socket.on('close', (code, reason) => {
    const uid = sessions.get(socket);
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
