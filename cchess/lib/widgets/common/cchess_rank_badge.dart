import 'package:flutter/material.dart';

import '../../core/constants/elo_constants.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_text_styles.dart';

/// Compact "ELO 1820" chip, colored by ELO band.
///
/// Replaces the old danh-xưng rank badge ("Kỳ Sĩ ⭐⭐⭐") — strength is now shown
/// as the raw number. [showStars] is retained only so existing call sites keep
/// compiling; it has no effect.
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
    final color = EloConstants.colorForElo(elo);

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? AppSpacing.sm : AppSpacing.md,
        vertical: compact ? 2 : AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: AppRadius.chip,
        border: Border.all(color: color.withValues(alpha: 0.6), width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.military_tech_outlined,
            color: color,
            size: compact ? 14 : 16,
          ),
          AppSpacing.hGapXs,
          Text(
            'ELO $elo',
            style: AppTextStyles.captionSm.copyWith(
              color: color,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
