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

GameRecord _cupRecord() {
  return GameRecord(
    id: 'r2',
    opponentLabel: 'Bot',
    mode: GameMode.cupVsBot,
    humanColor: PieceColor.red,
    startingFen: kInitialFen,
    moves: const ['b2e2', 'b7e7'],
    result: GameStatus.redWin,
    endReason: EndReason.checkmate,
    eloDelta: 0,
    duration: const Duration(minutes: 3),
    endedAt: DateTime(2026, 5, 17),
  );
}

/// Strong path always fails; weak path returns a labelled minimax analysis.
class _StrictFailEngine implements MoveEngine {
  int strictCalls = 0;
  int weakCalls = 0;

  @override
  Future<EngineMove?> bestMove(
    String fen, {
    required EngineLevel level,
    EngineUseCase useCase = EngineUseCase.bot,
    EngineConfig? config,
  }) async =>
      null;

  @override
  Future<GameAnalysis> analyze({
    required String startingFen,
    required List<String> moveUcis,
    void Function(double progress)? onProgress,
    bool allowWeakFallback = true,
  }) async {
    if (!allowWeakFallback) {
      strictCalls++;
      throw AnalysisUnavailableException('server down');
    }
    weakCalls++;
    onProgress?.call(1.0);
    return GameAnalysis.aggregate(
      const [],
      source: EngineSource.localMinimax,
    );
  }
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

    test('toggleCoachMode is a no-op for Cờ Úp records', () {
      final c = ReplayController(record: _cupRecord());
      c.toggleCoachMode();
      expect(c.state.coachMode, isFalse);
      expect(c.state.analysis, isNull);
      c.runAnalysis();
      expect(c.state.analysis, isNull);
    });

    test(
      'strong-engine failure surfaces analysisUnavailable instead of a '
      'silent weak fallback; runQuickAnalysis then opts into it',
      () async {
        final engine = _StrictFailEngine();
        final c = ReplayController(
          record: _sampleRecord(),
          analysisEngine: engine,
        );

        c.toggleCoachMode();
        await Future<void>.delayed(const Duration(milliseconds: 20));
        expect(c.state.analysis, isNull);
        expect(c.state.analysisUnavailable, isNotNull);
        expect(engine.strictCalls, 1);
        expect(engine.weakCalls, 0);

        c.runQuickAnalysis();
        await Future<void>.delayed(const Duration(milliseconds: 20));
        expect(c.state.analysisUnavailable, isNull);
        expect(c.state.analysis, isNotNull);
        expect(c.state.analysis!.source, EngineSource.localMinimax);
        expect(engine.weakCalls, 1);
      },
    );
  });

  group('GameRecord AI-analysis gate', () {
    test('cup modes do not support AI analysis, standard modes do', () {
      expect(_cupRecord().isCupMode, isTrue);
      expect(_cupRecord().supportsAiAnalysis, isFalse);
      expect(_sampleRecord().isCupMode, isFalse);
      expect(_sampleRecord().supportsAiAnalysis, isTrue);
    });
  });
}
