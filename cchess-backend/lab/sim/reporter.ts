import { createWriteStream, existsSync, mkdirSync, writeFileSync } from 'node:fs';
import path from 'node:path';
import type { Writable } from 'node:stream';
import type { InvariantViolation } from '../invariants';
import type { EngineMetricsSummary } from './engine_metrics';
import type { ProtocolViolation } from './monitor';

export interface SimEvent {
  runId: string;
  ts: number;
  type: string;
  agentId?: string;
  uid?: string;
  roomId?: string;
  data?: unknown;
}

export interface SimSummary {
  ok: boolean;
  runId: string;
  seed: number;
  target: string;
  profile: string;
  users: number;
  durationMs: number;
  elapsedMs: number;
  gamesStarted: number;
  gamesEnded: number;
  moves: number;
  chatMessages: number;
  errors: number;
  reconnects: number;
  spectatorSessions: number;
  abuseActions: number;
  abuseErrors: number;
  privateRooms: number;
  rematches: number;
  personaCounts: Record<string, number>;
  brainCounts: Record<string, number>;
  engine: EngineMetricsSummary;
  roomsAfterDrain: number;
  invariantViolations: InvariantViolation[];
  protocolViolations: ProtocolViolation[];
  reportDir: string;
  replay: string;
  failureRule?: string;
  failureRoomId?: string;
  failureAgents?: string[];
  recentEvents: SimEvent[];
  failure?: string;
}

export class SimReporter {
  readonly reportDir: string;
  readonly eventsPath: string;
  private readonly stream: Writable;
  private readonly recent: SimEvent[] = [];

  constructor(runId: string) {
    this.reportDir = path.resolve(__dirname, '..', 'reports', runId);
    this.eventsPath = path.join(this.reportDir, 'events.jsonl');
    if (!existsSync(this.reportDir)) mkdirSync(this.reportDir, { recursive: true });
    this.stream = createWriteStream(this.eventsPath, { flags: 'a' });
  }

  event(event: SimEvent): void {
    this.recent.push(event);
    if (this.recent.length > 40) this.recent.splice(0, this.recent.length - 40);
    this.stream.write(`${JSON.stringify(event)}\n`);
  }

  recentEvents(): SimEvent[] {
    return [...this.recent];
  }

  async close(): Promise<void> {
    await new Promise<void>((resolve, reject) => {
      this.stream.end((err: Error | null | undefined) => {
        if (err) reject(err);
        else resolve();
      });
    });
  }

  writeSummary(summary: SimSummary): void {
    writeFileSync(
      path.join(this.reportDir, 'summary.json'),
      `${JSON.stringify(summary, null, 2)}\n`,
      'utf8',
    );
    if (!summary.ok) {
      const lines = [
        `# ${summary.runId}`,
        '',
        `failure: ${summary.failure ?? 'unknown'}`,
        summary.failureRule ? `rule: ${summary.failureRule}` : undefined,
        summary.failureRoomId ? `roomId: ${summary.failureRoomId}` : undefined,
        summary.failureAgents?.length ? `agents: ${summary.failureAgents.join(', ')}` : undefined,
        `seed: ${summary.seed}`,
        `target: ${summary.target}`,
        `profile: ${summary.profile}`,
        `users: ${summary.users}`,
        `engine: ${summary.engine.errors}/${summary.engine.attempts} errors, ${summary.engine.fallbacks} fallbacks`,
        `events: ${this.eventsPath}`,
        `replay: ${summary.replay}`,
        '',
        '## Recent events',
        '',
        ...summary.recentEvents.map((event) => `- ${JSON.stringify(event)}`),
        '',
      ];
      writeFileSync(
        path.join(this.reportDir, 'failure.md'),
        lines.filter((line): line is string => line !== undefined).join('\n'),
        'utf8',
      );
    }
  }
}
