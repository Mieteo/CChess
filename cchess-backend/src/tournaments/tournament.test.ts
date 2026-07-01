import assert from 'node:assert/strict';
import { test } from 'node:test';
import { createServer, type Server } from 'node:http';
import type { AddressInfo } from 'node:net';

import { applyMatchResult, generateBracket, loserOf, nextPowerOfTwo } from './bracket';
import { createTournamentsApi, type TournamentsApiOptions } from './tournament_routes';
import type { RecordMatchResultArgs, TournamentStore } from './tournament_store';
import {
  TournamentError,
  validateCreateTournamentInput,
  type CreateTournamentInput,
  type MatchDoc,
  type ParticipantDoc,
  type TournamentDoc,
} from './types';

// ── Pure bracket.ts tests ───────────────────────────────────────────────────

test('nextPowerOfTwo', () => {
  assert.equal(nextPowerOfTwo(1), 1);
  assert.equal(nextPowerOfTwo(2), 2);
  assert.equal(nextPowerOfTwo(3), 4);
  assert.equal(nextPowerOfTwo(5), 8);
  assert.equal(nextPowerOfTwo(8), 8);
  assert.equal(nextPowerOfTwo(9), 16);
});

test('generateBracket: power-of-two field has no byes', () => {
  const matches = generateBracket(['a', 'b', 'c', 'd']);
  const round1 = matches.filter((m) => m.round === 1);
  assert.equal(round1.length, 2);
  for (const m of round1) {
    assert.equal(m.status, 'ready');
    assert.notEqual(m.player1Id, null);
    assert.notEqual(m.player2Id, null);
  }
  const final = matches.find((m) => m.round === 2)!;
  assert.equal(final.player1Id, null); // not decided until round 1 finishes
  assert.equal(final.player2Id, null);
  assert.equal(final.nextMatchId, null);
});

test('generateBracket: n=5 produces 3 byes, one-per-pair, with correct cascading', () => {
  const matches = generateBracket(['p1', 'p2', 'p3', 'p4', 'p5']);
  const byId = new Map(matches.map((m) => [m.id, m]));

  const round1 = matches.filter((m) => m.round === 1);
  assert.equal(round1.length, 4); // bracketSize=8 -> 4 first-round matches

  const byeMatches = round1.filter((m) => m.result === 'bye');
  assert.equal(byeMatches.length, 3);
  for (const m of byeMatches) {
    assert.equal(m.status, 'finished');
    // A bye always has exactly one real player present.
    assert.notEqual(m.player1Id === null, m.player2Id === null);
  }

  const readyMatches = round1.filter((m) => m.status === 'ready');
  assert.equal(readyMatches.length, 1);
  assert.equal(readyMatches[0].player1Id, 'p1');
  assert.equal(readyMatches[0].player2Id, 'p2');

  // r1_m1, r1_m2, r1_m3 are byes for p3, p4, p5 respectively.
  assert.equal(byId.get('r1_m1')!.player1Id, 'p3');
  assert.equal(byId.get('r1_m2')!.player1Id, 'p4');
  assert.equal(byId.get('r1_m3')!.player1Id, 'p5');

  // r1_m2 and r1_m3 are siblings feeding r2_m1 — both are byes, so their
  // winners (p4, p5) land in the SAME round-2 match, which becomes 'ready'
  // immediately (no game needed to reach that state).
  const r2m1 = byId.get('r2_m1')!;
  assert.equal(r2m1.player1Id, 'p4');
  assert.equal(r2m1.player2Id, 'p5');
  assert.equal(r2m1.status, 'ready');

  // r1_m0 (p1 vs p2) and r1_m1 (bye→p3) feed r2_m0 — only p3's slot is
  // filled yet; the other stays null until r1_m0 is actually played.
  const r2m0 = byId.get('r2_m0')!;
  assert.equal(r2m0.player1Id, null);
  assert.equal(r2m0.player2Id, 'p3');
  assert.equal(r2m0.status, 'pending');

  const final = byId.get('r3_m0')!;
  assert.equal(final.player1Id, null);
  assert.equal(final.player2Id, null);
});

