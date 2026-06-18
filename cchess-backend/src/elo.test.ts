// Step P-C (test-automation Phase C): unit tests for the pure Elo math that
// drives test-plan cases M5 (ELO 2 chiều, K=32) and G4 (delta dấu/màu). No
// Firebase — computeElo is a pure function, so this runs in `npm test`.

import assert from 'node:assert/strict';
import { test } from 'node:test';

import { computeElo, K_FACTOR } from './elo';

test('K factor is 32 (the rating swing budget the plan assumes)', () => {
  assert.equal(K_FACTOR, 32);
});

test('M5: equal-rated win moves exactly +/-16 (half of K=32)', () => {
  const u = computeElo(1000, 1000, 'red-win');
  assert.equal(u.redDelta, 16);
  assert.equal(u.blackDelta, -16);
  assert.equal(u.redNew, 1016);
  assert.equal(u.blackNew, 984);
});

test('M5: deltas are zero-sum and signs follow the result', () => {
  const win = computeElo(1200, 1000, 'red-win');
  assert.ok(win.redDelta > 0, 'winner gains');
  assert.ok(win.blackDelta < 0, 'loser drops');
  assert.equal(win.redDelta + win.blackDelta, 0, 'rating is conserved');

  const loss = computeElo(1200, 1000, 'black-win');
  assert.ok(loss.redDelta < 0);
  assert.ok(loss.blackDelta > 0);
  assert.equal(loss.redDelta + loss.blackDelta, 0);
});

test('M5: a favourite beating an underdog gains less than the upset would', () => {
  const favouriteWins = computeElo(1400, 1000, 'red-win'); // expected → small gain
  const underdogWins = computeElo(1000, 1400, 'red-win'); // upset → big gain
  assert.ok(
    underdogWins.redDelta > favouriteWins.redDelta,
    'beating a stronger opponent must be worth more rating',
  );
  // Both bounded by K=32.
  assert.ok(favouriteWins.redDelta > 0 && favouriteWins.redDelta <= K_FACTOR);
  assert.ok(underdogWins.redDelta > 0 && underdogWins.redDelta <= K_FACTOR);
});

test('G4: a draw between equal players changes nothing', () => {
  const d = computeElo(1000, 1000, 'draw');
  assert.equal(d.redDelta, 0);
  assert.equal(d.blackDelta, 0);
});

test('G4: a draw nudges the lower-rated player up and the higher one down', () => {
  const d = computeElo(1300, 1000, 'draw');
  assert.ok(d.redDelta < 0, 'the favourite loses rating on a draw');
  assert.ok(d.blackDelta > 0, 'the underdog gains rating on a draw');
  assert.equal(d.redDelta + d.blackDelta, 0);
});
