import 'package:cchess/core/chess_engine/chess_engine.dart';
import 'package:cchess/data/datasources/local/opening_seed.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Opening catalog', () {
    test('every opening has a unique id', () {
      final ids = kOpenings.map((o) => o.id).toSet();
      expect(ids.length, kOpenings.length);
    });

    test('every opening has non-empty fields', () {
      for (final o in kOpenings) {
        expect(o.nameVi, isNotEmpty, reason: o.id);
        expect(o.nameHan, isNotEmpty, reason: o.id);
        expect(o.descriptionVi, isNotEmpty, reason: o.id);
        expect(o.keyIdeasVi, isNotEmpty, reason: o.id);
        expect(o.mainLine, isNotEmpty, reason: o.id);
      }
    });

    test('every main-line move is legal from the previous position', () {
      for (final o in kOpenings) {
        final game = XiangqiGame.initial();
        for (int i = 0; i < o.mainLine.length; i++) {
          final coords = Move.parseUciCoords(o.mainLine[i]);
          expect(coords, isNotNull,
              reason: 'opening ${o.id} move[$i] = "${o.mainLine[i]}"');
          final (from, to) = coords!;
          expect(
            game.isValidMove(from, to),
            isTrue,
            reason:
                'opening ${o.id} move[$i] (${o.mainLine[i]}) is not legal '
                'in the current position',
          );
          game.makeMove(from, to);
        }
      }
    });

    test('main-line moves alternate Red / Black starting with Red', () {
      for (final o in kOpenings) {
        final game = XiangqiGame.initial();
        for (int i = 0; i < o.mainLine.length; i++) {
          final expected =
              i.isEven ? PieceColor.red : PieceColor.black;
          expect(game.turn, expected, reason: '${o.id} move[$i]');
          final (from, to) = Move.parseUciCoords(o.mainLine[i])!;
          game.makeMove(from, to);
        }
      }
    });

    test('Opening.turnAtPly returns the right color', () {
      for (final o in kOpenings) {
        expect(o.turnAtPly(0), PieceColor.red);
        expect(o.turnAtPly(1), PieceColor.black);
        expect(o.turnAtPly(2), PieceColor.red);
      }
    });
  });
}
