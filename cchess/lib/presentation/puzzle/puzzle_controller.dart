import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/chess_engine/chess_engine.dart';
import '../../data/models/chess_puzzle.dart';
import '../../data/repositories/daily_quest_repository.dart';
import '../../data/repositories/puzzle_repository.dart';

/// Feedback flash shown after the user attempts a move.
enum PuzzleFeedback { idle, correct, wrong, solved, failedShownSolution, hint }

/// Max number of progressive hint levels per solution step.
const int kMaxHintLevel = 3;

class PuzzleUiState {
  final ChessPuzzle puzzle;
  final XiangqiGame game;
  final Position? selected;
  final List<Position> validTargets;
  final Move? lastMove;
  final int solutionStep;
  final int wrongAttempts;

  /// Hint level revealed for the *current* solution step (0..[kMaxHintLevel]).
  /// Resets to 0 each time the player advances a step or restarts.
  final int hintLevel;

  /// Cumulative hint charges spent across the whole puzzle — drives the score
  /// penalty and the `hintsUsed` reported to the backend.
  final int hintsUsedTotal;

  /// Human-readable description of the current hint (null when none active).
  final String? hintText;

  final PuzzleFeedback feedback;
  final bool showingSolution;
  final Position? hintFrom;
  final Position? hintTo;
  final PuzzleProgress progress;

  /// Score (0..100) earned on the attempt that just solved the puzzle; null
  /// until solved this session.
  final int? lastScore;

  const PuzzleUiState({
    required this.puzzle,
    required this.game,
    required this.selected,
    required this.validTargets,
    required this.lastMove,
    required this.solutionStep,
    required this.wrongAttempts,
    required this.hintLevel,
    required this.hintsUsedTotal,
    required this.hintText,
    required this.feedback,
    required this.showingSolution,
    required this.hintFrom,
    required this.hintTo,
    required this.progress,
    required this.lastScore,
  });

  bool get isSolved => feedback == PuzzleFeedback.solved;
  bool get isPlayerTurn => game.turn == puzzle.playerColor;

  /// Remaining hint levels available for the current step.
  int get hintsRemaining => kMaxHintLevel - hintLevel;

  PuzzleUiState copyWith({
    XiangqiGame? game,
    Position? selected,
    bool clearSelected = false,
    List<Position>? validTargets,
    Move? lastMove,
    int? solutionStep,
    int? wrongAttempts,
    int? hintLevel,
    int? hintsUsedTotal,
    String? hintText,
    PuzzleFeedback? feedback,
    bool? showingSolution,
    Position? hintFrom,
    Position? hintTo,
    bool clearHint = false,
    PuzzleProgress? progress,
    int? lastScore,
  }) {
    return PuzzleUiState(
      puzzle: puzzle,
      game: game ?? this.game,
      selected: clearSelected ? null : (selected ?? this.selected),
      validTargets: validTargets ?? this.validTargets,
      lastMove: lastMove ?? this.lastMove,
      solutionStep: solutionStep ?? this.solutionStep,
      wrongAttempts: wrongAttempts ?? this.wrongAttempts,
      hintLevel: hintLevel ?? this.hintLevel,
      hintsUsedTotal: hintsUsedTotal ?? this.hintsUsedTotal,
      hintText: clearHint ? null : (hintText ?? this.hintText),
      feedback: feedback ?? this.feedback,
      showingSolution: showingSolution ?? this.showingSolution,
      hintFrom: clearHint ? null : (hintFrom ?? this.hintFrom),
      hintTo: clearHint ? null : (hintTo ?? this.hintTo),
      progress: progress ?? this.progress,
      lastScore: lastScore ?? this.lastScore,
    );
  }
}

class PuzzleController extends StateNotifier<PuzzleUiState> {
  final PuzzleRepository _repo;
  final DailyQuestController? _questController;

  PuzzleController({
    required ChessPuzzle puzzle,
    required PuzzleRepository repo,
    PuzzleProgress? progress,
    DailyQuestController? questController,
  })  : _repo = repo,
        _questController = questController,
        super(
          PuzzleUiState(
            puzzle: puzzle,
            game: XiangqiGame.fromFen(puzzle.fen),
            selected: null,
            validTargets: const [],
            lastMove: null,
            solutionStep: 0,
            wrongAttempts: 0,
            hintLevel: 0,
            hintsUsedTotal: 0,
            hintText: null,
            feedback: PuzzleFeedback.idle,
            showingSolution: false,
            hintFrom: null,
            hintTo: null,
            progress: progress ?? PuzzleProgress(puzzleId: puzzle.id),
            lastScore: null,
          ),
        ) {
    if (progress == null) _loadProgress();
  }

