// Storage layer for C3 — Câu Lạc Bộ (Club). The route handler talks only to
// the ClubStore interface, so tests inject an in-memory fake while production
// uses FirestoreClubStore (Admin SDK → bypasses security rules, which is what
// lets us maintain memberCount + enforce the per-user club cap honestly).
//
// join()/leave()/createClub() run inside a Firestore transaction so
// memberCount stays consistent with the members subcollection even under
// concurrent joins.

import { FieldValue, getFirestore, Timestamp, type Firestore } from 'firebase-admin/firestore';

import { ClubError, MAX_CLUBS_PER_USER, type ClubDoc, type ClubMemberDoc, type ClubRole, type CreateClubInput, type MyClubDoc } from './types';

export interface ClubProfileSnapshot {
  displayName: string;
  eloChess: number;
}

export interface ClubStore {
  listClubs(opts?: { limit?: number }): Promise<ClubDoc[]>;
  getClub(id: string): Promise<ClubDoc | null>;
  listMembers(clubId: string): Promise<ClubMemberDoc[]>;
  listMyClubs(uid: string): Promise<MyClubDoc[]>;
  createClub(founderUid: string, input: CreateClubInput): Promise<ClubDoc>;
  joinClub(uid: string, clubId: string): Promise<ClubDoc>;
  leaveClub(uid: string, clubId: string): Promise<void>;
}

const CLUBS = 'clubs';
const MEMBERS = 'members';
const USERS = 'users';

export interface FirestoreClubStoreOptions {
  getDb?: () => Firestore;
  now?: () => Date;
}

export class FirestoreClubStore implements ClubStore {
  private readonly getDb: () => Firestore;
  private readonly now: () => Date;

  constructor(opts: FirestoreClubStoreOptions = {}) {
    this.getDb = opts.getDb ?? (() => getFirestore());
    this.now = opts.now ?? (() => new Date());
  }

  async listClubs(opts: { limit?: number } = {}): Promise<ClubDoc[]> {
    // Filter active + sort by weeklyScore in memory (same trick as the shop
    // catalog) so this never needs a composite index — a `where('active')`
    // equality filter combined with `orderBy('weeklyScore')` on a different
    // field would otherwise require one, and the club list is small enough
    // that an in-memory sort is cheap.
    const snap = await this.getDb().collection(CLUBS).get();
    const clubs = snap.docs.map((d) => mapClub(d.id, d.data())).filter((c) => c.active);
    clubs.sort((a, b) => b.weeklyScore - a.weeklyScore || a.id.localeCompare(b.id));
    return opts.limit ? clubs.slice(0, opts.limit) : clubs;
  }

  async getClub(id: string): Promise<ClubDoc | null> {
    const snap = await this.getDb().collection(CLUBS).doc(id).get();
    return snap.exists ? mapClub(snap.id, snap.data() ?? {}) : null;
  }

  async listMembers(clubId: string): Promise<ClubMemberDoc[]> {
    const snap = await this.getDb().collection(CLUBS).doc(clubId).collection(MEMBERS).get();
    const members = snap.docs.map((d) => mapMember(d.id, d.data()));
    members.sort((a, b) => {
      if (a.role !== b.role) return a.role === 'owner' ? -1 : 1;
      return (a.joinedAtMs ?? 0) - (b.joinedAtMs ?? 0);
    });
    return members;
  }

  async listMyClubs(uid: string): Promise<MyClubDoc[]> {
    const snap = await this.getDb().collectionGroup(MEMBERS).where('uid', '==', uid).get();
    return snap.docs.map((d) => ({
      clubId: d.ref.parent.parent?.id ?? '',
      role: (d.data().role as ClubRole) ?? 'member',
      joinedAtMs: toMillis(d.data().joinedAt),
    }));
  }

  async createClub(founderUid: string, input: CreateClubInput): Promise<ClubDoc> {
    const db = this.getDb();
    const now = this.now();
    const profile = await this.readProfile(founderUid);
    const col = db.collection(CLUBS);
    const id = await uniqueId(col, slugifyId(input.name));
    const ref = col.doc(id);

    return db.runTransaction(async (tx) => {
      const existing = await this.countUserClubsTx(tx, founderUid);
      if (existing >= MAX_CLUBS_PER_USER) {
        throw new ClubError(409, 'club-limit-reached', `You may join at most ${MAX_CLUBS_PER_USER} clubs`);
      }
      const payload = {
        name: input.name,
        region: input.region,
        description: input.description,
        founderId: founderUid,
        memberCount: 1,
        weeklyScore: 0,
        active: true,
        createdAt: now,
      };
      tx.set(ref, payload);
      tx.set(ref.collection(MEMBERS).doc(founderUid), {
        uid: founderUid,
        role: 'owner',
        displayName: profile.displayName,
        eloChess: profile.eloChess,
        joinedAt: now,
      });
      return mapClub(id, payload);
    });
  }

