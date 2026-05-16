import 'package:cchess/core/chess_engine/chess_engine.dart';
import 'package:cchess/data/models/game_record.dart';
import 'package:cchess/presentation/replay/replay_controller.dart';
import 'package:flutter_test/flutter_test.dart';

GameRecord _sampleRecord() {
  return GameRecord(
    id: 'r1',
    opponentLabel: 'Bot',
    mode: GameMode.vsBot,
    humanColor: PieceColor.red,
    startingFen: kInitialFen,
    moves: const ['b2e2', 'b7e7', 'h2e2', 'h7e7'],
    result: GameStatus.draw,
    endReason: EndReason.drawAgreed,
    eloDelta: 0,
    duration: const Duration(minutes: 2),
    endedAt: DateTime(2026, 5, 16),
  );
}

void main() {
  group('ReplayController', () {
    test('starts at ply 0 with the initial board', () {
      final c = ReplayController(record: _sampleRecord());
      expect(c.state.currentPly, 0);
      expect(c.state.atStart, isTrue);
      expect(c.state.atEnd, isFalse);
      expect(c.state.lastMove, isNull);
      expect(c.state.board.occupied(), hasLength(32));
    });

    test('stepForward advances one ply and exposes the last move', () {
      final c = ReplayController(record: _sampleRecord());
      c.stepForward();
      expect(c.state.currentPly, 1);
      expect(c.state.lastMove, isNotNull);
      expect(c.state.lastMove!.toUci(), 'b2e2');
    });

    test('stepBackward decrements ply', () {
      final c = ReplayController(record: _sampleRecord());
      c.stepForward();
      c.stepForward();
      expect(c.state.currentPly, 2);
      c.stepBackward();
      expect(c.state.currentPly, 1);
      expect(c.state.lastMove!.toUci(), 'b2e2');
    });

    test('seek jumps to arbitrary ply and clamps to bounds', () {
      final c = ReplayController(record: _sampleRecord());
      c.seek(3);
      expect(c.state.currentPly, 3);
      c.seek(999);
      expect(c.state.currentPly, c.state.totalPly);
      c.seek(-5);
      expect(c.state.currentPly, 0);
    });

    test('goToEnd lands at the final ply and atEnd flips true', () {
      final c = ReplayController(record: _sampleRecord());
      c.goToEnd();
      expect(c.state.atEnd, isTrue);
      expect(c.state.currentPly, c.state.totalPly);
    });

    test('toggleCoachMode flips the flag', () {
      final c = ReplayController(record: _sampleRecord());
      expect(c.state.coachMode, isFalse);
      c.toggleCoachMode();
      expect(c.state.coachMode, isTrue);
    });
  });
}
