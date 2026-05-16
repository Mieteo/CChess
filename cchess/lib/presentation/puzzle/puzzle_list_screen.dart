import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants/app_constants.dart';
import '../../data/models/chess_puzzle.dart';
import '../../data/repositories/puzzle_repository.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_text_styles.dart';
import '../../widgets/common/common.dart';

class PuzzleListScreen extends ConsumerStatefulWidget {
  const PuzzleListScreen({super.key});

  @override
  ConsumerState<PuzzleListScreen> createState() => _PuzzleListScreenState();
}

class _PuzzleListScreenState extends ConsumerState<PuzzleListScreen> {
  late Future<Map<String, PuzzleProgress>> _progressFuture;

  @override
  void initState() {
    super.initState();
    _progressFuture =
        ref.read(puzzleRepositoryProvider).getAllProgress();
  }

  @override
  Widget build(BuildContext context) {
    final repo = ref.watch(puzzleRepositoryProvider);
    final puzzles = repo.allPuzzles();

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.woodDark,
        title: const Text('Bài Tập Tàn Cục'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go(AppConstants.routeLearning),
        ),
      ),
      body: SafeArea(
        child: FutureBuilder<Map<String, PuzzleProgress>>(
          future: _progressFuture,
          builder: (context, snap) {
            final progress = snap.data ?? const <String, PuzzleProgress>{};
            final solved =
                progress.values.where((p) => p.solved).length;
            return ListView(
              padding: const EdgeInsets.all(AppSpacing.base),
              children: [
                _ProgressSummary(
                  solved: solved,
                  total: puzzles.length,
                ),
                AppSpacing.vGapLg,
                const SectionHeader(title: 'Tất cả bài tập'),
                AppSpacing.vGapMd,
                for (final p in puzzles) ...[
                  _PuzzleListItem(
                    puzzle: p,
                    progress: progress[p.id] ??
                        PuzzleProgress(puzzleId: p.id),
                  ),
                  AppSpacing.vGapSm,
                ],
              ],
            );
          },
        ),
      ),
    );
  }
}

class _ProgressSummary extends StatelessWidget {
  final int solved;
  final int total;

  const _ProgressSummary({required this.solved, required this.total});

  @override
  Widget build(BuildContext context) {
    final ratio = total == 0 ? 0.0 : solved / total;
    return CChessCard(
      gradient: const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [AppColors.charcoalDark, AppColors.woodDark],
      ),
      borderColor: AppColors.accentGold.withValues(alpha: 0.4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text(
                'Tiến độ tổng',
                style: AppTextStyles.headingMd,
              ),
              const Spacer(),
              Text(
                '$solved / $total',
                style: AppTextStyles.titleLg.copyWith(
                  color: AppColors.accentGold,
                ),
              ),
            ],
          ),
          AppSpacing.vGapSm,
          CChessProgressBar(value: ratio),
          AppSpacing.vGapXs,
          Text(
            ratio == 1
                ? 'Hoàn thành tất cả bài tập!'
                : 'Tiếp tục giải để mở khóa bài mới.',
            style: AppTextStyles.captionSm.copyWith(
              color: AppColors.parchmentTan,
            ),
          ),
        ],
      ),
    );
  }
}

class _PuzzleListItem extends StatelessWidget {
  final ChessPuzzle puzzle;
  final PuzzleProgress progress;

  const _PuzzleListItem({
    required this.puzzle,
    required this.progress,
  });

  @override
  Widget build(BuildContext context) {
    return CChessCard(
      onTap: () => context.go('/puzzle/${puzzle.id}'),
      borderColor: progress.solved
          ? AppColors.tealSuccess.withValues(alpha: 0.5)
          : AppColors.outlineVariant,
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: progress.solved
                  ? AppColors.tealSuccess.withValues(alpha: 0.18)
                  : AppColors.surfaceContainerHigh,
              shape: BoxShape.circle,
              border: Border.all(
                color: progress.solved
                    ? AppColors.tealSuccess
                    : AppColors.outlineVariant,
              ),
            ),
            alignment: Alignment.center,
            child: Icon(
              progress.solved ? Icons.check : Icons.extension_outlined,
              color: progress.solved ? AppColors.tealSuccess : AppColors.primary,
              size: 22,
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
                        i <= puzzle.difficulty ? Icons.star : Icons.star_outline,
                        size: 12,
                        color: AppColors.accentGold,
                      ),
                    AppSpacing.hGapSm,
                    Text(
                      '${puzzle.solverMoveCount} nước',
                      style: AppTextStyles.captionSm.copyWith(
                        color: AppColors.onSurfaceVariant,
                      ),
                    ),
                    if (progress.attempts > 0) ...[
                      AppSpacing.hGapSm,
                      Text(
                        '• ${progress.attempts} lần thử',
                        style: AppTextStyles.captionSm.copyWith(
                          color: AppColors.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
          const Icon(Icons.chevron_right, color: AppColors.parchmentTan),
        ],
      ),
    );
  }
}
