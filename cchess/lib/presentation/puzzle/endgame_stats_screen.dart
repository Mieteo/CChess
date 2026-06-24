import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants/app_constants.dart';
import '../../data/models/puzzle_stats.dart';
import '../../data/repositories/puzzle_repository.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_text_styles.dart';
import '../../widgets/common/common.dart';

/// Aggregated endgame progress, recomputed each time the screen opens.
final puzzleStatsProvider = FutureProvider.autoDispose<PuzzleStats>((ref) {
  return ref.watch(puzzleRepositoryProvider).computeStats();
});

class EndgameStatsScreen extends ConsumerWidget {
  const EndgameStatsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final statsAsync = ref.watch(puzzleStatsProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.woodDark,
        title: const Text('Thống Kê Tàn Cục'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go(AppConstants.routePuzzle),
        ),
      ),
      body: SafeArea(
        child: statsAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, _) => Center(
            child: Text('Không tải được thống kê.', style: AppTextStyles.bodyMd),
          ),
          data: (stats) => _StatsBody(stats: stats),
        ),
      ),
    );
  }
}

class _StatsBody extends StatelessWidget {
  final PuzzleStats stats;
  const _StatsBody({required this.stats});

  @override
  Widget build(BuildContext context) {
    if (stats.attempted == 0) {
      return _EmptyStats();
    }
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.base),
      children: [
        _CompletionCard(stats: stats),
        AppSpacing.vGapLg,
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: AppSpacing.sm,
          crossAxisSpacing: AppSpacing.sm,
          childAspectRatio: 1.9,
          children: [
            _StatTile(
              icon: Icons.percent,
              label: 'Tỉ lệ giải',
              value: '${(stats.solveRate * 100).round()}%',
            ),
            _StatTile(
              icon: Icons.stars,
              label: 'Điểm trung bình',
              value: '${stats.averageScore}',
            ),
            _StatTile(
              icon: Icons.refresh,
              label: 'Tổng lượt thử',
              value: '${stats.totalAttempts}',
            ),
            _StatTile(
              icon: Icons.lightbulb_outline,
              label: 'Gợi ý đã dùng',
              value: '${stats.totalHints}',
            ),
          ],
        ),
        AppSpacing.vGapLg,
        SectionHeader(title: 'Theo độ khó'),
        AppSpacing.vGapMd,
        for (final bucket in stats.byDifficulty) ...[
          _DifficultyRow(bucket: bucket),
          AppSpacing.vGapSm,
        ],
      ],
    );
  }
}

class _CompletionCard extends StatelessWidget {
  final PuzzleStats stats;
  const _CompletionCard({required this.stats});

  @override
  Widget build(BuildContext context) {
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
              Text('Đã chinh phục', style: AppTextStyles.headingMd),
              const Spacer(),
              Text(
                '${stats.solved} / ${stats.catalogSize}',
                style: AppTextStyles.titleLg.copyWith(
                  color: AppColors.accentGold,
                ),
              ),
            ],
          ),
          AppSpacing.vGapSm,
          CChessProgressBar(value: stats.completion),
          AppSpacing.vGapXs,
          Text(
            'Hoàn thành ${(stats.completion * 100).round()}% kho tàn cục đã tải.',
            style: AppTextStyles.captionSm.copyWith(
              color: AppColors.parchmentTan,
            ),
          ),
        ],
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _StatTile({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return CChessCard(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Row(
        children: [
          Icon(icon, color: AppColors.accentGold, size: 22),
          AppSpacing.hGapMd,
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  value,
                  style: AppTextStyles.titleLg.copyWith(
                    color: AppColors.onSurface,
                  ),
                ),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.captionSm.copyWith(
                    color: AppColors.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DifficultyRow extends StatelessWidget {
  final DifficultyStat bucket;
  const _DifficultyRow({required this.bucket});

  @override
  Widget build(BuildContext context) {
    return CChessCard(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(child: _label()),
              Text(
                '${bucket.solved}/${bucket.attempted}',
                style: AppTextStyles.captionSm.copyWith(
                  color: AppColors.accentGold,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          AppSpacing.vGapSm,
          CChessProgressBar(value: bucket.ratio, height: 6),
        ],
      ),
    );
  }

  Widget _label() {
    if (bucket.difficulty == 0) {
      return Text(
        'Khác',
        style: AppTextStyles.captionSm.copyWith(color: AppColors.onSurface),
      );
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (int i = 1; i <= 5; i++)
          Icon(
            i <= bucket.difficulty ? Icons.star : Icons.star_outline,
            size: 13,
            color: AppColors.accentGold,
          ),
      ],
    );
  }
}

class _EmptyStats extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.insights, color: AppColors.onSurfaceVariant, size: 44),
            AppSpacing.vGapMd,
            Text(
              'Chưa có dữ liệu luyện tập',
              style: AppTextStyles.headingMd,
              textAlign: TextAlign.center,
            ),
            AppSpacing.vGapXs,
            Text(
              'Giải vài bài tàn cục để xem tiến độ của bạn ở đây.',
              style: AppTextStyles.captionSm.copyWith(
                color: AppColors.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            AppSpacing.vGapLg,
            CChessButton(
              label: 'Tới kho bài',
              icon: Icons.extension,
              onPressed: () => context.go(AppConstants.routePuzzle),
            ),
          ],
        ),
      ),
    );
  }
}
