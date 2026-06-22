import { createWriteStream, existsSync, mkdirSync, writeFileSync } from 'node:fs';
import path from 'node:path';
import type { Writable } from 'node:stream';
import type { InvariantViolation } from '../invariants';

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
  users: number;
  durationMs: number;
  elapsedMs: number;
  gamesStarted: number;
  gamesEnded: number;
  moves: number;
  chatMessages: number;
  errors: number;
  roomsAfterDrain: number;
  invariantViolations: InvariantViolation[];
  reportDir: string;
  replay: string;
  failure?: string;
}

export class SimReporter {
  readonly reportDir: string;
  readonly eventsPath: string;
  private readonly stream: Writable;

  constructor(runId: string) {
    this.reportDir = path.resolve(__dirname, '..', 'reports', runId);
    this.eventsPath = path.join(this.reportDir, 'events.jsonl');
    if (!existsSync(this.reportDir)) mkdirSync(this.reportDir, { recursive: true });
    this.stream = createWriteStream(this.eventsPath, { flags: 'a' });
  }

  event(event: SimEvent): void {
    this.stream.write(`${JSON.stringify(event)}\n`);
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
        `seed: ${summary.seed}`,
        `target: ${summary.target}`,
        `users: ${summary.users}`,
        `events: ${this.eventsPath}`,
        `replay: ${summary.replay}`,
        '',
      ];
      writeFileSync(path.join(this.reportDir, 'failure.md'), lines.join('\n'), 'utf8');
    }
  }
}
