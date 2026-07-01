import { spawn, type ChildProcessWithoutNullStreams } from 'child_process';

import { normalizeFen } from './fen';
import { parseBestMoveLine, parseInfoLine } from './uci_parser';
import { EngineServiceError, type EngineBestMove, type EngineLimit } from './types';

interface Waiter {
  predicate: (line: string) => boolean;
  resolve: (line: string) => void;
  reject: (error: Error) => void;
  timer: NodeJS.Timeout;
}

/** MultiPV width used while a blunder roll is active. Pikafish has no native
 * strength dial, so the ELO ladder's 2000-2900 bands fake one: ask for this
 * many candidate lines, then (with probability `limit.blunderRate`) play a
 * weaker one instead of line 1. */
const BLUNDER_MULTIPV = 4;

export interface UciEngineOptions {
  binaryPath: string;
  evalFile?: string;
  threads: number;
  hashMb: number;
  defaultMovetimeMs: number;
  initTimeoutMs: number;
  searchTimeoutMs: number;
  spawnProcess?: (binaryPath: string) => ChildProcessWithoutNullStreams;
}

export class UciEngine {
  private proc: ChildProcessWithoutNullStreams | null = null;
  private initPromise: Promise<void> | null = null;
  private stdoutBuffer = '';
  private waiters: Waiter[] = [];
  private subscribers = new Set<(line: string) => void>();
  private busy = false;
  private disposed = false;
  /** True while MultiPV is raised above 1 for a blunder roll, so we know to
   * reset it. The pool reuses one process across requests, so a leaked
   * MultiPV width would change move ordering/timing for every later search. */
  private multiPvDirty = false;
  private readonly stderrTail: string[] = [];

  constructor(private readonly options: UciEngineOptions) {}

  async start(): Promise<void> {
    if (this.initPromise) return this.initPromise;
    this.initPromise = this.startProcess();
    return this.initPromise;
  }

  async bestMove(fen: string, limit: EngineLimit = {}): Promise<EngineBestMove> {
    if (this.disposed) {
      throw new EngineServiceError(503, 'engine-disposed', 'Engine process has been disposed');
    }
    await this.start();
    if (this.busy) {
      throw new EngineServiceError(503, 'engine-busy', 'Engine process is already searching');
    }

    this.busy = true;
    let scoreCp: number | null = null;
    let depth: number | null = null;
    let pv: string[] = [];
    // MultiPV line index -> that line's top move. Index 1 is always the
    // engine's actual best move; populated regardless of blunderRate so the
    // map is simply empty (besides slot 1) when no blunder roll is wanted.
    const multiPvCandidates = new Map<number, string>();
    const unsubscribe = this.subscribe((line) => {
      const info = parseInfoLine(line);
      if (!info) return;
      const slot = info.multipv ?? 1;
      if (slot === 1) {
        if (info.scoreCp !== undefined) scoreCp = info.scoreCp;
        if (info.depth !== undefined) depth = info.depth;
        if (info.pv !== undefined) pv = info.pv;
      }
      if (info.pv && info.pv.length > 0) {
        multiPvCandidates.set(slot, info.pv[0]);
      }
    });

    try {
      this.writeLine(`position fen ${normalizeFen(fen)}`);
      this.applyBlunderMultiPv(limit);
      const goLimit = limit.depth !== undefined
        ? `depth ${limit.depth}`
        : `movetime ${limit.movetimeMs ?? this.options.defaultMovetimeMs}`;
      this.writeLine(`go ${goLimit}`);
      const line = await this.waitForLine(
        (candidate) => parseBestMoveLine(candidate) !== undefined,
        limit.timeoutMs ?? this.options.searchTimeoutMs,
        'engine-timeout',
      );
      const engineUci = parseBestMoveLine(line) ?? null;
      return {
        uci: this.maybeBlunder(engineUci, limit.blunderRate, multiPvCandidates),
        scoreCp,
        depth,
        pv,
      };
    } finally {
      this.resetMultiPv();
      unsubscribe();
      this.busy = false;
    }
  }

  /// Pikafish has no native strength dial (no `UCI_LimitStrength`/`UCI_Elo`/
  /// `Skill Level` — confirmed absent from the official release). Raise
  /// MultiPV instead so `maybeBlunder` has weaker alternates to fall back to.
  private applyBlunderMultiPv(limit: EngineLimit): void {
    if (limit.blunderRate !== undefined && limit.blunderRate > 0) {
      this.writeLine(`setoption name MultiPV value ${BLUNDER_MULTIPV}`);
      this.multiPvDirty = true;
    }
  }

  /// Restore MultiPV to 1 after a blunder-enabled search so the shared
  /// process doesn't leak extra candidate-line overhead into the next
  /// (possibly full-strength) request. No-op if nothing was changed.
  private resetMultiPv(): void {
    if (!this.multiPvDirty) return;
    this.multiPvDirty = false;
    if (!this.proc || this.disposed) return;
    try {
      this.writeLine('setoption name MultiPV value 1');
    } catch {
      // Engine already gone — nothing to reset.
    }
  }

