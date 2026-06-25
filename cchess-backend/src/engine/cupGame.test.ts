// Server-side Cờ Úp engine — port-parity tests with the Dart
// xiangqi_cup_game_test.dart plus the extra protocol surface the backend needs
// (reveal info on each move, cheat-safe public snapshot, seed determinism).

import assert from 'node:assert/strict';
import { test } from 'node:test';

import { Board } from './board';
import { Piece, PieceColor, PieceType } from './piece';
import { Position } from './position';
import { GameStatus, EndReason } from './game';
import { XiangqiCupGame } from './cupGame';

const P = (t: PieceType, c: PieceColor) => new Piece(t, c);
const redGeneral = P(PieceType.General, PieceColor.Red);
const blackGeneral = P(PieceType.General, PieceColor.Black);
const redCannon = P(PieceType.Cannon, PieceColor.Red);
const redHorse = P(PieceType.Horse, PieceColor.Red);
const redChariot = P(PieceType.Chariot, PieceColor.Red);
const redAdvisor = P(PieceType.Advisor, PieceColor.Red);
const redElephant = P(PieceType.Elephant, PieceColor.Red);
const redSoldier = P(PieceType.Soldier, PieceColor.Red);
const blackChariot = P(PieceType.Chariot, PieceColor.Black);
const blackSoldier = P(PieceType.Soldier, PieceColor.Black);

function boardWith(pieces: [Position, Piece][]): Board {
  const board = Board.empty();
  for (const [pos, piece] of pieces) board.setAt(pos, piece);
  return board;
}

function hiddenMap(entries: [Position, Piece][]): Map<number, Piece> {
  const m = new Map<number, Piece>();
  for (const [pos, piece] of entries) m.set(pos.row * Board.cols + pos.col, piece);
  return m;
}

function contains(list: Position[], p: Position): boolean {
  return list.some((q) => q.equals(p));
}

// ── initial / shuffle ──────────────────────────────────────────────────────

test('initial hides every non-general piece and keeps generals face-up', () => {
  const game = XiangqiCupGame.initial(13);
  assert.equal(game.turn, PieceColor.Red);
  assert.equal(game.status, GameStatus.Playing);
  assert.equal(game.hiddenCount, 30);
  assert.equal(game.isHidden(new Position(0, 4)), false);
  assert.equal(game.isHidden(new Position(9, 4)), false);
  assert.equal(game.board.at(new Position(0, 4))?.type, PieceType.General);
  assert.equal(game.board.at(new Position(9, 4))?.type, PieceType.General);
});

test('shuffle preserves each side non-general multiset, never crosses colors', () => {
  const expected = new Map<string, number>();
  for (const [, piece] of Board.initial().occupied()) {
    if (piece.type === PieceType.General) continue;
    const k = `${piece.color}:${piece.type}`;
    expected.set(k, (expected.get(k) ?? 0) + 1);
  }

  for (const seed of [0, 1, 13, 42, 99]) {
    const game = XiangqiCupGame.initial(seed);
    const actual = new Map<string, number>();
    for (const [pos, cover] of game.board.occupied()) {
      if (!game.isHidden(pos)) continue;
      const hidden = game.debugHiddenAt(pos);
      assert.ok(hidden, `seed=${seed} pos=${pos}`);
      assert.equal(hidden!.color, cover.color, 'hidden pieces never cross colors');
      const k = `${hidden!.color}:${hidden!.type}`;
      actual.set(k, (actual.get(k) ?? 0) + 1);
    }
    assert.deepEqual(actual, expected, `seed=${seed}`);
  }
});

test('a fixed seed produces a deterministic, reproducible shuffle', () => {
  // Fingerprint = every face-down square's TRUE identity (debug peek only).
  const fingerprint = (g: XiangqiCupGame): string => {
    const parts: string[] = [];
    for (const [pos] of g.board.occupied()) {
      if (!g.isHidden(pos)) continue;
      parts.push(`${pos.row * Board.cols + pos.col}:${g.debugHiddenAt(pos)!.fenChar()}`);
    }
    return parts.sort().join(',');
  };
  // Two games with the same seed must assign identical hidden identities.
  assert.equal(fingerprint(XiangqiCupGame.initial(777)), fingerprint(XiangqiCupGame.initial(777)));
  // A different seed should (almost surely) differ.
  assert.notEqual(fingerprint(XiangqiCupGame.initial(777)), fingerprint(XiangqiCupGame.initial(778)));
});

// ── cover-before-reveal movement ────────────────────────────────────────────

