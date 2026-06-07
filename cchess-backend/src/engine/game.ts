// Port of cchess/lib/core/chess_engine/xiangqi_game.dart
//
// Top-level Xiangqi game state — used by the backend `match.ts` to validate
// online moves (Step 5 of the WS roadmap).

import { Board } from './board';
import { Piece, PieceColor, PieceType, oppositeColor } from './piece';
import { Position } from './position';
import {
  areGeneralsFacing,
  isInCheck,
  pseudoLegalMoves,
} from './moveRules';

export enum GameStatus {
  Playing = 'playing',
  RedWin = 'red-win',
  BlackWin = 'black-win',
  Draw = 'draw',
}

export function statusIsOver(s: GameStatus): boolean {
  return s !== GameStatus.Playing;
}

export enum EndReason {
  Checkmate = 'checkmate',
  Stalemate = 'stalemate',
  Resignation = 'resignation',
  Timeout = 'timeout',
  DrawAgreed = 'drawAgreed',
  Repetition = 'repetition',
}

export interface MoveRecord {
  from: Position;
  to: Position;
  moved: Piece;
  captured: Piece | null;
}

export class XiangqiGame {
  private _board: Board;
  private _turn: PieceColor;
  private _status: GameStatus;
  private _endReason: EndReason | null;
  private _history: MoveRecord[];
  private _halfmoveClock: number;
  private _fullmoveNumber: number;

  private constructor(
    board: Board,
    turn: PieceColor,
    status: GameStatus,
    history: MoveRecord[],
    halfmoveClock: number,
    fullmoveNumber: number,
  ) {
    this._board = board;
    this._turn = turn;
    this._status = status;
    this._endReason = null;
    this._history = history;
    this._halfmoveClock = halfmoveClock;
    this._fullmoveNumber = fullmoveNumber;
  }

  static initial(): XiangqiGame {
    return new XiangqiGame(
      Board.initial(),
      PieceColor.Red,
      GameStatus.Playing,
      [],
      0,
      1,
    );
  }

  static fromFen(fen: string): XiangqiGame {
    const parts = fen.trim().split(/\s+/);
    const board = Board.fromFen(parts[0] ?? '');
    const turn = parts[1] === 'b' ? PieceColor.Black : PieceColor.Red;
    const halfmoveClock = Number.parseInt(parts[4] ?? '0', 10);
    const fullmoveNumber = Number.parseInt(parts[5] ?? '1', 10);
    return new XiangqiGame(
      board,
      turn,
      GameStatus.Playing,
      [],
      Number.isFinite(halfmoveClock) ? halfmoveClock : 0,
      Number.isFinite(fullmoveNumber) ? fullmoveNumber : 1,
    );
  }

  // ──────────────── public read-only state ────────────────

  get board(): Board { return this._board; }
  get turn(): PieceColor { return this._turn; }
  get status(): GameStatus { return this._status; }
  get endReason(): EndReason | null { return this._endReason; }
  get history(): readonly MoveRecord[] { return this._history; }
  get halfmoveClock(): number { return this._halfmoveClock; }
  get fullmoveNumber(): number { return this._fullmoveNumber; }
  get lastMove(): MoveRecord | null {
    return this._history.length === 0 ? null : this._history[this._history.length - 1];
  }

  toFen(): string {
    const side = this._turn === PieceColor.Red ? 'w' : 'b';
    return `${this._board.toFenPlacement()} ${side} - - ${this._halfmoveClock} ${this._fullmoveNumber}`;
  }

  // ──────────────── move generation ────────────────

  /// All fully-legal moves for the piece at `from`. Filters pseudo-legal
  /// moves by ensuring the resulting position does not leave the moving
  /// side's general attacked (including flying-general rule).
  getValidMoves(from: Position): Position[] {
    const piece = this._board.at(from);
    if (piece === null) return [];
    if (piece.color !== this._turn) return [];

    const candidates = pseudoLegalMoves(this._board, from);
    const legal: Position[] = [];
    for (const to of candidates) {
      if (this.isLegalMove(from, to, piece)) legal.push(to);
    }
    return legal;
  }

