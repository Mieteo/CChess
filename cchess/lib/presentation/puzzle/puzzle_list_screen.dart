import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants/app_constants.dart';
import '../../data/datasources/remote/remote_puzzle_source.dart';
import '../../data/models/chess_puzzle.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_text_styles.dart';
import '../../widgets/common/common.dart';
import 'puzzle_list_controller.dart';
import 'widgets/daily_challenge_banner.dart';

class PuzzleListScreen extends ConsumerStatefulWidget {
  const PuzzleListScreen({super.key});

  @override
  ConsumerState<PuzzleListScreen> createState() => _PuzzleListScreenState();
}

class _PuzzleListScreenState extends ConsumerState<PuzzleListScreen> {
  final ScrollController _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scroll.removeListener(_onScroll);
    _scroll.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scroll.hasClients) return;
    final pos = _scroll.position;
    if (pos.pixels >= pos.maxScrollExtent - 320) {
      ref.read(puzzleListControllerProvider.notifier).loadMore();
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(puzzleListControllerProvider);
    final controller = ref.read(puzzleListControllerProvider.notifier);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.woodDark,
        title: const Text('Bài Tập Tàn Cục'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go(AppConstants.routeLearning),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.bar_chart),
            tooltip: 'Thống kê',
            onPressed: () => context.go(AppConstants.routeEndgameStats),
          ),
        ],
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: controller.refresh,
          color: AppColors.accentGold,
          child: ListView(
            controller: _scroll,
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(AppSpacing.base),
            children: [
              const DailyChallengeBanner(),
              AppSpacing.vGapLg,
              _ProgressSummary(
                solved: state.solvedCount,
                shown: state.puzzles.length,
                onStatsTap: () => context.go(AppConstants.routeEndgameStats),
              ),
              AppSpacing.vGapLg,
              _PuzzleFilters(
                selectedCategory: state.category,
                selectedDifficulty: state.difficulty,
                selectedSort: state.sort,
                onCategoryChanged: controller.setCategory,
                onDifficultyChanged: controller.setDifficulty,
                onSortChanged: controller.setSort,
              ),
              AppSpacing.vGapLg,
              SectionHeader(title: 'Kho tàn cục (${state.puzzles.length})'),
              AppSpacing.vGapMd,
              ..._buildBody(state, controller),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _buildBody(
    PuzzleListState state,
    PuzzleListController controller,
  ) {
    if (state.isLoading && state.puzzles.isEmpty) {
      return const [
        Padding(
          padding: EdgeInsets.symmetric(vertical: AppSpacing.lg),
          child: Center(child: CircularProgressIndicator()),
        ),
      ];
    }
    if (state.error != null && state.puzzles.isEmpty) {
      return [_ErrorState(onRetry: controller.refresh)];
    }
    if (state.puzzles.isEmpty) {
      return const [_EmptyPuzzleState()];
    }
    return [
      for (final p in state.puzzles) ...[
        _PuzzleListItem(
          puzzle: p,
          progress: state.progress[p.id] ?? PuzzleProgress(puzzleId: p.id),
        ),
        AppSpacing.vGapSm,
      ],
      if (state.isLoadingMore)
        const Padding(
          padding: EdgeInsets.symmetric(vertical: AppSpacing.md),
          child: Center(child: CircularProgressIndicator()),
        )
      else if (!state.hasMore)
        Padding(
          padding: const EdgeInsets.only(top: AppSpacing.sm),
          child: Text(
            'Đã hết bài trong bộ lọc này.',
            textAlign: TextAlign.center,
            style: AppTextStyles.captionSm.copyWith(
              color: AppColors.onSurfaceVariant,
            ),
          ),
        ),
    ];
  }
}

class _ProgressSummary extends StatelessWidget {
  final int solved;
  final int shown;
  final VoidCallback onStatsTap;

  const _ProgressSummary({
    required this.solved,
    required this.shown,
    required this.onStatsTap,
  });

  @override
  Widget build(BuildContext context) {
    return CChessCard(
      onTap: onStatsTap,
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: AppColors.accentGold.withValues(alpha: 0.16),
              shape: BoxShape.circle,
              border: Border.all(color: AppColors.accentGold),
            ),
            alignment: Alignment.center,
            child: const Icon(
              Icons.workspace_premium,
              color: AppColors.accentGold,
              size: 22,
            ),
          ),
          AppSpacing.hGapMd,
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Tiến độ luyện tập', style: AppTextStyles.headingMd),
                AppSpacing.vGapXs,
                Text(
                  'Đã giải $solved bài • đang xem $shown bài',
                  style: AppTextStyles.captionSm.copyWith(
                    color: AppColors.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          Row(
            children: [
              Text(
                'Thống kê',
                style: AppTextStyles.captionSm.copyWith(
                  color: AppColors.accentGold,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Icon(Icons.chevron_right, color: AppColors.parchmentTan),
            ],
          ),
        ],
      ),
    );
  }
}

class _PuzzleFilters extends StatelessWidget {
  final String? selectedCategory;
  final int? selectedDifficulty;
  final PuzzleSort selectedSort;
  final ValueChanged<String?> onCategoryChanged;
  final ValueChanged<int?> onDifficultyChanged;
  final ValueChanged<PuzzleSort> onSortChanged;

  const _PuzzleFilters({
    required this.selectedCategory,
    required this.selectedDifficulty,
    required this.selectedSort,
    required this.onCategoryChanged,
    required this.onDifficultyChanged,
    required this.onSortChanged,
  });

  static const _sorts = <(PuzzleSort, String)>[
    (PuzzleSort.newest, 'Mới nhất'),
    (PuzzleSort.hardest, 'Khó nhất'),
    (PuzzleSort.easiest, 'Dễ nhất'),
  ];

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
          _FilterLabel('Chủ đề'),
          AppSpacing.vGapXs,
          _ChipRow(
            children: [
              for (final cat in kPuzzleCategories)
                _FilterChip(
                  label: cat.label,
                  selected: selectedCategory == cat.key,
                  onTap: () => onCategoryChanged(cat.key),
                ),
            ],
          ),
          AppSpacing.vGapMd,
          _FilterLabel('Độ khó'),
          AppSpacing.vGapXs,
          _ChipRow(
            children: [
              _FilterChip(
                label: 'Tất cả',
                selected: selectedDifficulty == null,
                onTap: () => onDifficultyChanged(null),
              ),
              for (int difficulty = 1; difficulty <= 5; difficulty++)
                _FilterChip(
                  label: '$difficulty★',
                  selected: selectedDifficulty == difficulty,
                  onTap: () => onDifficultyChanged(difficulty),
                ),
            ],
          ),
          AppSpacing.vGapMd,
          _FilterLabel('Sắp xếp'),
          AppSpacing.vGapXs,
          _ChipRow(
            children: [
              for (final (sort, label) in _sorts)
                _FilterChip(
                  label: label,
                  selected: selectedSort == sort,
                  onTap: () => onSortChanged(sort),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _FilterLabel extends StatelessWidget {
  final String text;
  const _FilterLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: AppTextStyles.captionSm.copyWith(
        color: AppColors.parchmentTan,
        fontWeight: FontWeight.w700,
      ),
    );
  }
}

/// Horizontally-scrollable row of chips with consistent spacing.
class _ChipRow extends StatelessWidget {
  final List<Widget> children;
  const _ChipRow({required this.children});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final child in children) ...[child, AppSpacing.hGapXs],
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
      onTap: () => context.go('${AppConstants.routePuzzle}/${puzzle.id}'),
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
                    if (progress.solved && progress.bestScore > 0)
                      _TinyMetaChip(label: 'Điểm ${progress.bestScore}'),
                    if (!progress.solved && progress.attempts > 0)
                      _TinyMetaChip(label: '${progress.attempts} lần thử'),
                    for (final tag in puzzle.tags.take(2))
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

class _ErrorState extends StatelessWidget {
  final VoidCallback onRetry;
  const _ErrorState({required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return CChessCard(
      child: Column(
        children: [
          const Icon(
            Icons.cloud_off,
            color: AppColors.onSurfaceVariant,
            size: 32,
          ),
          AppSpacing.vGapSm,
          Text('Không tải được kho bài', style: AppTextStyles.headingMd),
          AppSpacing.vGapXs,
          Text(
            'Kiểm tra kết nối mạng rồi thử lại.',
            style: AppTextStyles.captionSm.copyWith(
              color: AppColors.onSurfaceVariant,
            ),
            textAlign: TextAlign.center,
          ),
          AppSpacing.vGapMd,
          CChessButton(
            label: 'Thử lại',
            icon: Icons.refresh,
            onPressed: onRetry,
          ),
        ],
      ),
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
