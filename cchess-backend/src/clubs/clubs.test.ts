import assert from 'node:assert/strict';
import { test } from 'node:test';
import { createServer, type Server } from 'node:http';
import type { AddressInfo } from 'node:net';

import { createClubsApi, type ClubsApiOptions } from './clubs_routes';
import type { ClubStore } from './clubs_store';
import { ClubError, MAX_CLUBS_PER_USER, validateCreateClubInput, type ClubDoc, type ClubMemberDoc, type ClubRole, type CreateClubInput, type MyClubDoc } from './types';

// ── In-memory store fake ─────────────────────────────────────────────────────

interface FakeMember extends ClubMemberDoc {
  clubId: string;
}

class FakeClubStore implements ClubStore {
  readonly clubs = new Map<string, ClubDoc>();
  readonly members = new Map<string, FakeMember>(); // key: `${clubId}:${uid}`
  readonly profiles = new Map<string, { displayName: string; eloChess: number }>();
  private seq = 0;

  seedProfile(uid: string, displayName = 'Kỳ thủ', eloChess = 1000): void {
    this.profiles.set(uid, { displayName, eloChess });
  }

  private profileFor(uid: string) {
    return this.profiles.get(uid) ?? { displayName: 'Kỳ thủ', eloChess: 1000 };
  }

  private key(clubId: string, uid: string): string {
    return `${clubId}:${uid}`;
  }

  private countClubs(uid: string): number {
    return [...this.members.values()].filter((m) => m.uid === uid).length;
  }

  async listClubs(opts: { limit?: number } = {}): Promise<ClubDoc[]> {
    const all = [...this.clubs.values()]
      .filter((c) => c.active)
      .sort((a, b) => b.weeklyScore - a.weeklyScore || a.id.localeCompare(b.id));
    return opts.limit ? all.slice(0, opts.limit) : all;
  }

  async getClub(id: string): Promise<ClubDoc | null> {
    return this.clubs.get(id) ?? null;
  }

  async listMembers(clubId: string): Promise<ClubMemberDoc[]> {
    return [...this.members.values()]
      .filter((m) => m.clubId === clubId)
      .map(({ clubId: _clubId, ...m }) => m);
  }

  async listMyClubs(uid: string): Promise<MyClubDoc[]> {
    return [...this.members.values()]
      .filter((m) => m.uid === uid)
      .map((m) => ({ clubId: m.clubId, role: m.role, joinedAtMs: m.joinedAtMs }));
  }

  async createClub(founderUid: string, input: CreateClubInput): Promise<ClubDoc> {
    if (this.countClubs(founderUid) >= MAX_CLUBS_PER_USER) {
      throw new ClubError(409, 'club-limit-reached', `You may join at most ${MAX_CLUBS_PER_USER} clubs`);
    }
    const id = `club-${++this.seq}`;
    const club: ClubDoc = {
      id,
      name: input.name,
      region: input.region,
      description: input.description,
      founderId: founderUid,
      memberCount: 1,
      weeklyScore: 0,
      active: true,
      createdAtMs: ++this.seq,
    };
    this.clubs.set(id, club);
    const profile = this.profileFor(founderUid);
    this.members.set(this.key(id, founderUid), {
      clubId: id,
      uid: founderUid,
      role: 'owner',
      displayName: profile.displayName,
      eloChess: profile.eloChess,
      joinedAtMs: ++this.seq,
    });
    return club;
  }

  async joinClub(uid: string, clubId: string): Promise<ClubDoc> {
    const club = this.clubs.get(clubId);
    if (!club || !club.active) throw new ClubError(404, 'not-found', 'Club not found');
    if (this.members.has(this.key(clubId, uid))) {
      throw new ClubError(409, 'already-member', 'Already a member');
    }
    if (this.countClubs(uid) >= MAX_CLUBS_PER_USER) {
      throw new ClubError(409, 'club-limit-reached', `You may join at most ${MAX_CLUBS_PER_USER} clubs`);
    }
    const profile = this.profileFor(uid);
    this.members.set(this.key(clubId, uid), {
      clubId,
      uid,
      role: 'member' as ClubRole,
      displayName: profile.displayName,
      eloChess: profile.eloChess,
      joinedAtMs: ++this.seq,
    });
    club.memberCount += 1;
    return club;
  }

