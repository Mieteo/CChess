import 'package:cchess/core/chess_engine/chess_engine.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Board.initial', () {
    test('places 32 pieces in the standard starting setup', () {
      final b = Board.initial();
      final pieces = b.occupied().toList();
      expect(pieces.length, 32);
    });

    test('generals sit on their starting squares', () {
      final b = Board.initial();
      expect(b.cell(0, 4), Piece.blackGeneral);
      expect(b.cell(9, 4), Piece.redGeneral);
    });

    test('row 4 and row 5 are empty (the river)', () {
      final b = Board.initial();
      for (int c = 0; c < Board.cols; c++) {
        expect(b.cell(4, c), isNull, reason: 'row 4 col $c');
        expect(b.cell(5, c), isNull, reason: 'row 5 col $c');
      }
    });

    test('soldiers are correctly placed', () {
      final b = Board.initial();
      for (final c in [0, 2, 4, 6, 8]) {
        expect(b.cell(3, c), Piece.blackSoldier, reason: 'black soldier $c');
        expect(b.cell(6, c), Piece.redSoldier, reason: 'red soldier $c');
      }
    });

    test('cannons are at row 2 / 7, cols 1 and 7', () {
      final b = Board.initial();
      expect(b.cell(2, 1), Piece.blackCannon);
      expect(b.cell(2, 7), Piece.blackCannon);
      expect(b.cell(7, 1), Piece.redCannon);
      expect(b.cell(7, 7), Piece.redCannon);
    });
  });

  group('FEN round-trip', () {
    test('initial board → FEN → board produces the same placement', () {
      final b1 = Board.initial();
      final fen = b1.toFenPlacement();
      final b2 = Board.fromFen(fen);
      expect(b2.toFenPlacement(), fen);
      expect(b2.occupied().length, b1.occupied().length);
    });

    test('rejects malformed FEN (wrong rank count)', () {
      expect(() => Board.fromFen('9/9/9'), throwsFormatException);
    });
  });

  group('Position helpers', () {
    test('isInPalace works for both colors', () {
      expect(const Position(0, 4).isInPalace(false), isTrue);
      expect(const Position(2, 5).isInPalace(false), isTrue);
      expect(const Position(3, 4).isInPalace(false), isFalse);
      expect(const Position(9, 4).isInPalace(true), isTrue);
      expect(const Position(7, 3).isInPalace(true), isTrue);
      expect(const Position(6, 4).isInPalace(true), isFalse);
    });

    test('isValid catches out-of-bounds', () {
      expect(const Position(-1, 0).isValid, isFalse);
      expect(const Position(10, 0).isValid, isFalse);
      expect(const Position(0, 9).isValid, isFalse);
      expect(const Position(9, 8).isValid, isTrue);
    });
  });
}
