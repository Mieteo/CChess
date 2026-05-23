// Port of cchess/lib/core/chess_engine/board.dart

import { Piece, PieceType, PieceColor, fromFenLetter, INITIAL_FEN } from './piece';
import { Position } from './position';

export class Board {
  static readonly rows = 10;
  static readonly cols = 9;
  static readonly squares = Board.rows * Board.cols;

  private _cells: (Piece | null)[];

  private constructor(cells: (Piece | null)[]) {
    this._cells = cells;
  }

  static empty(): Board {
    return new Board(new Array<Piece | null>(Board.squares).fill(null));
  }

  static initial(): Board {
    return Board.fromFen(INITIAL_FEN);
  }

  static fromFen(fen: string): Board {
    const cells: (Piece | null)[] = new Array<Piece | null>(Board.squares).fill(null);
    const placement = fen.split(' ')[0];
    const rowStrings = placement.split('/');
    if (rowStrings.length !== Board.rows) {
      throw new Error(`Invalid FEN: expected ${Board.rows} ranks, got ${rowStrings.length} in "${placement}"`);
    }
    for (let r = 0; r < Board.rows; r++) {
      let c = 0;
      for (const ch of rowStrings[r].split('')) {
        const digit = parseInt(ch, 10);
        if (!Number.isNaN(digit)) {
          c += digit;
        } else {
          const parsed = fromFenLetter(ch);
          if (parsed === null) {
            throw new Error(`Invalid FEN piece char "${ch}"`);
          }
          if (c >= Board.cols) {
            throw new Error(`FEN rank overflow at row ${r}: "${ch}"`);
          }
          const [type, color] = parsed;
          cells[r * Board.cols + c] = new Piece(type, color);
          c++;
        }
      }
      if (c !== Board.cols) {
        throw new Error(`FEN rank ${r} has ${c} columns, expected ${Board.cols}: "${rowStrings[r]}"`);
      }
    }
    return new Board(cells);
  }

  copy(): Board {
    return new Board([...this._cells]);
  }

  at(p: Position): Piece | null {
    return this._cells[p.row * Board.cols + p.col];
  }

  cell(row: number, col: number): Piece | null {
    return this._cells[row * Board.cols + col];
  }

  setAt(p: Position, piece: Piece | null): void {
    this._cells[p.row * Board.cols + p.col] = piece;
  }

  /// Generator yielding every (Position, Piece) tuple that is occupied.
  *occupied(): IterableIterator<[Position, Piece]> {
    for (let i = 0; i < Board.squares; i++) {
      const p = this._cells[i];
      if (p !== null) {
        yield [new Position(Math.floor(i / Board.cols), i % Board.cols), p];
      }
    }
  }

  generalPosition(color: PieceColor): Position | null {
    for (let i = 0; i < Board.squares; i++) {
      const p = this._cells[i];
      if (p !== null && p.type === PieceType.General && p.color === color) {
        return new Position(Math.floor(i / Board.cols), i % Board.cols);
      }
    }
    return null;
  }

  toFenPlacement(): string {
    let out = '';
    for (let r = 0; r < Board.rows; r++) {
      let empty = 0;
      for (let c = 0; c < Board.cols; c++) {
        const p = this._cells[r * Board.cols + c];
        if (p === null) {
          empty++;
        } else {
          if (empty > 0) {
            out += empty;
            empty = 0;
          }
          out += p.fenChar();
        }
      }
      if (empty > 0) out += empty;
      if (r !== Board.rows - 1) out += '/';
    }
    return out;
  }
}