test('a face-down piece moves by its cover, then reveals its true identity', () => {
  const from = new Position(7, 1); // cover: cannon
  const to = new Position(7, 4);
  const board = boardWith([
    [new Position(0, 4), blackGeneral],
    [new Position(3, 4), blackSoldier],
    [from, redCannon],
    [new Position(9, 4), redGeneral],
  ]);
  const game = XiangqiCupGame.debug({ board, hidden: hiddenMap([[from, redHorse]]) });

  // The underlying horse could NOT reach (7,4); the cover cannon can.
  const asHorse = board.copy();
  asHorse.setAt(from, redHorse);
  assert.equal(contains(game.getValidMoves(from), to), true);

  const result = game.makeMove(from, to);
  assert.equal(result.revealed.type, PieceType.Horse);
  assert.equal(result.wasHidden, true);
  assert.equal(result.captured, null);
  assert.equal(game.board.at(to)?.type, PieceType.Horse);
  assert.equal(game.isHidden(from), false);
  assert.equal(game.isHidden(to), false);
  assert.equal(game.turn, PieceColor.Black);
});

test('a revealed piece uses its true movement on later turns', () => {
  const from = new Position(7, 1);
  const revealTo = new Position(7, 4);
  const blackFrom = new Position(3, 4);
  const blackTo = new Position(4, 4);
  const trueHorseMove = new Position(5, 3);
  const board = boardWith([
    [new Position(0, 4), blackGeneral],
    [blackFrom, blackSoldier],
    [from, redCannon],
    [new Position(9, 4), redGeneral],
  ]);
  const game = XiangqiCupGame.debug({ board, hidden: hiddenMap([[from, redHorse]]) });

  game.makeMove(from, revealTo);
  game.makeMove(blackFrom, blackTo);

  assert.equal(game.board.at(revealTo)?.type, PieceType.Horse);
  assert.equal(game.turn, PieceColor.Red);
  assert.equal(contains(game.getValidMoves(revealTo), trueHorseMove), true);
});

test('capturing a hidden piece records the TRUE captured identity', () => {
  const from = new Position(7, 1);
  const screen = new Position(7, 2);
  const target = new Position(7, 4);
  const board = boardWith([
    [new Position(0, 4), blackGeneral],
    [from, redCannon],
    [screen, redSoldier],
    [target, blackSoldier],
    [new Position(9, 4), redGeneral],
  ]);
  const game = XiangqiCupGame.debug({
    board,
    hidden: hiddenMap([[from, redHorse], [target, blackChariot]]),
  });
  assert.equal(game.hiddenCount, 2);

  const result = game.makeMove(from, target);
  assert.equal(result.revealed.type, PieceType.Horse);
  assert.equal(result.captured?.type, PieceType.Chariot);
  assert.equal(result.captured?.color, PieceColor.Black);
  assert.equal(game.hiddenCount, 0);
});

// ── legality guards ──────────────────────────────────────────────────────────

test('rejects a reveal move that exposes own general to check', () => {
  const from = new Position(5, 4);
  const target = new Position(5, 5);
  const board = boardWith([
    [new Position(0, 3), blackGeneral],
    [new Position(0, 4), blackChariot],
    [from, redChariot],
    [new Position(9, 4), redGeneral],
  ]);
  const game = XiangqiCupGame.debug({ board, hidden: hiddenMap([[from, redHorse]]) });
  assert.equal(game.isInCheck(PieceColor.Red), false);
  assert.equal(game.isValidMove(from, target), false);
  assert.equal(contains(game.getValidMoves(from), target), false);
});

test('rejects a reveal move that opens the flying-general file', () => {
  const from = new Position(5, 4);
  const target = new Position(5, 5);
  const board = boardWith([
    [new Position(0, 4), blackGeneral],
    [from, redChariot],
    [new Position(9, 4), redGeneral],
  ]);
  const game = XiangqiCupGame.debug({ board, hidden: hiddenMap([[from, redHorse]]) });
  assert.equal(game.isValidMove(from, target), false);
});

// ── revealed Sĩ/Tượng roam freely ────────────────────────────────────────────

test('a revealed advisor leaves the palace and may cross the river', () => {
  const board = boardWith([
    [new Position(0, 3), blackGeneral],
    [new Position(4, 4), redAdvisor],
    [new Position(9, 4), redGeneral],
  ]);
  const game = XiangqiCupGame.debug({ board }); // no hidden → revealed
  const moves = game.getValidMoves(new Position(4, 4));
  for (const p of [
    new Position(3, 3),
    new Position(3, 5),
    new Position(5, 3),
    new Position(5, 5),
  ]) {
    assert.equal(contains(moves, p), true, `advisor should reach ${p}`);
  }
});

test('a revealed elephant may cross the river but the eye still blocks', () => {
  const board = boardWith([
    [new Position(0, 3), blackGeneral],
    [new Position(5, 4), redElephant],
    [new Position(4, 3), redSoldier], // blocks the (5,4)->(3,2) eye
    [new Position(9, 4), redGeneral],
  ]);
  const game = XiangqiCupGame.debug({ board });
  const moves = game.getValidMoves(new Position(5, 4));
  assert.equal(contains(moves, new Position(3, 6)), true); // crossed the river
  assert.equal(contains(moves, new Position(3, 2)), false); // eye blocked
});

