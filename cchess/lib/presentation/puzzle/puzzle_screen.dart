import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/chess_engine/chess_engine.dart';
import '../../data/repositories/puzzle_repository.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_text_styles.dart';
import '../../widgets/chess/chess_board.dart';
import '../../widgets/common/common.dart';
import 'puzzle_controller.dart';

class PuzzleScreen extends ConsumerWidget {
  final String puzzleId;

  const PuzzleScreen({super.key, required this.puzzleId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.watch(puzzleRepositoryProvider);
    final puzzle = repo.puzzleById(puzzleId);
    if (puzzle == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Bài tập không tồn tại')),
        body: Center(
          child: Text(
            'Không tìm thấy bài tập "$puzzleId"',
            style: AppTextStyles.bodyMd,
          ),
        ),
      );
    }

    final state = ref.watch(puzzleControllerProvider(puzzleId));
    final controller = ref.read(puzzleControllerProvider(puzzleId).notifier);

    final checkedKing = state.game.isInCheck(state.game.turn)
        ? state.game.board.generalPosition(state.game.turn)
        : null;

    // Synthesize a hint marker as a "last move" highlight if a hint is on.
    final hintMove = (state.hintFrom != null && state.hintTo != null)
        ? Move(
            from: state.hintFrom!,
            to: state.hintTo!,
            moved: state.game.board.at(state.hintFrom!) ?? Piece.redChariot,
          )
        : null;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.woodDark,
        title: Text(puzzle.titleVi),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/puzzle'),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Làm lại',
            onPressed: controller.restart,
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.sm),
          child: Column(
            children: [
              _PuzzleInfoPanel(state: state),
              AppSpacing.vGapSm,
              Expanded(
                child: AspectRatio(
                  aspectRatio: 9 / 10,
                  child: ChessBoard(
                    board: state.game.board,
                    selected: state.selected,
                    validTargets: state.validTargets,
                    lastMove: hintMove ?? state.lastMove,
                    checkedKing: checkedKing,
                    onTap: controller.onTap,
                  ),
                ),
              ),
              AppSpacing.vGapSm,
              _PuzzleFeedbackPanel(state: state),
              AppSpacing.vGapSm,
              _PuzzleActions(state: state, controller: controller),
            ],
          ),
        ),
      ),
    );
  }
}

class _PuzzleInfoPanel extends StatelessWidget {
  final PuzzleUiState state;
  const _PuzzleInfoPanel({required this.state});

  @override
  Widget build(BuildContext context) {
    final puzzle = state.puzzle;
    return CChessCard(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: AppColors.accentGold.withValues(alpha: 0.15),
              shape: BoxShape.circle,
              border: Border.all(color: AppColors.accentGold),
            ),
            alignment: Alignment.center,
            child: Text(
              '${puzzle.solverMoveCount}',
              style: AppTextStyles.headingMd.copyWith(
                color: AppColors.accentGold,
              ),
            ),
          ),
          AppSpacing.hGapMd,
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(puzzle.titleVi, style: AppTextStyles.headingMd),
                AppSpacing.vGapXs,
                Row(
                  children: [
                    for (int i = 1; i <= 5; i++)
                      Icon(
                        i <= puzzle.difficulty
                            ? Icons.star
                            : Icons.star_outline,
                        size: 14,
                        color: AppColors.accentGold,
                      ),
                    AppSpacing.hGapSm,
                    for (final tag in puzzle.tags) ...[
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 1,
                        ),
                        margin: const EdgeInsets.only(right: 4),
                        decoration: BoxDecoration(
                          color: AppColors.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: AppColors.outlineVariant),
                        ),
                        child: Text(
                          tag,
                          style: AppTextStyles.captionSm.copyWith(fontSize: 10),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '${state.solutionStep ~/ 2}/${puzzle.solverMoveCount}',
                style: AppTextStyles.monoTimer.copyWith(
                  fontSize: 16,
                  color: AppColors.accentGold,
                ),
              ),
              Text(
                'nước',
                style: AppTextStyles.captionSm.copyWith(
                  color: AppColors.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PuzzleFeedbackPanel extends StatelessWidget {
  final PuzzleUiState state;
  const _PuzzleFeedbackPanel({required this.state});

  @override
  Widget build(BuildContext context) {
    final (icon, color, message) = switch (state.feedback) {
      PuzzleFeedback.idle => (
          Icons.touch_app_outlined,
          AppColors.onSurfaceVariant,
          state.isPlayerTurn
              ? 'Lượt của bạn — chọn nước tốt nhất.'
              : 'Đợi đối thủ đi…',
        ),
      PuzzleFeedback.correct => (
          Icons.check_circle,
          AppColors.tealSuccess,
          'Đúng rồi! Tiếp tục…',
        ),
      PuzzleFeedback.wrong => (
          Icons.cancel,
          AppColors.error,
          'Sai rồi — thử lại. (${3 - state.wrongAttempts} lần thử còn lại)',
        ),
      PuzzleFeedback.solved => (
          Icons.emoji_events,
          AppColors.accentGold,
          'Hoàn thành! +50 EXP',
        ),
      PuzzleFeedback.failedShownSolution => (
          Icons.lightbulb_outline,
          AppColors.accentGold,
          'Đáp án đã được tô sáng. Hãy thử lại.',
        ),
    };

    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        border: Border.all(color: color.withValues(alpha: 0.45)),
        borderRadius: AppRadius.card,
      ),
      child: Row(
        children: [
          Icon(icon, color: color),
          AppSpacing.hGapSm,
          Expanded(
            child: Text(
              message,
              style: AppTextStyles.bodyMd.copyWith(color: color),
            ),
          ),
        ],
      ),
    );
  }
}

class _PuzzleActions extends StatelessWidget {
  final PuzzleUiState state;
  final PuzzleController controller;

  const _PuzzleActions({required this.state, required this.controller});

  @override
  Widget build(BuildContext context) {
    final solved = state.isSolved;
    return Row(
      children: [
        Expanded(
          child: CChessButton(
            label: 'Gợi ý (${state.hintsRemaining})',
            variant: CChessButtonVariant.outline,
            icon: Icons.lightbulb_outline,
            fullWidth: true,
            onPressed:
                state.hintsRemaining > 0 && !solved ? controller.requestHint : null,
          ),
        ),
        AppSpacing.hGapMd,
        Expanded(
          child: CChessButton(
            label: solved ? 'Bài tiếp →' : 'Làm lại',
            icon: solved ? Icons.skip_next : Icons.refresh,
            fullWidth: true,
            onPressed: solved
                ? () => _goToNext(context)
                : controller.restart,
          ),
        ),
      ],
    );
  }

  void _goToNext(BuildContext context) {
    final repo = PuzzleRepository();
    final all = repo.allPuzzles();
    final idx = all.indexWhere((p) => p.id == state.puzzle.id);
    if (idx == -1 || idx + 1 >= all.length) {
      context.go('/puzzle');
      return;
    }
    context.go('/puzzle/${all[idx + 1].id}');
  }
}
