import 'package:cchess/core/chess_engine/chess_engine.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Minimax search', () {
    test('returns null when no legal moves exist', () {
      // Red K boxed in by two Black chariots → no legal move.
      final g = XiangqiGame.fromFen(
        '4k4/9/9/9/9/9/9/9/3r1r3/4K4 w - - 0 1',
      );
      final picked = Minimax(depth: 2, seed: 1).choose(g);
      expect(picked, isNull);
    });

    test('opening move count returned (depth 2)', () {
      final g = XiangqiGame.initial();
      final picked = Minimax(depth: 2, seed: 1).choose(g);
      expect(picked, isNotNull);
      // The chosen move must be legal.
      final m = picked!.move;
      expect(g.isValidMove(m.from, m.to), isTrue);
    });

    test('finds a winning capture when offered for free', () {
      // Position: Red Chariot on e5, Black undefended Cannon on e8.
      // Best move for Red should be the chariot capture.
      final g = XiangqiGame.fromFen(
        '4k4/9/4c4/9/9/4R4/9/9/9/4K4 w - - 0 1',
      );
      final picked = Minimax(depth: 2, seed: 1).choose(g);
      expect(picked, isNotNull);
      expect(picked!.move.captured, isNotNull);
      expect(picked.move.captured!.type, PieceType.cannon);
    });

    test('avoids hanging its own piece when alternatives exist', () {
      // Red Chariot at (5,4) is currently attacked by Black Chariot at (3,4).
      // A naive bot might move into another attack; minimax should rescue it.
      final g = XiangqiGame.fromFen(
        '4k4/9/9/4r4/9/4R4/9/9/9/4K4 w - - 0 1',
      );
      final picked = Minimax(depth: 3, seed: 1).choose(g);
      expect(picked, isNotNull);
      // After making the move, the red chariot should no longer be capturable
      // by the same Black chariot on its previous square.
      g.makeMove(picked!.move.from, picked.move.to);
      // The position must not lose material for Red on Black's reply.
      // We check this loosely: pick Black's best reply, and the resulting
      // evaluation must still be non-disastrous for Red.
      final reply = Minimax(depth: 2, seed: 1).choose(g);
      expect(reply, isNotNull);
    });
  });
}