  /// Pull the persisted progress (best score / solved flag) so a deep-linked
  /// puzzle shows the user's history without blocking construction.
  Future<void> _loadProgress() async {
    final loaded = await _repo.getProgress(state.puzzle.id);
    if (!mounted) return;
    // Don't clobber a fast solve that landed while this was loading.
    if (state.feedback == PuzzleFeedback.solved) return;
    state = state.copyWith(progress: loaded);
  }

  /// Reset back to the puzzle's starting position (keeps persisted progress).
  void restart() {
    state = PuzzleUiState(
      puzzle: state.puzzle,
      game: XiangqiGame.fromFen(state.puzzle.fen),
      selected: null,
      validTargets: const [],
      lastMove: null,
      solutionStep: 0,
      wrongAttempts: 0,
      hintLevel: 0,
      hintsUsedTotal: 0,
      hintText: null,
      feedback: PuzzleFeedback.idle,
      showingSolution: false,
      hintFrom: null,
      hintTo: null,
      progress: state.progress,
      lastScore: null,
    );
  }

  void onTap(int row, int col) {
    if (state.feedback == PuzzleFeedback.solved) return;
    if (state.feedback == PuzzleFeedback.failedShownSolution) return;
    if (!state.isPlayerTurn) return;

    final pos = Position(row, col);
    final piece = state.game.board.at(pos);

    // Selecting an own piece.
    if (state.selected == null) {
      if (piece != null && piece.color == state.game.turn) {
        _select(pos);
      }
      return;
    }

    if (state.selected == pos) {
      _clearSelection();
      return;
    }

    if (piece != null && piece.color == state.game.turn) {
      _select(pos);
      return;
    }

    if (state.validTargets.contains(pos)) {
      _attemptMove(state.selected!, pos);
      return;
    }

    _clearSelection();
  }

  void _select(Position pos) {
    state = state.copyWith(
      selected: pos,
      validTargets: state.game.getValidMoves(pos),
      feedback: PuzzleFeedback.idle,
      clearHint: true,
    );
  }

  void _clearSelection() {
    state = state.copyWith(
      clearSelected: true,
      validTargets: const [],
    );
  }

  Future<void> _attemptMove(Position from, Position to) async {
    final expected = state.puzzle.solution[state.solutionStep];
    final expectedCoords = Move.parseUciCoords(expected);
    if (expectedCoords == null) return;
    final (expFrom, expTo) = expectedCoords;

    if (from == expFrom && to == expTo) {
      // Correct move — play it and possibly advance opponent's reply.
      final move = state.game.makeMove(from, to);
      var nextStep = state.solutionStep + 1;
      var feedback = PuzzleFeedback.correct;
      Move? lastMove = move;

      // Auto-play opponent's reply if there is one.
      if (nextStep < state.puzzle.solution.length) {
        final opp = Move.parseUciCoords(state.puzzle.solution[nextStep]);
        if (opp != null) {
          final (oFrom, oTo) = opp;
          if (state.game.isValidMove(oFrom, oTo)) {
            lastMove = state.game.makeMove(oFrom, oTo);
            nextStep += 1;
          }
        }
      }

      final allSolved = nextStep >= state.puzzle.solution.length;
      if (allSolved) feedback = PuzzleFeedback.solved;

      state = state.copyWith(
        game: state.game,
        clearSelected: true,
        validTargets: const [],
        lastMove: lastMove,
        solutionStep: nextStep,
        feedback: feedback,
        // Advancing a step resets the per-step hint level + highlight.
        hintLevel: 0,
        clearHint: true,
      );

      if (allSolved) {
        await _onSolved();
      }
    } else {
      // Wrong move — provide feedback. After 3 wrong attempts reveal the
      // solution and lock further interaction.
      final wrong = state.wrongAttempts + 1;
      final failed = wrong >= 3;
      state = state.copyWith(
        clearSelected: true,
        validTargets: const [],
        wrongAttempts: wrong,
        feedback:
            failed ? PuzzleFeedback.failedShownSolution : PuzzleFeedback.wrong,
        hintFrom: failed ? expFrom : state.hintFrom,
        hintTo: failed ? expTo : state.hintTo,
        hintText: failed ? 'Đáp án đã được tô sáng.' : state.hintText,
      );
      if (failed) {
        await _onFailed();
      } else {
        // Local-only: count the attempt without spamming the backend.
        await _repo.recordAttempt(state.puzzle.id, mirror: false);
      }
    }
  }

