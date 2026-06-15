// A scripted WebSocket client ("bot") that speaks the CChess protocol. This is
// the reusable building block for BOTH the headless scenario runner and the
// live dashboard — a bot is one simulated user whose every action is a method
// call, never a manual UI gesture.

import { WebSocket } from 'ws';

export interface Msg {
  type: string;
  [k: string]: unknown;
}

export class Bot {
  readonly uid: string;
  private ws?: WebSocket;
  private readonly url: string;
  /// Every message received from the server, newest last (capped).
  readonly log: Msg[] = [];
  private readonly waiters: Array<{
    match: (m: Msg) => boolean;
    resolve: (m: Msg) => void;
    reject: (e: Error) => void;
    timer: NodeJS.Timeout;
  }> = [];
  private readonly queue: Msg[] = [];

  /// Last room/color the server told this bot about — handy for assertions.
  roomId?: string;
  color?: 'red' | 'black';

  constructor(url: string, uid: string) {
    this.url = url;
    this.uid = uid;
  }

  // ── connection lifecycle ────────────────────────────────────────────────
  async connect(): Promise<void> {
    const ws = new WebSocket(this.url);
    this.ws = ws;
    ws.on('message', (data) => this.onMessage(data.toString()));
    await new Promise<void>((resolve, reject) => {
      ws.once('open', () => resolve());
      ws.once('error', reject);
    });
  }

  /// Connect + complete the auth handshake. In the in-process lab the token IS
  /// the uid (stub auth); against a real server pass a genuine Firebase ID
  /// token (the smoke test mints one via anonymous sign-in).
  async connectAuthed(token?: string): Promise<void> {
    await this.connect();
    await this.waitType('welcome');
    this.send({ type: 'auth', token: token ?? this.uid });
    await this.waitType('authed');
  }

  /// Graceful close (server sees a normal WS close → reconnect grace path).
  close(): Promise<void> {
    const ws = this.ws;
    if (!ws || ws.readyState === WebSocket.CLOSED) return Promise.resolve();
    return new Promise((resolve) => {
      ws.once('close', () => resolve());
      ws.close();
    });
  }

  /// Hard drop — terminate the underlying socket to simulate a yanked network
  /// cable / killed app (no clean close frame). Server detects it via the
  /// 'close' event just the same, but this models the abrupt case.
  drop(): void {
    this.ws?.terminate();
  }

  private onMessage(raw: string): void {
    let msg: Msg;
    try {
      msg = JSON.parse(raw) as Msg;
    } catch {
      return;
    }
    // Track room/color hints so scenarios can assert without re-parsing.
    if (typeof msg.roomId === 'string') this.roomId = msg.roomId;
    if (msg.type === 'game-start' || msg.type === 'reconnected') {
      const c = msg.yourColor;
      if (c === 'red' || c === 'black') this.color = c;
    }
    this.log.push(msg);
    if (this.log.length > 200) this.log.splice(0, this.log.length - 200);

    const i = this.waiters.findIndex((w) => w.match(msg));
    if (i >= 0) {
      const [w] = this.waiters.splice(i, 1);
      clearTimeout(w.timer);
      w.resolve(msg);
    } else {
      this.queue.push(msg);
    }
  }

  // ── send + await ──────────────────────────────────────────────────────
  send(obj: Record<string, unknown>): void {
    this.ws?.send(JSON.stringify(obj));
  }

  waitFor(match: (m: Msg) => boolean, timeoutMs = 4000): Promise<Msg> {
    const i = this.queue.findIndex(match);
    if (i >= 0) return Promise.resolve(this.queue.splice(i, 1)[0]);
    return new Promise((resolve, reject) => {
      const timer = setTimeout(() => {
        const j = this.waiters.findIndex((w) => w.resolve === resolve);
        if (j >= 0) this.waiters.splice(j, 1);
        reject(
          new Error(
            `[${this.uid}] timeout waiting for message; recent=${JSON.stringify(
              this.log.slice(-6).map((m) => m.type),
            )}`,
          ),
        );
      }, timeoutMs);
      this.waiters.push({ match, resolve, reject, timer });
    });
  }

  waitType(type: string, timeoutMs?: number): Promise<Msg> {
    return this.waitFor((m) => m.type === type, timeoutMs);
  }

  /// Assert that a given message type does NOT arrive within `ms`.
  async expectNoMessage(type: string, ms = 600): Promise<void> {
    try {
      await this.waitType(type, ms);
      throw new Error(`[${this.uid}] unexpected '${type}' arrived`);
    } catch (e) {
      if (e instanceof Error && /timeout/.test(e.message)) return;
      throw e;
    }
  }

  // ── protocol convenience verbs ──────────────────────────────────────────
  createRoom(clockMs?: number): void {
    this.send(clockMs ? { type: 'create-room', clockMs } : { type: 'create-room' });
  }
  joinRoom(roomId: string): void {
    this.send({ type: 'join-room', roomId });
  }
  findMatch(clockMs?: number): void {
    this.send(clockMs ? { type: 'find-match', clockMs } : { type: 'find-match' });
  }
  cancelMatching(): void {
    this.send({ type: 'cancel-matching' });
  }
  reconnectRoom(roomId: string): void {
    this.send({ type: 'reconnect-room', roomId });
  }
  spectateRoom(roomId: string): void {
    this.send({ type: 'spectate-room', roomId });
  }
  listActiveRooms(): void {
    this.send({ type: 'list-active-rooms' });
  }
  move(uci: string): void {
    this.send({ type: 'move', uci });
  }
  resign(): void {
    this.send({ type: 'resign' });
  }
  leaveRoom(): void {
    this.send({ type: 'leave-room' });
  }
}
