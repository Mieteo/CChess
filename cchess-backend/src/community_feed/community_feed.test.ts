import assert from 'node:assert/strict';
import { test } from 'node:test';
import { createServer, type Server } from 'node:http';
import type { AddressInfo } from 'node:net';

import { createCommunityFeedApi, type CommunityFeedApiOptions } from './community_feed_routes';
import type { CommunityFeedStore } from './community_feed_store';
import { FeedError, validateFeedItemInput, type CommunityFeedDoc, type FeedItemInput } from './types';

// ── In-memory store fake ─────────────────────────────────────────────────────

class FakeFeedStore implements CommunityFeedStore {
  readonly items = new Map<string, CommunityFeedDoc>();
  private seq = 0;

  seedItem(doc: Partial<CommunityFeedDoc> & { id: string; type: CommunityFeedDoc['type']; title: string }): void {
    this.items.set(doc.id, {
      subtitle: '',
      meta: '',
      route: null,
      linkUrl: null,
      sortOrder: 0,
      active: true,
      createdAtMs: ++this.seq,
      updatedAtMs: this.seq,
      ...doc,
    });
  }

  async listItems(opts: { activeOnly?: boolean } = {}): Promise<CommunityFeedDoc[]> {
    let all = [...this.items.values()];
    if (opts.activeOnly !== false) all = all.filter((i) => i.active);
    all.sort((a, b) => a.sortOrder - b.sortOrder || a.id.localeCompare(b.id));
    return all;
  }

  async upsertItem(input: FeedItemInput): Promise<CommunityFeedDoc> {
    const id = input.id ?? `gen-${++this.seq}`;
    const doc: CommunityFeedDoc = {
      id,
      type: input.type,
      title: input.title,
      subtitle: input.subtitle,
      meta: input.meta,
      route: input.route,
      linkUrl: input.linkUrl,
      sortOrder: input.sortOrder,
      active: input.active,
      createdAtMs: ++this.seq,
      updatedAtMs: this.seq,
    };
    this.items.set(id, doc);
    return doc;
  }

  async removeItem(id: string): Promise<boolean> {
    return this.items.delete(id);
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
  store: FakeFeedStore,
  extra: CommunityFeedApiOptions,
  run: (baseUrl: string) => Promise<void>,
): Promise<void> {
  const api = createCommunityFeedApi({ store, ...extra });
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

// ── Validation ────────────────────────────────────────────────────────────────

test('validateFeedItemInput normalizes and defaults', () => {
  const input = validateFeedItemInput({
    type: 'puzzle',
    title: '  Tàn Cục Thách Đấu  ',
    subtitle: 'Chiếu hết 3 nước',
    route: 'daily_puzzle',
  });
  assert.equal(input.title, 'Tàn Cục Thách Đấu');
  assert.equal(input.route, 'daily_puzzle');
  assert.equal(input.linkUrl, null);
  assert.equal(input.active, true);
});

const hasCode = (code: string) => (e: unknown) => (e as FeedError).code === code;

test('validateFeedItemInput rejects bad type / missing fields', () => {
  assert.throws(() => validateFeedItemInput({ type: 'blog', title: 'x', subtitle: 'y' }), hasCode('invalid-type'));
  assert.throws(() => validateFeedItemInput({ type: 'news', title: '', subtitle: 'y' }), hasCode('invalid-title'));
  assert.throws(() => validateFeedItemInput({ type: 'news', title: 'x', subtitle: '' }), hasCode('invalid-subtitle'));
});

// ── Public feed ───────────────────────────────────────────────────────────────

test('GET /community/feed returns active items sorted, no auth needed', async () => {
  const store = new FakeFeedStore();
  store.seedItem({ id: 'a', type: 'news', title: 'A', sortOrder: 2 });
  store.seedItem({ id: 'b', type: 'puzzle', title: 'B', sortOrder: 1, route: 'daily_puzzle' });
  store.seedItem({ id: 'hidden', type: 'news', title: 'Hidden', active: false });
  await withServer(store, {}, async (baseUrl) => {
    const body = await getJson(await fetch(`${baseUrl}/community/feed`));
    assert.deepEqual(
      body.items.map((i: CommunityFeedDoc) => i.id),
      ['b', 'a'],
    );
    assert.equal(body.items[0].route, 'daily_puzzle');
  });
});

// ── Admin guard ───────────────────────────────────────────────────────────────

test('admin write requires credentials', async () => {
  const store = new FakeFeedStore();
  await withServer(store, { isAdmin: () => false }, async (baseUrl) => {
    const denied = await fetch(`${baseUrl}/admin/community/feed`, {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify({ type: 'news', title: 'X', subtitle: 'Y' }),
    });
    assert.equal(denied.status, 403);
  });
  await withServer(store, { isAdmin: () => true }, async (baseUrl) => {
    const ok = await fetch(`${baseUrl}/admin/community/feed`, {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify({ type: 'news', title: 'X', subtitle: 'Y' }),
    });
    assert.equal(ok.status, 201);
  });
});

test('admin can update and delete an item', async () => {
  const store = new FakeFeedStore();
  store.seedItem({ id: 'a', type: 'news', title: 'A', subtitle: 'orig' });
  await withServer(store, { isAdmin: () => true }, async (baseUrl) => {
    const updated = await getJson(
      await fetch(`${baseUrl}/admin/community/feed/a`, {
        method: 'PUT',
        headers: { 'content-type': 'application/json' },
        body: JSON.stringify({ type: 'news', title: 'A', subtitle: 'updated' }),
      }),
    );
    assert.equal(updated.subtitle, 'updated');

    const del = await fetch(`${baseUrl}/admin/community/feed/a`, { method: 'DELETE' });
    assert.equal(del.status, 200);
    const missing = await fetch(`${baseUrl}/admin/community/feed/a`, { method: 'DELETE' });
    assert.equal(missing.status, 404);
  });
});
