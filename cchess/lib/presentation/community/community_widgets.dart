import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants/app_constants.dart';
import '../../data/models/community_models.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_text_styles.dart';
import '../../widgets/common/common.dart';

class CommunityPageHeader extends StatelessWidget {
  const CommunityPageHeader({
    super.key,
    required this.title,
    required this.subtitle,
    required this.icon,
    this.showBack = false,
    this.trailing,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final bool showBack;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        if (showBack) ...[
          IconButton(
            tooltip: 'Quay lại',
            onPressed: () => context.go(AppConstants.routeCommunity),
            icon: const Icon(Icons.arrow_back, color: AppColors.accentGold),
          ),
          AppSpacing.hGapXs,
        ],
        Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: AppColors.accentGold.withValues(alpha: 0.14),
            border: Border.all(
              color: AppColors.accentGold.withValues(alpha: 0.45),
            ),
            borderRadius: BorderRadius.circular(AppRadius.lg),
          ),
          alignment: Alignment.center,
          child: Icon(icon, color: AppColors.accentGold, size: 26),
        ),
        AppSpacing.hGapMd,
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: AppTextStyles.titleLg),
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
        if (trailing != null) ...[AppSpacing.hGapSm, trailing!],
      ],
    );
  }
}

class CommunityMetricChip extends StatelessWidget {
  const CommunityMetricChip({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    this.color = AppColors.accentGold,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return CChessCard(
      padding: const EdgeInsets.all(AppSpacing.sm),
      borderColor: color.withValues(alpha: 0.35),
      child: Row(
        children: [
          Icon(icon, color: color, size: 18),
          AppSpacing.hGapSm,
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  style: AppTextStyles.headingMd.copyWith(color: color),
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  label,
                  style: AppTextStyles.captionSm.copyWith(
                    color: AppColors.onSurfaceVariant,
                    fontSize: 11,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class CommunityPlayerRow extends StatelessWidget {
  const CommunityPlayerRow({
    super.key,
    required this.player,
    this.rank,
    this.boardType = CommunityBoardType.chess,
    this.subtitle,
    this.trailing,
    this.onTap,
    this.highlight = false,
  });

  final CommunityPlayer player;
  final int? rank;
  final CommunityBoardType boardType;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final body = Row(
      children: [
        if (rank != null) ...[
          SizedBox(
            width: 28,
            child: Text(
              '#$rank',
              style: AppTextStyles.bodyMd.copyWith(
                color: rank! <= 3
                    ? AppColors.accentGold
                    : AppColors.parchmentTan,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          AppSpacing.hGapSm,
        ],
        Stack(
          clipBehavior: Clip.none,
          children: [
            CChessAvatar(
              initials: player.initials,
              size: 44,
              elo: player.eloFor(boardType),
            ),
            Positioned(
              right: -1,
              bottom: -1,
              child: Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  color: player.isOnline
                      ? AppColors.tealSuccess
                      : AppColors.surfaceContainerHighest,
                  shape: BoxShape.circle,
                  border: Border.all(color: AppColors.background, width: 2),
                ),
              ),
            ),
          ],
        ),
        AppSpacing.hGapMd,
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                player.displayName,
                style: AppTextStyles.bodyMd.copyWith(
                  fontWeight: FontWeight.w700,
                ),
                overflow: TextOverflow.ellipsis,
              ),
              AppSpacing.vGapXs,
              Text(
                subtitle ??
                    '${player.region} • ELO ${player.eloFor(boardType)}',
                style: AppTextStyles.captionSm.copyWith(
                  color: AppColors.onSurfaceVariant,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
        if (trailing != null) ...[AppSpacing.hGapSm, trailing!],
      ],
    );

    return CChessCard(
      onTap: onTap,
      color: highlight ? AppColors.surfaceContainerHigh : null,
      borderColor: highlight
          ? AppColors.accentGold.withValues(alpha: 0.45)
          : AppColors.outlineVariant,
      padding: const EdgeInsets.all(AppSpacing.md),
      child: body,
    );
  }
}

class CommunityEmptyState extends StatelessWidget {
  const CommunityEmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
  });

  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xl),
      child: Column(
        children: [
          Icon(icon, color: AppColors.parchmentTan, size: 48),
          AppSpacing.vGapMd,
          Text(
            title,
            style: AppTextStyles.headingMd,
            textAlign: TextAlign.center,
          ),
          AppSpacing.vGapSm,
          Text(
            message,
            style: AppTextStyles.bodyMd.copyWith(
              color: AppColors.onSurfaceVariant,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
