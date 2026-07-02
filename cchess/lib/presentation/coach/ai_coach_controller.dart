import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/chess_engine/chess_engine.dart';
import '../../data/models/chess_puzzle.dart';
import '../../data/models/game_record.dart';
import '../../data/repositories/game_history_repository.dart';
import '../../data/repositories/puzzle_repository.dart';

/// State for the AI Coach screen: a loading spinner while the engine grades the
/// game, the resulting [CoachReport], or an error to retry from.
class CoachUiState {
  final bool loading;
  final CoachReport? report;
  final Object? error;

  const CoachUiState({this.loading = true, this.report, this.error});

  bool get hasReport => report != null;
}

/// Runs the engine analysis for a saved game, then turns it into a coach report.
///
/// The analysis goes through the [EngineRouter], so it uses the remote Pikafish
/// service when available and transparently falls back to the on-device minimax
/// analyzer when offline — the coach logic is identical either way.
class AiCoachController extends StateNotifier<CoachUiState> {
  final MoveEngine _engine;
  final GameRecord _record;
  final CoachAnalyzer _analyzer;
  int _runId = 0;

  AiCoachController({
    required GameRecord record,
    required MoveEngine engine,
    CoachAnalyzer analyzer = const CoachAnalyzer(),
  })  : _record = record,
        _engine = engine,
        _analyzer = analyzer,
        super(const CoachUiState(loading: true)) {
    _run();
  }

  /// Whose moves the coach grades. Bot/online games carry the human's color;
  /// local 2-player games don't, so we default to Red.
  PieceColor get playerColor => _record.humanColor ?? PieceColor.red;

  Future<void> _run() async {
    final runId = ++_runId;
    state = const CoachUiState(loading: true);
    try {
      final analysis = await _engine.analyze(
        startingFen: _record.startingFen,
        moveUcis: _record.moves,
      );
      if (!mounted || runId != _runId) return;
      final report = _analyzer.analyze(analysis, playerColor);
      state = CoachUiState(loading: false, report: report);
    } catch (error) {
      if (!mounted || runId != _runId) return;
      state = CoachUiState(loading: false, error: error);
    }
  }

  void retry() => _run();
}

final aiCoachControllerProvider = StateNotifierProvider.autoDispose
    .family<AiCoachController, CoachUiState, GameRecord>((ref, record) {
  return AiCoachController(
    record: record,
    engine: ref.watch(engineRouterProvider),
  );
});

/// Personalized practice set for a coached game (spec B3: "đề xuất bài tập
/// cá nhân hoá hàng ngày"). Watches the coach analysis for [record]; once the
/// [CoachReport] is ready it derives a [CoachPlan] and pulls matching puzzles
/// from the catalog (backend → cache → seed), broadening the filter if the
/// specific tag/difficulty turns up nothing so the section is never empty when
/// any puzzle exists.
final coachRecommendedPuzzlesProvider = FutureProvider.autoDispose
    .family<List<ChessPuzzle>, GameRecord>((ref, record) async {
  final report = ref.watch(aiCoachControllerProvider(record)).report;
  if (report == null || report.isEmpty) return const [];

  final repo = ref.watch(puzzleRepositoryProvider);
  final plan = const CoachRecommender().plan(report);
  const want = 4;

  // Score candidates so the plan's focus/difficulty is preferred but we still
  // fill the set from the broader catalog rather than showing an empty list.
  final seen = <String>{};
  final picked = <ChessPuzzle>[];

  void take(Iterable<ChessPuzzle> puzzles) {
    for (final p in puzzles) {
      if (picked.length >= want) break;
      if (seen.add(p.id)) picked.add(p);
    }
  }

  // 1. Most specific: the plan's top tag within its difficulty band.
  for (final tag in plan.tags) {
    if (picked.length >= want) break;
    final page = await repo.fetchPuzzles(
      tag: tag,
      difficulty: plan.suggestedDifficulty,
      limit: want,
    );
    take(page.puzzles.where((p) => plan.difficultyInBand(p.difficulty)));
  }
  // 2. Broaden: any difficulty for the plan's top tag.
  if (picked.length < want && plan.tags.isNotEmpty) {
    final page = await repo.fetchPuzzles(tag: plan.tags.first, limit: want);
    take(page.puzzles);
  }
  // 3. Last resort: top of the catalog so the player always has something.
  if (picked.length < want) {
    final page = await repo.fetchPuzzles(limit: want);
    take(page.puzzles);
  }
  return picked;
});

/// The plan behind [coachRecommendedPuzzlesProvider] — exposes the focus and
/// rationale to the UI without recomputing it there.
final coachPlanProvider =
    Provider.autoDispose.family<CoachPlan?, GameRecord>((ref, record) {
  final report = ref.watch(aiCoachControllerProvider(record)).report;
  if (report == null || report.isEmpty) return null;
  return const CoachRecommender().plan(report);
});

/// The most recent finished game worth coaching (has moves). Used when the
/// coach is opened generically (e.g. from the Học Cờ "AI Tư Vấn" tile) rather
/// than for one specific record.
final latestCoachGameProvider =
    FutureProvider.autoDispose<GameRecord?>((ref) async {
  final repo = ref.watch(gameHistoryRepositoryProvider);
  final all = await repo.all();
  final coachable = all
      .where(
        (r) => r.isFinished && r.moves.isNotEmpty && r.supportsAiAnalysis,
      )
      .toList()
    ..sort((a, b) => b.endedAt.compareTo(a.endedAt));
  return coachable.isEmpty ? null : coachable.first;
});
