import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/chess_engine/chess_engine.dart';
import '../../data/models/chess_puzzle.dart';
import '../../data/repositories/puzzle_repository.dart';

/// Feedback flash shown after the user attempts a move.
enum PuzzleFeedback { idle, correct, wrong, solved, failedShownSolution }

class PuzzleUiState {
  final ChessPuzzle puzzle;
  final XiangqiGame game;
  final Position? selected;
  final List<Position> validTargets;
  final Move? lastMove;
  final int solutionStep;
  final int wrongAttempts;
  final int hintsRemaining;
  final PuzzleFeedback feedback;
  final bool showingSolution;
  final Position? hintFrom;
  final Position? hintTo;
  final PuzzleProgress progress;

  const PuzzleUiState({
    required this.puzzle,
    required this.game,
    required this.selected,
    required this.validTargets,
    required this.lastMove,
    required this.solutionStep,
    required this.wrongAttempts,
    required this.hintsRemaining,
    required this.feedback,
    required this.showingSolution,
    required this.hintFrom,
    required this.hintTo,
    required this.progress,
  });

  bool get isSolved => feedback == PuzzleFeedback.solved;
  bool get isPlayerTurn => game.turn == puzzle.playerColor;

  PuzzleUiState copyWith({
    XiangqiGame? game,
    Position? selected,
    bool clearSelected = false,
    List<Position>? validTargets,
    Move? lastMove,
    int? solutionStep,
    int? wrongAttempts,
    int? hintsRemaining,
    PuzzleFeedback? feedback,
    bool? showingSolution,
    Position? hintFrom,
    Position? hintTo,
    bool clearHint = false,
    PuzzleProgress? progress,
  }) {
    return PuzzleUiState(
      puzzle: puzzle,
      game: game ?? this.game,
      selected: clearSelected ? null : (selected ?? this.selected),
      validTargets: validTargets ?? this.validTargets,
      lastMove: lastMove ?? this.lastMove,
      solutionStep: solutionStep ?? this.solutionStep,
      wrongAttempts: wrongAttempts ?? this.wrongAttempts,
      hintsRemaining: hintsRemaining ?? this.hintsRemaining,
      feedback: feedback ?? this.feedback,
      showingSolution: showingSolution ?? this.showingSolution,
      hintFrom: clearHint ? null : (hintFrom ?? this.hintFrom),
      hintTo: clearHint ? null : (hintTo ?? this.hintTo),
      progress: progress ?? this.progress,
    );
  }
}

class PuzzleController extends StateNotifier<PuzzleUiState> {
  final PuzzleRepository _repo;

  PuzzleController({
    required ChessPuzzle puzzle,
    required PuzzleRepository repo,
    PuzzleProgress? progress,
  })  : _repo = repo,
        super(
          PuzzleUiState(
            puzzle: puzzle,
            game: XiangqiGame.fromFen(puzzle.fen),
            selected: null,
            validTargets: const [],
            lastMove: null,
            solutionStep: 0,
            wrongAttempts: 0,
            hintsRemaining: 3,
            feedback: PuzzleFeedback.idle,
            showingSolution: false,
            hintFrom: null,
            hintTo: null,
            progress:
                progress ?? PuzzleProgress(puzzleId: puzzle.id),
          ),
        );

  /// Reset back to the puzzle's starting position.
  void restart() {
    state = PuzzleUiState(
      puzzle: state.puzzle,
      game: XiangqiGame.fromFen(state.puzzle.fen),
      selected: null,
      validTargets: const [],
      lastMove: null,
      solutionStep: 0,
      wrongAttempts: 0,
      hintsRemaining: state.hintsRemaining,
      feedback: PuzzleFeedback.idle,
      showingSolution: false,
      hintFrom: null,
      hintTo: null,
      progress: state.progress,
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
        clearHint: true,
      );

      if (allSolved) {
        final updated = await _repo.recordAttempt(
          state.puzzle.id,
          solved: true,
        );
        state = state.copyWith(progress: updated);
      }
    } else {
      // Wrong move — provide feedback. After 3 wrong attempts reveal the
      // solution and lock further interaction.
      final wrong = state.wrongAttempts + 1;
      state = state.copyWith(
        clearSelected: true,
        validTargets: const [],
        wrongAttempts: wrong,
        feedback: wrong >= 3
            ? PuzzleFeedback.failedShownSolution
            : PuzzleFeedback.wrong,
        hintFrom: wrong >= 3 ? expFrom : state.hintFrom,
        hintTo: wrong >= 3 ? expTo : state.hintTo,
      );
      await _repo.recordAttempt(state.puzzle.id);
    }
  }

  /// Reveal the next correct move (consumes one hint charge).
  Future<void> requestHint() async {
    if (state.hintsRemaining <= 0) return;
    if (state.feedback == PuzzleFeedback.solved) return;
    final expected = state.puzzle.solution[state.solutionStep];
    final coords = Move.parseUciCoords(expected);
    if (coords == null) return;
    final (from, to) = coords;
    state = state.copyWith(
      hintFrom: from,
      hintTo: to,
      hintsRemaining: state.hintsRemaining - 1,
    );
    await _repo.recordAttempt(state.puzzle.id, hintUsed: true);
  }
}

final puzzleControllerProvider = StateNotifierProvider.autoDispose
    .family<PuzzleController, PuzzleUiState, String>((ref, puzzleId) {
  final repo = ref.watch(puzzleRepositoryProvider);
  final puzzle = repo.puzzleById(puzzleId);
  if (puzzle == null) {
    throw ArgumentError('Unknown puzzle id: $puzzleId');
  }
  return PuzzleController(puzzle: puzzle, repo: repo);
});
