import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/chess_engine/chess_engine.dart';
import '../../data/models/game_record.dart';
import '../../data/repositories/game_history_repository.dart';

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

/// The most recent finished game worth coaching (has moves). Used when the
/// coach is opened generically (e.g. from the Học Cờ "AI Tư Vấn" tile) rather
/// than for one specific record.
final latestCoachGameProvider =
    FutureProvider.autoDispose<GameRecord?>((ref) async {
  final repo = ref.watch(gameHistoryRepositoryProvider);
  final all = await repo.all();
  final coachable = all
      .where((r) => r.isFinished && r.moves.isNotEmpty)
      .toList()
    ..sort((a, b) => b.endedAt.compareTo(a.endedAt));
  return coachable.isEmpty ? null : coachable.first;
});
