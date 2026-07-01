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
        else if (trimmed.startsWith('go ')) {
          // Always report 4 MultiPV lines (regardless of whether MultiPV was
          // actually raised) so blunder-roll tests have alternates to pick.
          stdout.emit('data', 'info depth 5 multipv 1 score cp 50 pv h2e2 h7e7\n');
          stdout.emit('data', 'info depth 5 multipv 2 score cp 40 pv h2c2 h7e7\n');
          stdout.emit('data', 'info depth 5 multipv 3 score cp 30 pv b2c2 h7e7\n');
          stdout.emit('data', 'info depth 5 multipv 4 score cp 20 pv g3g4 h7e7\n');
          stdout.emit('data', 'bestmove h2e2\n');
        }
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

test('blunderRate 1 raises MultiPV before go, resets after, and plays an alternate', async () => {
  const writes: string[] = [];
  const engine = makeEngine(writes);

  const result = await engine.bestMove(FEN, { movetimeMs: 250, blunderRate: 1 });

  const goIdx = writes.findIndex((l) => l.startsWith('go '));
  const multiPvOnIdx = writes.indexOf('setoption name MultiPV value 4');
  assert.ok(multiPvOnIdx >= 0, 'raises MultiPV before searching');
  assert.ok(multiPvOnIdx < goIdx, 'MultiPV is set before the search starts');

  const resetIdx = writes.indexOf('setoption name MultiPV value 1');
  assert.ok(resetIdx > goIdx, 'MultiPV is reset to 1 after the search');

  // blunderRate 1 always rolls a blunder, so the engine's actual best move
  // (h2e2, multipv 1) must NOT be the one played.
  assert.notEqual(result.uci, 'h2e2');
  assert.ok(['h2c2', 'b2c2', 'g3g4'].includes(result.uci ?? ''));

  engine.dispose();
});

test('no blunderRate never touches MultiPV and always plays the engine\'s best move', async () => {
  const writes: string[] = [];
  const engine = makeEngine(writes);

  const result = await engine.bestMove(FEN, { movetimeMs: 250 });

  assert.ok(
    !writes.some((l) => l.startsWith('setoption name MultiPV')),
    'no MultiPV option for a full-strength search',
  );
  assert.equal(result.uci, 'h2e2');

  engine.dispose();
});

test('blunderRate 0 behaves identically to no blunderRate', async () => {
  const writes: string[] = [];
  const engine = makeEngine(writes);

  const result = await engine.bestMove(FEN, { movetimeMs: 250, blunderRate: 0 });

  assert.ok(!writes.some((l) => l.startsWith('setoption name MultiPV')));
  assert.equal(result.uci, 'h2e2');

  engine.dispose();
});
