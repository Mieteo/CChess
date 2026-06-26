import assert from 'node:assert/strict';
import { EventEmitter } from 'node:events';
import { test } from 'node:test';
import type { ChildProcessWithoutNullStreams } from 'node:child_process';

import { UciEngine } from './uci_engine';

const FEN = '4k4/9/9/9/9/9/9/9/9/4K4 w - - 0 1';

/// A stand-in Pikafish process that records every command written to stdin and
/// auto-replies (uciok / readyok / bestmove) like the real engine, so we can
/// assert exactly which `setoption` lines a search emits.
function makeFakeProcess(writes: string[]): ChildProcessWithoutNullStreams {
  const stdout = new EventEmitter() as EventEmitter & {
    setEncoding: (enc: string) => void;
  };
  stdout.setEncoding = () => {};
  const stderr = new EventEmitter() as EventEmitter & {
    setEncoding: (enc: string) => void;
  };
  stderr.setEncoding = () => {};

  const proc = new EventEmitter() as unknown as ChildProcessWithoutNullStreams & {
    killed: boolean;
  };
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  (proc as any).stdout = stdout;
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  (proc as any).stderr = stderr;
  proc.killed = false;
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  (proc as any).kill = () => {
    proc.killed = true;
    return true;
  };
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  (proc as any).stdin = {
    write(line: string) {
      const trimmed = line.replace(/\n$/, '');
      writes.push(trimmed);
      // Reply asynchronously so the waiter is registered before we emit.
      setImmediate(() => {
        if (trimmed === 'uci') stdout.emit('data', 'uciok\n');
        else if (trimmed === 'isready') stdout.emit('data', 'readyok\n');
        else if (trimmed.startsWith('go ')) stdout.emit('data', 'bestmove h2e2\n');
      });
      return true;
    },
  };
  return proc;
}

function makeEngine(writes: string[]): UciEngine {
  return new UciEngine({
    binaryPath: 'fake-pikafish',
    threads: 1,
    hashMb: 16,
    defaultMovetimeMs: 100,
    initTimeoutMs: 1000,
    searchTimeoutMs: 1000,
    spawnProcess: () => makeFakeProcess(writes),
  });
}

test('bestMove sets UCI_Elo before go, then resets to full strength after', async () => {
  const writes: string[] = [];
  const engine = makeEngine(writes);

  const result = await engine.bestMove(FEN, {
    movetimeMs: 250,
    skillLevel: 6,
    uciElo: 2050,
  });
  assert.equal(result.uci, 'h2e2');

  const goIdx = writes.findIndex((l) => l.startsWith('go '));
  const limitOnIdx = writes.indexOf('setoption name UCI_LimitStrength value true');
  const eloIdx = writes.indexOf('setoption name UCI_Elo value 2050');
  assert.ok(limitOnIdx >= 0 && eloIdx >= 0, 'enables UCI_LimitStrength + UCI_Elo');
  assert.ok(eloIdx < goIdx, 'strength is set before the search starts');

  const resetIdx = writes.indexOf('setoption name UCI_LimitStrength value false');
  assert.ok(resetIdx > goIdx, 'strength is reset after the search');
  assert.ok(
    writes.includes('setoption name Skill Level value 20'),
    'skill restored to full',
  );

  engine.dispose();
});

test('bestMove uses Skill Level when only skill is provided', async () => {
  const writes: string[] = [];
  const engine = makeEngine(writes);

  await engine.bestMove(FEN, { movetimeMs: 250, skillLevel: 6 });

  assert.ok(writes.includes('setoption name Skill Level value 6'));
  assert.ok(!writes.some((l) => l.includes('UCI_Elo')), 'no UCI_Elo when skill-only');

  engine.dispose();
});

test('full-strength search emits no strength options', async () => {
  const writes: string[] = [];
  const engine = makeEngine(writes);

  await engine.bestMove(FEN, { movetimeMs: 250 });

  assert.ok(
    !writes.some(
      (l) =>
        l.startsWith('setoption name UCI_LimitStrength') ||
        l.startsWith('setoption name UCI_Elo') ||
        l.startsWith('setoption name Skill Level'),
    ),
    'no strength options for a full-strength search',
  );

  engine.dispose();
});
