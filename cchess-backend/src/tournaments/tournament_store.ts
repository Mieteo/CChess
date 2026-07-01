// Storage layer for C4 — Giải Đấu (Tournament). Bracket math lives in the
// Firestore-free bracket.ts; this file is purely persistence: reading/writing
// tournaments/{id}, tournaments/{id}/participants/{uid} and
// tournaments/{id}/matches/{matchId} via the Admin SDK.

import { FieldValue, getFirestore, Timestamp, type Firestore } from 'firebase-admin/firestore';

import { applyMatchResult, generateBracket, loserOf } from './bracket';
import {
  TournamentError,
  type CreateTournamentInput,
  type MatchDoc,
  type ParticipantDoc,
  type TournamentDoc,
} from './types';

export interface RecordMatchResultArgs {
  tournamentId: string;
  matchId: string;
  outcome: { winnerUid: string } | { draw: true };
  /// The room the match was actually played in, recorded on the match doc.
  roomId?: string;
}

export interface TournamentStore {
  list(opts?: { limit?: number }): Promise<TournamentDoc[]>;
  get(id: string): Promise<TournamentDoc | null>;
  create(createdBy: string, input: CreateTournamentInput): Promise<TournamentDoc>;
  register(uid: string, tournamentId: string): Promise<TournamentDoc>;
  unregister(uid: string, tournamentId: string): Promise<void>;
  listParticipants(tournamentId: string): Promise<ParticipantDoc[]>;
  listMatches(tournamentId: string): Promise<MatchDoc[]>;
  getMatch(tournamentId: string, matchId: string): Promise<MatchDoc | null>;
  start(tournamentId: string): Promise<MatchDoc[]>;
  recordMatchResult(args: RecordMatchResultArgs): Promise<void>;
  /// Called (fire-and-forget, from the create-room WS handler) the first time
  /// a player creates a room for this match. No-ops if `requesterUid` isn't
  /// one of the match's two players, or a room is already attached
  /// (first-writer-wins) — see server.ts.
  attachRoomToMatch(tournamentId: string, matchId: string, roomId: string, requesterUid: string): Promise<void>;
}

const TOURNAMENTS = 'tournaments';
const PARTICIPANTS = 'participants';
const MATCHES = 'matches';
const USERS = 'users';

export interface FirestoreTournamentStoreOptions {
  getDb?: () => Firestore;
  now?: () => Date;
  /// Injectable for deterministic tests. Defaults to an in-place Fisher-Yates
  /// shuffle using Math.random.
  shuffle?: <T>(items: T[]) => T[];
}

export class FirestoreTournamentStore implements TournamentStore {
  private readonly getDb: () => Firestore;
  private readonly now: () => Date;
  private readonly shuffle: <T>(items: T[]) => T[];

  constructor(opts: FirestoreTournamentStoreOptions = {}) {
    this.getDb = opts.getDb ?? (() => getFirestore());
    this.now = opts.now ?? (() => new Date());
    this.shuffle = opts.shuffle ?? defaultShuffle;
  }

  async list(opts: { limit?: number } = {}): Promise<TournamentDoc[]> {
    const snap = await this.getDb().collection(TOURNAMENTS).get();
    const all = snap.docs.map((d) => mapTournament(d.id, d.data()));
    all.sort((a, b) => (a.startsAtMs ?? 0) - (b.startsAtMs ?? 0) || a.id.localeCompare(b.id));
    return opts.limit ? all.slice(0, opts.limit) : all;
  }

  async get(id: string): Promise<TournamentDoc | null> {
    const snap = await this.getDb().collection(TOURNAMENTS).doc(id).get();
    return snap.exists ? mapTournament(snap.id, snap.data() ?? {}) : null;
  }

  async create(createdBy: string, input: CreateTournamentInput): Promise<TournamentDoc> {
    const db = this.getDb();
    const now = this.now();
    const ref = db.collection(TOURNAMENTS).doc();
    const payload = {
      name: input.name,
      format: 'single_elimination' as const,
      status: 'registering' as const,
      createdBy,
      startsAt: new Date(input.startsAtMs),
      registrationDeadline: new Date(input.registrationDeadlineMs),
      minElo: input.minElo,
      maxElo: input.maxElo,
      capacity: input.capacity,
      participantCount: 0,
      prize: input.prize,
      rewards: input.rewards,
      winnerUid: null,
      createdAt: now,
    };
    await ref.set(payload);
    return mapTournament(ref.id, payload);
  }

