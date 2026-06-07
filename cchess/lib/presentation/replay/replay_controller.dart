import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/chess_engine/chess_engine.dart';
import '../../data/models/game_record.dart';
import '../../data/repositories/game_history_repository.dart';

class ReplayUiState {
  /// The saved game we're replaying.
  final GameRecord record;

  /// Number of moves applied so far (0 = starting position).
  final int currentPly;

  /// Current board after applying [currentPly] moves.
  final Board board;

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

  const ReplayUiState({
    required this.record,
    required this.currentPly,
    required this.board,
    required this.lastMove,
    required this.isPlaying,
    required this.speed,
    required this.coachMode,
    required this.analysis,
    required this.analysisProgress,
  });

  int get totalPly => record.moves.length;
  bool get atStart => currentPly == 0;
  bool get atEnd => currentPly >= totalPly;

  ReplayUiState copyWith({
    int? currentPly,
    Board? board,
    Move? lastMove,
    bool clearLastMove = false,
    bool? isPlaying,
    double? speed,
    bool? coachMode,
    GameAnalysis? analysis,
    double? analysisProgress,
  }) {
    return ReplayUiState(
      record: record,
      currentPly: currentPly ?? this.currentPly,
      board: board ?? this.board,
      lastMove: clearLastMove ? null : (lastMove ?? this.lastMove),
      isPlaying: isPlaying ?? this.isPlaying,
      speed: speed ?? this.speed,
      coachMode: coachMode ?? this.coachMode,
      analysis: analysis ?? this.analysis,
      analysisProgress: analysisProgress ?? this.analysisProgress,
    );
  }
}

/// Controller that walks through a saved [GameRecord] move-by-move.
class ReplayController extends StateNotifier<ReplayUiState> {
  Timer? _autoPlayTimer;
  int _analysisRunId = 0;
  final MoveEngine _analysisEngine;

  ReplayController({required GameRecord record, MoveEngine? analysisEngine})
    : _analysisEngine = analysisEngine ?? LocalMinimaxEngine(),
      super(
        ReplayUiState(
          record: record,
          currentPly: 0,
          board: Board.fromFen(record.startingFen),
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

  /// Jump to [ply] (0 = before first move, totalPly = after last move).
  void seek(int ply) {
    final target = ply.clamp(0, state.totalPly);
    final board = _rebuildBoardAt(target);
    final lastMove = target == 0 ? null : _moveAt(target - 1, board: null);
    state = state.copyWith(
      currentPly: target,
      board: board,
      lastMove: lastMove,
      clearLastMove: target == 0,
      isPlaying: target >= state.totalPly ? false : state.isPlaying,
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
  void goToEnd() => seek(state.totalPly);

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
    final next = !state.coachMode;
    state = state.copyWith(coachMode: next);
    if (next && state.analysis == null) {
      _runAnalysis();
    }
  }

  /// Re-run AI Coach analysis from scratch.
  void runAnalysis() => _runAnalysis();

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

  void _runAnalysis() {
    final runId = ++_analysisRunId;
    state = state.copyWith(analysisProgress: 0.05, analysis: null);
    unawaited(() async {
      try {
        final analysis = await _analysisEngine.analyze(
          startingFen: state.record.startingFen,
          moveUcis: state.record.moves,
        );
        if (!mounted || runId != _analysisRunId) return;
        state = state.copyWith(analysis: analysis, analysisProgress: 1.0);
      } catch (_) {
        if (!mounted || runId != _analysisRunId) return;
        state = state.copyWith(analysisProgress: 1.0);
      }
    }());
  }

  /// Rebuild a fresh board representing the position after [ply] moves.
  Board _rebuildBoardAt(int ply) {
    final game = XiangqiGame.fromFen(state.record.startingFen);
    for (int i = 0; i < ply; i++) {
      final coords = Move.parseUciCoords(state.record.moves[i]);
      if (coords == null) break;
      if (!game.isValidMove(coords.$1, coords.$2)) break;
      game.makeMove(coords.$1, coords.$2);
    }
    // Return a copy so callers can't mutate our snapshot.
    return game.board.copy();
  }

  /// Reconstruct the Move object at index [moveIndex] (0-based). We need
  /// the board *before* that move to know which piece moved + what was on
  /// the destination — so this method replays up to but not including the
  /// move first.
  Move? _moveAt(int moveIndex, {Board? board}) {
    if (moveIndex < 0 || moveIndex >= state.totalPly) return null;
    final coords = Move.parseUciCoords(state.record.moves[moveIndex]);
    if (coords == null) return null;
    final priorBoard = board ?? _rebuildBoardAt(moveIndex);
    final piece = priorBoard.at(coords.$1);
    if (piece == null) return null;
    return Move(
      from: coords.$1,
      to: coords.$2,
      moved: piece,
      captured: priorBoard.at(coords.$2),
    );
  }
}

final replayControllerProvider = StateNotifierProvider.autoDispose
    .family<ReplayController, ReplayUiState, GameRecord>((ref, record) {
      return ReplayController(
        record: record,
        analysisEngine: ref.watch(engineRouterProvider),
      );
    });

/// FutureProvider that loads a [GameRecord] by id.
final replayRecordProvider = FutureProvider.autoDispose
    .family<GameRecord?, String>((ref, id) async {
      final repo = ref.watch(gameHistoryRepositoryProvider);
      return repo.getById(id);
    });
