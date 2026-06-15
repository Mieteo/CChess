// Render deploy/monitor helper. Reads RENDER_API_KEY from the environment
// (never logged) and talks to the Render REST API so a deploy can be triggered
// and watched from the terminal — no dashboard needed.
//
//   RENDER_API_KEY=... npm run render:status            # latest deploy state
//   RENDER_API_KEY=... npm run render:deploy             # trigger + watch
//   ... npm run render:status -- cchess-engine           # a different service
//
// Get a key: Render dashboard → Account Settings → API Keys. Prefer setting it
// as a persistent env var rather than pasting it inline.

const API = 'https://api.render.com/v1';
const KEY = process.env.RENDER_API_KEY;

interface Service {
  id: string;
  name: string;
  type: string;
  suspended?: string;
}
interface Deploy {
  id: string;
  status: string;
  createdAt?: string;
  finishedAt?: string;
  commit?: { id?: string; message?: string };
}

const TERMINAL = new Set([
  'live',
  'deactivated',
  'build_failed',
  'update_failed',
  'pre_deploy_failed',
  'canceled',
]);
const FAILED = new Set([
  'build_failed',
  'update_failed',
  'pre_deploy_failed',
  'canceled',
  'deactivated',
]);

async function api<T>(path: string, init?: RequestInit): Promise<T> {
  const res = await fetch(`${API}${path}`, {
    ...init,
    headers: {
      Authorization: `Bearer ${KEY}`,
      Accept: 'application/json',
      'Content-Type': 'application/json',
      ...(init?.headers ?? {}),
    },
  });
  const text = await res.text();
  if (!res.ok) {
    throw new Error(`Render API ${res.status} on ${path}: ${text.slice(0, 300)}`);
  }
  return (text ? JSON.parse(text) : {}) as T;
}

async function findService(name: string): Promise<Service> {
  const rows = await api<{ service: Service }[]>(
    `/services?name=${encodeURIComponent(name)}&limit=20`,
  );
  const match = rows.map((r) => r.service).find((s) => s.name === name);
  if (!match) throw new Error(`no Render service named "${name}"`);
  return match;
}

async function latestDeploy(serviceId: string): Promise<Deploy | null> {
  const rows = await api<{ deploy: Deploy }[]>(
    `/services/${serviceId}/deploys?limit=1`,
  );
  return rows[0]?.deploy ?? null;
}

function fmt(d: Deploy): string {
  const c = d.commit?.id ? d.commit.id.slice(0, 7) : '—';
  const msg = d.commit?.message?.split('\n')[0] ?? '';
  return `deploy ${d.id} · status=${d.status} · commit ${c} ${msg}`;
}

const sleep = (ms: number): Promise<void> => new Promise((r) => setTimeout(r, ms));

async function watch(serviceId: string, deployId: string): Promise<void> {
  const started = Date.now();
  let last = '';
  for (;;) {
    const d = await api<Deploy>(`/services/${serviceId}/deploys/${deployId}`);
    if (d.status !== last) {
      console.log(`  · ${d.status}  (+${Math.round((Date.now() - started) / 1000)}s)`);
      last = d.status;
    }
    if (TERMINAL.has(d.status)) {
      if (FAILED.has(d.status)) {
        console.log(`\n✘ deploy ended: ${d.status}\n`);
        process.exitCode = 1;
      } else {
        console.log(`\n✔ deploy is LIVE (${fmt(d)})\n`);
      }
      return;
    }
    if (Date.now() - started > 20 * 60_000) {
      console.log('\n✘ gave up waiting after 20 min (still building?)\n');
      process.exitCode = 1;
      return;
    }
    await sleep(6000);
  }
}

async function main(): Promise<void> {
  if (!KEY) {
    console.error(
      'RENDER_API_KEY is not set. Get one at Render → Account Settings → API Keys,\n' +
        'then set it in your environment (do not paste it into the repo).',
    );
    process.exitCode = 1;
    return;
  }
  const cmd = process.argv[2] ?? 'status';
  const serviceName = process.argv[3] ?? 'cchess-backend';

  const svc = await findService(serviceName);
  console.log(`\nService: ${svc.name} (${svc.id})${svc.suspended === 'suspended' ? ' [SUSPENDED]' : ''}`);

  if (cmd === 'status') {
    const d = await latestDeploy(svc.id);
    console.log(d ? `Latest: ${fmt(d)}\n` : 'No deploys yet.\n');
    return;
  }

  if (cmd === 'deploy') {
    console.log('Triggering deploy of latest commit…');
    const d = await api<Deploy>(`/services/${svc.id}/deploys`, {
      method: 'POST',
      body: JSON.stringify({ clearCache: 'do_not_clear' }),
    });
    console.log(`Started ${fmt(d)}`);
    await watch(svc.id, d.id);
    return;
  }

  console.error(`unknown command "${cmd}" (use: status | deploy [serviceName])`);
  process.exitCode = 1;
}

main().catch((e) => {
  console.error(`\n✘ ${e instanceof Error ? e.message : String(e)}\n`);
  process.exitCode = 1;
});
