import 'package:flutter/material.dart';

import '../../core/constants/elo_constants.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_text_styles.dart';

/// "Kỳ Sĩ ⭐⭐⭐" style chip showing the user's current rank.
class CChessRankBadge extends StatelessWidget {
  final int elo;
  final bool showStars;
  final bool compact;

  const CChessRankBadge({
    super.key,
    required this.elo,
    this.showStars = true,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final rank = EloConstants.rankForElo(elo);

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? AppSpacing.sm : AppSpacing.md,
        vertical: compact ? 2 : AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: rank.color.withValues(alpha: 0.15),
        borderRadius: AppRadius.chip,
        border: Border.all(color: rank.color.withValues(alpha: 0.6), width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(rank.icon, color: rank.color, size: compact ? 14 : 16),
          AppSpacing.hGapXs,
          Text(
            rank.nameVi,
            style: AppTextStyles.captionSm.copyWith(
              color: rank.color,
              fontWeight: FontWeight.w700,
            ),
          ),
          if (showStars) ...[
            const SizedBox(width: 4),
            Text(
              '★' * rank.stars,
              style: TextStyle(
                color: AppColors.accentGold,
                fontSize: compact ? 10 : 12,
                height: 1.0,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
