import { SimWorld, type SimConfig, type SimTarget } from './world';

interface CliArgs {
  users: number;
  durationMs: number;
  seed: number;
  target: SimTarget;
  runId: string;
  wsUrl?: string;
  profileName?: string;
  engineUrl?: string;
  engineAuthToken?: string;
  engineTimeoutMs?: number;
  engineConcurrency?: number;
  engineMovetimeMs?: number;
  engineStrict?: boolean;
}

function parseDurationMs(raw: string): number {
  const match = raw.match(/^(\d+)(ms|s|m)?$/);
  if (!match) throw new Error(`invalid duration "${raw}"`);
  const value = Number(match[1]);
  const unit = match[2] ?? 'ms';
  if (unit === 'm') return value * 60_000;
  if (unit === 's') return value * 1000;
  return value;
}

function defaultRunId(): string {
  const iso = new Date().toISOString().replace(/[-:]/g, '').replace(/\..+$/, '');
  return `sim-${iso}`;
}

function parseArgs(argv: string[]): CliArgs {
  const args: CliArgs = {
    users: 10,
    durationMs: 60_000,
    seed: (Date.now() ^ Math.floor(Math.random() * 0xffffffff)) >>> 0,
    target: 'in-process',
    runId: defaultRunId(),
    profileName: nonEmpty(process.env.SIM_PROFILE),
    engineUrl: nonEmpty(process.env.CCHESS_ENGINE_URL ?? process.env.SIM_ENGINE_URL),
    engineAuthToken: nonEmpty(process.env.CCHESS_ENGINE_TOKEN ?? process.env.SIM_ENGINE_TOKEN),
  };
  for (const arg of argv) {
    if (arg.startsWith('--users=')) args.users = Number(arg.slice('--users='.length));
    else if (arg.startsWith('--duration=')) args.durationMs = parseDurationMs(arg.slice('--duration='.length));
    else if (arg.startsWith('--seed=')) args.seed = Number(arg.slice('--seed='.length)) >>> 0;
    else if (arg.startsWith('--target=')) args.target = arg.slice('--target='.length) as SimTarget;
    else if (arg.startsWith('--run-id=')) args.runId = arg.slice('--run-id='.length);
    else if (arg.startsWith('--ws=')) args.wsUrl = arg.slice('--ws='.length);
    else if (arg.startsWith('--profile=')) args.profileName = arg.slice('--profile='.length);
    else if (arg.startsWith('--engine-url=')) args.engineUrl = arg.slice('--engine-url='.length);
    else if (arg.startsWith('--engine-token=')) args.engineAuthToken = arg.slice('--engine-token='.length);
    else if (arg.startsWith('--engine-timeout=')) args.engineTimeoutMs = parseDurationMs(arg.slice('--engine-timeout='.length));
    else if (arg.startsWith('--engine-concurrency=')) args.engineConcurrency = Number(arg.slice('--engine-concurrency='.length));
    else if (arg.startsWith('--engine-movetime=')) args.engineMovetimeMs = parseDurationMs(arg.slice('--engine-movetime='.length));
    else if (arg === '--engine-strict') args.engineStrict = true;
    else if (arg === '--engine-nonstrict') args.engineStrict = false;
    else if (arg === '--replay') {
      throw new Error('--replay is reserved for Phase 2 failure replay; use --seed for Phase 1 replay');
    } else {
      throw new Error(`unknown argument ${arg}`);
    }
  }
  if (!Number.isInteger(args.users) || args.users < 2) throw new Error('--users must be an integer >= 2');
  if (!Number.isInteger(args.durationMs) || args.durationMs <= 0) throw new Error('--duration must be positive');
  if (!Number.isInteger(args.seed)) throw new Error('--seed must be an integer');
  if (args.engineTimeoutMs !== undefined && (!Number.isInteger(args.engineTimeoutMs) || args.engineTimeoutMs <= 0)) {
    throw new Error('--engine-timeout must be positive');
  }
  if (args.engineMovetimeMs !== undefined && (!Number.isInteger(args.engineMovetimeMs) || args.engineMovetimeMs <= 0)) {
    throw new Error('--engine-movetime must be positive');
  }
  if (args.engineConcurrency !== undefined && (!Number.isInteger(args.engineConcurrency) || args.engineConcurrency < 1)) {
    throw new Error('--engine-concurrency must be an integer >= 1');
  }
  return args;
}

