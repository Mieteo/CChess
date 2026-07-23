import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants/app_constants.dart';
import '../../data/models/economy_models.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_text_styles.dart';
import '../../widgets/common/common.dart';
import '../economy/economy_controller.dart';
import '../economy/economy_widgets.dart';
import '../puzzle/widgets/daily_challenge_banner.dart';

/// Trang Chủ — Main lobby for Đánh Cờ.
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.base,
        AppSpacing.base,
        AppSpacing.base,
        96,
      ),
      children: [
        // Real daily endgame challenge (B4): live countdown + today's puzzle,
        // shared with Học Cờ and the puzzle list.
        const DailyChallengeBanner(),
        AppSpacing.vGapLg,
        SectionHeader(
          title: 'Đánh Cờ Ngay',
          actionLabel: 'Xem tất cả',
          onActionPressed: () {},
        ),
        AppSpacing.vGapMd,
        Row(
          children: [
            Expanded(
              child: _PlayModeCard(
                title: 'Đánh Tại Chỗ',
                subtitle: '2 người cùng máy',
                icon: Icons.people_alt_outlined,
                accent: AppColors.accentGold,
                onTap: () => context.go('${AppConstants.routeGame}?mode=local'),
              ),
            ),
            AppSpacing.hGapMd,
            Expanded(
              child: _PlayModeCard(
                title: 'Đấu với AI',
                subtitle: 'Luyện tập 5 cấp độ',
                icon: Icons.smart_toy_outlined,
                accent: AppColors.tertiary,
                onTap: () => context.go(AppConstants.routeBotSelect),
              ),
            ),
          ],
        ),
        AppSpacing.vGapMd,
        Row(
          children: [
            Expanded(
              child: _PlayModeCard(
                title: 'Cờ Úp',
                subtitle: 'Biến thể bí ẩn',
                icon: Icons.help_outline,
                accent: AppColors.vermilionRed,
                badge: 'MỚI',
                onTap: () => context.go('${AppConstants.routeGame}?mode=cup'),
              ),
            ),
            AppSpacing.hGapMd,
            Expanded(
              child: _PlayModeCard(
                title: 'Mời Bạn',
                subtitle: 'Đấu cùng bạn bè',
                icon: Icons.group_add_outlined,
                accent: AppColors.tealSuccess,
                onTap: () =>
                    context.push('${AppConstants.routeOnlineLobby}?casual=1'),
              ),
            ),
          ],
        ),
        AppSpacing.vGapLg,
        SectionHeader(
          title: 'Phần Thưởng Hôm Nay',
          actionLabel: 'Nhiệm vụ',
          onActionPressed: () => context.go(AppConstants.routeDailyQuests),
        ),
        AppSpacing.vGapMd,
        const _DailyRewardCard(),
        AppSpacing.vGapLg,
        const SectionHeader(title: 'Khám Phá'),
        AppSpacing.vGapMd,
        _ExploreCard(onTap: () => context.push(AppConstants.routeExplore)),
      ],
    );
  }
}

class _ExploreCard extends StatelessWidget {
  final VoidCallback onTap;
  const _ExploreCard({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return CChessCard(
      onTap: onTap,
      borderColor: AppColors.accentGold.withValues(alpha: 0.4),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppColors.accentGold.withValues(alpha: 0.12),
              shape: BoxShape.circle,
              border: Border.all(
                color: AppColors.accentGold.withValues(alpha: 0.4),
              ),
            ),
            child: const Icon(
              Icons.storefront,
              color: AppColors.accentGold,
              size: 22,
            ),
          ),
          AppSpacing.hGapMd,
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Thương Thành & Balo', style: AppTextStyles.headingMd),
                AppSpacing.vGapXs,
                Text(
                  'Sắm bàn cờ, quân cờ và trang bị vật phẩm',
                  style: AppTextStyles.captionSm.copyWith(
                    color: AppColors.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const Icon(Icons.chevron_right, color: AppColors.onSurfaceVariant),
        ],
      ),
    );
  }
}

