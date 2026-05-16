import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants/app_constants.dart';
import '../../data/models/daily_quest.dart';
import '../../data/repositories/daily_quest_repository.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_text_styles.dart';
import '../../widgets/common/common.dart';
import '../profile/profile_controller.dart';

class DailyQuestsScreen extends ConsumerWidget {
  const DailyQuestsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncState = ref.watch(dailyQuestControllerProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.woodDark,
        title: const Text('Nhiệm Vụ Hôm Nay'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go(AppConstants.routeHome),
        ),
      ),
      body: SafeArea(
        child: asyncState.when(
          loading: () => const Center(child: BrushStrokeSpinner()),
          error: (e, _) => Center(child: Text('Lỗi: $e')),
          data: (state) {
            final completedCount =
                kDailyQuests.where(state.isComplete).length;
            return ListView(
              padding: const EdgeInsets.all(AppSpacing.base),
              children: [
                _Summary(
                  completed: completedCount,
                  total: kDailyQuests.length,
                  day: state.day,
                ),
                AppSpacing.vGapLg,
                for (final quest in kDailyQuests) ...[
                  _QuestCard(quest: quest, state: state),
                  AppSpacing.vGapMd,
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
  final int completed;
  final int total;
  final String day;

  const _Summary({
    required this.completed,
    required this.total,
    required this.day,
  });

  @override
  Widget build(BuildContext context) {
    final ratio = total == 0 ? 0.0 : completed / total;
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
              const Icon(
                Icons.task_alt,
                color: AppColors.accentGold,
                size: 28,
              ),
              AppSpacing.hGapSm,
              Text(
                'Tiến độ hôm nay',
                style: AppTextStyles.headingMd,
              ),
              const Spacer(),
              Text(
                '$completed / $total',
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
            'Ngày $day · Đặt lại lúc 00:00.',
            style: AppTextStyles.captionSm.copyWith(
              color: AppColors.parchmentTan,
            ),
          ),
        ],
      ),
    );
  }
}

class _QuestCard extends ConsumerWidget {
  final DailyQuest quest;
  final DailyQuestState state;

  const _QuestCard({required this.quest, required this.state});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final progress = state.progress(quest);
    final complete = state.isComplete(quest);
    final claimed = state.isClaimed(quest);
    final ratio = quest.target == 0
        ? 1.0
        : (progress / quest.target).clamp(0.0, 1.0).toDouble();

    return CChessCard(
      borderColor: claimed
          ? AppColors.tealSuccess.withValues(alpha: 0.5)
          : complete
              ? AppColors.accentGold.withValues(alpha: 0.7)
              : AppColors.outlineVariant,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: claimed
                      ? AppColors.tealSuccess.withValues(alpha: 0.18)
                      : AppColors.surfaceContainerHigh,
                  border: Border.all(
                    color: claimed
                        ? AppColors.tealSuccess
                        : AppColors.outlineVariant,
                  ),
                ),
                child: Icon(
                  claimed ? Icons.check : quest.kind.icon,
                  color: claimed
                      ? AppColors.tealSuccess
                      : AppColors.primary,
                ),
              ),
              AppSpacing.hGapMd,
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(quest.titleVi, style: AppTextStyles.headingMd),
                    AppSpacing.vGapXs,
                    Text(
                      quest.descVi,
                      style: AppTextStyles.captionSm.copyWith(
                        color: AppColors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Row(
                    children: [
                      const Icon(
                        Icons.savings,
                        size: 14,
                        color: AppColors.accentGold,
                      ),
                      AppSpacing.hGapXs,
                      Text(
                        '+${quest.rewardCoins}',
                        style: AppTextStyles.captionSm.copyWith(
                          color: AppColors.accentGold,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                  if (quest.rewardGems > 0)
                    Row(
                      children: [
                        const Icon(
                          Icons.diamond_outlined,
                          size: 14,
                          color: AppColors.tertiary,
                        ),
                        AppSpacing.hGapXs,
                        Text(
                          '+${quest.rewardGems}',
                          style: AppTextStyles.captionSm.copyWith(
                            color: AppColors.tertiary,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            ],
          ),
          AppSpacing.vGapSm,
          CChessProgressBar(value: ratio),
          AppSpacing.vGapXs,
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '${progress.clamp(0, quest.target)} / ${quest.target}',
                style: AppTextStyles.captionSm.copyWith(
                  color: AppColors.parchmentTan,
                ),
              ),
              if (complete && !claimed)
                CChessButton(
                  label: 'Nhận thưởng',
                  icon: Icons.redeem,
                  height: 32,
                  onPressed: () async {
                    final rewards = await ref
                        .read(dailyQuestControllerProvider.notifier)
                        .claim(quest);
                    if (rewards == null) return;
                    // Apply reward to profile.
                    await ref
                        .read(profileControllerProvider.notifier)
                        .update((p) => p.copyWith(
                              coins: p.coins + rewards.coins,
                              gems: p.gems + rewards.gems,
                            ));
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          'Nhận thưởng: +${rewards.coins} đồng'
                          '${rewards.gems > 0 ? " +${rewards.gems} ngọc" : ""}',
                        ),
                      ),
                    );
                  },
                )
              else if (claimed)
                Text(
                  'Đã nhận',
                  style: AppTextStyles.captionSm.copyWith(
                    color: AppColors.tealSuccess,
                    fontWeight: FontWeight.w700,
                  ),
                )
              else
                Text(
                  'Còn ${quest.target - progress}',
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
