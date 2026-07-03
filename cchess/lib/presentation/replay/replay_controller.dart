import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/chess_engine/chess_engine.dart';
import '../../data/models/game_record.dart';
import '../../data/repositories/analysis_cache_repository.dart';
import '../../data/repositories/game_history_repository.dart';

class ReplayUiState {
  /// The saved game we're replaying.
  final GameRecord record;

  /// Number of moves applied so far (0 = starting position).
  final int currentPly;

  /// Current board after applying [currentPly] moves.
  final Board board;

  /// Squares whose piece is still face-down at [currentPly] (Cờ Úp only).
  final Set<Position> hiddenPositions;

  /// How many leading moves of the record can actually be applied. Equals
  /// [totalPly] for intact records; smaller when the record is corrupt from
  /// some move on, and 0 for legacy Cờ Úp records without reveal data.
  final int playableMoves;

  /// Last move played (i.e. the move at index currentPly-1), if any.
  final Move? lastMove;

  /// Whether replay is auto-playing.
  final bool isPlaying;

  /// Replay speed (1.0 = 1 move/sec, 2.0 = 2 moves/sec, ...).
  final double speed;

  /// True if the user activated AI Coach mode (per-move quality badges).
  final bool coachMode;

  /// Loaded analysis or null while still computing.
  final GameAnalysis? analysis;

  /// Fraction in [0, 1] for analysis progress.
  final double analysisProgress;

  /// Set when a strong (Pikafish-grade) analysis could not be obtained and
  /// the user must choose: retry, or accept the quick offline analyzer.
  /// Never set while [analysis] is non-null.
  final AnalysisUnavailableException? analysisUnavailable;

  const ReplayUiState({
    required this.record,
    required this.currentPly,
    required this.board,
    required this.hiddenPositions,
    required this.playableMoves,
    required this.lastMove,
    required this.isPlaying,
    required this.speed,
    required this.coachMode,
    required this.analysis,
    required this.analysisProgress,
    this.analysisUnavailable,
  });

  int get totalPly => record.moves.length;
  bool get atStart => currentPly == 0;

  /// Playback stops at [playableMoves], not [totalPly]: past that point the
  /// stored moves can't be applied (corrupt data / legacy Cờ Úp record) and
  /// letting the cursor run further is exactly the frozen-board bug of P3.
  bool get atEnd => currentPly >= playableMoves;

  /// True when part of the move list can't be replayed on the board.
  bool get replayTruncated => playableMoves < totalPly;

  ReplayUiState copyWith({
    int? currentPly,
    Board? board,
    Set<Position>? hiddenPositions,
    Move? lastMove,
    bool clearLastMove = false,
    bool? isPlaying,
    double? speed,
    bool? coachMode,
    GameAnalysis? analysis,
    double? analysisProgress,
    AnalysisUnavailableException? analysisUnavailable,
    bool clearAnalysisUnavailable = false,
  }) {
    return ReplayUiState(
      record: record,
      currentPly: currentPly ?? this.currentPly,
      board: board ?? this.board,
      hiddenPositions: hiddenPositions ?? this.hiddenPositions,
      playableMoves: playableMoves,
      lastMove: clearLastMove ? null : (lastMove ?? this.lastMove),
      isPlaying: isPlaying ?? this.isPlaying,
      speed: speed ?? this.speed,
      coachMode: coachMode ?? this.coachMode,
      analysis: analysis ?? this.analysis,
      analysisProgress: analysisProgress ?? this.analysisProgress,
      analysisUnavailable: clearAnalysisUnavailable
          ? null
          : (analysisUnavailable ?? this.analysisUnavailable),
    );
  }
}

/// Controller that walks through a saved [GameRecord] move-by-move.
///
/// Playback is delegated to a variant-aware [ReplaySession]: standard rules
/// for normal games, [CupReplaySession] for Cờ Úp records that carry their
/// hidden deal, and a start-position-only session for legacy cup records.
class ReplayController extends StateNotifier<ReplayUiState> {
  Timer? _autoPlayTimer;
  int _analysisRunId = 0;
  final ReplaySession _session;
  final MoveEngine _analysisEngine;
  final AnalysisCacheRepository? _analysisCache;

  factory ReplayController({
    required GameRecord record,
    MoveEngine? analysisEngine,
    AnalysisCacheRepository? analysisCache,
  }) {
    return ReplayController._(
      record: record,
      session: ReplaySession.build(
        isCupGame: record.isCupMode,
        startingFen: record.startingFen,
        moveUcis: record.moves,
        cupHiddenFen: record.cupHiddenFen,
        cupReveals: record.cupReveals,
      ),
      analysisEngine: analysisEngine,
      analysisCache: analysisCache,
    );
  }

  ReplayController._({
    required GameRecord record,
    required ReplaySession session,
    MoveEngine? analysisEngine,
    AnalysisCacheRepository? analysisCache,
  })  : _session = session,
        _analysisEngine = analysisEngine ?? LocalMinimaxEngine(),
        _analysisCache = analysisCache,
        super(
          ReplayUiState(
            record: record,
            currentPly: 0,
            board: session.frameAt(0).board,
            hiddenPositions: session.frameAt(0).hiddenPositions,
            playableMoves: session.playableMoves,
            lastMove: null,
            isPlaying: false,
            speed: 1.0,
            coachMode: false,
            analysis: null,
            analysisProgress: 0,
          ),
        );