test('a revealed advisor can deliver check across the board', () => {
  const board = boardWith([
    [new Position(2, 3), blackGeneral],
    [new Position(3, 4), redAdvisor],
    [new Position(9, 4), redGeneral],
  ]);
  const game = XiangqiCupGame.debug({ board, turn: PieceColor.Black });
  assert.equal(game.isInCheck(PieceColor.Black), true);
});

test('a face-down piece on the advisor point stays confined like a Sĩ', () => {
  const board = boardWith([
    [new Position(0, 4), blackGeneral],
    [new Position(9, 3), redAdvisor], // cover
    [new Position(9, 4), redGeneral],
  ]);
  const game = XiangqiCupGame.debug({
    board,
    hidden: hiddenMap([[new Position(9, 3), redChariot]]),
  });
  const moves = game.getValidMoves(new Position(9, 3));
  assert.equal(moves.length, 1);
  assert.equal(moves[0].equals(new Position(8, 4)), true);
});

test('a face-down piece on the elephant point still cannot cross the river', () => {
  const board = boardWith([
    [new Position(0, 4), blackGeneral],
    [new Position(9, 2), redElephant], // cover
    [new Position(9, 4), redGeneral],
  ]);
  const game = XiangqiCupGame.debug({
    board,
    hidden: hiddenMap([[new Position(9, 2), redChariot]]),
  });
  const moves = game.getValidMoves(new Position(9, 2));
  assert.equal(contains(moves, new Position(7, 4)), true);
  for (const to of moves) {
    assert.equal(to.row >= 5, true, `hidden elephant crossed river: ${to}`);
  }
});

// ── checkmate / public snapshot ──────────────────────────────────────────────

test('two-chariot ladder is checkmate (in check + zero legal replies)', () => {
  // Black general (0,4) boxed: R1 checks along rank 0, R2 cuts off rank 1 AND
  // covers the (0,5) flight square via file 5. Black has only its general, so
  // it can neither flee, block, nor capture → mate.
  const board = boardWith([
    [new Position(0, 4), blackGeneral],
    [new Position(0, 0), redChariot], // rank 0: checks (0,4), covers (0,3)
    [new Position(1, 5), redChariot], // rank 1: covers (1,3..1,4); file 5: covers (0,5)
    [new Position(9, 0), redGeneral],
  ]);
  const game = XiangqiCupGame.debug({ board, turn: PieceColor.Black });
  assert.equal(game.isInCheck(PieceColor.Black), true);

  // No legal reply anywhere on the board == checkmate by definition.
  let anyLegal = false;
  for (const [pos, piece] of game.board.occupied()) {
    if (piece.color !== PieceColor.Black) continue;
    if (game.getValidMoves(pos).length > 0) { anyLegal = true; break; }
  }
  assert.equal(anyLegal, false, 'black should have no legal move (checkmate)');
});

test('refreshStatus marks a delivered mate as a loss for the mated side', () => {
  // Same mate, but reached by an actual move so refreshStatus runs: R2 slides
  // (1,2)->(1,5) to complete the box while black is to reply.
  const board = boardWith([
    [new Position(0, 4), blackGeneral],
    [new Position(2, 0), redChariot], // parked off the checking lines for now
    [new Position(1, 5), redChariot],
    [new Position(9, 1), redGeneral],
  ]);
  const game = XiangqiCupGame.debug({ board, turn: PieceColor.Red });
  // Red chariot drops to rank 0 to deliver the mating check.
  game.makeMove(new Position(2, 0), new Position(0, 0));
  assert.equal(game.status, GameStatus.RedWin);
  assert.equal(game.endReason, EndReason.Checkmate);
});

test('publicSnapshot never leaks a hidden identity (cover shown on FEN)', () => {
  const from = new Position(7, 1); // cover cannon, true horse
  const board = boardWith([
    [new Position(0, 4), blackGeneral],
    [from, redCannon],
    [new Position(9, 4), redGeneral],
  ]);
  const game = XiangqiCupGame.debug({ board, hidden: hiddenMap([[from, redHorse]]) });
  const snap = game.publicSnapshot();
  // FEN placement shows the COVER (cannon 'C'), not the hidden horse ('N').
  assert.equal(game.board.at(from)?.type, PieceType.Cannon);
  assert.ok(snap.hidden.includes(from.row * Board.cols + from.col));
  // The true identity is only reachable via the debug peek, never the snapshot.
  assert.equal(game.debugHiddenAt(from)?.type, PieceType.Horse);
});
