import '../constants/piece_constants.dart';
import 'piece.dart';
import 'position.dart';

/// Mutable but copyable 10×9 board of optional pieces.
///
/// We use a flat `List<Piece?>` of length 90 (row * 9 + col) for performance.
class Board {
  static const int rows = 10;
  static const int cols = 9;
  static const int squares = rows * cols;

  final List<Piece?> _cells;

  Board._(this._cells);

  /// Empty board.
  factory Board.empty() => Board._(List<Piece?>.filled(squares, null));

  /// Standard starting position.
  factory Board.initial() => Board.fromFen(kInitialFen);

  /// Parse a FEN board section. Only the piece-placement field matters here;
  /// extra fields (side to move, halfmove counters) are ignored.
  factory Board.fromFen(String fen) {
    final cells = List<Piece?>.filled(squares, null);
    final placement = fen.split(' ').first;
    final rowStrings = placement.split('/');
    if (rowStrings.length != rows) {
      throw FormatException('Invalid FEN: expected $rows ranks, got '
          '${rowStrings.length} in "$placement"');
    }
    for (int r = 0; r < rows; r++) {
      int c = 0;
      for (final ch in rowStrings[r].split('')) {
        final digit = int.tryParse(ch);
        if (digit != null) {
          c += digit;
        } else {
          final parsed = PieceTypeX.fromFenLetter(ch);
          if (parsed == null) {
            throw FormatException('Invalid FEN piece char "$ch"');
          }
          if (c >= cols) {
            throw FormatException('FEN rank overflow at row $r: "$ch"');
          }
          final (type, color) = parsed;
          cells[r * cols + c] = Piece(type, color);
          c++;
        }
      }
      if (c != cols) {
        throw FormatException(
          'FEN rank $r has $c columns, expected $cols: "${rowStrings[r]}"',
        );
      }
    }
    return Board._(cells);
  }

  /// Deep copy.
  Board copy() => Board._(List<Piece?>.from(_cells));

  Piece? at(Position p) => _cells[p.row * cols + p.col];
  Piece? cell(int row, int col) => _cells[row * cols + col];

  void setAt(Position p, Piece? piece) {
    _cells[p.row * cols + p.col] = piece;
  }

  /// Iterate every (Position, Piece) tuple that is occupied.
  Iterable<(Position, Piece)> occupied() sync* {
    for (int i = 0; i < squares; i++) {
      final p = _cells[i];
      if (p != null) {
        yield (Position(i ~/ cols, i % cols), p);
      }
    }
  }

  /// Returns the position of the (single) general of the given color, or null
  /// if it has been captured (which shouldn't happen in a legal game).
  Position? generalPosition(PieceColor color) {
    for (int i = 0; i < squares; i++) {
      final p = _cells[i];
      if (p != null && p.type == PieceType.general && p.color == color) {
        return Position(i ~/ cols, i % cols);
      }
    }
    return null;
  }

  /// Serialize the piece-placement field of a FEN string.
  String toFenPlacement() {
    final buf = StringBuffer();
    for (int r = 0; r < rows; r++) {
      int empty = 0;
      for (int c = 0; c < cols; c++) {
        final p = _cells[r * cols + c];
        if (p == null) {
          empty++;
        } else {
          if (empty > 0) {
            buf.write(empty);
            empty = 0;
          }
          buf.write(p.fenChar);
        }
      }
      if (empty > 0) buf.write(empty);
      if (r != rows - 1) buf.write('/');
    }
    return buf.toString();
  }

  @override
  String toString() {
    // Pretty grid for debugging.
    final buf = StringBuffer();
    for (int r = 0; r < rows; r++) {
      buf.write(r.toString().padLeft(2));
      buf.write(' ');
      for (int c = 0; c < cols; c++) {
        final p = _cells[r * cols + c];
        buf.write(p?.fenChar ?? '.');
        buf.write(' ');
      }
      buf.writeln();
      if (r == 4) buf.writeln('   - - - - - - - - -');
    }
    buf.writeln('   a b c d e f g h i');
    return buf.toString();
  }
}
