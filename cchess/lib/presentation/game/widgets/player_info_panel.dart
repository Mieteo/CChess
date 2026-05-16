import 'package:flutter/material.dart';

import '../../../core/chess_engine/chess_engine.dart';
import '../../../theme/app_colors.dart';
import '../../../theme/app_spacing.dart';
import '../../../theme/app_text_styles.dart';
import '../../../widgets/common/common.dart';

/// Compact player strip shown above and below the chess board: avatar +
/// name + rank + countdown timer + captured-piece count.
class PlayerInfoPanel extends StatelessWidget {
  final String displayName;
  final int elo;
  final PieceColor color;
  final bool isMyTurn;
  final Duration timeLeft;
  final int capturedCount;
  final bool topAlign;

  const PlayerInfoPanel({
    super.key,
    required this.displayName,
    required this.elo,
    required this.color,
    required this.isMyTurn,
    required this.timeLeft,
    this.capturedCount = 0,
    this.topAlign = false,
  });

  String _formatDuration(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final isLowTime = timeLeft.inSeconds <= 10;
    final timerColor = isLowTime ? AppColors.error : AppColors.onSurface;

    final children = <Widget>[
      CChessAvatar(initials: displayName[0], size: 36, elo: elo),
      AppSpacing.hGapSm,
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: color == PieceColor.red
                        ? AppColors.vermilionRed
                        : AppColors.deepNavyBlack,
                    shape: BoxShape.circle,
                  ),
                ),
                AppSpacing.hGapXs,
                Flexible(
                  child: Text(
                    displayName,
                    style: AppTextStyles.bodyMd.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            AppSpacing.vGapXs,
            Row(
              children: [
                CChessRankBadge(elo: elo, compact: true, showStars: false),
                if (capturedCount > 0) ...[
                  AppSpacing.hGapSm,
                  const Icon(Icons.close, size: 12, color: AppColors.parchmentTan),
                  Text(
                    '$capturedCount',
                    style: AppTextStyles.captionSm.copyWith(
                      color: AppColors.parchmentTan,
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
      AppSpacing.hGapSm,
      Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: AppSpacing.xs,
        ),
        decoration: BoxDecoration(
          color: isMyTurn
              ? AppColors.accentGold.withValues(alpha: 0.16)
              : AppColors.surfaceContainerHigh,
          borderRadius: AppRadius.chip,
          border: Border.all(
            color: isMyTurn
                ? AppColors.accentGold
                : AppColors.outlineVariant,
            width: isMyTurn ? 1.2 : 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.timer_outlined,
              size: 14,
              color: timerColor,
            ),
            AppSpacing.hGapXs,
            Text(
              _formatDuration(timeLeft),
              style: AppTextStyles.monoTimer.copyWith(
                color: timerColor,
                fontSize: 14,
              ),
            ),
          ],
        ),
      ),
    ];

    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: isMyTurn
            ? AppColors.surfaceContainerHigh
            : AppColors.surfaceContainer,
        border: Border.all(
          color: isMyTurn ? AppColors.accentGold : AppColors.outlineVariant,
          width: isMyTurn ? 1.2 : 1,
        ),
        borderRadius: AppRadius.card,
      ),
      child: Row(
        crossAxisAlignment: topAlign
            ? CrossAxisAlignment.center
            : CrossAxisAlignment.center,
        children: children,
      ),
    );
  }
}