  async register(uid: string, tournamentId: string): Promise<TournamentDoc> {
    const db = this.getDb();
    const now = this.now();
    const profile = await this.readProfile(uid);
    const tournamentRef = db.collection(TOURNAMENTS).doc(tournamentId);
    const participantRef = tournamentRef.collection(PARTICIPANTS).doc(uid);

    return db.runTransaction(async (tx) => {
      const [tSnap, pSnap] = await Promise.all([tx.get(tournamentRef), tx.get(participantRef)]);
      if (!tSnap.exists) throw new TournamentError(404, 'not-found', 'Tournament not found');
      const tournament = mapTournament(tSnap.id, tSnap.data() ?? {});
      if (tournament.status !== 'registering') {
        throw new TournamentError(400, 'registration-closed', 'Registration is closed');
      }
      if (tournament.registrationDeadlineMs !== null && now.getTime() > tournament.registrationDeadlineMs) {
        throw new TournamentError(400, 'registration-closed', 'Registration deadline has passed');
      }
      if (pSnap.exists) {
        throw new TournamentError(409, 'already-registered', 'Already registered for this tournament');
      }
      if (tournament.participantCount >= tournament.capacity) {
        throw new TournamentError(409, 'tournament-full', 'Tournament is full');
      }
      if (tournament.minElo !== null && profile.eloChess < tournament.minElo) {
        throw new TournamentError(400, 'elo-too-low', `Requires ELO at least ${tournament.minElo}`);
      }
      if (tournament.maxElo !== null && profile.eloChess > tournament.maxElo) {
        throw new TournamentError(400, 'elo-too-high', `Requires ELO at most ${tournament.maxElo}`);
      }

      tx.set(participantRef, {
        uid,
        displayName: profile.displayName,
        eloAtRegistration: profile.eloChess,
        status: 'registered',
        registeredAt: now,
      });
      tx.update(tournamentRef, { participantCount: FieldValue.increment(1) });
      return { ...tournament, participantCount: tournament.participantCount + 1 };
    });
  }

  async unregister(uid: string, tournamentId: string): Promise<void> {
    const db = this.getDb();
    const tournamentRef = db.collection(TOURNAMENTS).doc(tournamentId);
    const participantRef = tournamentRef.collection(PARTICIPANTS).doc(uid);

    await db.runTransaction(async (tx) => {
      const [tSnap, pSnap] = await Promise.all([tx.get(tournamentRef), tx.get(participantRef)]);
      if (!tSnap.exists) throw new TournamentError(404, 'not-found', 'Tournament not found');
      const tournament = mapTournament(tSnap.id, tSnap.data() ?? {});
      if (tournament.status !== 'registering') {
        throw new TournamentError(400, 'registration-closed', 'Cannot unregister after the tournament has started');
      }
      if (!pSnap.exists) throw new TournamentError(404, 'not-registered', 'Not registered for this tournament');
      tx.delete(participantRef);
      tx.update(tournamentRef, { participantCount: FieldValue.increment(-1) });
    });
  }

  async listParticipants(tournamentId: string): Promise<ParticipantDoc[]> {
    const snap = await this.getDb().collection(TOURNAMENTS).doc(tournamentId).collection(PARTICIPANTS).get();
    const list = snap.docs.map((d) => mapParticipant(d.id, d.data()));
    list.sort((a, b) => (a.registeredAtMs ?? 0) - (b.registeredAtMs ?? 0));
    return list;
  }

  async listMatches(tournamentId: string): Promise<MatchDoc[]> {
    const snap = await this.getDb().collection(TOURNAMENTS).doc(tournamentId).collection(MATCHES).get();
    const list = snap.docs.map((d) => mapMatch(d.id, d.data()));
    list.sort((a, b) => a.round - b.round || a.slotIndex - b.slotIndex);
    return list;
  }

  async getMatch(tournamentId: string, matchId: string): Promise<MatchDoc | null> {
    const snap = await this.getDb().collection(TOURNAMENTS).doc(tournamentId).collection(MATCHES).doc(matchId).get();
    return snap.exists ? mapMatch(snap.id, snap.data() ?? {}) : null;
  }

