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
  String? _selectedTag;
  int? _selectedDifficulty;

  @override
  void initState() {
    super.initState();
    _progressFuture = ref.read(puzzleRepositoryProvider).getAllProgress();
  }

  @override
  Widget build(BuildContext context) {
    final repo = ref.watch(puzzleRepositoryProvider);
    final allPuzzles = repo.allPuzzles();
    final puzzles = repo.filteredPuzzles(
      tag: _selectedTag,
      difficulty: _selectedDifficulty,
    );
    final tags = repo.availableTags();
    final dailyPuzzle = repo.dailyPuzzle();

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
            final solved = progress.values.where((p) => p.solved).length;
            return ListView(
              padding: const EdgeInsets.all(AppSpacing.base),
              children: [
                _ProgressSummary(
                  solved: solved,
                  total: allPuzzles.length,
                  dailyPuzzleTitle: dailyPuzzle?.titleVi,
                  onDailyTap: dailyPuzzle == null
                      ? null
                      : () => context.go('/puzzle/${dailyPuzzle.id}'),
                ),
                AppSpacing.vGapLg,
                _PuzzleFilters(
                  tags: tags,
                  selectedTag: _selectedTag,
                  selectedDifficulty: _selectedDifficulty,
                  onTagChanged: (tag) {
                    setState(() => _selectedTag = tag);
                  },
                  onDifficultyChanged: (difficulty) {
                    setState(() => _selectedDifficulty = difficulty);
                  },
                ),
                AppSpacing.vGapLg,
                SectionHeader(title: 'Kho tàn cục (${puzzles.length})'),
                AppSpacing.vGapMd,
                if (puzzles.isEmpty)
                  const _EmptyPuzzleState()
                else
                  for (final p in puzzles) ...[
                    _PuzzleListItem(
                      puzzle: p,
                      progress:
                          progress[p.id] ?? PuzzleProgress(puzzleId: p.id),
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
  final String? dailyPuzzleTitle;
  final VoidCallback? onDailyTap;

  const _ProgressSummary({
    required this.solved,
    required this.total,
    required this.dailyPuzzleTitle,
    required this.onDailyTap,
  });

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
              Text('Tiến độ tổng', style: AppTextStyles.headingMd),
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
                : 'Kho hiện có $total bài tàn cục offline.',
            style: AppTextStyles.captionSm.copyWith(
              color: AppColors.parchmentTan,
            ),
          ),
          if (dailyPuzzleTitle != null) ...[
            AppSpacing.vGapMd,
            CChessButton(
              label: 'Thử thách: $dailyPuzzleTitle',
              icon: Icons.local_fire_department,
              variant: CChessButtonVariant.danger,
              fullWidth: true,
              onPressed: onDailyTap,
            ),
          ],
        ],
      ),
    );
  }
}

class _PuzzleFilters extends StatelessWidget {
  final List<String> tags;
  final String? selectedTag;
  final int? selectedDifficulty;
  final ValueChanged<String?> onTagChanged;
  final ValueChanged<int?> onDifficultyChanged;

  const _PuzzleFilters({
    required this.tags,
    required this.selectedTag,
    required this.selectedDifficulty,
    required this.onTagChanged,
    required this.onDifficultyChanged,
  });