  @override
  void dispose() {
    _autoPlayTimer?.cancel();
    _analysisRunId++;
    super.dispose();
  }

  /// Jump to [ply] (0 = before first move). Clamped to [ReplayUiState.playableMoves]
  /// so a corrupt record stops AT the bad move instead of the highlight
  /// running ahead of a frozen board.
  void seek(int ply) {
    final target = ply.clamp(0, state.playableMoves);
    final frame = _session.frameAt(target);
    state = state.copyWith(
      currentPly: target,
      board: frame.board,
      hiddenPositions: frame.hiddenPositions,
      lastMove: frame.lastMove,
      clearLastMove: frame.lastMove == null,
      isPlaying: target >= state.playableMoves ? false : state.isPlaying,
    );
  }

  void stepForward() {
    if (state.atEnd) {
      _stopAutoPlay();
      return;
    }
    seek(state.currentPly + 1);
  }

  void stepBackward() {
    if (state.atStart) return;
    seek(state.currentPly - 1);
  }

  void goToStart() => seek(0);
  void goToEnd() => seek(state.playableMoves);

  void toggleAutoPlay() {
    if (state.isPlaying) {
      _stopAutoPlay();
    } else {
      _startAutoPlay();
    }
  }

  void setSpeed(double speed) {
    state = state.copyWith(speed: speed);
    if (state.isPlaying) {
      // Restart timer at the new tempo.
      _startAutoPlay();
    }
  }

  void toggleCoachMode() {
    // Cờ Úp: grading moves made under imperfect information with a
    // full-information engine is meaningless (P0 decision), so the coach
    // stays off even for post-P3 records that do carry replay data.
    if (state.record.isCupMode) return;
    final next = !state.coachMode;
    state = state.copyWith(coachMode: next);
    if (next && state.analysis == null) {
      _runAnalysis();
    }
  }

  /// (Re-)run the AI Coach analysis, demanding a strong engine (server or
  /// offline Pikafish). On failure the state exposes [ReplayUiState.analysisUnavailable]
  /// so the UI can offer "retry" / "quick offline analysis".
  void runAnalysis() {
    if (state.record.isCupMode) return;
    _runAnalysis();
  }

  /// User explicitly accepted the shallow offline analyzer after the strong
  /// engines were unavailable.
  void runQuickAnalysis() {
    if (state.record.isCupMode) return;
    _runAnalysis(allowWeakFallback: true, useCache: false);
  }

  void _startAutoPlay() {
    _autoPlayTimer?.cancel();
    final intervalMs = (1000 / state.speed).round().clamp(150, 5000);
    state = state.copyWith(isPlaying: true);
    _autoPlayTimer = Timer.periodic(Duration(milliseconds: intervalMs), (_) {
      if (state.atEnd) {
        _stopAutoPlay();
      } else {
        stepForward();
      }
    });
  }

  void _stopAutoPlay() {
    _autoPlayTimer?.cancel();
    _autoPlayTimer = null;
    if (state.isPlaying) {
      state = state.copyWith(isPlaying: false);
    }
  }

  void _runAnalysis({bool allowWeakFallback = false, bool useCache = true}) {
    final runId = ++_analysisRunId;
    state = state.copyWith(
      analysisProgress: 0.02,
      analysis: null,
      clearAnalysisUnavailable: true,
    );
    unawaited(() async {
      try {
        // A finished review is cached per record — replaying it is free.
        if (useCache) {
          final cached = await _analysisCache?.get(state.record);
          if (!mounted || runId != _analysisRunId) return;
          if (cached != null) {
            state = state.copyWith(analysis: cached, analysisProgress: 1.0);
            return;
          }
        }

        final analysis = await _analysisEngine.analyze(
          startingFen: state.record.startingFen,
          moveUcis: state.record.moves,
          allowWeakFallback: allowWeakFallback,
          onProgress: (fraction) {
            if (!mounted || runId != _analysisRunId) return;
            state = state.copyWith(
              analysisProgress: fraction.clamp(0.02, 1.0),
            );
          },
        );
        if (!mounted || runId != _analysisRunId) return;
        state = state.copyWith(analysis: analysis, analysisProgress: 1.0);
        // Strong results are worth keeping; the cache ignores weak ones.
        unawaited(
          Future<void>.value(_analysisCache?.put(state.record, analysis)),
        );
      } on AnalysisUnavailableException catch (error) {
        if (!mounted || runId != _analysisRunId) return;
        state = state.copyWith(
          analysisProgress: 0,
          analysisUnavailable: error,
        );
      } catch (error) {
        if (!mounted || runId != _analysisRunId) return;
        state = state.copyWith(
          analysisProgress: 0,
          analysisUnavailable: AnalysisUnavailableException(error.toString()),
        );
      }
    }());
  }

}

final replayControllerProvider = StateNotifierProvider.autoDispose
    .family<ReplayController, ReplayUiState, GameRecord>((ref, record) {
      return ReplayController(
        record: record,
        analysisEngine: ref.watch(engineRouterProvider),
        analysisCache: ref.watch(analysisCacheRepositoryProvider),
      );
    });

/// FutureProvider that loads a [GameRecord] by id.
final replayRecordProvider = FutureProvider.autoDispose
    .family<GameRecord?, String>((ref, id) async {
      final repo = ref.watch(gameHistoryRepositoryProvider);
      return repo.getById(id);
    });
