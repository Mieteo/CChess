// Dashboard control server. Hosts ONE long-lived in-process CChess server for
// hands-on exploration: the browser is just a control panel, while the actual
// WebSocket clients are Node-side Bots driven by button clicks. Live server
// state (rooms, queue, invariant violations) is polled and rendered.
//
// Scenario buttons run the headless runner in a CHILD PROCESS so a scripted
// scenario's state can't collide with the rooms you're manually poking at (the
// server's room map is a module singleton shared in-process).
//
//   npx tsx lab/control.ts      then open http://localhost:7700

import { createServer, type IncomingMessage, type ServerResponse } from 'node:http';
import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { spawn } from 'node:child_process';
import { Bot } from './bot';
import { startLabServer } from './harness';
import { snapshot } from './invariants';
import { scenarios } from './scenarios';

const PORT = Number(process.env.LAB_PORT ?? 7700);
// Generous-but-short timing so you can actually WATCH grace countdowns / TTLs.
const TIMING = {
  reconnectGraceMs: 15_000,
  waitingRoomTtlMs: 30_000,
  heartbeatIntervalMs: 2_000,
  livenessTimeoutMs: 6_000,
};

async function main(): Promise<void> {
  // Silence the embedded server's logs (+ harmless Firebase ELO warning).
  if (!process.env.LAB_VERBOSE) {
    console.warn = () => {};
    console.error = () => {};
  }
  const lab = await startLabServer(TIMING);
  const log = console.log.bind(console);

  // uid → bot. We keep dropped bots around (marked) so you can reconnect them.
  const bots = new Map<string, Bot>();
  const lastRoomId = new Map<string, string>();

  function rememberRoom(uid: string): void {
    const r = bots.get(uid)?.roomId;
    if (r) lastRoomId.set(uid, r);
  }

  const here = __dirname;
  const html = readFileSync(join(here, 'public', 'index.html'), 'utf8');

  async function handleCmd(body: Record<string, unknown>): Promise<unknown> {
    const action = String(body.action ?? '');
    const uid = typeof body.uid === 'string' ? body.uid : '';
    const roomId = typeof body.roomId === 'string' ? body.roomId : '';

    switch (action) {
      case 'spawn': {
        if (bots.has(uid)) return { ok: false, error: 'uid exists' };
        const b = new Bot(lab.url, uid);
        await b.connectAuthed();
        bots.set(uid, b);
        return { ok: true };
      }
      case 'create':
        bots.get(uid)?.createRoom();
        return { ok: true };
      case 'find':
        bots.get(uid)?.findMatch();
        return { ok: true };
      case 'cancel':
        bots.get(uid)?.cancelMatching();
        return { ok: true };
      case 'join':
        bots.get(uid)?.joinRoom(roomId);
        return { ok: true };
      case 'spectate':
        bots.get(uid)?.spectateRoom(roomId);
        return { ok: true };
      case 'resign':
        bots.get(uid)?.resign();
        return { ok: true };
      case 'leave':
        bots.get(uid)?.leaveRoom();
        return { ok: true };
      case 'drop':
        rememberRoom(uid);
        bots.get(uid)?.drop();
        return { ok: true };
      case 'reconnect': {
        // Fresh socket, same uid → resume the last room it was in.
        const target = roomId || lastRoomId.get(uid) || bots.get(uid)?.roomId;
        const b = new Bot(lab.url, uid);
        await b.connectAuthed();
        bots.set(uid, b);
        if (target) b.reconnectRoom(target);
        return { ok: true, roomId: target };
      }
      case 'remove': {
        await bots.get(uid)?.close().catch(() => {});
        bots.delete(uid);
        lastRoomId.delete(uid);
        return { ok: true };
      }
      case 'clear': {
        for (const b of bots.values()) await b.close().catch(() => {});
        bots.clear();
        lastRoomId.clear();
        return { ok: true };
      }
      case 'scenario':
        return runScenarioChild(String(body.name ?? ''));
      default:
        return { ok: false, error: `unknown action: ${action}` };
    }
  }

  function runScenarioChild(name: string): Promise<unknown> {
    // Only allow names we actually know about (no shell injection).
    if (!scenarios.some((s) => s.name === name)) {
      return Promise.resolve({ ok: false, error: `unknown scenario: ${name}` });
    }
    return new Promise((resolve) => {
      const child = spawn(`npx tsx lab/runner.ts ${name}`, {
        cwd: join(here, '..'),
        shell: true,
        env: process.env,
      });
      let out = '';
      child.stdout.on('data', (d) => (out += d.toString()));
      child.stderr.on('data', (d) => (out += d.toString()));
      child.on('close', (code) => resolve({ ok: code === 0, output: out.trim() }));
    });
  }

  function botsView(): unknown[] {
    return [...bots.values()].map((b) => ({
      uid: b.uid,
      roomId: b.roomId ?? null,
      color: b.color ?? null,
      recent: b.log.slice(-5).map((m) => m.type),
    }));
  }

  const server = createServer((req: IncomingMessage, res: ServerResponse) => {
    const url = new URL(req.url ?? '/', 'http://localhost');
    const send = (code: number, type: string, data: string) => {
      res.writeHead(code, { 'Content-Type': type });
      res.end(data);
    };
    const json = (obj: unknown) =>
      send(200, 'application/json', JSON.stringify(obj));

    if (url.pathname === '/') return send(200, 'text/html; charset=utf-8', html);

    if (url.pathname === '/lab/state') {
      return json({ server: snapshot(), bots: botsView() });
    }
    if (url.pathname === '/lab/scenarios') {
      return json(scenarios.map((s) => ({ name: s.name, why: s.why })));
    }
    if (url.pathname === '/lab/cmd' && req.method === 'POST') {
      let raw = '';
      req.on('data', (c) => (raw += c));
      req.on('end', () => {
        let body: Record<string, unknown> = {};
        try {
          body = raw ? JSON.parse(raw) : {};
        } catch {
          return json({ ok: false, error: 'invalid json' });
        }
        handleCmd(body)
          .then(json)
          .catch((e) => json({ ok: false, error: String(e) }));
      });
      return;
    }
    send(404, 'text/plain', 'not found');
  });

  server.listen(PORT, () => {
    log(`\nCChess test-lab dashboard → http://localhost:${PORT}`);
    log(`(in-process server at ${lab.url}, grace ${TIMING.reconnectGraceMs}ms)\n`);
  });

  const shutdown = (): void => {
    void (async () => {
      for (const b of bots.values()) await b.close().catch(() => {});
      await lab.close();
      server.close(() => process.exit(0));
    })();
  };
  process.on('SIGINT', shutdown);
  process.on('SIGTERM', shutdown);
}

void main();