test('generateBracket rejects fewer than 2 participants', () => {
  assert.throws(() => generateBracket(['solo']));
  assert.throws(() => generateBracket([]));
});

test('applyMatchResult advances the winner into the precomputed next slot', () => {
  const matches = generateBracket(['a', 'b', 'c', 'd']);
  const out = applyMatchResult(matches, 'r1_m0', { winnerUid: 'a' });
  assert.equal(out.alreadyFinished, false);
  assert.equal(out.tournamentFinished, false);
  const updated = out.matches.find((m) => m.id === 'r1_m0')!;
  assert.equal(updated.status, 'finished');
  assert.equal(updated.result, 'player1');
  const next = out.matches.find((m) => m.id === 'r2_m0')!;
  assert.equal(next.player1Id, 'a');
  assert.equal(next.status, 'pending'); // still waiting on r1_m1's winner
});

test('applyMatchResult on the final match finishes the tournament', () => {
  const matches = generateBracket(['a', 'b']); // bracketSize=2 -> a single final match
  const out = applyMatchResult(matches, 'r1_m0', { winnerUid: 'b' });
  assert.equal(out.tournamentFinished, true);
  assert.equal(out.winnerUid, 'b');
});

test('applyMatchResult is idempotent on an already-finished match', () => {
  const matches = generateBracket(['a', 'b']);
  const first = applyMatchResult(matches, 'r1_m0', { winnerUid: 'a' });
  const second = applyMatchResult(first.matches, 'r1_m0', { winnerUid: 'b' });
  assert.equal(second.alreadyFinished, true);
  // Second call must not flip the recorded winner.
  const m = second.matches.find((x) => x.id === 'r1_m0')!;
  assert.equal(m.result, 'player1');
});

test('applyMatchResult on a draw resets the match to ready with no roomId, no advancement', () => {
  const matches = generateBracket(['a', 'b', 'c', 'd']);
  matches.find((m) => m.id === 'r1_m0')!.roomId = 'room-1';
  const out = applyMatchResult(matches, 'r1_m0', { draw: true });
  const m = out.matches.find((x) => x.id === 'r1_m0')!;
  assert.equal(m.status, 'ready');
  assert.equal(m.roomId, null);
  assert.equal(m.result, null);
  const next = out.matches.find((x) => x.id === 'r2_m0')!;
  assert.equal(next.player1Id, null); // not advanced
});

test('applyMatchResult rejects a winner who is not in the match', () => {
  const matches = generateBracket(['a', 'b']);
  assert.throws(() => applyMatchResult(matches, 'r1_m0', { winnerUid: 'nope' }));
});

test('loserOf', () => {
  const matches = generateBracket(['a', 'b']);
  const m = matches.find((x) => x.id === 'r1_m0')!;
  assert.equal(loserOf(m, 'a'), 'b');
  assert.equal(loserOf(m, 'b'), 'a');
});

// ── Validation ────────────────────────────────────────────────────────────────

test('validateCreateTournamentInput normalizes and validates', () => {
  const input = validateCreateTournamentInput({
    name: '  CChess Open  ',
    startsAtMs: 2_000,
    registrationDeadlineMs: 1_000,
    capacity: 16,
    minElo: 1000,
    maxElo: 2000,
    prize: '1000 xu',
  });
  assert.equal(input.name, 'CChess Open');
  assert.equal(input.capacity, 16);

  assert.throws(
    () => validateCreateTournamentInput({ name: '', startsAtMs: 1, registrationDeadlineMs: 1 }),
    (e) => (e as TournamentError).code === 'invalid-name',
  );
  assert.throws(
    () => validateCreateTournamentInput({ name: 'x', startsAtMs: 1, registrationDeadlineMs: 2 }),
    (e) => (e as TournamentError).code === 'invalid-deadline',
  );
  assert.throws(
    () => validateCreateTournamentInput({ name: 'x', startsAtMs: 10, registrationDeadlineMs: 1, minElo: 2000, maxElo: 1000 }),
    (e) => (e as TournamentError).code === 'invalid-elo-range',
  );
});