  async start(tournamentId: string): Promise<MatchDoc[]> {
    const db = this.getDb();
    const now = this.now();
    const tournamentRef = db.collection(TOURNAMENTS).doc(tournamentId);
    const tSnap = await tournamentRef.get();
    if (!tSnap.exists) throw new TournamentError(404, 'not-found', 'Tournament not found');
    const tournament = mapTournament(tSnap.id, tSnap.data() ?? {});
    if (tournament.status !== 'registering') {
      throw new TournamentError(400, 'already-started', 'Tournament has already started');
    }
    const participantsSnap = await tournamentRef.collection(PARTICIPANTS).get();
    const uids = participantsSnap.docs.map((d) => d.id);
    if (uids.length < 2) {
      throw new TournamentError(400, 'not-enough-participants', 'Need at least 2 participants to start');
    }

    const matches = generateBracket(this.shuffle([...uids]));

    const batch = db.batch();
    const matchesCol = tournamentRef.collection(MATCHES);
    for (const m of matches) {
      batch.set(matchesCol.doc(m.id), {
        round: m.round,
        slotIndex: m.slotIndex,
        player1Id: m.player1Id,
        player2Id: m.player2Id,
        result: m.result,
        roomId: m.roomId,
        status: m.status,
        nextMatchId: m.nextMatchId,
        nextMatchSlot: m.nextMatchSlot,
        createdAt: now,
        finishedAt: m.status === 'finished' ? now : null,
      });
    }
    for (const uid of uids) {
      batch.set(tournamentRef.collection(PARTICIPANTS).doc(uid), { status: 'active' }, { merge: true });
    }
    batch.update(tournamentRef, { status: 'in_progress' });
    await batch.commit();
    return matches;
  }

  async recordMatchResult(args: RecordMatchResultArgs): Promise<void> {
    const db = this.getDb();
    const now = this.now();
    const tournamentRef = db.collection(TOURNAMENTS).doc(args.tournamentId);
    const matchesCol = tournamentRef.collection(MATCHES);
    const matchRef = matchesCol.doc(args.matchId);

    await db.runTransaction(async (tx) => {
      const matchSnap = await tx.get(matchRef);
      if (!matchSnap.exists) throw new TournamentError(404, 'not-found', 'Match not found');
      const match = mapMatch(matchSnap.id, matchSnap.data() ?? {});

      const nextRef = match.nextMatchId ? matchesCol.doc(match.nextMatchId) : null;
      const nextSnap = nextRef ? await tx.get(nextRef) : null;
      const inputMatches = [match, ...(nextSnap?.exists ? [mapMatch(nextSnap.id, nextSnap.data() ?? {})] : [])];

      const result = applyMatchResult(inputMatches, args.matchId, args.outcome);
      if (result.alreadyFinished) return; // idempotent no-op

      const updatedMatch = result.matches.find((m) => m.id === args.matchId)!;
      tx.set(
        matchRef,
        {
          result: updatedMatch.result,
          status: updatedMatch.status,
          roomId: 'draw' in args.outcome ? null : (args.roomId ?? updatedMatch.roomId),
          finishedAt: updatedMatch.status === 'finished' ? now : null,
        },
        { merge: true },
      );

      if (nextRef && match.nextMatchId) {
        const updatedNext = result.matches.find((m) => m.id === match.nextMatchId);
        if (updatedNext) {
          tx.set(
            nextRef,
            {
              player1Id: updatedNext.player1Id,
              player2Id: updatedNext.player2Id,
              status: updatedNext.status,
            },
            { merge: true },
          );
        }
      }

      if (!('draw' in args.outcome)) {
        const winnerUid = args.outcome.winnerUid;
        const loser = loserOf(match, winnerUid);
        const participantsCol = tournamentRef.collection(PARTICIPANTS);
        if (loser) {
          tx.set(participantsCol.doc(loser), { status: 'eliminated' }, { merge: true });
        }
        if (result.tournamentFinished) {
          tx.set(participantsCol.doc(winnerUid), { status: 'champion' }, { merge: true });
          tx.set(tournamentRef, { status: 'finished', winnerUid }, { merge: true });
        }
      }
    });
  }

