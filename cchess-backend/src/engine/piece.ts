// Port of cchess/lib/core/constants/piece_constants.dart + piece.dart
// Convention: Red is the bottom side (row 9), Black is the top (row 0).

export enum PieceColor {
  Red = 'red',
  Black = 'black',
}

export function oppositeColor(c: PieceColor): PieceColor {
  return c === PieceColor.Red ? PieceColor.Black : PieceColor.Red;
}

export enum PieceType {
  General = 'general',
  Advisor = 'advisor',
  Elephant = 'elephant',
  Horse = 'horse',
  Chariot = 'chariot',
  Cannon = 'cannon',
  Soldier = 'soldier',
}

export class Piece {
  constructor(
    public readonly type: PieceType,
    public readonly color: PieceColor,
  ) {}

  get isRed(): boolean {
    return this.color === PieceColor.Red;
  }

  fenChar(): string {
    return PieceTypeFenLetter(this.type, this.color);
  }

  equals(other: Piece): boolean {
    return this.type === other.type && this.color === other.color;
  }

  toString(): string {
    return this.fenChar();
  }
}

export function PieceTypeFenLetter(t: PieceType, c: PieceColor): string {
  let letter: string;
  switch (t) {
    case PieceType.General: letter = 'k'; break;
    case PieceType.Advisor: letter = 'a'; break;
    case PieceType.Elephant: letter = 'b'; break;
    case PieceType.Horse: letter = 'n'; break;
    case PieceType.Chariot: letter = 'r'; break;
    case PieceType.Cannon: letter = 'c'; break;
    case PieceType.Soldier: letter = 'p'; break;
  }
  return c === PieceColor.Red ? letter.toUpperCase() : letter;
}

/// Parse a FEN letter to [type, color]. Returns null for empty squares.
export function fromFenLetter(letter: string): [PieceType, PieceColor] | null {
  if (letter.length === 0) return null;
  const isRed = letter === letter.toUpperCase();
  const color = isRed ? PieceColor.Red : PieceColor.Black;
  switch (letter.toLowerCase()) {
    case 'k': return [PieceType.General, color];
    case 'a': return [PieceType.Advisor, color];
    case 'b':
    case 'e': return [PieceType.Elephant, color];
    case 'n':
    case 'h': return [PieceType.Horse, color];
    case 'r': return [PieceType.Chariot, color];
    case 'c': return [PieceType.Cannon, color];
    case 'p': return [PieceType.Soldier, color];
    default: return null;
  }
}

export const INITIAL_FEN =
  'rnbakabnr/9/1c5c1/p1p1p1p1p/9/9/P1P1P1P1P/1C5C1/9/RNBAKABNR w - - 0 1';