// ── In-memory store fake (reuses the real bracket.ts algorithms) ───────────────

class FakeTournamentStore implements TournamentStore {
  readonly tournaments = new Map<string, TournamentDoc>();
  readonly participants = new Map<string, Map<string, ParticipantDoc>>();
  readonly matches = new Map<string, Map<string, MatchDoc>>();
  readonly profiles = new Map<string, { displayName: string; eloChess: number }>();
  private seq = 0;

  seedProfile(uid: string, displayName = 'Kỳ thủ', eloChess = 1000): void {
    this.profiles.set(uid, { displayName, eloChess });
  }
  private profileFor(uid: string) {
    return this.profiles.get(uid) ?? { displayName: 'Kỳ thủ', eloChess: 1000 };
  }

  async list(opts: { limit?: number } = {}): Promise<TournamentDoc[]> {
    const all = [...this.tournaments.values()].sort((a, b) => (a.startsAtMs ?? 0) - (b.startsAtMs ?? 0));
    return opts.limit ? all.slice(0, opts.limit) : all;
  }

  async get(id: string): Promise<TournamentDoc | null> {
    return this.tournaments.get(id) ?? null;
  }

  async create(createdBy: string, input: CreateTournamentInput): Promise<TournamentDoc> {
    const id = `t-${++this.seq}`;
    const doc: TournamentDoc = {
      id,
      name: input.name,
      format: 'single_elimination',
      status: 'registering',
      createdBy,
      startsAtMs: input.startsAtMs,
      registrationDeadlineMs: input.registrationDeadlineMs,
      minElo: input.minElo,
      maxElo: input.maxElo,
      capacity: input.capacity,
      participantCount: 0,
      prize: input.prize,
      rewards: input.rewards,
      winnerUid: null,
      createdAtMs: ++this.seq,
    };
    this.tournaments.set(id, doc);
    this.participants.set(id, new Map());
    this.matches.set(id, new Map());
    return doc;
  }

  async register(uid: string, tournamentId: string): Promise<TournamentDoc> {
    const t = this.tournaments.get(tournamentId);
    if (!t) throw new TournamentError(404, 'not-found', 'Tournament not found');
    if (t.status !== 'registering') throw new TournamentError(400, 'registration-closed', 'closed');
    if (t.registrationDeadlineMs !== null && Date.now() > t.registrationDeadlineMs) {
      throw new TournamentError(400, 'registration-closed', 'deadline passed');
    }
    const parts = this.participants.get(tournamentId)!;
    if (parts.has(uid)) throw new TournamentError(409, 'already-registered', 'already');
    if (t.participantCount >= t.capacity) throw new TournamentError(409, 'tournament-full', 'full');
    const profile = this.profileFor(uid);
    if (t.minElo !== null && profile.eloChess < t.minElo) throw new TournamentError(400, 'elo-too-low', 'low');
    if (t.maxElo !== null && profile.eloChess > t.maxElo) throw new TournamentError(400, 'elo-too-high', 'high');
    parts.set(uid, {
      uid,
      displayName: profile.displayName,
      eloAtRegistration: profile.eloChess,
      status: 'registered',
      registeredAtMs: ++this.seq,
    });
    t.participantCount += 1;
    return t;
  }

  async unregister(uid: string, tournamentId: string): Promise<void> {
    const t = this.tournaments.get(tournamentId);
    if (!t) throw new TournamentError(404, 'not-found', 'not found');
    if (t.status !== 'registering') throw new TournamentError(400, 'registration-closed', 'closed');
    const parts = this.participants.get(tournamentId)!;
    if (!parts.has(uid)) throw new TournamentError(404, 'not-registered', 'not registered');
    parts.delete(uid);
    t.participantCount -= 1;
  }

