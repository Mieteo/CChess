// Spin up the real CChess WebSocket server IN-PROCESS, with stubbed auth +
// persistence so no Firebase is needed and the token string IS the uid (so a
// bot fully controls which uid it presents). Timing knobs (grace / waiting-room
// TTL / heartbeat) are shrunk to scenario-friendly windows and are overridable.
//
// IMPORTANT: the server + match modules read their timing constants from env AT
// IMPORT TIME, so we MUST set env BEFORE importing them — hence the dynamic
// import inside startLabServer (mirrors how the integration tests do it).

import type { AddressInfo } from 'node:net';
import type { CChessServer } from '../src/server';

export interface LabServer {
  server: CChessServer;
  url: string;
  close: () => Promise<void>;
}

export interface LabTiming {
  reconnectGraceMs?: number;
  waitingRoomTtlMs?: number;
  heartbeatIntervalMs?: number;
  livenessTimeoutMs?: number;
  /// Lowest per-side clock the server will accept (ms). Lowered far below the
  /// 60s production floor so timeout flows finish in ~1s.
  minClockMs?: number;
}

const DEFAULTS: Required<LabTiming> = {
  reconnectGraceMs: 1000,
  waitingRoomTtlMs: 1000,
  heartbeatIntervalMs: 500,
  livenessTimeoutMs: 1500,
  minClockMs: 200,
};

export async function startLabServer(timing: LabTiming = {}): Promise<LabServer> {
  const t = { ...DEFAULTS, ...timing };
  process.env.CCHESS_NO_LISTEN = '1';
  process.env.CCHESS_RECONNECT_GRACE_MS = String(t.reconnectGraceMs);
  process.env.CCHESS_WAITING_ROOM_TTL_MS = String(t.waitingRoomTtlMs);
  process.env.CCHESS_HEARTBEAT_INTERVAL_MS = String(t.heartbeatIntervalMs);
  process.env.CCHESS_LIVENESS_TIMEOUT_MS = String(t.livenessTimeoutMs);
  process.env.CCHESS_MIN_CLOCK_MS = String(t.minClockMs);

  const { createCChessServer } = await import('../src/server');
  const server = createCChessServer({
    authenticate: async (token: string) => ({ uid: token }),
    persist: async () => null,
  });

  const url: string = await new Promise((resolve) => {
    server.httpServer.listen(0, '127.0.0.1', () => {
      const { port } = server.httpServer.address() as AddressInfo;
      resolve(`ws://127.0.0.1:${port}`);
    });
  });

  return { server, url, close: () => server.close() };
}

export const sleep = (ms: number): Promise<void> =>
  new Promise((r) => setTimeout(r, ms));
