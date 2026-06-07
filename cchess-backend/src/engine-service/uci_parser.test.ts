import assert from 'node:assert/strict';
import { test } from 'node:test';

import { parseBestMoveLine, parseInfoLine } from './uci_parser';

test('parseInfoLine extracts depth cp score and pv', () => {
  const parsed = parseInfoLine('info depth 12 score cp 35 nodes 100 pv h2e2 h7e7');
  assert.deepEqual(parsed, {
    depth: 12,
    scoreCp: 35,
    pv: ['h2e2', 'h7e7'],
  });
});

test('parseInfoLine converts mate score to large centipawns', () => {
  const parsed = parseInfoLine('info depth 8 score mate -3 pv e0e1');
  assert.equal(parsed?.scoreCp, -99_997);
});

test('parseBestMoveLine accepts Xiangqi UCI and none', () => {
  assert.equal(parseBestMoveLine('bestmove h2e2 ponder h7e7'), 'h2e2');
  assert.equal(parseBestMoveLine('bestmove (none)'), null);
  assert.equal(parseBestMoveLine('info depth 1'), undefined);
});