class _PlayModeCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final Color accent;
  final String? badge;
  final VoidCallback onTap;

  const _PlayModeCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.accent,
    this.badge,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return CChessCard(
      onTap: onTap,
      padding: const EdgeInsets.all(AppSpacing.base),
      borderColor: accent.withValues(alpha: 0.4),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 44,
                height: 44,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.12),
                  border: Border.all(color: accent.withValues(alpha: 0.4)),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: accent, size: 22),
              ),
              AppSpacing.vGapMd,
              Text(title, style: AppTextStyles.headingMd),
              AppSpacing.vGapXs,
              Text(
                subtitle,
                style: AppTextStyles.captionSm.copyWith(
                  color: AppColors.onSurfaceVariant,
                ),
              ),
            ],
          ),
          if (badge != null)
            Positioned(
              top: -4,
              right: -4,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.vermilionRed,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  badge!,
                  style: AppTextStyles.captionSm.copyWith(
                    color: Colors.white,
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.8,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Điểm danh hàng ngày — the REAL S16 welfare check-in: same provider and
/// claim action as the Phúc Lợi screen, compact for the lobby. Tapping the
/// card opens the full welfare page.
class _DailyRewardCard extends ConsumerWidget {
  const _DailyRewardCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final welfare = ref.watch(welfareProvider);
    return welfare.when(
      loading: () => const CChessCard(
        child: SizedBox(
          height: 64,
          child: Center(child: BrushStrokeSpinner(size: 28)),
        ),
      ),
      error: (_, _) => CChessCard(
        onTap: () => ref.invalidate(welfareProvider),
        child: Row(
          children: [
            const Icon(Icons.cloud_off, color: AppColors.parchmentTan),
            AppSpacing.hGapSm,
            Expanded(
              child: Text(
                'Không tải được điểm danh — chạm để thử lại.',
                style: AppTextStyles.captionSm.copyWith(
                  color: AppColors.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
      ),
      data: (status) => _DailyRewardLoaded(status: status),
    );
  }
}

class _DailyRewardLoaded extends ConsumerWidget {
  final WelfareStatus status;
  const _DailyRewardLoaded({required this.status});

  Future<void> _claim(BuildContext context, WidgetRef ref) async {
    try {
      final outcome = await ref.read(economyControllerProvider).checkin();
      if (context.mounted) showRewardSnack(context, outcome.reward);
    } catch (e) {
      if (context.mounted) showEconomyError(context, e);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return CChessCard(
      onTap: () => context.push(AppConstants.routeWelfare),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.card_giftcard, color: AppColors.accentGold),
              AppSpacing.hGapSm,
              Expanded(
                child: Text(
                  'Điểm danh hàng ngày',
                  style: AppTextStyles.headingMd,
                ),
              ),
              Text(
                'Streak: ${status.streak} ngày',
                style: AppTextStyles.captionSm.copyWith(
                  color: AppColors.accentGold,
                ),
              ),
            ],
          ),
          AppSpacing.vGapMd,
          if (status.cycle.isNotEmpty)
            SizedBox(
              height: 84,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: status.cycle.length,
                separatorBuilder: (_, _) => AppSpacing.hGapSm,
                itemBuilder: (_, i) => _DayChip(
                  day: i + 1,
                  reward: status.cycle[i],
                  collected: status.todayClaimed
                      ? i <= status.todayIndex
                      : i < status.todayIndex,
                  isToday: i == status.todayIndex,
                ),
              ),
            ),
          AppSpacing.vGapMd,
          CChessButton(
            label: status.todayClaimed
                ? 'Hôm nay đã điểm danh'
                : 'Điểm danh hôm nay',
            fullWidth: true,
            icon: status.todayClaimed ? Icons.check : Icons.redeem,
            onPressed: status.todayClaimed ? null : () => _claim(context, ref),
          ),
        ],
      ),
    );
  }
}

/// One slot of the 7-day cycle strip (mirrors the Phúc Lợi grid, horizontal).
class _DayChip extends StatelessWidget {
  final int day;
  final RewardBundle reward;
  final bool collected;
  final bool isToday;

  const _DayChip({
    required this.day,
    required this.reward,
    required this.collected,
    required this.isToday,
  });

  @override
  Widget build(BuildContext context) {
    final highlight = isToday && !collected;
    return Container(
      width: 60,
      decoration: BoxDecoration(
        color: collected
            ? AppColors.tealSuccess.withValues(alpha: 0.12)
            : highlight
            ? AppColors.accentGold.withValues(alpha: 0.18)
            : AppColors.surfaceContainerHigh,
        borderRadius: AppRadius.card,
        border: Border.all(
          color: collected
              ? AppColors.tealSuccess.withValues(alpha: 0.5)
              : highlight
              ? AppColors.accentGold
              : AppColors.outlineVariant,
          width: highlight ? 1.5 : 1,
        ),
      ),
      alignment: Alignment.center,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            'N$day',
            style: AppTextStyles.captionSm.copyWith(
              color: highlight
                  ? AppColors.accentGold
                  : collected
                  ? AppColors.tealSuccess
                  : AppColors.parchmentTan,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 2),
          if (collected)
            const Icon(
              Icons.check_circle,
              size: 18,
              color: AppColors.tealSuccess,
            )
          else
            Icon(
              reward.gems > 0 ? Icons.diamond_outlined : Icons.savings,
              size: 18,
              color: reward.gems > 0
                  ? AppColors.tertiary
                  : AppColors.accentGold,
            ),
          const SizedBox(height: 2),
          Text(
            '${reward.gems > 0 ? reward.gems : reward.coins}',
            style: AppTextStyles.captionSm.copyWith(
              color: AppColors.onSurface,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