  async listParticipants(tournamentId: string): Promise<ParticipantDoc[]> {
    return [...(this.participants.get(tournamentId)?.values() ?? [])];
  }

  async listMatches(tournamentId: string): Promise<MatchDoc[]> {
    const list = [...(this.matches.get(tournamentId)?.values() ?? [])];
    list.sort((a, b) => a.round - b.round || a.slotIndex - b.slotIndex);
    return list;
  }

  async getMatch(tournamentId: string, matchId: string): Promise<MatchDoc | null> {
    return this.matches.get(tournamentId)?.get(matchId) ?? null;
  }

  async start(tournamentId: string): Promise<MatchDoc[]> {
    const t = this.tournaments.get(tournamentId);
    if (!t) throw new TournamentError(404, 'not-found', 'not found');
    if (t.status !== 'registering') throw new TournamentError(400, 'already-started', 'started');
    const uids = [...(this.participants.get(tournamentId)?.keys() ?? [])];
    if (uids.length < 2) throw new TournamentError(400, 'not-enough-participants', 'need 2+');
    const bracket = generateBracket(uids); // no shuffle — deterministic for tests
    const matchMap = this.matches.get(tournamentId)!;
    for (const m of bracket) matchMap.set(m.id, m);
    for (const uid of uids) this.participants.get(tournamentId)!.get(uid)!.status = 'active';
    t.status = 'in_progress';
    return bracket;
  }

  async recordMatchResult(args: RecordMatchResultArgs): Promise<void> {
    const matchMap = this.matches.get(args.tournamentId)!;
    const match = matchMap.get(args.matchId);
    if (!match) throw new TournamentError(404, 'not-found', 'match not found');
    const next = match.nextMatchId ? matchMap.get(match.nextMatchId) : undefined;
    const input = [match, ...(next ? [next] : [])];
    const result = applyMatchResult(input, args.matchId, args.outcome);
    if (result.alreadyFinished) return;
    matchMap.set(args.matchId, result.matches.find((m) => m.id === args.matchId)!);
    if (match.nextMatchId) {
      const updatedNext = result.matches.find((m) => m.id === match.nextMatchId);
      if (updatedNext) matchMap.set(match.nextMatchId, updatedNext);
    }
    if (!('draw' in args.outcome)) {
      const winnerUid = args.outcome.winnerUid;
      const loser = loserOf(match, winnerUid);
      const parts = this.participants.get(args.tournamentId)!;
      if (loser && parts.has(loser)) parts.get(loser)!.status = 'eliminated';
      if (result.tournamentFinished) {
        if (parts.has(winnerUid)) parts.get(winnerUid)!.status = 'champion';
        const t = this.tournaments.get(args.tournamentId)!;
        t.status = 'finished';
        t.winnerUid = winnerUid;
      }
    }
  }

  async attachRoomToMatch(tournamentId: string, matchId: string, roomId: string, requesterUid: string): Promise<void> {
    const matchMap = this.matches.get(tournamentId);
    const match = matchMap?.get(matchId);
    if (!match) return;
    if (match.player1Id !== requesterUid && match.player2Id !== requesterUid) return;
    if (match.roomId) return;
    matchMap!.set(matchId, { ...match, roomId, status: match.status === 'ready' ? 'in_progress' : match.status });
  }
}

// ── HTTP test harness ─────────────────────────────────────────────────────────

async function getJson(res: Response): Promise<any> {
  return res.json();
}

function listen(server: Server): Promise<string> {
  return new Promise((resolve) => {
    server.listen(0, '127.0.0.1', () => {
      const addr = server.address() as AddressInfo;
      resolve(`http://127.0.0.1:${addr.port}`);
    });
  });
}

async function withServer(
  store: FakeTournamentStore,
  extra: TournamentsApiOptions,
  run: (baseUrl: string) => Promise<void>,
): Promise<void> {
  const api = createTournamentsApi({ store, ...extra });
  const server = createServer((req, res) => {
    void api.handle(req, res).then((handled) => {
      if (!handled && !res.headersSent) {
        res.writeHead(404);
        res.end();
      }
    });
  });
  try {
    const baseUrl = await listen(server);
    await run(baseUrl);
  } finally {
    await new Promise<void>((resolve) => server.close(() => resolve()));
  }
}

