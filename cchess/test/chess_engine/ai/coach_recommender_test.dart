import 'package:cchess/core/chess_engine/ai/coach_analyzer.dart';
import 'package:cchess/core/chess_engine/ai/coach_recommender.dart';
import 'package:cchess/core/chess_engine/ai/game_analyzer.dart';
import 'package:cchess/core/chess_engine/move.dart';
import 'package:cchess/core/chess_engine/piece.dart';
import 'package:cchess/core/chess_engine/position.dart';
import 'package:cchess/core/constants/piece_constants.dart';
import 'package:flutter_test/flutter_test.dart';

/// Minimal MoveAnalysis builder (mirrors coach_analyzer_test): only moveIndex,
/// mover, quality matter to the coach/recommender.
MoveAnalysis mv(int index, MoveQuality quality, {int loss = 0}) {
  return MoveAnalysis(
    moveIndex: index,
    move: Move(
      from: const Position(9, 0),
      to: const Position(8, 0),
      moved: Piece.redSoldier,
    ),
    mover: PieceColor.red,
    recommendedMove: null,
    bestEval: 0,
    actualEval: 0,
    centipawnLoss: loss,
    quality: quality,
  );
}

GameAnalysis aggregate(List<MoveAnalysis> moves) {
  int count = 0, score = 0, blunders = 0, mistakes = 0;
  for (final m in moves) {
    count++;
    score += m.quality.scoreOut100;
    if (m.quality == MoveQuality.blunder) blunders++;
    if (m.quality == MoveQuality.mistake) mistakes++;
  }
  return GameAnalysis(
    moves: moves,
    redAccuracy: count == 0 ? 0 : score / count,
    blackAccuracy: 0,
    redBlunders: blunders,
    blackBlunders: 0,
    redMistakes: mistakes,
    blackMistakes: 0,
  );
}

CoachReport reportFor(List<MoveAnalysis> moves) =>
    const CoachAnalyzer().analyze(aggregate(moves), PieceColor.red);

void main() {
  const recommender = CoachRecommender();

  test('weak opening → opening focus + opening tags', () {
    // Opening poor (blunders), middlegame + endgame solid.
    final report = reportFor([
      mv(0, MoveQuality.blunder, loss: 400),
      mv(2, MoveQuality.mistake, loss: 200),
      mv(4, MoveQuality.blunder, loss: 350),
      mv(16, MoveQuality.best),
      mv(18, MoveQuality.best),
      mv(20, MoveQuality.best),
      mv(48, MoveQuality.best),
      mv(50, MoveQuality.best),
      mv(52, MoveQuality.best),
    ]);
    final plan = recommender.plan(report);
    expect(report.weakestPhase, GamePhase.opening);
    expect(plan.focus, CoachFocus.opening);
    expect(plan.targetPhase, GamePhase.opening);
    expect(plan.tags.first, 'Khai môn');
    expect(plan.category, 'opening');
  });

  test('weak endgame → endgame focus + Tàn cục tag', () {
    final report = reportFor([
      mv(0, MoveQuality.best),
      mv(2, MoveQuality.best),
      mv(4, MoveQuality.best),
      mv(16, MoveQuality.good),
      mv(18, MoveQuality.good),
      mv(20, MoveQuality.good),
      mv(48, MoveQuality.blunder, loss: 400),
      mv(50, MoveQuality.mistake, loss: 200),
      mv(52, MoveQuality.blunder, loss: 350),
    ]);
    final plan = recommender.plan(report);
    expect(plan.focus, CoachFocus.endgame);
    expect(plan.tags, contains('Tàn cục'));
    expect(plan.category, 'endgame');
  });

  test('blunder-heavy middlegame → attack focus', () {
    final report = reportFor([
      mv(0, MoveQuality.best),
      mv(2, MoveQuality.best),
      mv(4, MoveQuality.best),
      // Middlegame: blunders dominate.
      mv(16, MoveQuality.blunder, loss: 400),
      mv(18, MoveQuality.blunder, loss: 350),
      mv(20, MoveQuality.good),
      mv(48, MoveQuality.best),
      mv(50, MoveQuality.best),
      mv(52, MoveQuality.best),
    ]);
    final plan = recommender.plan(report);
    expect(plan.targetPhase, GamePhase.middlegame);
    expect(plan.focus, CoachFocus.attack);
    expect(plan.tags.first, 'Chiếu hết');
  });

  test('mistake-only middlegame (no blunders) → defense focus', () {
    final report = reportFor([
      mv(0, MoveQuality.best),
      mv(2, MoveQuality.best),
      mv(4, MoveQuality.best),
      // Middlegame: mistakes but no blunders.
      mv(16, MoveQuality.mistake, loss: 200),
      mv(18, MoveQuality.mistake, loss: 180),
      mv(20, MoveQuality.mistake, loss: 220),
      mv(48, MoveQuality.best),
      mv(50, MoveQuality.best),
      mv(52, MoveQuality.best),
    ]);
    final plan = recommender.plan(report);
    expect(plan.targetPhase, GamePhase.middlegame);
    expect(plan.focus, CoachFocus.defense);
    expect(plan.tags, contains('Phòng thủ'));
  });

  test('difficulty band scales with overall accuracy', () {
    // All blunders → ~0% accuracy → easiest band.
    final weak = recommender.plan(reportFor([
      mv(16, MoveQuality.blunder, loss: 400),
      mv(18, MoveQuality.blunder, loss: 400),
      mv(20, MoveQuality.blunder, loss: 400),
    ]));
    expect(weak.minDifficulty, 1);
    expect(weak.maxDifficulty, 2);

    // All best → 100% accuracy → hardest band. (No weak phase: falls back to a
    // sensible target, but the band must reflect the strong play.)
    final strong = recommender.plan(reportFor([
      mv(16, MoveQuality.best),
      mv(18, MoveQuality.best),
      mv(20, MoveQuality.best),
    ]));
    expect(strong.minDifficulty, 4);
    expect(strong.maxDifficulty, 5);
  });

  test('suggestedDifficulty and difficultyInBand are consistent', () {
    final plan = recommender.plan(reportFor([
      mv(16, MoveQuality.good),
      mv(18, MoveQuality.inaccuracy, loss: 100),
      mv(20, MoveQuality.good),
    ]));
    expect(plan.difficultyInBand(plan.suggestedDifficulty), isTrue);
    expect(plan.difficultyInBand(plan.minDifficulty), isTrue);
    expect(plan.difficultyInBand(plan.maxDifficulty), isTrue);
    expect(plan.difficultyInBand(plan.maxDifficulty + 1), isFalse);
  });
}
