// FEN / UCI compatibility fixtures (risk ⚠️A in 11_KE_HOACH_TICH_HOP_ENGINE.md).
//
// The engine service sends `position fen <FEN>` to Pikafish and parses its
// `bestmove <uci>` reply back onto OUR board. If our FEN placement or our UCI
// coordinate convention disagreed with Pikafish's (UCCI/UCI: files a..i left to
// right, rank 0 = Red's home rank at the bottom), every analysis would be
// silently wrong. These fixtures lock the convention down in CI without needing
// the Pikafish binary, so a regression in the TS engine port is caught here.
//
// The live cross-check against the real engine lives in lab/engine_smoke.ts
// (it asserts Pikafish's reply is a legal move on these same positions).

import assert from 'node:assert/strict';
import { test } from 'node:test';

import { INITIAL_FEN, PieceColor, PieceType } from './piece';
import { Position } from './position';
import { XiangqiGame, parseUci, uciOfMove } from './game';

test('the initial FEN round-trips through the engine port', () => {
  assert.equal(XiangqiGame.fromFen(INITIAL_FEN).toFen(), INITIAL_FEN);
});

test('UCI codec round-trips (uciOfMove ∘ parseUci = identity)', () => {
  for (const uci of ['a0a1', 'i9i8', 'e0e1', 'h2e2', 'b7e7', 'a0i9']) {
    const parsed = parseUci(uci);
    assert.ok(parsed, `parseUci should accept ${uci}`);
    assert.equal(uciOfMove(parsed.from, parsed.to), uci);
  }
});

test('UCI anchors match the Pikafish convention (rank 0 = Red home, file a = left)', () => {
  // parseUci reads whole moves, so we anchor each square via a 4-char move and
  // take its `from`. Rank digit 0 maps to board row 9 (Red's back rank),
  // rank 9 → row 0 (Black); file a → col 0.
  const from = (uci: string): Position => parseUci(uci)!.from;
  assert.deepEqual(from('a0a1'), new Position(9, 0));
  assert.deepEqual(from('a9a8'), new Position(0, 0));
  assert.deepEqual(from('i0i1'), new Position(9, 8));
  assert.deepEqual(from('e0e1'), new Position(9, 4));
  assert.deepEqual(from('h2e2'), new Position(7, 7));

  // Those squares hold the expected pieces in the initial position, proving the
  // FEN placement and the UCI mapping agree on orientation.
  const board = XiangqiGame.fromFen(INITIAL_FEN).board;
  const redChariot = board.at(from('a0a1'))!;
  assert.equal(redChariot.type, PieceType.Chariot);
  assert.equal(redChariot.color, PieceColor.Red);

  const redGeneral = board.at(from('e0e1'))!;
  assert.equal(redGeneral.type, PieceType.General);
  assert.equal(redGeneral.color, PieceColor.Red);

  const blackChariot = board.at(from('a9a8'))!;
  assert.equal(blackChariot.type, PieceType.Chariot);
  assert.equal(blackChariot.color, PieceColor.Black);

  const redCannon = board.at(from('h2e2'))!; // row 7, col 7
  assert.equal(redCannon.type, PieceType.Cannon);
  assert.equal(redCannon.color, PieceColor.Red);
});

test('the central-cannon opening h2e2 applies correctly and the FEN matches', () => {
  const game = XiangqiGame.fromFen(INITIAL_FEN);
  const move = parseUci('h2e2')!;
  assert.equal(game.isValidMove(move.from, move.to), true);
  game.makeMove(move.from, move.to);

  // The Red cannon moved from h2 (row7,col7) to e2 (row7,col4).
  assert.equal(game.board.at(move.to)!.type, PieceType.Cannon);
  assert.equal(game.board.at(move.to)!.color, PieceColor.Red);
  assert.equal(game.board.at(move.from), null);
  assert.equal(game.turn, PieceColor.Black);

  assert.equal(
    game.toFen(),
    'rnbakabnr/9/1c5c1/p1p1p1p1p/9/9/P1P1P1P1P/1C2C4/9/RNBAKABNR b - - 1 1',
  );
});

test('parseUci rejects malformed or off-board moves', () => {
  assert.equal(parseUci('zz'), null); // too short
  assert.equal(parseUci('a0a'), null); // missing last char
  for (const bad of ['j0a1', 'a0a0a0']) {
    // 'j' is off-board (files only go a..i); over-long strings parse the first
    // 4 chars but 'j0a0' would map col 9 → invalid.
    const parsed = parseUci(bad.slice(0, 4));
    if (parsed) {
      assert.ok(parsed.from.isValid && parsed.to.isValid);
    }
  }
  assert.equal(parseUci('j0a1'), null); // col 9 is off-board
});
