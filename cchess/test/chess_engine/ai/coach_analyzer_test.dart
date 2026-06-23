import 'package:cchess/core/chess_engine/ai/coach_analyzer.dart';
import 'package:cchess/core/chess_engine/ai/game_analyzer.dart';
import 'package:cchess/core/chess_engine/move.dart';
import 'package:cchess/core/chess_engine/piece.dart';
import 'package:cchess/core/chess_engine/position.dart';
import 'package:cchess/core/constants/piece_constants.dart';
import 'package:flutter_test/flutter_test.dart';

/// Builds a MoveAnalysis whose only meaningful fields for the coach are
/// moveIndex, mover, quality and centipawnLoss. The Move itself is a throwaway.
MoveAnalysis mv(
  int index,
  PieceColor color,
  MoveQuality quality, {
  int loss = 0,
}) {
  return MoveAnalysis(
    moveIndex: index,
    move: Move(
      from: const Position(9, 0),
      to: const Position(8, 0),
      moved: color == PieceColor.red ? Piece.redSoldier : Piece.blackSoldier,
    ),
    mover: color,
    recommendedMove: null,
    bestEval: 0,
    actualEval: 0,
    centipawnLoss: loss,
    quality: quality,
  );
}

/// Aggregate a move list into a GameAnalysis the same way GameAnalyzer does, so
/// accuracyFor() reflects the per-move qualities.
GameAnalysis aggregate(List<MoveAnalysis> moves) {
  int redCount = 0, blackCount = 0, redScore = 0, blackScore = 0;
  int redBlunder = 0, blackBlunder = 0, redMistake = 0, blackMistake = 0;
  for (final m in moves) {
    if (m.mover == PieceColor.red) {
      redCount++;
      redScore += m.quality.scoreOut100;
      if (m.quality == MoveQuality.blunder) redBlunder++;
      if (m.quality == MoveQuality.mistake) redMistake++;
    } else {
      blackCount++;
      blackScore += m.quality.scoreOut100;
      if (m.quality == MoveQuality.blunder) blackBlunder++;
      if (m.quality == MoveQuality.mistake) blackMistake++;
    }
  }
  return GameAnalysis(
    moves: moves,
    redAccuracy: redCount == 0 ? 0 : redScore / redCount,
    blackAccuracy: blackCount == 0 ? 0 : blackScore / blackCount,
    redBlunders: redBlunder,
    blackBlunders: blackBlunder,
    redMistakes: redMistake,
    blackMistakes: blackMistake,
  );
}

void main() {
  const coach = CoachAnalyzer();

  test('phaseForPly buckets plies into opening/middlegame/endgame', () {
    expect(coach.phaseForPly(0), GamePhase.opening);
    expect(coach.phaseForPly(15), GamePhase.opening);
    expect(coach.phaseForPly(16), GamePhase.middlegame);
    expect(coach.phaseForPly(47), GamePhase.middlegame);
    expect(coach.phaseForPly(48), GamePhase.endgame);
  });

  test('identifies the weakest/strongest phase and routes advice', () {
    final moves = <MoveAnalysis>[
      // Opening: strong (3 best moves → 100%).
      mv(0, PieceColor.red, MoveQuality.best),
      mv(2, PieceColor.red, MoveQuality.best),
      mv(4, PieceColor.red, MoveQuality.best),
      // Middlegame: solid (3 good → 80%).
      mv(16, PieceColor.red, MoveQuality.good),
      mv(18, PieceColor.red, MoveQuality.good),
      mv(20, PieceColor.red, MoveQuality.good),
      // Endgame: poor (2 blunders + 1 mistake).
      mv(48, PieceColor.red, MoveQuality.blunder, loss: 400),
      mv(50, PieceColor.red, MoveQuality.mistake, loss: 200),
      mv(52, PieceColor.red, MoveQuality.blunder, loss: 350),
    ];
    final report = coach.analyze(aggregate(moves), PieceColor.red);

    expect(report.weakestPhase, GamePhase.endgame);
    expect(report.strongestPhase, GamePhase.opening);
    expect(report.phaseReport(GamePhase.opening).accuracy, 100);
    expect(report.phaseReport(GamePhase.endgame).blunders, 2);
    expect(report.phaseReport(GamePhase.endgame).mistakes, 1);
    expect(report.analysedMoveCount, 9);

    // Endgame weakness routes to puzzle practice; the strong opening earns praise.
    expect(
      report.insights.any((i) => i.action == CoachActionKind.practicePuzzles),
      isTrue,
    );
    expect(report.insights.any((i) => i.tone == CoachTone.praise), isTrue);
  });

  test('a weak opening routes to opening study', () {
    final moves = <MoveAnalysis>[
      // Opening: weak (3 mistakes).
      mv(0, PieceColor.red, MoveQuality.mistake, loss: 200),
      mv(2, PieceColor.red, MoveQuality.mistake, loss: 180),
      mv(4, PieceColor.red, MoveQuality.inaccuracy, loss: 100),
      // Middlegame: strong.
      mv(16, PieceColor.red, MoveQuality.best),
      mv(18, PieceColor.red, MoveQuality.best),
      mv(20, PieceColor.red, MoveQuality.excellent),
    ];
    final report = coach.analyze(aggregate(moves), PieceColor.red);

    expect(report.weakestPhase, GamePhase.opening);
    expect(
      report.insights.any((i) => i.action == CoachActionKind.studyOpenings),
      isTrue,
    );
  });

  test('critical moments are the player\'s worst moves, worst first, capped at 3', () {
    final moves = <MoveAnalysis>[
      mv(0, PieceColor.red, MoveQuality.blunder, loss: 300),
      mv(2, PieceColor.red, MoveQuality.best), // ignored (not a mistake)
      mv(4, PieceColor.red, MoveQuality.mistake, loss: 150),
      mv(6, PieceColor.red, MoveQuality.blunder, loss: 500),
      mv(8, PieceColor.red, MoveQuality.mistake, loss: 200),
      // Opponent blunders must not appear in the player's review list.
      mv(1, PieceColor.black, MoveQuality.blunder, loss: 999),
    ];
    final report = coach.analyze(aggregate(moves), PieceColor.red);

    expect(report.criticalMoments.length, 3);
    expect(report.criticalMoments[0].centipawnLoss, 500);
    expect(report.criticalMoments[1].centipawnLoss, 300);
    expect(report.criticalMoments[2].centipawnLoss, 200);
    expect(
      report.criticalMoments.every((m) => m.mover == PieceColor.red),
      isTrue,
    );
  });

  test('empty when the player never moved', () {
    final moves = <MoveAnalysis>[
      mv(0, PieceColor.black, MoveQuality.good),
      mv(2, PieceColor.black, MoveQuality.mistake, loss: 200),
    ];
    final report = coach.analyze(aggregate(moves), PieceColor.red);

    expect(report.isEmpty, isTrue);
    expect(report.insights, isEmpty);
    expect(report.criticalMoments, isEmpty);
  });

  test('high overall accuracy yields a praise headline', () {
    final moves = [
      for (var i = 0; i < 6; i++) mv(i * 2, PieceColor.red, MoveQuality.best),
    ];
    final report = coach.analyze(aggregate(moves), PieceColor.red);

    expect(report.overallAccuracy, 100);
    expect(report.gradeVi, 'Xuất sắc');
    expect(report.insights.first.tone, CoachTone.praise);
  });
}
