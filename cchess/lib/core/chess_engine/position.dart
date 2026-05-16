import 'package:equatable/equatable.dart';

/// Coordinate on the 10×9 Xiangqi board.
///
/// Convention used everywhere in this engine:
/// - `row` is 0..9. Row 0 is Black's back rank (top of screen); row 9 is
///   Red's back rank (bottom of screen).
/// - `col` is 0..8 left-to-right from Red's perspective.
class Position extends Equatable implements Comparable<Position> {
  final int row;
  final int col;

  const Position(this.row, this.col);

  bool get isValid => row >= 0 && row <= 9 && col >= 0 && col <= 8;

  /// Whether this square is within the 3×3 palace for the given color.
  bool isInPalace(bool forRed) {
    if (col < 3 || col > 5) return false;
    if (forRed) {
      return row >= 7 && row <= 9;
    } else {
      return row >= 0 && row <= 2;
    }
  }

  /// Whether this square is on the red half of the board (rows 5..9).
  bool get isOnRedSide => row >= 5;

  /// Whether this square is on the black half of the board (rows 0..4).
  bool get isOnBlackSide => row <= 4;

  Position offset(int dRow, int dCol) => Position(row + dRow, col + dCol);

  @override
  int compareTo(Position other) {
    final r = row.compareTo(other.row);
    if (r != 0) return r;
    return col.compareTo(other.col);
  }

  @override
  String toString() => '($row,$col)';

  @override
  List<Object?> get props => [row, col];
}