  async joinClub(uid: string, clubId: string): Promise<ClubDoc> {
    const db = this.getDb();
    const now = this.now();
    const profile = await this.readProfile(uid);
    const clubRef = db.collection(CLUBS).doc(clubId);
    const memberRef = clubRef.collection(MEMBERS).doc(uid);

    return db.runTransaction(async (tx) => {
      const [clubSnap, memberSnap] = await Promise.all([tx.get(clubRef), tx.get(memberRef)]);
      if (!clubSnap.exists) throw new ClubError(404, 'not-found', 'Club not found');
      const club = mapClub(clubSnap.id, clubSnap.data() ?? {});
      if (!club.active) throw new ClubError(404, 'not-found', 'Club is not active');
      if (memberSnap.exists) throw new ClubError(409, 'already-member', 'You are already a member of this club');

      const clubCount = await this.countUserClubsTx(tx, uid);
      if (clubCount >= MAX_CLUBS_PER_USER) {
        throw new ClubError(409, 'club-limit-reached', `You may join at most ${MAX_CLUBS_PER_USER} clubs`);
      }

      tx.set(memberRef, {
        uid,
        role: 'member',
        displayName: profile.displayName,
        eloChess: profile.eloChess,
        joinedAt: now,
      });
      tx.update(clubRef, { memberCount: FieldValue.increment(1) });
      return { ...club, memberCount: club.memberCount + 1 };
    });
  }

  async leaveClub(uid: string, clubId: string): Promise<void> {
    const db = this.getDb();
    const clubRef = db.collection(CLUBS).doc(clubId);
    const memberRef = clubRef.collection(MEMBERS).doc(uid);

    await db.runTransaction(async (tx) => {
      const [clubSnap, memberSnap] = await Promise.all([tx.get(clubRef), tx.get(memberRef)]);
      if (!clubSnap.exists) throw new ClubError(404, 'not-found', 'Club not found');
      if (!memberSnap.exists) throw new ClubError(404, 'not-member', 'You are not a member of this club');
      const member = mapMember(memberSnap.id, memberSnap.data() ?? {});
      const club = mapClub(clubSnap.id, clubSnap.data() ?? {});
      if (member.role === 'owner' && club.memberCount > 1) {
        throw new ClubError(
          400,
          'owner-cannot-leave',
          'The founder cannot leave while other members remain — ownership transfer is not supported yet',
        );
      }
      tx.delete(memberRef);
      tx.update(clubRef, { memberCount: FieldValue.increment(-1) });
    });
  }

  /// Reads a user's public profile fields needed to denormalize a member doc.
  /// Never trusts client-supplied profile data (avoids spoofing displayName/elo).
  private async readProfile(uid: string): Promise<ClubProfileSnapshot> {
    const snap = await this.getDb().collection(USERS).doc(uid).get();
    const data = snap.exists ? snap.data() ?? {} : {};
    return {
      displayName: typeof data.displayName === 'string' && data.displayName.length > 0 ? data.displayName : 'Kỳ thủ',
      eloChess: typeof data.eloChess === 'number' ? data.eloChess : 1000,
    };
  }

  private async countUserClubsTx(
    tx: FirebaseFirestore.Transaction,
    uid: string,
  ): Promise<number> {
    const snap = await tx.get(this.getDb().collectionGroup(MEMBERS).where('uid', '==', uid));
    return snap.size;
  }
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

function mapClub(id: string, data: Record<string, unknown>): ClubDoc {
  return {
    id,
    name: String(data.name ?? 'Kỳ Xã'),
    region: String(data.region ?? 'Toàn quốc'),
    description: String(data.description ?? ''),
    founderId: String(data.founderId ?? ''),
    memberCount: num(data.memberCount),
    weeklyScore: num(data.weeklyScore),
    active: data.active !== false,
    createdAtMs: toMillis(data.createdAt),
  };
}

function mapMember(uid: string, data: Record<string, unknown>): ClubMemberDoc {
  return {
    uid: String(data.uid ?? uid),
    role: data.role === 'owner' ? 'owner' : 'member',
    displayName: String(data.displayName ?? 'Kỳ thủ'),
    eloChess: num(data.eloChess, 1000),
    joinedAtMs: toMillis(data.joinedAt),
  };
}

/// Slug a human name into a stable-ish id when the caller didn't supply one.
function slugifyId(name: string): string {
  const base = name
    .normalize('NFD')
    .replace(/[̀-ͯ]/g, '') // strip diacritics
    .toLowerCase()
    .replace(/đ/g, 'd')
    .replace(/[^a-z0-9]+/g, '-')
    .replace(/^-+|-+$/g, '')
    .slice(0, 40);
  return base.length > 0 ? base : 'club';
}

async function uniqueId(col: FirebaseFirestore.CollectionReference, base: string): Promise<string> {
  if (!(await col.doc(base).get()).exists) return base;
  for (let i = 2; i < 1000; i++) {
    const candidate = `${base}-${i}`;
    if (!(await col.doc(candidate).get()).exists) return candidate;
  }
  return `${base}-${Date.now()}`;
}
