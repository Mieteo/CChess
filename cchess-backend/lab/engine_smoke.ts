// Black-box smoke test for the standalone cchess-engine HTTP service.
//
// Default target is the deployed Render engine service. For local Docker/dev:
//
//   CCHESS_ENGINE_URL=http://localhost:8090 ENGINE_SMOKE_AUTH=disabled npm run engine:smoke
//
// Auth modes:
//   ENGINE_SMOKE_AUTH=auto      Probe auth automatically (default).
//   ENGINE_SMOKE_AUTH=required  Require Bearer auth and mint/use a Firebase token.
//   ENGINE_SMOKE_AUTH=disabled  Send no token (for ENGINE_AUTH_DISABLED=1 services).
//
// Optional quota smoke:
//   ENGINE_SMOKE_CHECK_QUOTA=1 npm run engine:smoke
//   npm run engine:smoke:quota
//   npm run engine:smoke -- --quota --quota-limit=3
//
// Quota smoke mints a fresh anonymous Firebase user, calls /engine/hint until
// the configured free limit is exhausted, then expects quota-exceeded.

import { INITIAL_FEN, parseUci, PieceColor, uciOfMove, XiangqiGame } from '../src/engine';

// Fixed positions for the FEN/UCI cross-check (risk ⚠️A): each must have at
// least one legal move, so the engine's bestmove proves Pikafish and our board
// agree on coordinates — a disagreement would map its reply to an illegal move.
const FIXED_POSITIONS: { name: string; fen: string }[] = [
  { name: 'initial', fen: INITIAL_FEN },
  {
    name: 'after central cannon h2e2 (black to move)',
    fen: 'rnbakabnr/9/1c5c1/p1p1p1p1p/9/9/P1P1P1P1P/1C2C4/9/RNBAKABNR b - - 1 1',
  },
  {
    name: 'rook-and-king endgame (red to move)',
    fen: '4k4/9/9/9/9/9/9/9/4R4/4K4 w - - 0 1',
  },
];

const ENGINE_URL = normalizeBaseUrl(
  nonEmptyEnv('CCHESS_ENGINE_URL') ?? 'https://cchess-engine.onrender.com',
);
const API_KEY =
  nonEmptyEnv('FIREBASE_API_KEY') ?? 'AIzaSyBIoJ-uY79BtqM8nMkd4RfhzoQ_xqdDExY';
const REQUEST_TIMEOUT_MS = envInt('ENGINE_SMOKE_REQUEST_TIMEOUT_MS', 20_000);
const MOVETIME_MS = envInt('ENGINE_SMOKE_MOVETIME_MS', 120);
const MAX_BEST_MOVE_MS = envInt('ENGINE_SMOKE_MAX_BEST_MOVE_MS', 15_000);
const CHECK_QUOTA = flagEnabled('ENGINE_SMOKE_CHECK_QUOTA', 'quota');
const HINT_QUOTA_LIMIT = cliOrEnvInt('quota-limit', 'ENGINE_SMOKE_HINT_QUOTA_LIMIT', 3);

const UCI_REGEX = /^[a-i][0-9][a-i][0-9]$/;

type AuthMode = 'auto' | 'required' | 'disabled';

interface AnonUser {
  idToken: string;
  uid: string;
}

interface AuthContext {
  required: boolean;
  token?: string;
}

interface HttpJson {
  status: number;
  body: unknown;
  elapsedMs: number;
}