  /// Persist + sync a solved puzzle, awarding a score that decays with wrong
  /// moves and hints used.
  Future<void> _onSolved() async {
    final score = _computeScore();
    final wasSolvedBefore = state.progress.solved;

    // Persist locally first (attempts++, hints folded in, bestScore) without a
    // background mirror — the awaited sync below is the single source of truth.
    await _repo.recordAttempt(
      state.puzzle.id,
      solved: true,
      hintsUsed: state.hintsUsedTotal,
      score: score,
      mirror: false,
    );
    final merged = await _repo.syncProgress(
      state.puzzle.id,
      solved: true,
      hintsUsed: state.hintsUsedTotal,
      score: score,
    );

    if (mounted) {
      state = state.copyWith(progress: merged, lastScore: score);
    }
    if (!wasSolvedBefore) {
      await _questController?.recordPuzzleSolved();
    }
  }

  /// Record a failed attempt (3 wrong moves) — counts the attempt + any hints
  /// and reports the (unsolved) attempt so the server's solve-rate stays honest.
  Future<void> _onFailed() async {
    await _repo.recordAttempt(
      state.puzzle.id,
      hintsUsed: state.hintsUsedTotal,
      mirror: false,
    );
    final merged = await _repo.syncProgress(
      state.puzzle.id,
      solved: false,
      hintsUsed: state.hintsUsedTotal,
      score: 0,
    );
    if (mounted) state = state.copyWith(progress: merged);
  }

  /// 100 base, minus 15 per wrong move and 12 per hint charge; floored at 20
  /// because reaching the solution is always worth something.
  int _computeScore() {
    final raw = 100 - state.wrongAttempts * 15 - state.hintsUsedTotal * 12;
    return raw.clamp(20, 100);
  }

  /// Reveal the next level of hint for the current step (text → source square →
  /// full move). Each press consumes one hint charge.
  Future<void> requestHint() async {
    if (state.feedback == PuzzleFeedback.solved) return;
    if (state.feedback == PuzzleFeedback.failedShownSolution) return;
    if (state.hintLevel >= kMaxHintLevel) return;

    final expected = state.puzzle.solution[state.solutionStep];
    final coords = Move.parseUciCoords(expected);
    if (coords == null) return;
    final (from, to) = coords;
    final pieceName = state.game.board.at(from)?.type.nameVi;
    final nextLevel = state.hintLevel + 1;

    Position? hintFrom;
    Position? hintTo;
    String text;
    switch (nextLevel) {
      case 1:
        text = pieceName != null
            ? 'Gợi ý 1/3: Hãy tính nước đi của quân $pieceName.'
            : 'Gợi ý 1/3: Tìm nước chiếu hoặc bắt quân mạnh nhất.';
      case 2:
        hintFrom = from;
        text = 'Gợi ý 2/3: Di chuyển quân ${pieceName ?? ''} đang được tô sáng.'
            .trim();
      default: // 3
        hintFrom = from;
        hintTo = to;
        text = 'Gợi ý 3/3: Đi theo nước được tô sáng.';
    }

    state = state.copyWith(
      hintLevel: nextLevel,
      hintsUsedTotal: state.hintsUsedTotal + 1,
      hintText: text,
      hintFrom: hintFrom,
      hintTo: hintTo,
      feedback: PuzzleFeedback.hint,
    );
  }
}

/// Resolves a puzzle by id through the repository (remote → cache → seed).
final puzzleByIdProvider =
    FutureProvider.autoDispose.family<ChessPuzzle?, String>((ref, id) {
  return ref.watch(puzzleRepositoryProvider).fetchPuzzleById(id);
});

/// Controller for an already-resolved puzzle. Keyed by the puzzle itself so the
/// screen can hand over the value it fetched via [puzzleByIdProvider].
final puzzleControllerProvider = StateNotifierProvider.autoDispose
    .family<PuzzleController, PuzzleUiState, ChessPuzzle>((ref, puzzle) {
  final repo = ref.watch(puzzleRepositoryProvider);
  return PuzzleController(
    puzzle: puzzle,
    repo: repo,
    questController: ref.read(dailyQuestControllerProvider.notifier),
  );
});