function printSummary(summary: Awaited<ReturnType<SimWorld['execute']>>): void {
  const status = summary.ok ? 'PASS' : 'FAIL';
  console.log(`${status} ${summary.runId}`);
  console.log(`seed: ${summary.seed}`);
  console.log(`profile: ${summary.profile}`);
  console.log(`users: ${summary.users}`);
  console.log(`duration: ${summary.durationMs}ms`);
  console.log(`personas: ${JSON.stringify(summary.personaCounts)}`);
  console.log(`brains: ${JSON.stringify(summary.brainCounts)}`);
  console.log(`games started: ${summary.gamesStarted}`);
  console.log(`games ended: ${summary.gamesEnded}`);
  console.log(`private rooms: ${summary.privateRooms}`);
  console.log(`rematches: ${summary.rematches}`);
  console.log(`moves: ${summary.moves}`);
  console.log(`reconnects: ${summary.reconnects}`);
  console.log(`spectator sessions: ${summary.spectatorSessions}`);
  console.log(`abuse actions: ${summary.abuseActions}`);
  console.log(`abuse errors: ${summary.abuseErrors}`);
  console.log(`chat messages: ${summary.chatMessages}`);
  console.log(`engine attempts: ${summary.engine.attempts}`);
  console.log(`engine http calls: ${summary.engine.httpCalls}`);
  console.log(`engine errors: ${summary.engine.errors}`);
  console.log(`engine fallbacks: ${summary.engine.fallbacks}`);
  console.log(`engine cache hits: ${summary.engine.cacheHits}`);
  console.log(`engine latency p95: ${summary.engine.latency.p95Ms}ms`);
  console.log(`errors: ${summary.errors}`);
  console.log(`rooms after drain: ${summary.roomsAfterDrain}`);
  console.log(`invariant violations: ${summary.invariantViolations.length}`);
  console.log(`protocol violations: ${summary.protocolViolations.length}`);
  console.log(`events: ${summary.reportDir}\\events.jsonl`);
  console.log(`replay: ${summary.replay}`);
  if (summary.failureRule) console.log(`rule: ${summary.failureRule}`);
  if (summary.engine.lastError) console.log(`engine last error: ${JSON.stringify(summary.engine.lastError)}`);
  if (summary.failure) console.log(`failure: ${summary.failure}`);
}

async function main(): Promise<void> {
  const print = console.log.bind(console);
  if (!process.env.LAB_VERBOSE) {
    console.log = () => {};
    console.warn = () => {};
    console.error = () => {};
  }
  try {
    const args = parseArgs(process.argv.slice(2));
    const config: SimConfig = {
      runId: args.runId,
      seed: args.seed,
      target: args.target,
      users: args.users,
      durationMs: args.durationMs,
      wsUrl: args.wsUrl,
      profileName: args.profileName,
      engineUrl: args.engineUrl,
      engineAuthToken: args.engineAuthToken,
      engineTimeoutMs: args.engineTimeoutMs,
      engineConcurrency: args.engineConcurrency,
      engineMovetimeMs: args.engineMovetimeMs,
      engineStrict: args.engineStrict,
    };
    const world = new SimWorld(config);
    const summary = await world.execute();
    console.log = print;
    printSummary(summary);
    if (!summary.ok) process.exitCode = 1;
  } catch (e) {
    console.log = print;
    console.error(e instanceof Error ? e.message : String(e));
    process.exitCode = 1;
  }
}

void main();

function nonEmpty(value: string | undefined): string | undefined {
  const trimmed = value?.trim();
  return trimmed ? trimmed : undefined;
}