async function main(): Promise<void> {
  console.log(`\nCChess engine smoke test -> ${ENGINE_URL}\n`);

  const failures: { name: string; error: string }[] = [];
  let passed = 0;
  let auth: AuthContext | undefined;

  async function run(name: string, fn: () => Promise<void>): Promise<void> {
    const t0 = Date.now();
    try {
      await fn();
      console.log(`  PASS ${name} (${Date.now() - t0}ms)`);
      passed++;
    } catch (e) {
      console.log(`  FAIL ${name} (${Date.now() - t0}ms)`);
      failures.push({ name, error: e instanceof Error ? e.message : String(e) });
    }
  }

  await run('health reports a live engine pool', async () => {
    const { body } = await getJson('/health');
    const health = assertRecord(body, 'health body');
    assert(health.ok === true, 'health.ok should be true');
    assert(health.engine === true, 'health.engine should be true (PIKAFISH_PATH configured)');
    assert(isRecord(health.stats) || health.stats === null, 'health.stats should be an object or null');
  });

  await run('auth mode is explicit and validation runs before engine search', async () => {
    auth = await resolveAuthContext();
  });

  const resolvedAuth = auth;
  if (resolvedAuth !== undefined && failures.length === 0) {
    await run('invalid FEN is rejected without touching Pikafish search', async () => {
      const res = await postJson(
        '/engine/best-move',
        { fen: 'not-a-fen', movetimeMs: MOVETIME_MS },
        resolvedAuth,
        [400],
      );
      const body = assertRecord(res.body, 'invalid-fen body');
      assert(body.code === 'invalid-fen', `expected invalid-fen, got ${String(body.code)}`);
    });

    await run('best-move returns a valid Xiangqi UCI move within budget', async () => {
      const res = await postJson(
        '/engine/best-move',
        { fen: INITIAL_FEN, movetimeMs: MOVETIME_MS },
        resolvedAuth,
        [200],
      );
      assert(
        res.elapsedMs <= MAX_BEST_MOVE_MS,
        `best-move exceeded budget: ${res.elapsedMs}ms > ${MAX_BEST_MOVE_MS}ms`,
      );
      assertBestMove(res.body, 'best-move');
    });

    await run('repeating best-move hits the service cache', async () => {
      await postJson('/engine/best-move', { fen: INITIAL_FEN, movetimeMs: MOVETIME_MS }, resolvedAuth, [200]);
      const second = await postJson(
        '/engine/best-move',
        { fen: INITIAL_FEN, movetimeMs: MOVETIME_MS },
        resolvedAuth,
        [200],
      );
      const body = assertBestMove(second.body, 'cached best-move');
      assert(body.cached === true, 'second identical best-move should report cached=true');
    });

    await run('hint endpoint returns the same response shape', async () => {
      const res = await postJson('/engine/hint', { fen: INITIAL_FEN, movetimeMs: MOVETIME_MS }, resolvedAuth, [200]);
      assertBestMove(res.body, 'hint');
    });

    await run('analyze endpoint accepts a legal move list', async () => {
      const uci = firstLegalRedUci();
      const res = await postJson(
        '/engine/analyze',
        { startingFen: INITIAL_FEN, movesUci: [uci], movetimeMs: MOVETIME_MS },
        resolvedAuth,
        [200],
      );
      const body = assertRecord(res.body, 'analyze body');
      assert(Array.isArray(body.perMove), 'analyze.perMove should be an array');
      assert(body.perMove.length === 1, `expected 1 analyzed move, got ${body.perMove.length}`);
      const first = assertRecord(body.perMove[0], 'first analyzed move');
      assert(first.uci === uci, `analyze should echo ${uci}, got ${String(first.uci)}`);
      assert(isRecord(body.summary), 'analyze.summary should be an object');
    });

    await run("Pikafish's best move is legal on our board for fixed positions", async () => {
      for (const { name, fen } of FIXED_POSITIONS) {
        const res = await postJson(
          '/engine/best-move',
          { fen, movetimeMs: MOVETIME_MS },
          resolvedAuth,
          [200],
        );
        const body = assertBestMove(res.body, `best-move ${name}`);
        assert(
          typeof body.uci === 'string',
          `expected a move for ${name}, got ${String(body.uci)}`,
        );
        assertLegalUciFor(fen, body.uci, name);
      }
    });

    if (CHECK_QUOTA) {
      await run('quota limit eventually returns quota-exceeded', async () => {
        assert(resolvedAuth.required === true, 'quota smoke needs auth so each run can use a fresh uid');
        assert(
          HINT_QUOTA_LIMIT >= 1,
          `ENGINE_SMOKE_HINT_QUOTA_LIMIT/--quota-limit must be >= 1, got ${HINT_QUOTA_LIMIT}`,
        );
        const quotaUser = await anonSignIn();
        const quotaAuth: AuthContext = { required: true, token: quotaUser.idToken };
        for (let i = 0; i < HINT_QUOTA_LIMIT; i++) {
          const res = await postJson('/engine/hint', { fen: INITIAL_FEN, movetimeMs: MOVETIME_MS }, quotaAuth, [200]);
          assertBestMove(res.body, `quota hint ${i + 1}/${HINT_QUOTA_LIMIT}`);
        }
        const limited = await postJson(
          '/engine/hint',
          { fen: INITIAL_FEN, movetimeMs: MOVETIME_MS },
          quotaAuth,
          [429],
        );
        const body = assertRecord(limited.body, 'quota error body');
        assert(
          body.code === 'quota-exceeded',
          `expected quota-exceeded, got ${String(body.code)}`,
        );
      });
    } else {
      console.log('  SKIP quota smoke (set ENGINE_SMOKE_CHECK_QUOTA=1 or pass --quota to enable)\n');
    }
  }

  console.log(`${passed}/${passed + failures.length} passed`);
  if (failures.length > 0) {
    console.log('\nFailures:');
    for (const f of failures) console.log(`  FAIL ${f.name}\n    ${f.error}`);
    process.exitCode = 1;
  }
  console.log('');
}

