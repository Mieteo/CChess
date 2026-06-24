import 'package:equatable/equatable.dart';

/// Solved / attempted tally for one difficulty bucket (1..5, or 0 = unknown
/// difficulty for puzzles whose metadata is no longer in the local catalog).
class DifficultyStat extends Equatable {
  final int difficulty;
  final int solved;
  final int attempted;

  const DifficultyStat({
    required this.difficulty,
    required this.solved,
    required this.attempted,
  });

  double get ratio => attempted == 0 ? 0 : solved / attempted;

  @override
  List<Object?> get props => [difficulty, solved, attempted];
}

/// Aggregated view of the user's endgame (tàn cục) progress, derived from the
/// local progress box joined against the local puzzle catalog. Powers
/// `EndgameStatsScreen`.
class PuzzleStats extends Equatable {
  /// Distinct puzzles with at least one attempt (or already solved).
  final int attempted;

  /// Distinct puzzles solved.
  final int solved;

  /// Total puzzles known locally (seed + cached remote) — the "/ total" denom.
  final int catalogSize;

  /// Sum of attempt counters across all puzzles.
  final int totalAttempts;

  /// Sum of hint charges spent across all puzzles.
  final int totalHints;

  /// Sum of best scores over puzzles that have a non-zero best score.
  final int _bestScoreSum;

  /// Number of puzzles contributing to [_bestScoreSum].
  final int _scoredCount;

  /// Per-difficulty breakdown, sorted ascending by difficulty.
  final List<DifficultyStat> byDifficulty;

  const PuzzleStats({
    required this.attempted,
    required this.solved,
    required this.catalogSize,
    required this.totalAttempts,
    required this.totalHints,
    required int bestScoreSum,
    required int scoredCount,
    required this.byDifficulty,
  })  : _bestScoreSum = bestScoreSum,
        _scoredCount = scoredCount;

  static const empty = PuzzleStats(
    attempted: 0,
    solved: 0,
    catalogSize: 0,
    totalAttempts: 0,
    totalHints: 0,
    bestScoreSum: 0,
    scoredCount: 0,
    byDifficulty: [],
  );

  /// Share of attempted puzzles that were solved, in 0..1.
  double get solveRate => attempted == 0 ? 0 : solved / attempted;

  /// Share of the whole catalog that has been solved, in 0..1.
  double get completion => catalogSize == 0 ? 0 : solved / catalogSize;

  /// Mean best score over scored puzzles (0 when none scored yet).
  int get averageScore =>
      _scoredCount == 0 ? 0 : (_bestScoreSum / _scoredCount).round();

  @override
  List<Object?> get props => [
        attempted,
        solved,
        catalogSize,
        totalAttempts,
        totalHints,
        _bestScoreSum,
        _scoredCount,
        byDifficulty,
      ];
}
