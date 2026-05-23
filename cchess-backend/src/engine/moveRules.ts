// Port of cchess/lib/core/chess_engine/move_rules.dart

import { Board } from './board';
import { Piece, PieceColor, PieceType, oppositeColor } from './piece';
import { Position } from './position';

/// Returns all pseudo-legal target squares for the piece at `from`.
/// "Pseudo-legal" = follows piece movement but may leave own general in check.
export function pseudoLegalMoves(board: Board, from: Position): Position[] {
  const piece = board.at(from);
  if (piece === null) return [];
  switch (piece.type) {
    case PieceType.General: return generalMoves(board, from, piece);
    case PieceType.Advisor: return advisorMoves(board, from, piece);
    case PieceType.Elephant: return elephantMoves(board, from, piece);
    case PieceType.Horse: return horseMoves(board, from, piece);
    case PieceType.Chariot: return chariotMoves(board, from, piece);
    case PieceType.Cannon: return cannonMoves(board, from, piece);
    case PieceType.Soldier: return soldierMoves(board, from, piece);
  }
}

export function isInCheck(board: Board, color: PieceColor): boolean {
  const kingPos = board.generalPosition(color);
  if (kingPos === null) return false;
  if (areGeneralsFacing(board)) return true;
  return isSquareAttackedBy(board, kingPos, oppositeColor(color));
}

export function areGeneralsFacing(board: Board): boolean {
  const red = board.generalPosition(PieceColor.Red);
  const black = board.generalPosition(PieceColor.Black);
  if (red === null || black === null) return false;
  if (red.col !== black.col) return false;
  const col = red.col;
  const low = red.row < black.row ? red.row + 1 : black.row + 1;
  const high = red.row < black.row ? black.row - 1 : red.row - 1;
  for (let r = low; r <= high; r++) {
    if (board.cell(r, col) !== null) return false;
  }
  return true;
}

// ────────────────── individual piece rules ──────────────────

function generalMoves(b: Board, from: Position, p: Piece): Position[] {
  const out: Position[] = [];
  const deltas: [number, number][] = [[-1, 0], [1, 0], [0, -1], [0, 1]];
  for (const [dr, dc] of deltas) {
    const to = from.offset(dr, dc);
    if (!to.isValid) continue;
    if (!to.isInPalace(p.isRed)) continue;
    const occupant = b.at(to);
    if (occupant === null || occupant.color !== p.color) out.push(to);
  }
  return out;
}

function advisorMoves(b: Board, from: Position, p: Piece): Position[] {
  const out: Position[] = [];
  const deltas: [number, number][] = [[-1, -1], [-1, 1], [1, -1], [1, 1]];
  for (const [dr, dc] of deltas) {
    const to = from.offset(dr, dc);
    if (!to.isValid) continue;
    if (!to.isInPalace(p.isRed)) continue;
    const occupant = b.at(to);
    if (occupant === null || occupant.color !== p.color) out.push(to);
  }
  return out;
}

function elephantMoves(b: Board, from: Position, p: Piece): Position[] {
  const out: Position[] = [];
  const deltas: [number, number][] = [[-2, -2], [-2, 2], [2, -2], [2, 2]];
  for (const [dr, dc] of deltas) {
    const to = from.offset(dr, dc);
    if (!to.isValid) continue;
    // Elephants cannot cross the river.
    if (p.isRed && to.row < 5) continue;
    if (!p.isRed && to.row > 4) continue;
    // "Elephant eye" — the midpoint square must be empty.
    const eye = from.offset(Math.trunc(dr / 2), Math.trunc(dc / 2));
    if (b.at(eye) !== null) continue;
    const occupant = b.at(to);
    if (occupant === null || occupant.color !== p.color) out.push(to);
  }
  return out;
}

function horseMoves(b: Board, from: Position, p: Piece): Position[] {
  const out: Position[] = [];
  const legs: [number, number, [number, number][]][] = [
    [-1, 0, [[-2, -1], [-2, 1]]],
    [1, 0, [[2, -1], [2, 1]]],
    [0, -1, [[-1, -2], [1, -2]]],
    [0, 1, [[-1, 2], [1, 2]]],
  ];
  for (const [legDr, legDc, landings] of legs) {
    const legPos = from.offset(legDr, legDc);
    if (!legPos.isValid) continue;
    if (b.at(legPos) !== null) continue; // blocked
    for (const [dr, dc] of landings) {
      const to = from.offset(dr, dc);
      if (!to.isValid) continue;
      const occupant = b.at(to);
      if (occupant === null || occupant.color !== p.color) out.push(to);
    }
  }
  return out;
}

function chariotMoves(b: Board, from: Position, p: Piece): Position[] {
  const out: Position[] = [];
  const directions: [number, number][] = [[-1, 0], [1, 0], [0, -1], [0, 1]];
  for (const [dr, dc] of directions) {
    let r = from.row + dr;
    let c = from.col + dc;
    while (r >= 0 && r < Board.rows && c >= 0 && c < Board.cols) {
      const occupant = b.cell(r, c);
      if (occupant === null) {
        out.push(new Position(r, c));
      } else {
        if (occupant.color !== p.color) out.push(new Position(r, c));
        break;
      }
      r += dr;
      c += dc;
    }
  }
  return out;
}

function cannonMoves(b: Board, from: Position, p: Piece): Position[] {
  const out: Position[] = [];
  const directions: [number, number][] = [[-1, 0], [1, 0], [0, -1], [0, 1]];
  for (const [dr, dc] of directions) {
    let r = from.row + dr;
    let c = from.col + dc;
    // First leg: empty squares (non-capture moves).
    while (r >= 0 && r < Board.rows && c >= 0 && c < Board.cols) {
      if (b.cell(r, c) === null) {
        out.push(new Position(r, c));
        r += dr;
        c += dc;
      } else {
        break;
      }
    }
    // Second leg: after the carriage (the piece we just landed on), the first
    // enemy piece encountered may be captured.
    if (r >= 0 && r < Board.rows && c >= 0 && c < Board.cols) {
      r += dr;
      c += dc;
      while (r >= 0 && r < Board.rows && c >= 0 && c < Board.cols) {
        const occupant = b.cell(r, c);
        if (occupant !== null) {
          if (occupant.color !== p.color) out.push(new Position(r, c));
          break;
        }
        r += dr;
        c += dc;
      }
    }
  }
  return out;
}

function soldierMoves(b: Board, from: Position, p: Piece): Position[] {
  const out: Position[] = [];
  const forwardDr = p.isRed ? -1 : 1;

  const fwd = from.offset(forwardDr, 0);
  if (fwd.isValid) {
    const occupant = b.at(fwd);
    if (occupant === null || occupant.color !== p.color) out.push(fwd);
  }

  // After crossing the river, soldiers can also move sideways.
  const hasCrossed = p.isRed ? from.row <= 4 : from.row >= 5;
  if (hasCrossed) {
    for (const dc of [-1, 1]) {
      const side = from.offset(0, dc);
      if (!side.isValid) continue;
      const occupant = b.at(side);
      if (occupant === null || occupant.color !== p.color) out.push(side);
    }
  }
  return out;
}

function isSquareAttackedBy(
  board: Board,
  target: Position,
  attacker: PieceColor,
): boolean {
  for (const [pos, piece] of board.occupied()) {
    if (piece.color !== attacker) continue;
    const moves = pseudoLegalMoves(board, pos);
    for (const m of moves) {
      if (m.equals(target)) return true;
    }
  }
  return false;
}
