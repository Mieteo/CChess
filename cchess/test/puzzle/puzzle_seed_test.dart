import 'package:cchess/core/chess_engine/chess_engine.dart';
import 'package:cchess/data/datasources/local/puzzle_seed.dart';
import 'package:cchess/data/repositories/puzzle_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Built-in puzzle seed', () {
    test('every puzzle has a non-empty solution', () {
      for (final p in seedPuzzles) {
        expect(p.solution, isNotEmpty, reason: 'puzzle ${p.id}');
      }
    });

    test('catalog has stable unique ids and enough starter content', () {
      final ids = seedPuzzles.map((p) => p.id).toSet();

      expect(seedPuzzles, hasLength(greaterThanOrEqualTo(20)));
      expect(ids, hasLength(seedPuzzles.length));
      expect(seedPuzzles.first.id, 'p001');
    });

    test('catalog covers beginner practice tags', () {
      final tags = seedPuzzles.expand((p) => p.tags).toSet();

      expect(tags, containsAll(['Xe', 'Pháo', 'Mã', 'Tốt', 'Tàn cục']));
    });

    test('repository filters by tag and difficulty', () {
      final repo = PuzzleRepository();

      final cannonPuzzles = repo.filteredPuzzles(tag: 'Pháo');
      final easyPuzzles = repo.filteredPuzzles(difficulty: 1);
      final cannonDifficulty2 = repo.filteredPuzzles(
        tag: 'Pháo',
        difficulty: 2,
      );

      expect(cannonPuzzles, isNotEmpty);
      expect(cannonPuzzles.every((p) => p.tags.contains('Pháo')), isTrue);
      expect(easyPuzzles.every((p) => p.difficulty == 1), isTrue);
      expect(
        cannonDifficulty2.every(
          (p) => p.tags.contains('Pháo') && p.difficulty == 2,
        ),
        isTrue,
      );
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
          expect(
            coords,
            isNotNull,
            reason: 'puzzle ${p.id} solution[$i] = "${p.solution[i]}"',
          );
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
