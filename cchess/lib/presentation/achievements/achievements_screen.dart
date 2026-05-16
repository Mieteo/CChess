import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants/app_constants.dart';
import '../../data/models/achievement.dart';
import '../../data/repositories/achievement_repository.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_text_styles.dart';
import '../../widgets/common/common.dart';

class AchievementsScreen extends ConsumerStatefulWidget {
  const AchievementsScreen({super.key});

  @override
  ConsumerState<AchievementsScreen> createState() =>
      _AchievementsScreenState();
}

class _AchievementsScreenState extends ConsumerState<AchievementsScreen> {
  late Future<Map<String, AchievementProgress>> _progressFuture;

  @override
  void initState() {
    super.initState();
    _progressFuture =
        ref.read(achievementRepositoryProvider).getAllProgress();
  }

  @override
  Widget build(BuildContext context) {
    final repo = ref.watch(achievementRepositoryProvider);
    final achievements = repo.all();

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.woodDark,
        title: const Text('Huy Chương'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go(AppConstants.routeProfile),
        ),
      ),
      body: SafeArea(
        child: FutureBuilder<Map<String, AchievementProgress>>(
          future: _progressFuture,
          builder: (context, snap) {
            final progress = snap.data ?? const <String, AchievementProgress>{};
            final unlocked = progress.values.where((p) => p.unlocked).length;

            // Group achievements by category.
            final byCategory = <AchievementCategory, List<Achievement>>{};
            for (final a in achievements) {
              byCategory.putIfAbsent(a.category, () => []).add(a);
            }

            return ListView(
              padding: const EdgeInsets.all(AppSpacing.base),
              children: [
                _Summary(unlocked: unlocked, total: achievements.length),
                AppSpacing.vGapLg,
                for (final cat in AchievementCategory.values)
                  if (byCategory[cat] != null && byCategory[cat]!.isNotEmpty) ...[
                    SectionHeader(title: cat.nameVi),
                    AppSpacing.vGapMd,
                    GridView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 3,
                        mainAxisSpacing: AppSpacing.sm,
                        crossAxisSpacing: AppSpacing.sm,
                        childAspectRatio: 0.78,
                      ),
                      itemCount: byCategory[cat]!.length,
                      itemBuilder: (_, i) {
                        final a = byCategory[cat]![i];
                        return _AchievementTile(
                          achievement: a,
                          progress: progress[a.id] ??
                              AchievementProgress(id: a.id),
                        );
                      },
                    ),
                    AppSpacing.vGapLg,
                  ],
              ],
            );
          },
        ),
      ),
    );
  }
}

class _Summary extends StatelessWidget {
  final int unlocked;
  final int total;

  const _Summary({required this.unlocked, required this.total});

  @override
  Widget build(BuildContext context) {
    final ratio = total == 0 ? 0.0 : unlocked / total;
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
              const Icon(Icons.emoji_events, color: AppColors.accentGold, size: 28),
              AppSpacing.hGapSm,
              Text('Tổng huy chương', style: AppTextStyles.headingMd),
              const Spacer(),
              Text(
                '$unlocked / $total',
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
                ? 'Hoàn thành tất cả huy chương!'
                : 'Tiếp tục chơi và học để mở khoá thêm huy chương.',
            style: AppTextStyles.captionSm.copyWith(
              color: AppColors.parchmentTan,
            ),
          ),
        ],
      ),
    );
  }
}

class _AchievementTile extends StatelessWidget {
  final Achievement achievement;
  final AchievementProgress progress;

  const _AchievementTile({
    required this.achievement,
    required this.progress,
  });

  @override
  Widget build(BuildContext context) {
    final unlocked = progress.unlocked;
    final tierColor = achievement.tier.color;

    return CChessCard(
      borderColor: unlocked
          ? tierColor.withValues(alpha: 0.6)
          : AppColors.outlineVariant,
      padding: const EdgeInsets.all(AppSpacing.sm),
      onTap: () {
        showDialog(
          context: context,
          builder: (_) => CChessDialog(
            title: achievement.nameVi,
            leadingIcon: achievement.icon,
            leadingIconColor: tierColor,
            content: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  achievement.descVi,
                  style: AppTextStyles.bodyMd,
                ),
                AppSpacing.vGapSm,
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: tierColor.withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        'Cấp ${achievement.tier.nameVi}',
                        style: AppTextStyles.captionSm.copyWith(
                          color: tierColor,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    AppSpacing.hGapSm,
                    Text(
                      unlocked
                          ? 'Đã mở khoá'
                          : 'Mục tiêu: ${achievement.target}',
                      style: AppTextStyles.captionSm.copyWith(
                        color: unlocked
                            ? AppColors.tealSuccess
                            : AppColors.parchmentTan,
                      ),
                    ),
                  ],
                ),
                if (unlocked && progress.unlockedAt != null) ...[
                  AppSpacing.vGapXs,
                  Text(
                    'Mở khoá ngày ${progress.unlockedAt!.day}/${progress.unlockedAt!.month}/${progress.unlockedAt!.year}',
                    style: AppTextStyles.captionSm.copyWith(
                      color: AppColors.parchmentTan,
                    ),
                  ),
                ],
              ],
            ),
            actions: [
              CChessButton(
                label: 'Đóng',
                variant: CChessButtonVariant.outline,
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
        );
      },
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: unlocked
                  ? tierColor.withValues(alpha: 0.18)
                  : AppColors.surfaceContainerHigh,
              border: Border.all(
                color: unlocked ? tierColor : AppColors.outlineVariant,
                width: unlocked ? 2 : 1,
              ),
            ),
            child: Icon(
              achievement.icon,
              color: unlocked ? tierColor : AppColors.parchmentTan,
              size: 26,
            ),
          ),
          AppSpacing.vGapXs,
          Text(
            achievement.nameVi,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: AppTextStyles.captionSm.copyWith(
              color: unlocked ? AppColors.onSurface : AppColors.onSurfaceVariant,
              fontWeight: FontWeight.w700,
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }
}
