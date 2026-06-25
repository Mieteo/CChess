// Port of cchess/lib/core/chess_engine/xiangqi_cup_game.dart (server-authoritative).
//
// Cờ Úp / Xiangqi blind variant. Non-general pieces start FACE-DOWN. A face-down
// piece moves once according to its visible COVER (the square's nominal role),
// then reveals its shuffled true identity on the destination square. Generals
// stay fixed and face-up.
//
// The SERVER owns the shuffle + hidden assignments — neither client ever learns
// a piece's true identity until it is revealed by a move (or captured). This is
// what makes online Cờ Úp cheat-resistant: clients only see covers + reveals.
//
// Key insight that keeps the client thin: cup MOVE LEGALITY depends only on the
// covers + the true types of ALREADY-REVEALED pieces (for blocking / check) — it
// never depends on a face-down piece's hidden identity. So `board.toFenPlacement()`
// (covers on hidden squares, true pieces on revealed squares) + the set of hidden
// squares is a complete PUBLIC snapshot the server can safely broadcast.

import { Board } from './board';
import { Piece, PieceColor, PieceType, oppositeColor } from './piece';
import { Position } from './position';
import { areGeneralsFacing, pseudoLegalMoves } from './moveRules';
import { GameStatus, EndReason, statusIsOver } from './game';

/// Square index in [0, 90) used as a Map/Set key (Position has no value equality).
function idx(p: Position): number {
  return p.row * Board.cols + p.col;
}

