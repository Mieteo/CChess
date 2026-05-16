import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants/app_constants.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_text_styles.dart';
import '../../widgets/common/common.dart';

/// Đối Đầu — chế độ thi đấu (matchmaking, bot, tournament).
class CompeteScreen extends StatelessWidget {
  const CompeteScreen({super.key});

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
        Text('Đối Đầu', style: AppTextStyles.titleLg),
        AppSpacing.vGapXs,
        Text(
          'Chọn chế độ phù hợp với bạn',
          style: AppTextStyles.captionSm.copyWith(
            color: AppColors.onSurfaceVariant,
          ),
        ),
        AppSpacing.vGapLg,
        _CompeteOption(
          title: 'Xếp Hạng Online',
          subtitle: 'Tính ELO, ghép theo trình độ',
          icon: Icons.public,
          color: AppColors.accentGold,
          badge: 'Sprint 8',
          onTap: () {},
        ),
        AppSpacing.vGapMd,
        _CompeteOption(
          title: 'Đấu Tại Chỗ',
          subtitle: '2 người trên cùng máy',
          icon: Icons.people_alt_outlined,
          color: AppColors.accentGold,
          badge: 'MVP',
          onTap: () =>
              context.go('${AppConstants.routeGame}?mode=local'),
        ),
        AppSpacing.vGapMd,
        _CompeteOption(
          title: 'Đấu Bot AI',
          subtitle: '5 cấp độ — luyện tập an toàn',
          icon: Icons.smart_toy_outlined,
          color: AppColors.tertiary,
          onTap: () => context.go(AppConstants.routeBotSelect),
        ),
        AppSpacing.vGapMd,
        _CompeteOption(
          title: 'Cờ Úp',
          subtitle: 'Quân úp — luật bí ẩn',
          icon: Icons.help_outline,
          color: AppColors.vermilionRed,
          onTap: () {},
        ),
        AppSpacing.vGapMd,
        _CompeteOption(
          title: 'Giải Đấu',
          subtitle: 'Bracket loại trực tiếp',
          icon: Icons.emoji_events_outlined,
          color: AppColors.accentGold,
          onTap: () {},
        ),
        AppSpacing.vGapMd,
        _CompeteOption(
          title: 'Mời Bạn Đấu',
          subtitle: 'Chia sẻ link, không tính ELO',
          icon: Icons.share_outlined,
          color: AppColors.tealSuccess,
          onTap: () {},
        ),
      ],
    );
  }
}

class _CompeteOption extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
  final String? badge;
  final VoidCallback onTap;

  const _CompeteOption({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
    this.badge,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return CChessCard(
      onTap: onTap,
      borderColor: color.withValues(alpha: 0.4),
      padding: const EdgeInsets.all(AppSpacing.base),
      child: Row(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              shape: BoxShape.circle,
              border: Border.all(color: color.withValues(alpha: 0.4)),
            ),
            alignment: Alignment.center,
            child: Icon(icon, color: color, size: 28),
          ),
          AppSpacing.hGapMd,
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(title, style: AppTextStyles.headingMd),
                    if (badge != null) ...[
                      AppSpacing.hGapSm,
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 1,
                        ),
                        decoration: BoxDecoration(
                          color: color.withValues(alpha: 0.18),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          badge!,
                          style: AppTextStyles.captionSm.copyWith(
                            color: color,
                            fontWeight: FontWeight.w700,
                            fontSize: 10,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                AppSpacing.vGapXs,
                Text(
                  subtitle,
                  style: AppTextStyles.captionSm.copyWith(
                    color: AppColors.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const Icon(
            Icons.chevron_right,
            color: AppColors.parchmentTan,
          ),
        ],
      ),
    );
  }
}
