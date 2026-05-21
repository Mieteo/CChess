import { createServer } from 'http';
import { WebSocketServer, WebSocket } from 'ws';

// Step 1 from 08_HUONG_DAN_BACKEND_WEBSOCKET.md: echo server.
// Run with `npm run dev`. Test from any WS client (vd Chrome console):
//   const ws = new WebSocket('ws://localhost:8080');
//   ws.onmessage = e => console.log('echo:', e.data);
//   ws.onopen = () => ws.send('hello');

const PORT = Number(process.env.PORT ?? 8080);

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

wss.on('connection', (socket: WebSocket, request) => {
  const remote = request.socket.remoteAddress;
  console.log(`[ws] connected from ${remote}`);

  socket.send(JSON.stringify({ type: 'welcome', ts: Date.now() }));

  socket.on('message', (data, isBinary) => {
    const text = isBinary ? '[binary]' : data.toString();
    console.log(`[ws] <- ${text}`);
    // Echo back
    socket.send(
      JSON.stringify({
        type: 'echo',
        original: text,
        ts: Date.now(),
      }),
    );
  });

  socket.on('close', (code, reason) => {
    console.log(`[ws] closed: ${code} ${reason.toString()}`);
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

// Graceful shutdown
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