/// Deterministic PRNG (mulberry32) so tests can pin a shuffle by seed. When no
/// seed is given we fall back to Math.random for real games.
function makeRng(seed?: number): () => number {
  if (seed === undefined) return Math.random;
  let a = seed >>> 0;
  return () => {
    a |= 0;
    a = (a + 0x6d2b79f5) | 0;
    let t = Math.imul(a ^ (a >>> 15), 1 | a);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

/// Reveal info produced by a cup move — broadcast so clients can update their
/// cover-board view without ever knowing hidden identities ahead of time.
export interface CupMoveResult {
  /// True identity of the piece that just landed on `to` (now face-up).
  revealed: Piece;
  /// True identity of the captured piece, or null for a non-capture.
  captured: Piece | null;
  /// Whether the moving piece was face-down before this move (i.e. a reveal).
  wasHidden: boolean;
  status: GameStatus;
  endReason: EndReason | null;
}

/// Public, cheat-safe snapshot of a cup game (no hidden identities leaked).
export interface CupPublicSnapshot {
  /// Visible board: covers on face-down squares, true pieces on revealed ones.
  fen: string;
  /// Square indices (row*9+col) that are still face-down.
  hidden: number[];
}

export class XiangqiCupGame {
  private _board: Board;
  private _turn: PieceColor;
  private _status: GameStatus;
  private _endReason: EndReason | null;
  private _halfmoveClock: number;
  private _fullmoveNumber: number;
  /// posIndex -> TRUE identity for every face-down square.
  private _hidden: Map<number, Piece>;
  private _moveCount: number;

  private constructor(
    board: Board,
    turn: PieceColor,
    status: GameStatus,
    halfmoveClock: number,
    fullmoveNumber: number,
    hidden: Map<number, Piece>,
  ) {
    this._board = board;
    this._turn = turn;
    this._status = status;
    this._endReason = null;
    this._halfmoveClock = halfmoveClock;
    this._fullmoveNumber = fullmoveNumber;
    this._hidden = hidden;
    this._moveCount = 0;
  }

  /// Fresh shuffled game. `seed` makes the shuffle deterministic (tests only).
  static initial(seed?: number): XiangqiCupGame {
    const board = Board.initial();
    const hidden = XiangqiCupGame.randomizeHiddenPieces(board, seed);
    return new XiangqiCupGame(
      board,
      PieceColor.Red,
      GameStatus.Playing,
      0,
      1,
      hidden,
    );
  }

  /// Test/debug hook: build a game with explicit covers + hidden assignments.
  static debug(opts: {
    board: Board;
    turn?: PieceColor;
    status?: GameStatus;
    halfmoveClock?: number;
    fullmoveNumber?: number;
    /// posIndex -> true identity for each face-down square.
    hidden?: Map<number, Piece>;
  }): XiangqiCupGame {
    return new XiangqiCupGame(
      opts.board,
      opts.turn ?? PieceColor.Red,
      opts.status ?? GameStatus.Playing,
      opts.halfmoveClock ?? 0,
      opts.fullmoveNumber ?? 1,
      opts.hidden ?? new Map<number, Piece>(),
    );
  }

  // ──────────────── read-only state ────────────────

  get board(): Board { return this._board; }
  get turn(): PieceColor { return this._turn; }
  get status(): GameStatus { return this._status; }
  get endReason(): EndReason | null { return this._endReason; }
  get halfmoveClock(): number { return this._halfmoveClock; }
  get fullmoveNumber(): number { return this._fullmoveNumber; }
  get moveCount(): number { return this._moveCount; }
  get hiddenCount(): number { return this._hidden.size; }

  isHidden(p: Position): boolean { return this._hidden.has(idx(p)); }

  /// TEST-ONLY peek at the shuffled identity. Never send this to a client.
  debugHiddenAt(p: Position): Piece | undefined { return this._hidden.get(idx(p)); }

  toFen(): string {
    const side = this._turn === PieceColor.Red ? 'w' : 'b';
    return `${this._board.toFenPlacement()} ${side} - - ${this._halfmoveClock} ${this._fullmoveNumber}`;
  }

  /// Cheat-safe public view (covers + revealed pieces + which squares are down).
  publicSnapshot(): CupPublicSnapshot {
    return { fen: this.toFen(), hidden: [...this._hidden.keys()] };
  }

  // ──────────────── move generation ────────────────

  getValidMoves(from: Position): Position[] {
    const piece = this._board.at(from);
    if (piece === null || piece.color !== this._turn) return [];
    const out: Position[] = [];
    for (const to of this.cupPseudoLegal(from)) {
      if (this.isLegalMove(from, to, piece)) out.push(to);
    }
    return out;
  }

  isValidMove(from: Position, to: Position): boolean {
    if (statusIsOver(this._status)) return false;
    const piece = this._board.at(from);
    if (piece === null || piece.color !== this._turn) return false;
    let inCandidates = false;
    for (const c of this.cupPseudoLegal(from)) {
      if (c.equals(to)) { inCandidates = true; break; }
    }
    if (!inCandidates) return false;
    return this.isLegalMove(from, to, piece);
  }

  private isLegalMove(from: Position, to: Position, coverPiece: Piece): boolean {
    const target = this._board.at(to);
    if (target !== null && target.color === coverPiece.color) return false;

    const movedAfterReveal = this._hidden.get(idx(from)) ?? coverPiece;
    const copy = this._board.copy();
    copy.setAt(to, movedAfterReveal);
    copy.setAt(from, null);
    // After the move `from` is empty and `to` holds the now-revealed piece, so
    // neither is face-down when we test the resulting position for check.
    const hiddenAfter = new Set<number>(this._hidden.keys());
    hiddenAfter.delete(idx(from));
    hiddenAfter.delete(idx(to));
    if (XiangqiCupGame.cupInCheck(copy, hiddenAfter, coverPiece.color)) return false;
    return true;
  }

  /// Apply (from, to). Throws if illegal. Returns reveal info for broadcast.
  makeMove(from: Position, to: Position): CupMoveResult {
    if (statusIsOver(this._status)) {
      throw new Error(`Game is over (${this._status})`);
    }
    const coverPiece = this._board.at(from);
    if (coverPiece === null) throw new Error(`No piece at ${from.toString()}`);
    if (coverPiece.color !== this._turn) {
      throw new Error(`It is ${this._turn}'s turn but piece is ${coverPiece.color}`);
    }
    if (!this.isValidMove(from, to)) {
      throw new Error(`Illegal move: ${from.toString()} -> ${to.toString()}`);
    }

    const fromIdx = idx(from);
    const toIdx = idx(to);
    const wasHidden = this._hidden.has(fromIdx);
    const moved = this._hidden.get(fromIdx) ?? coverPiece;
    const captured = this._hidden.get(toIdx) ?? this._board.at(to);
    this._hidden.delete(fromIdx);
    this._hidden.delete(toIdx);

    this._board.setAt(to, moved);
    this._board.setAt(from, null);

    if (captured !== null || moved.type === PieceType.Soldier) {
      this._halfmoveClock = 0;
    } else {
      this._halfmoveClock++;
    }
    if (this._turn === PieceColor.Black) this._fullmoveNumber++;
    this._turn = oppositeColor(this._turn);
    this._moveCount++;

    this.refreshStatus();
    return {
      revealed: moved,
      captured,
      wasHidden,
      status: this._status,
      endReason: this._endReason,
    };
  }

  private refreshStatus(): void {
    const color = this._turn;
    const inCheck = this.inCheckNow(color);
    const hasAnyMove = this.sideHasAnyLegalMove(color);

    if (!hasAnyMove) {
      // Stalemate is a LOSS for the side to move in Xiangqi (and Cờ Úp).
      this._status = color === PieceColor.Red ? GameStatus.BlackWin : GameStatus.RedWin;
      this._endReason = inCheck ? EndReason.Checkmate : EndReason.Stalemate;
    } else if (this._halfmoveClock >= 120) {
      this._status = GameStatus.Draw;
      this._endReason = EndReason.DrawAgreed;
    }
  }

  private sideHasAnyLegalMove(color: PieceColor): boolean {
    for (const [pos, piece] of this._board.occupied()) {
      if (piece.color !== color) continue;
      for (const to of this.cupPseudoLegal(pos)) {
        if (this.isLegalMove(pos, to, piece)) return true;
      }
    }
    return false;
  }

  isInCheck(color: PieceColor): boolean {
    return this.inCheckNow(color);
  }

  private inCheckNow(color: PieceColor): boolean {
    const hidden = new Set<number>(this._hidden.keys());
    return XiangqiCupGame.cupInCheck(this._board, hidden, color);
  }

  // ──────────────── cup rule helpers ────────────────

  /// A FACE-DOWN piece moves by its cover (so a cover Sĩ/Tượng stays confined).
  /// Once REVEALED, Sĩ and Tượng shed the palace / river limits and roam the
  /// whole board, keeping only their 1-/2-step diagonal pattern (Tượng still
  /// blocked by a "cản mắt"). Every other piece uses the standard rules.
  private cupPseudoLegal(from: Position): Position[] {
    return XiangqiCupGame.cupPseudoLegalOn(
      this._board,
      new Set<number>(this._hidden.keys()),
      from,
    );
  }

  static cupPseudoLegalOn(
    board: Board,
    hidden: Set<number>,
    from: Position,
  ): Position[] {
    const piece = board.at(from);
    if (piece === null) return [];
    if (!hidden.has(idx(from))) {
      if (piece.type === PieceType.Advisor) {
        return XiangqiCupGame.freeDiagonalMoves(board, from, piece, 1);
      }
      if (piece.type === PieceType.Elephant) {
        return XiangqiCupGame.freeDiagonalMoves(board, from, piece, 2);
      }
    }
    return pseudoLegalMoves(board, from);
  }

  /// Diagonal slider for revealed Sĩ (step 1) and Tượng (step 2) in Cờ Úp:
  /// no palace / river bounds, but the 2-step Tượng is still blocked when the
  /// midpoint ("mắt Tượng") is occupied.
  private static freeDiagonalMoves(
    b: Board,
    from: Position,
    p: Piece,
    step: number,
  ): Position[] {
    const out: Position[] = [];
    const deltas: [number, number][] = [
      [-step, -step],
      [-step, step],
      [step, -step],
      [step, step],
    ];
    for (const [dr, dc] of deltas) {
      const to = from.offset(dr, dc);
      if (!to.isValid) continue;
      if (step === 2 && b.at(from.offset(dr / 2, dc / 2)) !== null) {
        continue; // cản mắt Tượng
      }
      const occupant = b.at(to);
      if (occupant === null || occupant.color !== p.color) out.push(to);
    }
    return out;
  }

  /// Check detection honouring the cup reach of revealed Sĩ/Tượng (and the
  /// flying-general face-off). Face-down pieces still threaten by their cover.
  static cupInCheck(board: Board, hidden: Set<number>, color: PieceColor): boolean {
    const kingPos = board.generalPosition(color);
    if (kingPos === null) return false;
    if (areGeneralsFacing(board)) return true;
    for (const [pos, piece] of board.occupied()) {
      if (piece.color === color) continue;
      for (const m of XiangqiCupGame.cupPseudoLegalOn(board, hidden, pos)) {
        if (m.equals(kingPos)) return true;
      }
    }
    return false;
  }

  resign(resigningColor: PieceColor): void {
    if (statusIsOver(this._status)) return;
    this._status = resigningColor === PieceColor.Red ? GameStatus.BlackWin : GameStatus.RedWin;
    this._endReason = EndReason.Resignation;
  }

  // ──────────────── shuffle ────────────────

  /// Shuffle each color's non-general pieces among their own starting squares.
  /// Generals stay put and face-up. Covers (the board) are unchanged; only the
  /// hidden TRUE identity per square is randomized.
  private static randomizeHiddenPieces(board: Board, seed?: number): Map<number, Piece> {
    const rng = makeRng(seed);
    const hidden = new Map<number, Piece>();
    for (const color of [PieceColor.Red, PieceColor.Black]) {
      const squares: number[] = [];
      const pieces: Piece[] = [];
      for (const [pos, piece] of board.occupied()) {
        if (piece.color !== color || piece.type === PieceType.General) continue;
        squares.push(idx(pos)); // board.occupied() yields in row-major order
        pieces.push(piece);
      }
      // Fisher-Yates shuffle of the identities across the fixed squares.
      for (let i = pieces.length - 1; i > 0; i--) {
        const j = Math.floor(rng() * (i + 1));
        const tmp = pieces[i];
        pieces[i] = pieces[j];
        pieces[j] = tmp;
      }
      for (let i = 0; i < squares.length; i++) {
        hidden.set(squares[i], pieces[i]);
      }
    }
    return hidden;
  }
}
