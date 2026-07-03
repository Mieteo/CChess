import 'package:cchess/core/chess_engine/chess_engine.dart';
import 'package:cchess/widgets/chess/eval_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

GameAnalysis _analysis(List<int?> evals) {
  final game = XiangqiGame.fromFen(kInitialFen);
  const ucis = ['h2e2', 'h7e7', 'b0c2'];
  final moves = <MoveAnalysis>[];
  for (var i = 0; i < evals.length; i++) {
    final (from, to) = Move.parseUciCoords(ucis[i])!;
    final piece = game.board.at(from)!;
    moves.add(
      MoveAnalysis(
        moveIndex: i,
        move: Move(
          from: from,
          to: to,
          moved: piece,
          captured: game.board.at(to),
        ),
        mover: game.turn,
        recommendedMove: null,
        bestEval: 0,
        actualEval: evals[i] ?? 0,
        centipawnLoss: 0,
        quality: i == 1 ? MoveQuality.blunder : MoveQuality.good,
        evalAfterCp: evals[i],
      ),
    );
    game.makeMove(from, to);
  }
  return GameAnalysis(
    moves: moves,
    redAccuracy: 90,
    blackAccuracy: 80,
    redBlunders: 0,
    blackBlunders: 1,
    redMistakes: 0,
    blackMistakes: 0,
  );
}

void main() {
  group('EvalChart mapping helpers', () {
    test('evalSeries places evalAfterCp by move index', () {
      final series = EvalChart.evalSeries(_analysis([12, -300, 40]), 4);
      expect(series, [12, -300, 40, null]);
    });

    test('yFraction: midline for 0, clamped at the edges, mate at edge', () {
      expect(EvalChart.yFraction(0), 0.5);
      expect(EvalChart.yFraction(EvalChart.displayCapCp), 0.0);
      expect(EvalChart.yFraction(-EvalChart.displayCapCp), 1.0);
      expect(EvalChart.yFraction(29999), 0.0); // mate flattens to the edge
      expect(EvalChart.yFraction(-29999), 1.0);
      expect(EvalChart.yFraction(750), 0.25);
    });

    test('plyForDx maps taps across the width onto 0..totalPly', () {
      expect(EvalChart.plyForDx(0, 300, 60), 0);
      expect(EvalChart.plyForDx(300, 300, 60), 60);
      expect(EvalChart.plyForDx(150, 300, 60), 30);
      expect(EvalChart.plyForDx(-20, 300, 60), 0); // clamps
      expect(EvalChart.plyForDx(150, 300, 0), 0); // empty game
    });
  });

  testWidgets('tapping the chart seeks to the matching ply', (tester) async {
    int? seeked;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 300,
              height: 80,
              child: EvalChart(
                analysis: _analysis([12, -300, 40]),
                totalPly: 3,
                currentPly: 0,
                onSeek: (ply) => seeked = ply,
              ),
            ),
          ),
        ),
      ),
    );

    // Tap the horizontal middle → ply round(0.5 × 3) = 2.
    await tester.tapAt(tester.getCenter(find.byType(EvalChart)));
    expect(seeked, 2);
  });
}