  /// True if the (from, to) pair is currently a legal move.
  isValidMove(from: Position, to: Position): boolean {
    if (statusIsOver(this._status)) return false;
    const piece = this._board.at(from);
    if (piece === null || piece.color !== this._turn) return false;
    const candidates = pseudoLegalMoves(this._board, from);
    let inCandidates = false;
    for (const c of candidates) {
      if (c.equals(to)) { inCandidates = true; break; }
    }
    if (!inCandidates) return false;
    return this.isLegalMove(from, to, piece);
  }

  private isLegalMove(from: Position, to: Position, piece: Piece): boolean {
    // Try the move on a copy, then check.
    const copy = this._board.copy();
    const captured = copy.at(to);
    copy.setAt(to, piece);
    copy.setAt(from, null);
    if (isInCheck(copy, piece.color)) return false;
    if (areGeneralsFacing(copy)) return false;
    return captured === null || captured.color !== piece.color;
  }

  /// Apply the given move, advancing the game state. Throws if illegal.
  makeMove(from: Position, to: Position): MoveRecord {
    if (statusIsOver(this._status)) {
      throw new Error(`Game is over (${this._status})`);
    }
    const piece = this._board.at(from);
    if (piece === null) {
      throw new Error(`No piece at ${from.toString()}`);
    }
    if (piece.color !== this._turn) {
      throw new Error(
        `It is ${this._turn}'s turn but piece is ${piece.color}`,
      );
    }
    if (!this.isValidMove(from, to)) {
      throw new Error(`Illegal move: ${from.toString()} → ${to.toString()}`);
    }

    const captured = this._board.at(to);
    const move: MoveRecord = { from, to, moved: piece, captured };

    this._board.setAt(to, piece);
    this._board.setAt(from, null);
    this._history.push(move);

    if (captured !== null || piece.type === PieceType.Soldier) {
      this._halfmoveClock = 0;
    } else {
      this._halfmoveClock++;
    }
    if (this._turn === PieceColor.Black) this._fullmoveNumber++;
    this._turn = oppositeColor(this._turn);

    this.refreshStatus();
    return move;
  }

  private refreshStatus(): void {
    const color = this._turn;
    const inCheck = isInCheck(this._board, color);
    const hasAnyMove = this.sideHasAnyLegalMove(color);

    if (!hasAnyMove) {
      // Stalemate is a LOSS for the side to move in Xiangqi.
      this._status = color === PieceColor.Red
        ? GameStatus.BlackWin
        : GameStatus.RedWin;
      this._endReason = inCheck ? EndReason.Checkmate : EndReason.Stalemate;
    } else if (this._halfmoveClock >= 120) {
      this._status = GameStatus.Draw;
      this._endReason = EndReason.DrawAgreed;
    }
  }

  private sideHasAnyLegalMove(color: PieceColor): boolean {
    for (const [pos, piece] of this._board.occupied()) {
      if (piece.color !== color) continue;
      const candidates = pseudoLegalMoves(this._board, pos);
      for (const to of candidates) {
        if (this.isLegalMove(pos, to, piece)) return true;
      }
    }
    return false;
  }

  // ──────────────── queries ────────────────

  isInCheck(color: PieceColor): boolean {
    return isInCheck(this._board, color);
  }
}

// UCI helpers (port of Move.toUci / Move.parseUciCoords)

export function uciOfMove(from: Position, to: Position): string {
  const fileLetter = (col: number): string =>
    String.fromCharCode('a'.charCodeAt(0) + col);
  const rankDigit = (row: number): number => 9 - row;
  return `${fileLetter(from.col)}${rankDigit(from.row)}${fileLetter(to.col)}${rankDigit(to.row)}`;
}

export function parseUci(uci: string): { from: Position; to: Position } | null {
  if (uci.length < 4) return null;
  const fromCol = uci.charCodeAt(0) - 'a'.charCodeAt(0);
  const fromRank = parseInt(uci[1], 10);
  const toCol = uci.charCodeAt(2) - 'a'.charCodeAt(0);
  const toRank = parseInt(uci[3], 10);
  if (Number.isNaN(fromRank) || Number.isNaN(toRank)) return null;
  const from = new Position(9 - fromRank, fromCol);
  const to = new Position(9 - toRank, toCol);
  if (!from.isValid || !to.isValid) return null;
  return { from, to };
}