const asUid: TournamentsApiOptions = { authenticate: async (t) => ({ uid: t }) };
const bearer = (uid: string) => ({ authorization: `Bearer ${uid}` });
const jsonHeaders = (uid: string) => ({ ...bearer(uid), 'content-type': 'application/json' });
const admin: TournamentsApiOptions = { isAdmin: () => true };

const createBody = (overrides: Partial<Record<string, unknown>> = {}) => ({
  name: 'CChess Open',
  startsAtMs: Date.now() + 100_000,
  registrationDeadlineMs: Date.now() + 50_000,
  capacity: 8,
  prize: '1000 xu',
  ...overrides,
});

test('admin creates a tournament; public reads work; non-admin create is rejected', async () => {
  const store = new FakeTournamentStore();
  await withServer(store, { ...asUid, isAdmin: () => false }, async (baseUrl) => {
    const denied = await fetch(`${baseUrl}/tournaments`, {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify(createBody()),
    });
    assert.equal(denied.status, 403);
  });
  await withServer(store, { ...asUid, ...admin }, async (baseUrl) => {
    const created = await getJson(
      await fetch(`${baseUrl}/tournaments`, {
        method: 'POST',
        headers: { 'content-type': 'application/json' },
        body: JSON.stringify(createBody()),
      }),
    );
    assert.equal(created.status, 'registering');
    assert.equal(created.capacity, 8);

    const list = await getJson(await fetch(`${baseUrl}/tournaments`));
    assert.equal(list.tournaments.length, 1);
    const got = await getJson(await fetch(`${baseUrl}/tournaments/${created.id}`));
    assert.equal(got.name, 'CChess Open');
  });
});

test('register enforces deadline, elo window, capacity and duplicates', async () => {
  const store = new FakeTournamentStore();
  store.seedProfile('lowElo', 'Low', 800);
  store.seedProfile('inRange', 'InRange', 1200);
  const t = await store.create('system', {
    name: 'Elo Gated',
    startsAtMs: Date.now() + 100_000,
    registrationDeadlineMs: Date.now() + 50_000,
    capacity: 1,
    minElo: 1000,
    maxElo: 1500,
    prize: '',
    rewards: {},
  });

  await withServer(store, asUid, async (baseUrl) => {
    const tooLow = await fetch(`${baseUrl}/tournaments/${t.id}/register`, { method: 'POST', headers: jsonHeaders('lowElo') });
    assert.equal(tooLow.status, 400);
    assert.equal((await getJson(tooLow)).code, 'elo-too-low');

    const ok = await fetch(`${baseUrl}/tournaments/${t.id}/register`, { method: 'POST', headers: jsonHeaders('inRange') });
    assert.equal(ok.status, 200);

    const dup = await fetch(`${baseUrl}/tournaments/${t.id}/register`, { method: 'POST', headers: jsonHeaders('inRange') });
    assert.equal(dup.status, 409);
    assert.equal((await getJson(dup)).code, 'already-registered');

    store.seedProfile('another', 'Another', 1100);
    const full = await fetch(`${baseUrl}/tournaments/${t.id}/register`, { method: 'POST', headers: jsonHeaders('another') });
    assert.equal(full.status, 409);
    assert.equal((await getJson(full)).code, 'tournament-full');
  });
});

