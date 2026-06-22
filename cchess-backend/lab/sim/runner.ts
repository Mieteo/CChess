import { readFileSync } from 'node:fs';
import path from 'node:path';

import { cleanupFirebaseRun, type SimGameFact } from './firebase_probe';
import { SimWorld, type SimConfig, type SimTarget } from './world';
import type { SimAuthMode } from './firebase_auth';

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
  authMode?: SimAuthMode;
  firebaseApiKey?: string;
  firebaseIdTokens?: string[];
  uidPrefix?: string;
  verifyPersistence?: boolean;
  cleanupAfter?: boolean;
  cleanupDryRun?: boolean;
  cleanupDeleteUserDocs?: boolean;
  cleanupDeleteAuthUsers?: boolean;
  cleanupRunId?: string;
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
    authMode: nonEmpty(process.env.SIM_AUTH_MODE) as SimAuthMode | undefined,
    firebaseApiKey: nonEmpty(process.env.FIREBASE_API_KEY),
    firebaseIdTokens: splitCsv(process.env.SIM_FIREBASE_ID_TOKENS),
    uidPrefix: nonEmpty(process.env.SIM_UID_PREFIX),
    verifyPersistence: flagFromEnv('SIM_VERIFY_PERSISTENCE'),
    cleanupAfter: flagFromEnv('SIM_CLEANUP_AFTER'),
    cleanupDryRun: flagFromEnv('SIM_CLEANUP_DRY_RUN'),
    cleanupDeleteUserDocs: flagFromEnv('SIM_CLEANUP_DELETE_USER_DOCS'),
    cleanupDeleteAuthUsers: flagFromEnv('SIM_CLEANUP_DELETE_AUTH_USERS'),
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
    else if (arg.startsWith('--auth-mode=')) args.authMode = arg.slice('--auth-mode='.length) as SimAuthMode;
    else if (arg.startsWith('--firebase-api-key=')) args.firebaseApiKey = arg.slice('--firebase-api-key='.length);
    else if (arg.startsWith('--firebase-id-tokens=')) args.firebaseIdTokens = splitCsv(arg.slice('--firebase-id-tokens='.length));
    else if (arg.startsWith('--uid-prefix=')) args.uidPrefix = arg.slice('--uid-prefix='.length);
    else if (arg === '--verify-persistence') args.verifyPersistence = true;
    else if (arg === '--no-verify-persistence') args.verifyPersistence = false;
    else if (arg === '--cleanup-after') args.cleanupAfter = true;
    else if (arg === '--cleanup-dry-run') args.cleanupDryRun = true;
    else if (arg === '--cleanup-delete-user-docs') args.cleanupDeleteUserDocs = true;
    else if (arg === '--cleanup-delete-auth-users') args.cleanupDeleteAuthUsers = true;
    else if (arg.startsWith('--cleanup-run-id=')) args.cleanupRunId = arg.slice('--cleanup-run-id='.length);
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
  if (args.authMode !== undefined && !['stub', 'anonymous', 'custom-token', 'id-token-list'].includes(args.authMode)) {
    throw new Error('--auth-mode must be stub, anonymous, custom-token, or id-token-list');
  }
  if (args.target === 'prod-smoke' && (args.users > 4 || args.durationMs > 120_000)) {
    throw new Error('--target=prod-smoke is capped at --users<=4 and --duration<=120s');
  }
  if (args.cleanupRunId && !/^[-_A-Za-z0-9:.]+$/.test(args.cleanupRunId)) {
    throw new Error('--cleanup-run-id contains unsafe characters');
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
  console.log(`persistence: ${summary.persistence.enabled ? `${summary.persistence.ok ? 'ok' : 'fail'} (${summary.persistence.expectedGames} games, ${summary.persistence.recordsChecked} records)` : 'disabled'}`);
  console.log(`cleanup: ${summary.cleanup.enabled ? `${summary.cleanup.recordsDeleted} records, ${summary.cleanup.userDocsDeleted} user docs, ${summary.cleanup.authUsersDeleted} auth users${summary.cleanup.dryRun ? ' (dry-run)' : ''}` : 'disabled'}`);
  console.log(`errors: ${summary.errors}`);
  console.log(`rooms after drain: ${summary.roomsAfterDrain}`);
  console.log(`invariant violations: ${summary.invariantViolations.length}`);
  console.log(`protocol violations: ${summary.protocolViolations.length}`);
  console.log(`events: ${summary.reportDir}\\events.jsonl`);
  console.log(`replay: ${summary.replay}`);
  if (summary.failureRule) console.log(`rule: ${summary.failureRule}`);
  if (summary.engine.lastError) console.log(`engine last error: ${JSON.stringify(summary.engine.lastError)}`);
  if (summary.persistence.error) console.log(`persistence error: ${summary.persistence.error}`);
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
    if (args.cleanupRunId) {
      const cleanup = await cleanupFromReport(args);
      console.log = print;
      console.log(`CLEANUP ${args.cleanupRunId}`);
      console.log(`records deleted: ${cleanup.recordsDeleted}`);
      console.log(`user docs deleted: ${cleanup.userDocsDeleted}`);
      console.log(`auth users deleted: ${cleanup.authUsersDeleted}`);
      console.log(`dry-run: ${cleanup.dryRun}`);
      console.log(`errors: ${cleanup.errors.length}`);
      for (const error of cleanup.errors) console.log(`cleanup error: ${error}`);
      if (cleanup.errors.length > 0) process.exitCode = 1;
      return;
    }
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
      authMode: args.authMode,
      firebaseApiKey: args.firebaseApiKey,
      firebaseIdTokens: args.firebaseIdTokens,
      uidPrefix: args.uidPrefix,
      verifyPersistence: args.verifyPersistence,
      cleanupAfter: args.cleanupAfter,
      cleanupDryRun: args.cleanupDryRun,
      cleanupDeleteUserDocs: args.cleanupDeleteUserDocs,
      cleanupDeleteAuthUsers: args.cleanupDeleteAuthUsers,
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

async function cleanupFromReport(args: CliArgs) {
  const summaryPath = path.resolve(__dirname, '..', 'reports', args.cleanupRunId!, 'summary.json');
  const summary = JSON.parse(readFileSync(summaryPath, 'utf8')) as {
    games?: SimGameFact[];
    identities?: Array<{ uid?: unknown }>;
  };
  const games = Array.isArray(summary.games) ? summary.games : [];
  const uids = Array.isArray(summary.identities)
    ? summary.identities
        .map((identity) => identity.uid)
        .filter((uid): uid is string => typeof uid === 'string' && uid.length > 0)
    : [];
  return cleanupFirebaseRun({
    games,
    uids,
    deleteUserDocs: args.cleanupDeleteUserDocs ?? false,
    deleteAuthUsers: args.cleanupDeleteAuthUsers ?? false,
    dryRun: args.cleanupDryRun ?? false,
  });
}

function nonEmpty(value: string | undefined): string | undefined {
  const trimmed = value?.trim();
  return trimmed ? trimmed : undefined;
}

function splitCsv(value: string | undefined): string[] | undefined {
  const items = value
    ?.split(',')
    .map((item) => item.trim())
    .filter((item) => item.length > 0);
  return items && items.length > 0 ? items : undefined;
}

function flagFromEnv(name: string): boolean | undefined {
  const value = process.env[name];
  if (value === undefined) return undefined;
  return value === '1' || value.toLowerCase() === 'true';
}
