// Port of cchess/lib/core/chess_engine/position.dart
//
// row 0..9, col 0..8. row 0 = Black's back rank (top of screen),
// row 9 = Red's back rank (bottom of screen).

export class Position {
  constructor(public readonly row: number, public readonly col: number) {}

  get isValid(): boolean {
    return this.row >= 0 && this.row <= 9 && this.col >= 0 && this.col <= 8;
  }

  /// Whether this square is within the 3×3 palace for the given color.
  isInPalace(forRed: boolean): boolean {
    if (this.col < 3 || this.col > 5) return false;
    if (forRed) return this.row >= 7 && this.row <= 9;
    return this.row >= 0 && this.row <= 2;
  }

  offset(dRow: number, dCol: number): Position {
    return new Position(this.row + dRow, this.col + dCol);
  }

  equals(other: Position): boolean {
    return this.row === other.row && this.col === other.col;
  }

  toString(): string {
    return `(${this.row},${this.col})`;
  }
}
