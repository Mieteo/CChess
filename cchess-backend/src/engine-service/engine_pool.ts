import { EngineServiceError, type EngineBestMove, type EngineLimit } from './types';

export interface SearchEngine {
  bestMove(fen: string, limit?: EngineLimit): Promise<EngineBestMove>;
  dispose(): void;
}

export interface EnginePoolOptions {
  maxConcurrency: number;
  maxQueueSize: number;
  taskTimeoutMs: number;
  createEngine: () => SearchEngine;
}

interface WorkerState {
  engine: SearchEngine;
  busy: boolean;
}

interface SearchTask {
  fen: string;
  limit: EngineLimit;
  resolve: (value: EngineBestMove) => void;
  reject: (error: Error) => void;
}

export class EnginePool {
  private readonly workers: WorkerState[];
  private readonly queue: SearchTask[] = [];
  private disposed = false;

  constructor(private readonly options: EnginePoolOptions) {
    if (options.maxConcurrency < 1) {
      throw new Error('maxConcurrency must be at least 1');
    }
    this.workers = Array.from({ length: options.maxConcurrency }, () => ({
      engine: options.createEngine(),
      busy: false,
    }));
  }

  bestMove(fen: string, limit: EngineLimit = {}): Promise<EngineBestMove> {
    if (this.disposed) {
      return Promise.reject(
        new EngineServiceError(503, 'engine-pool-disposed', 'Engine pool has been disposed'),
      );
    }

    return new Promise((resolve, reject) => {
      const task: SearchTask = { fen, limit, resolve, reject };
      const worker = this.workers.find((candidate) => !candidate.busy);
      if (worker) {
        this.run(worker, task);
        return;
      }
      if (this.queue.length >= this.options.maxQueueSize) {
        reject(new EngineServiceError(429, 'engine-overloaded', 'Engine queue is full'));
        return;
      }
      this.queue.push(task);
    });
  }

  stats(): { maxConcurrency: number; busy: number; queued: number; maxQueueSize: number } {
    return {
      maxConcurrency: this.workers.length,
      busy: this.workers.filter((worker) => worker.busy).length,
      queued: this.queue.length,
      maxQueueSize: this.options.maxQueueSize,
    };
  }

  dispose(): void {
    this.disposed = true;
    while (this.queue.length > 0) {
      const task = this.queue.shift();
      task?.reject(new EngineServiceError(503, 'engine-pool-disposed', 'Engine pool disposed'));
    }
    for (const worker of this.workers) worker.engine.dispose();
  }

  private run(worker: WorkerState, task: SearchTask): void {
    worker.busy = true;
    const timeoutMs = task.limit.timeoutMs ?? this.options.taskTimeoutMs;
    const limit = { ...task.limit, timeoutMs };
    void withTimeout(worker.engine.bestMove(task.fen, limit), timeoutMs)
      .then(task.resolve)
      .catch((error: Error) => {
        task.reject(error);
        this.replaceWorker(worker);
      })
      .finally(() => {
        worker.busy = false;
        this.drain();
      });
  }

  private drain(): void {
    if (this.disposed) return;
    let worker = this.workers.find((candidate) => !candidate.busy);
    while (worker && this.queue.length > 0) {
      const task = this.queue.shift();
      if (!task) return;
      this.run(worker, task);
      worker = this.workers.find((candidate) => !candidate.busy);
    }
  }

  private replaceWorker(worker: WorkerState): void {
    try {
      worker.engine.dispose();
    } catch {
      // Ignore cleanup failures; a fresh process is created below.
    }
    if (!this.disposed) worker.engine = this.options.createEngine();
  }
}

function withTimeout<T>(promise: Promise<T>, timeoutMs: number): Promise<T> {
  return new Promise((resolve, reject) => {
    const timer = setTimeout(() => {
      reject(new EngineServiceError(504, 'engine-timeout', 'Engine task timed out'));
    }, timeoutMs);
    promise.then(
      (value) => {
        clearTimeout(timer);
        resolve(value);
      },
      (error: Error) => {
        clearTimeout(timer);
        reject(error);
      },
    );
  });
}
