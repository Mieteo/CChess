// Run a single scenario against a fresh, isolated in-process server. Shared by
// the headless runner (lab/runner.ts) and the dashboard's scenario buttons
// (lab/control.ts) so both agree on setup, teardown, and the final invariant
// check.

import { Bot } from './bot';
import { startLabServer, sleep } from './harness';
import { checkInvariants } from './invariants';
import type { Lab, Scenario } from './scenarios';
import { __resetRoomsForLab } from '../src/rooms';
import { __resetQueueForLab } from '../src/matchmaking';

export function resetState(): void {
  __resetRoomsForLab();
  __resetQueueForLab();
}

export function assertHealthy(label = ''): void {
  const violations = checkInvariants();
  if (violations.length > 0) {
    const lines = violations.map((v) => `    • [${v.rule}] ${v.detail}`).join('\n');
    throw new Error(`invariant(s) violated${label ? ` (${label})` : ''}:\n${lines}`);
  }
}

export interface ScenarioResult {
  name: string;
  ok: boolean;
  ms: number;
  error?: string;
}

export async function runScenario(sc: Scenario): Promise<ScenarioResult> {
  const t0 = Date.now();
  resetState();
  const { url, close } = await startLabServer(sc.timing);
  const bots: Bot[] = [];
  const lab: Lab = {
    url,
    bot: async (uid) => {
      const b = new Bot(url, uid);
      bots.push(b);
      await b.connectAuthed();
      return b;
    },
    rawBot: (uid) => {
      const b = new Bot(url, uid);
      bots.push(b);
      return b;
    },
    assertHealthy,
    sleep,
  };
  try {
    await sc.run(lab);
    assertHealthy('final');
    return { name: sc.name, ok: true, ms: Date.now() - t0 };
  } catch (e) {
    return {
      name: sc.name,
      ok: false,
      ms: Date.now() - t0,
      error: e instanceof Error ? e.message : String(e),
    };
  } finally {
    for (const b of bots) await b.close().catch(() => {});
    await close();
  }
}
