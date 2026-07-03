import 'dart:math';

import 'package:cchess/core/chess_engine/chess_engine.dart';
import 'package:flutter_test/flutter_test.dart';

/// Plays [maxMoves] deterministic pseudo-random legal moves on [game].
void _playSeededMoves(XiangqiCupGame game, {required int seed, int maxMoves = 40}) {
  final rng = Random(seed);
  while (game.history.length < maxMoves && !game.status.isOver) {
    final candidates = <(Position, Position)>[];
    for (final (pos, piece) in game.board.occupied()) {
      if (piece.color != game.turn) continue;
      for (final to in game.getValidMoves(pos)) {
        candidates.add((pos, to));
      }
    }
    if (candidates.isEmpty) break;
    final (from, to) = candidates[rng.nextInt(candidates.length)];
    game.makeMove(from, to);
  }
}

void main() {
  group('CupRecordCodec', () {
    test('hidden map survives an encode/decode round trip', () {
      final game = XiangqiCupGame.initial(seed: 7);
      final original = game.initialHiddenAssignments;
      expect(original, hasLength(30)); // 32 pieces minus the 2 generals

      final decoded =
          CupRecordCodec.decodeHiddenMap(CupRecordCodec.encodeHiddenMap(original));
      expect(decoded, isNotNull);
      expect(decoded, hasLength(original.length));
      original.forEach((pos, piece) {
        expect(decoded![pos], piece, reason: 'identity mismatch at $pos');
      });
    });

    test('decodeHiddenMap returns null for malformed input', () {
      expect(CupRecordCodec.decodeHiddenMap('not-a-fen'), isNull);
      expect(CupRecordCodec.decodeHiddenMap('9/9/9'), isNull);
      expect(CupRecordCodec.decodeHiddenMap(''), isNull);
    });

    test('deriveReveals flags face-down movers with their true identity', () {
      final game = XiangqiCupGame.initial(seed: 3);
      _playSeededMoves(game, seed: 3, maxMoves: 20);

      final reveals = CupRecordCodec.deriveReveals(
        game.initialHiddenAssignments,
        game.history,
      );
      expect(reveals, hasLength(game.history.length));

      // Replay the reveal bookkeeping by hand and compare.
      final hidden = Set<Position>.from(game.initialHiddenAssignments.keys);
      for (var i = 0; i < game.history.length; i++) {
        final move = game.history[i];
        if (hidden.remove(move.from)) {
          expect(reveals[i], move.moved.fenChar,
              reason: 'move $i flipped a face-down piece');
        } else {
          expect(reveals[i], isNull, reason: 'move $i moved a face-up piece');
        }
        hidden.remove(move.to);
      }
    });
  });

  group('CupReplaySession round trip (doc 14 §4.4)', () {
    test('replays a seeded game ply-by-ply: boards + face-down sets match', () {
      // 1. Play the "real" game, snapshotting the truth after every ply.
      final game = XiangqiCupGame.initial(seed: 42);
      final initialHidden = game.initialHiddenAssignments;
      final placements = <String>[game.board.toFenPlacement()];
      final hiddenSets = <Set<Position>>[game.hiddenPositions];
      _playSeededMoves(game, seed: 42, maxMoves: 40);
      final ucis = <String>[];
      for (final move in game.history) {
        ucis.add(move.toUci());
      }
      // Snapshots have to be taken as the game progresses — rebuild them from
      // a second deterministic game with the same seed and the same moves.
      // Same seed ⇒ same deal (verified per square via the debug hook).
      final shadow = XiangqiCupGame.initial(seed: 42);
      for (final pos in initialHidden.keys) {
        expect(shadow.debugHiddenPieceAt(pos), initialHidden[pos],
            reason: 'seeded deal not deterministic at $pos');
      }
      for (final uci in ucis) {
        final coords = Move.parseUciCoords(uci)!;
        shadow.makeMove(coords.$1, coords.$2);
        placements.add(shadow.board.toFenPlacement());
        hiddenSets.add(shadow.hiddenPositions);
      }

      // 2. Persist exactly what GameRecord would store…
      final cupHiddenFen = CupRecordCodec.encodeHiddenMap(initialHidden);
      final cupReveals =
          CupRecordCodec.deriveReveals(initialHidden, game.history);

      // 3. …and replay from storage only.
      final session = CupReplaySession(
        startingFen: kInitialFen,
        initialHidden: CupRecordCodec.decodeHiddenMap(cupHiddenFen)!,
        moveUcis: ucis,
        expectedReveals: cupReveals,
      );

      expect(session.playableMoves, ucis.length);
      for (var ply = 0; ply <= ucis.length; ply++) {
        final frame = session.frameAt(ply);
        expect(frame.board.toFenPlacement(), placements[ply],
            reason: 'board diverged at ply $ply');
        expect(frame.hiddenPositions, hiddenSets[ply],
            reason: 'face-down set diverged at ply $ply');
        if (ply > 0) {
          expect(frame.lastMove?.toUci(), ucis[ply - 1]);
        }
      }
    });

    test('a tampered reveal log stops playback at the mismatch', () {
      final game = XiangqiCupGame.initial(seed: 9);
      _playSeededMoves(game, seed: 9, maxMoves: 12);
      final initialHidden = game.initialHiddenAssignments;
      final ucis = game.history.map((m) => m.toUci()).toList();
      final reveals = CupRecordCodec.deriveReveals(initialHidden, game.history);

      // Corrupt the log at move 5: claim the opposite reveal state.
      const k = 5;
      reveals[k] = reveals[k] == null ? 'R' : null;

      final session = CupReplaySession(
        startingFen: kInitialFen,
        initialHidden: initialHidden,
        moveUcis: ucis,
        expectedReveals: reveals,
      );
      expect(session.playableMoves, k);
    });
  });

  group('LegacyCupReplaySession', () {
    test('shows only the face-down starting position', () {
      final session = LegacyCupReplaySession(startingFen: kInitialFen);
      expect(session.playableMoves, 0);
      final frame = session.frameAt(0);
      expect(frame.board.occupied(), hasLength(32));
      expect(frame.hiddenPositions, hasLength(30));
      expect(
        frame.hiddenPositions,
        isNot(contains(Position(9, 4))), // red general stays face-up
      );
      // frameAt clamps: asking past the end returns the same start frame.
      expect(session.frameAt(99).board.toFenPlacement(),
          frame.board.toFenPlacement());
    });
  });

  group('StandardReplaySession', () {
    test('stops at the first inapplicable move instead of skipping it', () {
      final session = StandardReplaySession(
        startingFen: kInitialFen,
        // Move 2 tries to move a RED piece on Black's turn → invalid.
        moveUcis: const ['b2e2', 'e0e1', 'h7e7'],
      );
      expect(session.playableMoves, 1);
      expect(session.frameAt(1).lastMove?.toUci(), 'b2e2');
    });
  });

  group('ReplaySession.build dispatch', () {
    test('picks the right session per variant + data completeness', () {
      final cupGame = XiangqiCupGame.initial(seed: 1);
      final hiddenFen =
          CupRecordCodec.encodeHiddenMap(cupGame.initialHiddenAssignments);

      expect(
        ReplaySession.build(
          isCupGame: false,
          startingFen: kInitialFen,
          moveUcis: const ['b2e2'],
        ),
        isA<StandardReplaySession>(),
      );
      expect(
        ReplaySession.build(
          isCupGame: true,
          startingFen: kInitialFen,
          moveUcis: const [],
          cupHiddenFen: hiddenFen,
        ),
        isA<CupReplaySession>(),
      );
      expect(
        ReplaySession.build(
          isCupGame: true,
          startingFen: kInitialFen,
          moveUcis: const ['b2e2'],
        ),
        isA<LegacyCupReplaySession>(),
      );
      // A cup record with an unreadable deal degrades to the legacy path.
      expect(
        ReplaySession.build(
          isCupGame: true,
          startingFen: kInitialFen,
          moveUcis: const ['b2e2'],
          cupHiddenFen: 'garbage',
        ),
        isA<LegacyCupReplaySession>(),
      );
    });
  });
}