  /// With probability `blunderRate`, replace the engine's actual best move
  /// with a weaker MultiPV alternate (line 2..N) — the same blunder-band idea
  /// as the local minimax engine, since Pikafish itself can't be told to play
  /// below full strength.
  private maybeBlunder(
    bestUci: string | null,
    blunderRate: number | undefined,
    candidates: Map<number, string>,
  ): string | null {
    if (bestUci === null || !blunderRate || blunderRate <= 0) return bestUci;
    if (Math.random() >= blunderRate) return bestUci;
    const alternates = [...candidates.entries()]
      .filter(([slot]) => slot > 1)
      .map(([, uci]) => uci);
    if (alternates.length === 0) return bestUci;
    return alternates[Math.floor(Math.random() * alternates.length)];
  }

  dispose(): void {
    this.disposed = true;
    this.rejectAll(new EngineServiceError(503, 'engine-disposed', 'Engine process disposed'));
    if (this.proc && !this.proc.killed) {
      this.proc.kill('SIGKILL');
    }
    this.proc = null;
  }

  private async startProcess(): Promise<void> {
    const proc = this.options.spawnProcess
      ? this.options.spawnProcess(this.options.binaryPath)
      : spawn(this.options.binaryPath, [], { stdio: 'pipe' });
    this.proc = proc;

    proc.stdout.setEncoding('utf8');
    proc.stderr.setEncoding('utf8');
    proc.stdout.on('data', (chunk: string) => this.handleStdout(chunk));
    proc.stderr.on('data', (chunk: string) => this.handleStderr(chunk));
    proc.once('exit', (code, signal) => {
      const reason = `Pikafish exited code=${code ?? 'null'} signal=${signal ?? 'null'}`;
      this.rejectAll(new EngineServiceError(503, 'engine-exit', reason));
      this.proc = null;
      this.initPromise = null;
    });
    proc.once('error', (error) => {
      this.rejectAll(new EngineServiceError(503, 'engine-error', error.message));
      this.proc = null;
      this.initPromise = null;
    });

    this.writeLine('uci');
    await this.waitForLine((line) => line === 'uciok', this.options.initTimeoutMs, 'engine-init-timeout');
    if (this.options.evalFile) {
      this.writeLine(`setoption name EvalFile value ${this.options.evalFile}`);
    }
    this.writeLine(`setoption name Threads value ${this.options.threads}`);
    this.writeLine(`setoption name Hash value ${this.options.hashMb}`);
    this.writeLine('isready');
    await this.waitForLine((line) => line === 'readyok', this.options.initTimeoutMs, 'engine-init-timeout');
  }

  private writeLine(line: string): void {
    const proc = this.proc;
    if (!proc) {
      throw new EngineServiceError(503, 'engine-not-started', 'Engine process is not started');
    }
    proc.stdin.write(`${line}\n`);
  }

  private waitForLine(
    predicate: (line: string) => boolean,
    timeoutMs: number,
    timeoutCode: string,
  ): Promise<string> {
    return new Promise((resolve, reject) => {
      const waiter: Waiter = {
        predicate,
        resolve,
        reject,
        timer: setTimeout(() => {
          this.waiters = this.waiters.filter((w) => w !== waiter);
          reject(new EngineServiceError(504, timeoutCode, 'Timed out waiting for engine response'));
        }, timeoutMs),
      };
      this.waiters.push(waiter);
    });
  }

  private subscribe(callback: (line: string) => void): () => void {
    this.subscribers.add(callback);
    return () => this.subscribers.delete(callback);
  }

  private handleStdout(chunk: string): void {
    this.stdoutBuffer += chunk;
    let newline = this.stdoutBuffer.search(/\r?\n/);
    while (newline >= 0) {
      const line = this.stdoutBuffer.slice(0, newline).trim();
      this.stdoutBuffer = this.stdoutBuffer.slice(
        this.stdoutBuffer[newline] === '\r' ? newline + 2 : newline + 1,
      );
      if (line.length > 0) this.handleLine(line);
      newline = this.stdoutBuffer.search(/\r?\n/);
    }
  }

  private handleLine(line: string): void {
    for (const subscriber of this.subscribers) subscriber(line);
    const index = this.waiters.findIndex((waiter) => waiter.predicate(line));
    if (index < 0) return;
    const [waiter] = this.waiters.splice(index, 1);
    clearTimeout(waiter.timer);
    waiter.resolve(line);
  }

  private handleStderr(chunk: string): void {
    for (const line of chunk.split(/\r?\n/)) {
      const trimmed = line.trim();
      if (trimmed.length === 0) continue;
      this.stderrTail.push(trimmed);
      if (this.stderrTail.length > 20) this.stderrTail.shift();
    }
  }

  private rejectAll(error: Error): void {
    const waiters = this.waiters.splice(0);
    for (const waiter of waiters) {
      clearTimeout(waiter.timer);
      waiter.reject(error);
    }
  }
}