async function resolveAuthContext(): Promise<AuthContext> {
  const mode = authMode();
  const probe = await postJsonRaw(
    '/engine/best-move',
    { fen: 'not-a-fen', movetimeMs: MOVETIME_MS },
    undefined,
    [400, 401],
  );
  const actualRequiresAuth = probe.status === 401;

  if (mode === 'required') {
    assert(actualRequiresAuth, `expected auth-required service, got HTTP ${probe.status}`);
  } else if (mode === 'disabled') {
    assert(!actualRequiresAuth, 'expected no-auth service, but missing token returned 401');
    return { required: false };
  }

  if (!actualRequiresAuth) return { required: false };
  const token = await resolveToken();
  return { required: true, token };
}

async function resolveToken(): Promise<string> {
  const supplied =
    nonEmptyEnv('ENGINE_FIREBASE_ID_TOKEN') ??
    nonEmptyEnv('FIREBASE_ID_TOKEN') ??
    nonEmptyEnv('FIREBASE_ID_TOKEN_A');
  if (supplied !== undefined) return supplied;
  const user = await anonSignIn();
  return user.idToken;
}

async function anonSignIn(): Promise<AnonUser> {
  const res = await fetch(
    `https://identitytoolkit.googleapis.com/v1/accounts:signUp?key=${API_KEY}`,
    {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify({ returnSecureToken: true }),
    },
  );
  const data = (await res.json()) as {
    idToken?: string;
    localId?: string;
    error?: { message?: string };
  };
  if (!res.ok || !data.idToken || !data.localId) {
    const why = data.error?.message ?? JSON.stringify(data);
    throw new Error(
      `anonymous sign-in failed (${why}). Enable Anonymous auth or pass ENGINE_FIREBASE_ID_TOKEN.`,
    );
  }
  return { idToken: data.idToken, uid: data.localId };
}

async function getJson(path: string): Promise<HttpJson> {
  return requestJson(path, { method: 'GET' }, [200]);
}

async function postJson(
  path: string,
  body: unknown,
  auth: AuthContext,
  expectedStatuses: number[],
): Promise<HttpJson> {
  return postJsonRaw(path, body, auth.required ? auth.token : undefined, expectedStatuses);
}

async function postJsonRaw(
  path: string,
  body: unknown,
  token: string | undefined,
  expectedStatuses: number[],
): Promise<HttpJson> {
  const headers: Record<string, string> = { 'content-type': 'application/json' };
  if (token !== undefined) headers.authorization = `Bearer ${token}`;
  return requestJson(
    path,
    {
      method: 'POST',
      headers,
      body: JSON.stringify(body),
    },
    expectedStatuses,
  );
}

async function requestJson(
  path: string,
  init: RequestInit,
  expectedStatuses: number[],
): Promise<HttpJson> {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), REQUEST_TIMEOUT_MS);
  const started = Date.now();
  try {
    const res = await fetch(urlFor(path), { ...init, signal: controller.signal });
    const elapsedMs = Date.now() - started;
    const text = await res.text();
    const body = text.length === 0 ? null : JSON.parse(text);
    assert(
      expectedStatuses.includes(res.status),
      `expected HTTP ${expectedStatuses.join('/')} for ${path}, got ${res.status}: ${text}`,
    );
    return { status: res.status, body, elapsedMs };
  } catch (e) {
    if (e instanceof Error && e.name === 'AbortError') {
      throw new Error(`${path} timed out after ${REQUEST_TIMEOUT_MS}ms`);
    }
    throw e;
  } finally {
    clearTimeout(timer);
  }
}

