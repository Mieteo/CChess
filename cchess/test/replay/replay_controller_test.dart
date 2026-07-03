import 'dart:math';

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
    // A fully legal opening — the old fixture contained an illegal 3rd move
    // that the pre-P3 controller silently skipped (the frozen-board bug).
    moves: const ['b2e2', 'h7e7', 'b0c2', 'b9c7'],
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

/// Plays a deterministic Cờ Úp game and packages it the way
/// `game_screen._persistGameResult` does post-P3 (deal + reveal log included).
GameRecord _cupRecordWithReplayData({int seed = 42, int maxMoves = 12}) {
  final game = XiangqiCupGame.initial(seed: seed);
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
  return GameRecord(
    id: 'r3',
    opponentLabel: 'Người Chơi 2',
    mode: GameMode.cupLocal,
    humanColor: null,
    startingFen: kInitialFen,
    moves: game.history.map((m) => m.toUci()).toList(),
    result: game.status,
    endReason: game.endReason,
    eloDelta: 0,
    duration: const Duration(minutes: 4),
    endedAt: DateTime(2026, 7, 3),
    cupHiddenFen:
        CupRecordCodec.encodeHiddenMap(game.initialHiddenAssignments),
    cupReveals: CupRecordCodec.deriveReveals(
      game.initialHiddenAssignments,
      game.history,
    ),
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

    test('AI stays off for cup records even when replay data exists (P0)', () {
      final record = _cupRecordWithReplayData();
      expect(record.hasCupReplayData, isTrue);
      expect(record.supportsAiAnalysis, isFalse);
      final c = ReplayController(record: record);
      c.toggleCoachMode();
      expect(c.state.coachMode, isFalse);
    });
  });

  group('Cờ Úp replay (P3)', () {
    test('record with replay data plays back with true reveal states', () {
      final record = _cupRecordWithReplayData();
      final c = ReplayController(record: record);

      // At the start everything except the two generals is face-down.
      expect(c.state.playableMoves, record.moves.length);
      expect(c.state.replayTruncated, isFalse);
      expect(c.state.hiddenPositions, hasLength(30));

      final startPlacement = c.state.board.toFenPlacement();
      c.goToEnd();
      expect(c.state.currentPly, record.moves.length);
      expect(c.state.board.toFenPlacement(), isNot(startPlacement));
      // Every applied move flips at most one square face-up and can capture
      // at most one more — the face-down count must shrink accordingly.
      expect(
        c.state.hiddenPositions.length,
        inInclusiveRange(30 - 2 * record.moves.length, 30),
      );
      expect(c.state.lastMove?.toUci(), record.moves.last);
    });

    test('legacy cup record: board playback disabled, no crash', () {
      final c = ReplayController(record: _cupRecord());
      expect(c.state.record.hasCupReplayData, isFalse);
      expect(c.state.playableMoves, 0);
      expect(c.state.replayTruncated, isTrue);
      expect(c.state.atEnd, isTrue);
      // The start position renders face-down, and seeking goes nowhere.
      expect(c.state.hiddenPositions, hasLength(30));
      final placement = c.state.board.toFenPlacement();
      c.seek(2);
      expect(c.state.currentPly, 0);
      expect(c.state.board.toFenPlacement(), placement);
      c.stepForward();
      expect(c.state.currentPly, 0);
    });

    test('corrupt record stops exactly at the first invalid move', () {
      final record = GameRecord(
        id: 'r4',
        opponentLabel: 'Bot',
        mode: GameMode.vsBot,
        humanColor: PieceColor.red,
        startingFen: kInitialFen,
        // Move 2 moves a red piece on Black's turn → inapplicable.
        moves: const ['b2e2', 'e0e1', 'h7e7'],
        result: GameStatus.draw,
        endReason: EndReason.drawAgreed,
        eloDelta: 0,
        duration: const Duration(minutes: 1),
        endedAt: DateTime(2026, 7, 3),
      );
      final c = ReplayController(record: record);
      expect(c.state.playableMoves, 1);
      expect(c.state.replayTruncated, isTrue);
      c.seek(3);
      expect(c.state.currentPly, 1);
      expect(c.state.lastMove?.toUci(), 'b2e2');
      expect(c.state.atEnd, isTrue);
    });
  });

  group('GameRecord cup replay serialization', () {
    test('cup fields survive a JSON round trip', () {
      final record = _cupRecordWithReplayData();
      final restored = GameRecord.fromJson(record.toJson());
      expect(restored, record);
      expect(restored.hasCupReplayData, isTrue);
      expect(restored.cupReveals, record.cupReveals);
    });

    test('null entries in cupReveals survive a JSON round trip', () {
      final base = _cupRecord();
      final record = GameRecord(
        id: base.id,
        opponentLabel: base.opponentLabel,
        mode: base.mode,
        humanColor: base.humanColor,
        startingFen: base.startingFen,
        moves: base.moves,
        result: base.result,
        endReason: base.endReason,
        eloDelta: base.eloDelta,
        duration: base.duration,
        endedAt: base.endedAt,
        cupHiddenFen: 'rnbakabnr/9/1c5c1/p1p1p1p1p/9/9/P1P1P1P1P/1C5C1/9/RNBAKABNR',
        cupReveals: const ['C', null],
      );
      final restored = GameRecord.fromJson(record.toJson());
      expect(restored.cupReveals, const ['C', null]);
      expect(restored, record);
    });

    test('legacy JSON without cup fields still parses (backward compat)', () {
      final json = _cupRecord().toJson();
      expect(json.containsKey('cupHiddenFen'), isFalse);
      expect(json.containsKey('cupReveals'), isFalse);
      final restored = GameRecord.fromJson(json);
      expect(restored.cupHiddenFen, isNull);
      expect(restored.cupReveals, isNull);
      expect(restored.hasCupReplayData, isFalse);
      expect(restored.variant, 'cup');
      expect(_sampleRecord().variant, 'standard');
    });
  });
}
