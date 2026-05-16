import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants/app_constants.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_text_styles.dart';
import '../../widgets/common/common.dart';

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
        const _WelcomeBanner(),
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
                onTap: () => context.go(
                  '${AppConstants.routeGame}?mode=local',
                ),
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
                onTap: () => _showSoon(context, 'Cờ Úp sẽ có ở Sprint 7.'),
              ),
            ),
            AppSpacing.hGapMd,
            Expanded(
              child: _PlayModeCard(
                title: 'Mời Bạn',
                subtitle: 'Đấu cùng bạn bè',
                icon: Icons.group_add_outlined,
                accent: AppColors.tealSuccess,
                onTap: () => _showSoon(context, 'Mời bạn sẽ có ở Sprint 8.'),
              ),
            ),
          ],
        ),
        AppSpacing.vGapLg,
        SectionHeader(
          title: 'Phần Thưởng Hôm Nay',
          actionLabel: 'Nhiệm vụ',
          onActionPressed: () =>
              context.go(AppConstants.routeDailyQuests),
        ),
        AppSpacing.vGapMd,
        const _DailyRewardCard(),
      ],
    );
  }

  void _showSoon(BuildContext context, String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg)),
    );
  }
}

class _WelcomeBanner extends StatelessWidget {
  const _WelcomeBanner();

  @override
  Widget build(BuildContext context) {
    return CChessCard(
      padding: const EdgeInsets.all(AppSpacing.lg),
      gradient: const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [AppColors.woodDark, AppColors.charcoalDark],
      ),
      borderColor: AppColors.accentGold.withValues(alpha: 0.4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.sm,
                  vertical: 2,
                ),
                decoration: BoxDecoration(
                  color: AppColors.vermilionRed.withValues(alpha: 0.2),
                  border: Border.all(
                    color: AppColors.vermilionRed.withValues(alpha: 0.5),
                  ),
                  borderRadius: AppRadius.chip,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.local_fire_department,
                      size: 14,
                      color: AppColors.error,
                    ),
                    AppSpacing.hGapXs,
                    Text(
                      'NÓNG HỔI',
                      style: AppTextStyles.captionSm.copyWith(
                        color: AppColors.error,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.2,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          AppSpacing.vGapSm,
          Text(
            'Tàn Cục Thách Đấu Hôm Nay',
            style: AppTextStyles.titleLg.copyWith(color: AppColors.onSurface),
          ),
          AppSpacing.vGapXs,
          Row(
            children: [
              const Icon(Icons.timer_outlined, size: 16, color: AppColors.parchmentTan),
              AppSpacing.hGapXs,
              Text(
                'Kết thúc sau: 05:42:10',
                style: AppTextStyles.monoTimer.copyWith(
                  color: AppColors.onSurfaceVariant,
                  fontSize: 14,
                ),
              ),
            ],
          ),
          AppSpacing.vGapMd,
          CChessButton(
            label: 'Thử Ngay',
            variant: CChessButtonVariant.danger,
            icon: Icons.bolt,
            onPressed: () {},
          ),
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

class _DailyRewardCard extends StatelessWidget {
  const _DailyRewardCard();

  static const _days = [
    ('T2', 10, false),
    ('T3', 20, false),
    ('T4', 30, true), // today
    ('T5', 40, false),
    ('T6', 60, false),
    ('T7', 80, false),
    ('CN', 200, false),
  ];

  @override
  Widget build(BuildContext context) {
    return CChessCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.card_giftcard, color: AppColors.accentGold),
              AppSpacing.hGapSm,
              Text(
                'Điểm danh hàng ngày',
                style: AppTextStyles.headingMd,
              ),
              const Spacer(),
              Text(
                'Streak: 3 ngày',
                style: AppTextStyles.captionSm.copyWith(
                  color: AppColors.accentGold,
                ),
              ),
            ],
          ),
          AppSpacing.vGapMd,
          SizedBox(
            height: 84,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _days.length,
              separatorBuilder: (_, _) => AppSpacing.hGapSm,
              itemBuilder: (_, i) {
                final (day, amount, isToday) = _days[i];
                return Container(
                  width: 60,
                  decoration: BoxDecoration(
                    color: isToday
                        ? AppColors.accentGold.withValues(alpha: 0.18)
                        : AppColors.surfaceContainerHigh,
                    borderRadius: AppRadius.card,
                    border: Border.all(
                      color: isToday
                          ? AppColors.accentGold
                          : AppColors.outlineVariant,
                      width: isToday ? 1.5 : 1,
                    ),
                  ),
                  alignment: Alignment.center,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        day,
                        style: AppTextStyles.captionSm.copyWith(
                          color: isToday
                              ? AppColors.accentGold
                              : AppColors.parchmentTan,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      const Icon(
                        Icons.savings,
                        size: 18,
                        color: AppColors.accentGold,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '$amount',
                        style: AppTextStyles.captionSm.copyWith(
                          color: AppColors.onSurface,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
          AppSpacing.vGapMd,
          CChessButton(
            label: 'Nhận thưởng hôm nay',
            fullWidth: true,
            icon: Icons.redeem,
            onPressed: () {},
          ),
        ],
      ),
    );
  }
}
