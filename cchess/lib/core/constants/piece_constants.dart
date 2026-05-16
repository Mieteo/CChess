// Xiangqi piece definitions: type enum, Vietnamese name, Hán character.
//
// Convention: Red is the bottom side (player 1), Black is the top side
// (player 2). The board is stored row 0..9 from Red's bottom row up.

/// Color of a chess piece — red plays first.
enum PieceColor { red, black }

extension PieceColorX on PieceColor {
  PieceColor get opposite =>
      this == PieceColor.red ? PieceColor.black : PieceColor.red;

  String get nameVi => this == PieceColor.red ? 'Đỏ' : 'Đen';
}

/// Logical piece type — same enum value used for both colors.
enum PieceType {
  general, // Tướng (帥/將)
  advisor, // Sĩ (仕/士)
  elephant, // Tượng (相/象)
  horse, // Mã (馬)
  chariot, // Xe (車)
  cannon, // Pháo (炮/砲)
  soldier, // Tốt/Binh (兵/卒)
}

extension PieceTypeX on PieceType {
  /// Vietnamese name of the piece type.
  String get nameVi {
    switch (this) {
      case PieceType.general:
        return 'Tướng';
      case PieceType.advisor:
        return 'Sĩ';
      case PieceType.elephant:
        return 'Tượng';
      case PieceType.horse:
        return 'Mã';
      case PieceType.chariot:
        return 'Xe';
      case PieceType.cannon:
        return 'Pháo';
      case PieceType.soldier:
        return 'Tốt';
    }
  }

  /// Returns the Han character used on the piece face for the given color.
  String hanChar(PieceColor color) {
    switch (this) {
      case PieceType.general:
        return color == PieceColor.red ? '帥' : '將';
      case PieceType.advisor:
        return color == PieceColor.red ? '仕' : '士';
      case PieceType.elephant:
        return color == PieceColor.red ? '相' : '象';
      case PieceType.horse:
        return color == PieceColor.red ? '馬' : '馬';
      case PieceType.chariot:
        return color == PieceColor.red ? '車' : '車';
      case PieceType.cannon:
        return color == PieceColor.red ? '炮' : '砲';
      case PieceType.soldier:
        return color == PieceColor.red ? '兵' : '卒';
    }
  }

  /// FEN letter used in Xiangqi FEN strings.
  /// Red pieces use uppercase, black use lowercase.
  String fenLetter(PieceColor color) {
    final String letter;
    switch (this) {
      case PieceType.general:
        letter = 'k';
        break;
      case PieceType.advisor:
        letter = 'a';
        break;
      case PieceType.elephant:
        letter = 'b';
        break;
      case PieceType.horse:
        letter = 'n';
        break;
      case PieceType.chariot:
        letter = 'r';
        break;
      case PieceType.cannon:
        letter = 'c';
        break;
      case PieceType.soldier:
        letter = 'p';
        break;
    }
    return color == PieceColor.red ? letter.toUpperCase() : letter;
  }

  /// Parse a FEN letter to (type, color). Returns null for empty squares.
  static (PieceType, PieceColor)? fromFenLetter(String letter) {
    if (letter.isEmpty) return null;
    final isRed = letter == letter.toUpperCase();
    final color = isRed ? PieceColor.red : PieceColor.black;
    switch (letter.toLowerCase()) {
      case 'k':
        return (PieceType.general, color);
      case 'a':
        return (PieceType.advisor, color);
      case 'b':
      case 'e':
        return (PieceType.elephant, color);
      case 'n':
      case 'h':
        return (PieceType.horse, color);
      case 'r':
        return (PieceType.chariot, color);
      case 'c':
        return (PieceType.cannon, color);
      case 'p':
        return (PieceType.soldier, color);
      default:
        return null;
    }
  }
}

/// Standard Xiangqi starting position in FEN-like notation.
///
/// Row 0 is Black back rank, row 9 is Red back rank.
/// Columns 0..8 left-to-right from Red's perspective.
const String kInitialFen =
    'rnbakabnr/9/1c5c1/p1p1p1p1p/9/9/P1P1P1P1P/1C5C1/9/RNBAKABNR w - - 0 1';