function assertBestMove(body: unknown, label: string): Record<string, unknown> {
  const data = assertRecord(body, `${label} body`);
  assert(
    data.uci === null || (typeof data.uci === 'string' && UCI_REGEX.test(data.uci)),
    `${label}.uci should be null or Xiangqi UCI, got ${String(data.uci)}`,
  );
  assert(
    data.scoreCp === null || typeof data.scoreCp === 'number',
    `${label}.scoreCp should be number or null`,
  );
  assert(
    data.depth === null || typeof data.depth === 'number',
    `${label}.depth should be number or null`,
  );
  assert(Array.isArray(data.pv), `${label}.pv should be an array`);
  return data;
}

function assertLegalUciFor(fen: string, uci: string, label: string): void {
  assert(UCI_REGEX.test(uci), `${label}: engine returned non-UCI move ${uci}`);
  const parsed = parseUci(uci);
  assert(parsed !== null, `${label}: could not parse engine move ${uci}`);
  const game = XiangqiGame.fromFen(fen);
  assert(
    game.isValidMove(parsed.from, parsed.to),
    `${label}: engine move ${uci} is NOT legal on our board for fen "${fen}" ` +
      '(Pikafish/our coordinate convention may disagree)',
  );
}

function firstLegalRedUci(): string {
  const game = XiangqiGame.initial();
  for (const [pos, piece] of game.board.occupied()) {
    if (piece.color !== PieceColor.Red) continue;
    const moves = game.getValidMoves(pos);
    if (moves.length > 0) return uciOfMove(pos, moves[0]);
  }
  throw new Error('no legal red move from the initial position');
}

function authMode(): AuthMode {
  if (process.env.ENGINE_SMOKE_NO_AUTH === '1') return 'disabled';
  const raw = (process.env.ENGINE_SMOKE_AUTH ?? 'auto').toLowerCase();
  if (raw === 'required' || raw === 'disabled' || raw === 'auto') return raw;
  throw new Error(`unsupported ENGINE_SMOKE_AUTH=${raw}; use auto|required|disabled`);
}

function assertRecord(value: unknown, label: string): Record<string, unknown> {
  assert(isRecord(value), `${label} should be a JSON object`);
  return value;
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === 'object' && value !== null && !Array.isArray(value);
}

function assert(cond: unknown, msg: string): asserts cond {
  if (!cond) throw new Error(msg);
}

function envInt(name: string, fallback: number): number {
  const value = Number(process.env[name]);
  return Number.isFinite(value) ? Math.trunc(value) : fallback;
}

function cliOrEnvInt(flag: string, envName: string, fallback: number): number {
  const cli = cliValue(flag);
  const value = Number(cli ?? process.env[envName]);
  return Number.isFinite(value) ? Math.trunc(value) : fallback;
}

function flagEnabled(envName: string, flag: string): boolean {
  const args = process.argv.slice(2);
  if (args.includes(`--no-${flag}`)) return false;
  if (args.includes(`--${flag}`)) return true;
  return process.env[envName] === '1';
}

function cliValue(flag: string): string | undefined {
  const args = process.argv.slice(2);
  const inlinePrefix = `--${flag}=`;
  const inline = args.find((arg) => arg.startsWith(inlinePrefix));
  if (inline !== undefined) return inline.slice(inlinePrefix.length);
  const index = args.indexOf(`--${flag}`);
  return index >= 0 ? args[index + 1] : undefined;
}

function normalizeBaseUrl(raw: string): string {
  return raw.replace(/\/+$/, '');
}

function urlFor(path: string): string {
  return `${ENGINE_URL}${path.startsWith('/') ? path : `/${path}`}`;
}

function nonEmptyEnv(name: string): string | undefined {
  const value = process.env[name]?.trim();
  return value && value.length > 0 ? value : undefined;
}

void main();