test('unregister works while registering, rejected after start', async () => {
  const store = new FakeTournamentStore();
  store.seedProfile('a');
  store.seedProfile('b');
  const t = await store.create('system', {
    name: 'T',
    startsAtMs: Date.now() + 100_000,
    registrationDeadlineMs: Date.now() + 50_000,
    capacity: 8,
    minElo: null,
    maxElo: null,
    prize: '',
    rewards: {},
  });
  await store.register('a', t.id);
  await store.register('b', t.id);

  await withServer(store, asUid, async (baseUrl) => {
    const unreg = await fetch(`${baseUrl}/tournaments/${t.id}/unregister`, { method: 'POST', headers: jsonHeaders('a') });
    assert.equal(unreg.status, 200);
  });
  await store.register('a', t.id);

  await withServer(store, { ...asUid, ...admin }, async (baseUrl) => {
    const start = await fetch(`${baseUrl}/tournaments/${t.id}/start`, { method: 'POST' });
    assert.equal(start.status, 200);
  });
  await withServer(store, asUid, async (baseUrl) => {
    const tooLate = await fetch(`${baseUrl}/tournaments/${t.id}/unregister`, { method: 'POST', headers: jsonHeaders('a') });
    assert.equal(tooLate.status, 400);
    assert.equal((await getJson(tooLate)).code, 'registration-closed');
  });
});

test('start requires 2+ participants and admin credentials, generates a bracket', async () => {
  const store = new FakeTournamentStore();
  store.seedProfile('solo');
  const t = await store.create('system', {
    name: 'T',
    startsAtMs: Date.now() + 100_000,
    registrationDeadlineMs: Date.now() + 50_000,
    capacity: 8,
    minElo: null,
    maxElo: null,
    prize: '',
    rewards: {},
  });
  await store.register('solo', t.id);

  await withServer(store, { ...asUid, isAdmin: () => false }, async (baseUrl) => {
    const denied = await fetch(`${baseUrl}/tournaments/${t.id}/start`, { method: 'POST' });
    assert.equal(denied.status, 403);
  });
  await withServer(store, { ...asUid, ...admin }, async (baseUrl) => {
    const notEnough = await fetch(`${baseUrl}/tournaments/${t.id}/start`, { method: 'POST' });
    assert.equal(notEnough.status, 400);
    assert.equal((await getJson(notEnough)).code, 'not-enough-participants');
  });

  store.seedProfile('two');
  await store.register('two', t.id);
  await withServer(store, { ...asUid, ...admin }, async (baseUrl) => {
    const started = await getJson(await fetch(`${baseUrl}/tournaments/${t.id}/start`, { method: 'POST' }));
    assert.equal(started.matches.length, 1);
    const matches = await getJson(await fetch(`${baseUrl}/tournaments/${t.id}/matches`));
    assert.equal(matches.matches[0].status, 'ready');
  });
});

test('full flow: register -> start -> recordMatchResult finishes the tournament', async () => {
  const store = new FakeTournamentStore();
  store.seedProfile('a');
  store.seedProfile('b');
  const t = await store.create('system', {
    name: 'T',
    startsAtMs: Date.now() + 100_000,
    registrationDeadlineMs: Date.now() + 50_000,
    capacity: 8,
    minElo: null,
    maxElo: null,
    prize: '',
    rewards: {},
  });
  await store.register('a', t.id);
  await store.register('b', t.id);
  await store.start(t.id);

  await store.attachRoomToMatch(t.id, 'r1_m0', 'room-xyz', 'a');
  let match = await store.getMatch(t.id, 'r1_m0');
  assert.equal(match!.roomId, 'room-xyz');
  assert.equal(match!.status, 'in_progress');

  // A third party can't hijack the room slot.
  await store.attachRoomToMatch(t.id, 'r1_m0', 'room-fake', 'stranger');
  match = await store.getMatch(t.id, 'r1_m0');
  assert.equal(match!.roomId, 'room-xyz');

  await store.recordMatchResult({ tournamentId: t.id, matchId: 'r1_m0', outcome: { winnerUid: 'a' }, roomId: 'room-xyz' });
  const finished = await store.get(t.id);
  assert.equal(finished!.status, 'finished');
  assert.equal(finished!.winnerUid, 'a');
  const participants = await store.listParticipants(t.id);
  assert.equal(participants.find((p) => p.uid === 'a')!.status, 'champion');
  assert.equal(participants.find((p) => p.uid === 'b')!.status, 'eliminated');
});