  @override
  Widget build(BuildContext context) {
    return CChessCard(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.tune, size: 18, color: AppColors.accentGold),
              AppSpacing.hGapSm,
              Text('Bộ lọc luyện tập', style: AppTextStyles.headingMd),
            ],
          ),
          AppSpacing.vGapMd,
          Text(
            'Chủ đề',
            style: AppTextStyles.captionSm.copyWith(
              color: AppColors.parchmentTan,
              fontWeight: FontWeight.w700,
            ),
          ),
          AppSpacing.vGapXs,
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _FilterChip(
                  label: 'Tất cả',
                  selected: selectedTag == null,
                  onTap: () => onTagChanged(null),
                ),
                AppSpacing.hGapXs,
                for (final tag in tags) ...[
                  _FilterChip(
                    label: tag,
                    selected: selectedTag == tag,
                    onTap: () => onTagChanged(tag),
                  ),
                  AppSpacing.hGapXs,
                ],
              ],
            ),
          ),
          AppSpacing.vGapMd,
          Text(
            'Độ khó',
            style: AppTextStyles.captionSm.copyWith(
              color: AppColors.parchmentTan,
              fontWeight: FontWeight.w700,
            ),
          ),
          AppSpacing.vGapXs,
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _FilterChip(
                  label: 'Tất cả',
                  selected: selectedDifficulty == null,
                  onTap: () => onDifficultyChanged(null),
                ),
                AppSpacing.hGapXs,
                for (int difficulty = 1; difficulty <= 5; difficulty++) ...[
                  _FilterChip(
                    label: '$difficulty★',
                    selected: selectedDifficulty == difficulty,
                    onTap: () => onDifficultyChanged(difficulty),
                  ),
                  AppSpacing.hGapXs,
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = selected ? AppColors.accentGold : AppColors.outlineVariant;
    return Material(
      color: Colors.transparent,
      borderRadius: AppRadius.chip,
      child: InkWell(
        borderRadius: AppRadius.chip,
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 32),
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.sm,
            vertical: 6,
          ),
          decoration: BoxDecoration(
            color: selected
                ? AppColors.accentGold.withValues(alpha: 0.16)
                : AppColors.surfaceContainerHighest,
            borderRadius: AppRadius.chip,
            border: Border.all(color: color),
          ),
          child: Text(
            label,
            style: AppTextStyles.captionSm.copyWith(
              color: selected ? AppColors.accentGold : AppColors.onSurface,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
            ),
          ),
        ),
      ),
    );
  }
}

class _PuzzleListItem extends StatelessWidget {
  final ChessPuzzle puzzle;
  final PuzzleProgress progress;

  const _PuzzleListItem({required this.puzzle, required this.progress});

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
              color: progress.solved
                  ? AppColors.tealSuccess
                  : AppColors.primary,
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
                Text(
                  puzzle.descriptionVi,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.captionSm.copyWith(
                    color: AppColors.onSurfaceVariant,
                    height: 1.35,
                  ),
                ),
                AppSpacing.vGapSm,
                Wrap(
                  spacing: AppSpacing.xs,
                  runSpacing: AppSpacing.xs,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    _DifficultyStars(value: puzzle.difficulty),
                    _TinyMetaChip(label: '${puzzle.solverMoveCount} nước'),
                    if (progress.attempts > 0)
                      _TinyMetaChip(label: '${progress.attempts} lần thử'),
                    for (final tag in puzzle.tags.take(3))
                      _TinyMetaChip(label: tag),
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

class _DifficultyStars extends StatelessWidget {
  final int value;

  const _DifficultyStars({required this.value});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (int i = 1; i <= 5; i++)
          Icon(
            i <= value ? Icons.star : Icons.star_outline,
            size: 12,
            color: AppColors.accentGold,
          ),
      ],
    );
  }
}

class _TinyMetaChip extends StatelessWidget {
  final String label;

  const _TinyMetaChip({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: AppColors.outlineVariant),
      ),
      child: Text(label, style: AppTextStyles.captionSm.copyWith(fontSize: 10)),
    );
  }
}

class _EmptyPuzzleState extends StatelessWidget {
  const _EmptyPuzzleState();

  @override
  Widget build(BuildContext context) {
    return CChessCard(
      child: Column(
        children: [
          const Icon(
            Icons.search_off,
            color: AppColors.onSurfaceVariant,
            size: 32,
          ),
          AppSpacing.vGapSm,
          Text(
            'Không có bài phù hợp bộ lọc',
            style: AppTextStyles.headingMd,
            textAlign: TextAlign.center,
          ),
          AppSpacing.vGapXs,
          Text(
            'Đổi chủ đề hoặc độ khó để tiếp tục luyện.',
            style: AppTextStyles.captionSm.copyWith(
              color: AppColors.onSurfaceVariant,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