  async leaveClub(uid: string, clubId: string): Promise<void> {
    const club = this.clubs.get(clubId);
    if (!club) throw new ClubError(404, 'not-found', 'Club not found');
    const member = this.members.get(this.key(clubId, uid));
    if (!member) throw new ClubError(404, 'not-member', 'Not a member');
    if (member.role === 'owner' && club.memberCount > 1) {
      throw new ClubError(400, 'owner-cannot-leave', 'Owner cannot leave a non-empty club');
    }
    this.members.delete(this.key(clubId, uid));
    club.memberCount -= 1;
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
  store: FakeClubStore,
  extra: ClubsApiOptions,
  run: (baseUrl: string) => Promise<void>,
): Promise<void> {
  const api = createClubsApi({ store, ...extra });
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

const asUid: ClubsApiOptions = { authenticate: async (t) => ({ uid: t }) };
const bearer = (uid: string) => ({ authorization: `Bearer ${uid}` });
const jsonHeaders = (uid: string) => ({ ...bearer(uid), 'content-type': 'application/json' });

// ── Validation ────────────────────────────────────────────────────────────────

test('validateCreateClubInput normalizes and validates', () => {
  const input = validateCreateClubInput({ name: '  Kỳ Xã Test  ', region: 'Hà Nội', description: '' });
  assert.equal(input.name, 'Kỳ Xã Test');
  assert.equal(input.region, 'Hà Nội');
  assert.equal(input.description, '');

  assert.throws(() => validateCreateClubInput({ name: '', region: 'A' }), (e) => (e as ClubError).code === 'invalid-name');
  assert.throws(() => validateCreateClubInput({ name: 'A', region: '' }), (e) => (e as ClubError).code === 'invalid-region');
  assert.throws(
    () => validateCreateClubInput({ name: 'A'.repeat(61), region: 'A' }),
    (e) => (e as ClubError).code === 'invalid-name',
  );
});

// ── Create / join / leave flow ────────────────────────────────────────────────

test('create club then list/get it', async () => {
  const store = new FakeClubStore();
  store.seedProfile('founder', 'Người Sáng Lập', 1500);
  await withServer(store, asUid, async (baseUrl) => {
    const created = await getJson(
      await fetch(`${baseUrl}/clubs`, {
        method: 'POST',
        headers: jsonHeaders('founder'),
        body: JSON.stringify({ name: 'Kỳ Xã Thăng Long', region: 'Hà Nội', description: 'Vui vẻ' }),
      }),
    );
    assert.equal(created.founderId, 'founder');
    assert.equal(created.memberCount, 1);

    const list = await getJson(await fetch(`${baseUrl}/clubs`));
    assert.equal(list.clubs.length, 1);

    const got = await getJson(await fetch(`${baseUrl}/clubs/${created.id}`));
    assert.equal(got.name, 'Kỳ Xã Thăng Long');

    const members = await getJson(await fetch(`${baseUrl}/clubs/${created.id}/members`));
    assert.equal(members.members.length, 1);
    assert.equal(members.members[0].role, 'owner');
  });
});

test('join then leave updates memberCount, and mine reflects membership', async () => {
  const store = new FakeClubStore();
  store.seedProfile('founder');
  store.seedProfile('joiner');
  await withServer(store, asUid, async (baseUrl) => {
    const club = await getJson(
      await fetch(`${baseUrl}/clubs`, {
        method: 'POST',
        headers: jsonHeaders('founder'),
        body: JSON.stringify({ name: 'CLB', region: 'HN' }),
      }),
    );

    const joined = await getJson(
      await fetch(`${baseUrl}/clubs/${club.id}/join`, { method: 'POST', headers: jsonHeaders('joiner') }),
    );
    assert.equal(joined.memberCount, 2);

    const mine = await getJson(await fetch(`${baseUrl}/clubs/mine`, { headers: bearer('joiner') }));
    assert.deepEqual(
      mine.clubs.map((c: MyClubDoc) => c.clubId),
      [club.id],
    );

    const left = await fetch(`${baseUrl}/clubs/${club.id}/leave`, { method: 'POST', headers: jsonHeaders('joiner') });
    assert.equal(left.status, 200);
    const club2 = await getJson(await fetch(`${baseUrl}/clubs/${club.id}`));
    assert.equal(club2.memberCount, 1);
  });
});

test('joining a 4th club is rejected with club-limit-reached', async () => {
  const store = new FakeClubStore();
  store.seedProfile('u1');
  await withServer(store, asUid, async (baseUrl) => {
    // u1 founds the first club (1 membership), then joins 2 more (3 total = the cap).
    const founded = await getJson(
      await fetch(`${baseUrl}/clubs`, {
        method: 'POST',
        headers: jsonHeaders('u1'),
        body: JSON.stringify({ name: 'CLB 0', region: 'HN' }),
      }),
    );
    assert.equal(founded.memberCount, 1);
    for (let i = 1; i < MAX_CLUBS_PER_USER; i++) {
      const club = await getJson(
        await fetch(`${baseUrl}/clubs`, {
          method: 'POST',
          headers: jsonHeaders(`founder${i}`),
          body: JSON.stringify({ name: `CLB ${i}`, region: 'HN' }),
        }),
      );
      const res = await fetch(`${baseUrl}/clubs/${club.id}/join`, { method: 'POST', headers: jsonHeaders('u1') });
      assert.equal(res.status, 200);
    }
    // u1 now has exactly MAX_CLUBS_PER_USER memberships — one more join must be rejected.
    const oneMore = await getJson(
      await fetch(`${baseUrl}/clubs`, {
        method: 'POST',
        headers: jsonHeaders('founderX'),
        body: JSON.stringify({ name: 'Overflow', region: 'HN' }),
      }),
    );
    const res = await fetch(`${baseUrl}/clubs/${oneMore.id}/join`, { method: 'POST', headers: jsonHeaders('u1') });
    assert.equal(res.status, 409);
    assert.equal((await getJson(res)).code, 'club-limit-reached');
  });
});

test('double-join is rejected with already-member', async () => {
  const store = new FakeClubStore();
  store.seedProfile('founder');
  store.seedProfile('u1');
  await withServer(store, asUid, async (baseUrl) => {
    const club = await getJson(
      await fetch(`${baseUrl}/clubs`, {
        method: 'POST',
        headers: jsonHeaders('founder'),
        body: JSON.stringify({ name: 'CLB', region: 'HN' }),
      }),
    );
    await fetch(`${baseUrl}/clubs/${club.id}/join`, { method: 'POST', headers: jsonHeaders('u1') });
    const res = await fetch(`${baseUrl}/clubs/${club.id}/join`, { method: 'POST', headers: jsonHeaders('u1') });
    assert.equal(res.status, 409);
    assert.equal((await getJson(res)).code, 'already-member');
  });
});

test('owner cannot leave a non-empty club', async () => {
  const store = new FakeClubStore();
  store.seedProfile('founder');
  store.seedProfile('u1');
  await withServer(store, asUid, async (baseUrl) => {
    const club = await getJson(
      await fetch(`${baseUrl}/clubs`, {
        method: 'POST',
        headers: jsonHeaders('founder'),
        body: JSON.stringify({ name: 'CLB', region: 'HN' }),
      }),
    );
    await fetch(`${baseUrl}/clubs/${club.id}/join`, { method: 'POST', headers: jsonHeaders('u1') });
    const res = await fetch(`${baseUrl}/clubs/${club.id}/leave`, { method: 'POST', headers: jsonHeaders('founder') });
    assert.equal(res.status, 400);
    assert.equal((await getJson(res)).code, 'owner-cannot-leave');
  });
});

test('public reads work without a token', async () => {
  const store = new FakeClubStore();
  store.seedProfile('founder');
  await withServer(store, asUid, async (baseUrl) => {
    await fetch(`${baseUrl}/clubs`, {
      method: 'POST',
      headers: jsonHeaders('founder'),
      body: JSON.stringify({ name: 'CLB', region: 'HN' }),
    });
    assert.equal((await fetch(`${baseUrl}/clubs`)).status, 200);
    assert.equal((await fetch(`${baseUrl}/clubs/mine`)).status, 401);
  });
});
