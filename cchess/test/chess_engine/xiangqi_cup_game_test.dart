import 'package:cchess/core/chess_engine/chess_engine.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('XiangqiCupGame.initial', () {
    test('hides every non-general piece and keeps generals face-up', () {
      final game = XiangqiCupGame.initial(seed: 13);

      expect(game.turn, PieceColor.red);
      expect(game.status, GameStatus.playing);
      expect(game.hiddenCount, 30);
      expect(game.isHidden(const Position(0, 4)), isFalse);
      expect(game.isHidden(const Position(9, 4)), isFalse);
      expect(game.board.at(const Position(0, 4))?.type, PieceType.general);
      expect(game.board.at(const Position(9, 4))?.type, PieceType.general);
    });

    test('uses cover-piece movement before revealing the shuffled piece', () {
      final game = XiangqiCupGame.initial(seed: 13);
      const from = Position(7, 1); // red cannon cover
      const to = Position(7, 4);
      final hiddenPiece = game.debugHiddenPieceAt(from);

      expect(hiddenPiece, isNotNull);
      expect(game.isHidden(from), isTrue);
      expect(game.getValidMoves(from), contains(to));

      final move = game.makeMove(from, to);

      expect(move.from, from);
      expect(move.to, to);
      expect(move.moved, hiddenPiece);
      expect(game.board.at(from), isNull);
      expect(game.board.at(to), hiddenPiece);
      expect(game.isHidden(from), isFalse);
      expect(game.isHidden(to), isFalse);
      expect(game.turn, PieceColor.black);
      expect(game.hiddenCount, 29);
    });

    test('undo restores board, turn, and hidden assignment', () {
      final game = XiangqiCupGame.initial(seed: 13);
      const from = Position(7, 1);
      const to = Position(7, 4);
      final fenBefore = game.toFen();
      final hiddenBefore = game.debugHiddenPieceAt(from);

      game.makeMove(from, to);
      final undone = game.undoMove();

      expect(undone, isNotNull);
      expect(game.toFen(), fenBefore);
      expect(game.turn, PieceColor.red);
      expect(game.hiddenCount, 30);
      expect(game.isHidden(from), isTrue);
      expect(game.debugHiddenPieceAt(from), hiddenBefore);
      expect(game.board.at(to), isNull);
    });
  });

  group('XiangqiCupGame hidden-piece movement rules', () {
    test('shuffle preserves each side non-general piece multiset', () {
      final expected = _nonGeneralPieceCounts(Board.initial());

      for (final seed in [0, 1, 13, 42, 99]) {
        final game = XiangqiCupGame.initial(seed: seed);
        final actual = <String, int>{};

        for (final pos in game.hiddenPositions) {
          final cover = game.board.at(pos);
          final hidden = game.debugHiddenPieceAt(pos);
          expect(cover, isNotNull, reason: 'seed=$seed pos=$pos');
          expect(hidden, isNotNull, reason: 'seed=$seed pos=$pos');
          expect(
            hidden!.color,
            cover!.color,
            reason: 'hidden pieces never cross colors',
          );
          _increment(actual, hidden);
        }

        expect(actual, expected, reason: 'seed=$seed');
      }
    });

    test('first move uses the visible cover piece before reveal', () {
      const from = Position(7, 1);
      const to = Position(7, 4);
      final board = _boardWith({
        const Position(0, 4): Piece.blackGeneral,
        const Position(3, 4): Piece.blackSoldier,
        from: Piece.redCannon,
        const Position(9, 4): Piece.redGeneral,
      });
      final game = XiangqiCupGame.debug(
        board: board,
        hiddenAssignments: {from: Piece.redHorse},
      );

      final asHorse = board.copy()..setAt(from, Piece.redHorse);
      expect(MoveRules.pseudoLegalMoves(asHorse, from), isNot(contains(to)));
      expect(game.getValidMoves(from), contains(to));

      final move = game.makeMove(from, to);

      expect(move.moved, Piece.redHorse);
      expect(game.board.at(to), Piece.redHorse);
      expect(game.isHidden(from), isFalse);
      expect(game.isHidden(to), isFalse);
      expect(game.turn, PieceColor.black);
    });

    test('revealed piece uses its true movement on later turns', () {
      const from = Position(7, 1);
      const revealTo = Position(7, 4);
      const blackFrom = Position(3, 4);
      const blackTo = Position(4, 4);
      const trueHorseMove = Position(5, 3);
      final board = _boardWith({
        const Position(0, 4): Piece.blackGeneral,
        blackFrom: Piece.blackSoldier,
        from: Piece.redCannon,
        const Position(9, 4): Piece.redGeneral,
      });
      final game = XiangqiCupGame.debug(
        board: board,
        hiddenAssignments: {from: Piece.redHorse},
      );

      game.makeMove(from, revealTo);
      game.makeMove(blackFrom, blackTo);

      final asCoverCannon = game.board.copy()..setAt(revealTo, Piece.redCannon);
      expect(
        MoveRules.pseudoLegalMoves(asCoverCannon, revealTo),
        isNot(contains(trueHorseMove)),
      );
      expect(game.board.at(revealTo), Piece.redHorse);
      expect(game.turn, PieceColor.red);
      expect(game.getValidMoves(revealTo), contains(trueHorseMove));
    });

    test('capturing a hidden piece records the true captured piece', () {
      const from = Position(7, 1);
      const screen = Position(7, 2);
      const target = Position(7, 4);
      final board = _boardWith({
        const Position(0, 4): Piece.blackGeneral,
        from: Piece.redCannon,
        screen: Piece.redSoldier,
        target: Piece.blackSoldier,
        const Position(9, 4): Piece.redGeneral,
      });
      final game = XiangqiCupGame.debug(
        board: board,
        hiddenAssignments: {from: Piece.redHorse, target: Piece.blackChariot},
      );

      expect(game.hiddenCount, 2);
      expect(game.getValidMoves(from), contains(target));

      final move = game.makeMove(from, target);

      expect(move.moved, Piece.redHorse);
      expect(move.captured, Piece.blackChariot);
      expect(move.captured, isNot(Piece.blackSoldier));
      expect(game.board.at(target), Piece.redHorse);
      expect(game.hiddenCount, 0);
    });

    test('undo after hidden capture restores both hidden assignments', () {
      const from = Position(7, 1);
      const screen = Position(7, 2);
      const target = Position(7, 4);
      final board = _boardWith({
        const Position(0, 4): Piece.blackGeneral,
        from: Piece.redCannon,
        screen: Piece.redSoldier,
        target: Piece.blackSoldier,
        const Position(9, 4): Piece.redGeneral,
      });
      final game = XiangqiCupGame.debug(
        board: board,
        hiddenAssignments: {from: Piece.redHorse, target: Piece.blackChariot},
      );
      final fenBefore = game.toFen();

      game.makeMove(from, target);
      final undone = game.undoMove();

      expect(undone, isNotNull);
      expect(game.toFen(), fenBefore);
      expect(game.turn, PieceColor.red);
      expect(game.hiddenCount, 2);
      expect(game.debugHiddenPieceAt(from), Piece.redHorse);
      expect(game.debugHiddenPieceAt(target), Piece.blackChariot);
      expect(game.board.at(from), Piece.redCannon);
      expect(game.board.at(target), Piece.blackSoldier);
    });

    test('rejects reveal move that exposes own general to check', () {
      const from = Position(5, 4);
      const target = Position(5, 5);
      final board = _boardWith({
        const Position(0, 3): Piece.blackGeneral,
        const Position(0, 4): Piece.blackChariot,
        from: Piece.redChariot,
        const Position(9, 4): Piece.redGeneral,
      });
      final game = XiangqiCupGame.debug(
        board: board,
        hiddenAssignments: {from: Piece.redHorse},
      );

      expect(MoveRules.pseudoLegalMoves(board, from), contains(target));
      expect(game.isInCheck(PieceColor.red), isFalse);
      expect(game.isValidMove(from, target), isFalse);
      expect(game.getValidMoves(from), isNot(contains(target)));
    });

    test('rejects reveal move that opens the flying-general file', () {
      const from = Position(5, 4);
      const target = Position(5, 5);
      final board = _boardWith({
        const Position(0, 4): Piece.blackGeneral,
        from: Piece.redChariot,
        const Position(9, 4): Piece.redGeneral,
      });
      final game = XiangqiCupGame.debug(
        board: board,
        hiddenAssignments: {from: Piece.redHorse},
      );

      expect(MoveRules.pseudoLegalMoves(board, from), contains(target));
      expect(game.areGeneralsFacing(), isFalse);
      expect(game.isValidMove(from, target), isFalse);
      expect(game.getValidMoves(from), isNot(contains(target)));
    });
  });

  group('XiangqiCupGame revealed Sĩ/Tượng roam freely', () {
    test('a revealed advisor leaves the palace and may cross the river', () {
      // Red advisor revealed OUTSIDE its palace, in the black half.
      final board = _boardWith({
        const Position(0, 3): Piece.blackGeneral,
        const Position(4, 4): Piece.redAdvisor,
        const Position(9, 4): Piece.redGeneral,
      });
      final game = XiangqiCupGame.debug(board: board); // no hidden → revealed

      final moves = game.getValidMoves(const Position(4, 4));
      // Diagonal-1 in every direction, no palace / river bound.
      expect(
        moves,
        containsAll(const [
          Position(3, 3), // deeper into enemy territory
          Position(3, 5),
          Position(5, 3),
          Position(5, 5),
        ]),
      );
    });

    test('a revealed advisor still steps only one diagonal square', () {
      final board = _boardWith({
        const Position(0, 3): Piece.blackGeneral,
        const Position(5, 4): Piece.redAdvisor,
        const Position(9, 4): Piece.redGeneral,
      });
      final game = XiangqiCupGame.debug(board: board);

      for (final to in game.getValidMoves(const Position(5, 4))) {
        expect((to.row - 5).abs(), 1, reason: 'advisor moved >1 row: $to');
        expect((to.col - 4).abs(), 1, reason: 'advisor moved >1 col: $to');
      }
    });

    test('a revealed elephant may cross the river (eye still blocks)', () {
      // Red elephant revealed near the river; one diagonal eye is blocked.
      final board = _boardWith({
        const Position(0, 3): Piece.blackGeneral,
        const Position(5, 4): Piece.redElephant,
        const Position(4, 3): Piece.redSoldier, // blocks the (5,4)->(3,2) eye
        const Position(9, 4): Piece.redGeneral,
      });
      final game = XiangqiCupGame.debug(board: board);

      final moves = game.getValidMoves(const Position(5, 4));
      expect(moves, contains(const Position(3, 6))); // crossed the river
      expect(
        moves,
        isNot(contains(const Position(3, 2))),
        reason: 'blocked elephant eye should forbid (3,2)',
      );
    });

    test('a revealed advisor can deliver check across the board', () {
      // Black general at (2,3); a red advisor diagonally adjacent threatens it.
      // Generals sit on different files so the check is the advisor's, not a
      // flying-general face-off.
      final board = _boardWith({
        const Position(2, 3): Piece.blackGeneral,
        const Position(3, 4): Piece.redAdvisor,
        const Position(9, 4): Piece.redGeneral,
      });
      final game = XiangqiCupGame.debug(board: board, turn: PieceColor.black);

      expect(game.isInCheck(PieceColor.black), isTrue);
    });

    test('hidden piece on the advisor point still moves like a confined Sĩ', () {
      // Cover = advisor but the true hidden piece is a chariot. While face
      // down it must move like its cover (one diagonal step inside the palace),
      // NOT like the powerful piece underneath and NOT roam freely.
      final board = _boardWith({
        const Position(0, 4): Piece.blackGeneral,
        const Position(9, 3): Piece.redAdvisor, // cover
        const Position(9, 4): Piece.redGeneral,
      });
      final game = XiangqiCupGame.debug(
        board: board,
        hiddenAssignments: {const Position(9, 3): Piece.redChariot},
      );

      expect(game.getValidMoves(const Position(9, 3)), [const Position(8, 4)]);
    });

    test('hidden piece on the elephant point still cannot cross the river', () {
      final board = _boardWith({
        const Position(0, 4): Piece.blackGeneral,
        const Position(9, 2): Piece.redElephant, // cover
        const Position(9, 4): Piece.redGeneral,
      });
      final game = XiangqiCupGame.debug(
        board: board,
        hiddenAssignments: {const Position(9, 2): Piece.redChariot},
      );

      final moves = game.getValidMoves(const Position(9, 2));
      expect(moves, contains(const Position(7, 4))); // elephant diagonal
      for (final to in moves) {
        expect(to.row >= 5, isTrue, reason: 'hidden elephant crossed river: $to');
      }
    });
  });
}

Board _boardWith(Map<Position, Piece> pieces) {
  final board = Board.empty();
  for (final entry in pieces.entries) {
    board.setAt(entry.key, entry.value);
  }
  return board;
}

Map<String, int> _nonGeneralPieceCounts(Board board) {
  final counts = <String, int>{};
  for (final (_, piece) in board.occupied()) {
    if (piece.type == PieceType.general) continue;
    _increment(counts, piece);
  }
  return counts;
}

void _increment(Map<String, int> counts, Piece piece) {
  final key = '${piece.color.name}:${piece.type.name}';
  counts[key] = (counts[key] ?? 0) + 1;
}
