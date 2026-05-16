import 'package:cchess/core/chess_engine/chess_engine.dart';
import 'package:cchess/data/datasources/local/puzzle_seed.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Built-in puzzle seed', () {
    test('every puzzle has a non-empty solution', () {
      for (final p in seedPuzzles) {
        expect(p.solution, isNotEmpty, reason: 'puzzle ${p.id}');
      }
    });

    test('every puzzle\'s FEN parses without throwing', () {
      for (final p in seedPuzzles) {
        XiangqiGame.fromFen(p.fen);
      }
    });

    test('side-to-move is NOT already in check', () {
      for (final p in seedPuzzles) {
        final g = XiangqiGame.fromFen(p.fen);
        expect(
          g.isInCheck(g.turn),
          isFalse,
          reason: 'puzzle ${p.id} starts with the solver already in check',
        );
      }
    });

    test('all solution moves are legal in sequence', () {
      for (final p in seedPuzzles) {
        final g = XiangqiGame.fromFen(p.fen);
        for (int i = 0; i < p.solution.length; i++) {
          final coords = Move.parseUciCoords(p.solution[i]);
          expect(coords, isNotNull,
              reason: 'puzzle ${p.id} solution[$i] = "${p.solution[i]}"');
          final (from, to) = coords!;
          expect(
            g.isValidMove(from, to),
            isTrue,
            reason:
                'puzzle ${p.id} solution[$i] (${p.solution[i]}) not a legal '
                'move in current position',
          );
          g.makeMove(from, to);
        }
      }
    });

    test('mate-themed puzzles end with opponent in checkmate', () {
      for (final p in seedPuzzles) {
        if (!p.tags.contains('Chiếu hết')) continue;
        final g = XiangqiGame.fromFen(p.fen);
        for (final uci in p.solution) {
          final (from, to) = Move.parseUciCoords(uci)!;
          g.makeMove(from, to);
        }
        // After playing through the full solution, the side now to move
        // must have no legal reply (i.e., checkmate, since we tagged it).
        expect(
          g.isCheckmate(g.turn),
          isTrue,
          reason: 'puzzle ${p.id} tagged "Chiếu hết" but no mate detected',
        );
      }
    });
  });
}