  async attachRoomToMatch(tournamentId: string, matchId: string, roomId: string, requesterUid: string): Promise<void> {
    const db = this.getDb();
    const matchRef = db.collection(TOURNAMENTS).doc(tournamentId).collection(MATCHES).doc(matchId);
    await db.runTransaction(async (tx) => {
      const snap = await tx.get(matchRef);
      if (!snap.exists) return;
      const match = mapMatch(snap.id, snap.data() ?? {});
      if (match.player1Id !== requesterUid && match.player2Id !== requesterUid) return;
      if (match.roomId) return; // first writer wins
      tx.set(
        matchRef,
        { roomId, status: match.status === 'ready' ? 'in_progress' : match.status },
        { merge: true },
      );
    });
  }

  /// Reads a user's public profile fields needed to denormalize a
  /// participant doc. Never trusts client-supplied profile data.
  private async readProfile(uid: string): Promise<{ displayName: string; eloChess: number }> {
    const snap = await this.getDb().collection(USERS).doc(uid).get();
    const data = snap.exists ? snap.data() ?? {} : {};
    return {
      displayName: typeof data.displayName === 'string' && data.displayName.length > 0 ? data.displayName : 'Kỳ thủ',
      eloChess: typeof data.eloChess === 'number' ? data.eloChess : 1000,
    };
  }
}

function defaultShuffle<T>(items: T[]): T[] {
  const arr = [...items];
  for (let i = arr.length - 1; i > 0; i--) {
    const j = Math.floor(Math.random() * (i + 1));
    [arr[i], arr[j]] = [arr[j], arr[i]];
  }
  return arr;
}

// ── Mapping helpers ───────────────────────────────────────────────────────────

function toMillis(value: unknown): number | null {
  if (value === null || value === undefined) return null;
  if (typeof value === 'number') return value;
  if (value instanceof Date) return value.getTime();
  if (value instanceof Timestamp) return value.toMillis();
  const maybe = value as { toMillis?: () => number };
  if (typeof maybe.toMillis === 'function') return maybe.toMillis();
  return null;
}

function num(value: unknown, fallback = 0): number {
  return typeof value === 'number' && Number.isFinite(value) ? value : fallback;
}

function nullableNum(value: unknown): number | null {
  return typeof value === 'number' && Number.isFinite(value) ? value : null;
}

function str(value: unknown, fallback = ''): string {
  return typeof value === 'string' ? value : fallback;
}

function nullableStr(value: unknown): string | null {
  return typeof value === 'string' && value.length > 0 ? value : null;
}

function mapTournament(id: string, data: Record<string, unknown>): TournamentDoc {
  return {
    id,
    name: str(data.name, 'Giải đấu CChess'),
    format: 'single_elimination',
    status: (data.status as TournamentDoc['status']) ?? 'registering',
    createdBy: str(data.createdBy, 'system'),
    startsAtMs: toMillis(data.startsAt),
    registrationDeadlineMs: toMillis(data.registrationDeadline),
    minElo: nullableNum(data.minElo),
    maxElo: nullableNum(data.maxElo),
    capacity: num(data.capacity, 32),
    participantCount: num(data.participantCount),
    prize: str(data.prize),
    rewards: (data.rewards as Record<string, number>) ?? {},
    winnerUid: nullableStr(data.winnerUid),
    createdAtMs: toMillis(data.createdAt),
  };
}

function mapParticipant(uid: string, data: Record<string, unknown>): ParticipantDoc {
  return {
    uid: str(data.uid, uid),
    displayName: str(data.displayName, 'Kỳ thủ'),
    eloAtRegistration: num(data.eloAtRegistration, 1000),
    status: (data.status as ParticipantDoc['status']) ?? 'registered',
    registeredAtMs: toMillis(data.registeredAt),
  };
}

function mapMatch(id: string, data: Record<string, unknown>): MatchDoc {
  return {
    id,
    round: num(data.round, 1),
    slotIndex: num(data.slotIndex),
    player1Id: nullableStr(data.player1Id),
    player2Id: nullableStr(data.player2Id),
    result: (data.result as MatchDoc['result']) ?? null,
    roomId: nullableStr(data.roomId),
    status: (data.status as MatchDoc['status']) ?? 'pending',
    nextMatchId: nullableStr(data.nextMatchId),
    nextMatchSlot: (data.nextMatchSlot as MatchDoc['nextMatchSlot']) ?? null,
    createdAtMs: toMillis(data.createdAt),
    finishedAtMs: toMillis(data.finishedAt),
  };
}
