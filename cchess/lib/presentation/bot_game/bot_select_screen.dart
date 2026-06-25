import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/chess_engine/chess_engine.dart';
import '../../core/constants/app_constants.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_text_styles.dart';
import '../../widgets/common/common.dart';

/// Screen where the user picks a bot difficulty before starting a CPU game.
/// [variant] selects the rule set: 'standard' Xiangqi or 'cup' (Cờ Úp). The cup
/// variant uses the offline cup-aware bot, so the Pikafish "Đại Sư+" tier (which
/// can't read hidden pieces) is hidden.
class BotSelectScreen extends StatelessWidget {
  final String variant;

  const BotSelectScreen({super.key, this.variant = 'standard'});

  bool get _isCup => variant == 'cup';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.woodDark,
        title: Text(_isCup ? 'Cờ Úp với Máy' : 'Chọn cấp độ Bot'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go(AppConstants.routeHome),
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.base),
          children: [
            Text(
              _isCup ? 'Bot Cờ Úp offline' : 'Bot AI offline',
              style: AppTextStyles.titleLg,
            ),
            AppSpacing.vGapXs,
            Text(
              _isCup
                  ? 'Máy chỉ thấy mặt phủ và quân đã lộ như bạn — định giá quân úp theo kỳ vọng. Cấp càng cao tính càng sâu.'
                  : 'Mỗi cấp độ tính trước số nước khác nhau. Càng cao càng chậm và khó.',
              style: AppTextStyles.bodyMd.copyWith(
                color: AppColors.onSurfaceVariant,
              ),
            ),
            AppSpacing.vGapLg,
            for (final difficulty in BotDifficulty.values) ...[
              _BotCard(difficulty: difficulty, variant: variant),
              AppSpacing.vGapMd,
            ],
            // Pikafish can't reason about hidden pieces — only standard chess.
            if (!_isCup) const _GrandmasterCard(),
          ],
        ),
      ),
    );
  }
}

class _BotCard extends StatelessWidget {
  final BotDifficulty difficulty;
  final String variant;

  const _BotCard({required this.difficulty, this.variant = 'standard'});

  Color get _accent {
    switch (difficulty) {
      case BotDifficulty.veryEasy:
        return AppColors.tealSuccess;
      case BotDifficulty.easy:
        return AppColors.tertiary;
      case BotDifficulty.medium:
        return AppColors.accentGold;
      case BotDifficulty.hard:
        return AppColors.vermilionRed;
      case BotDifficulty.veryHard:
        return AppColors.primary;
    }
  }

  IconData get _icon {
    switch (difficulty) {
      case BotDifficulty.veryEasy:
        return Icons.spa_outlined;
      case BotDifficulty.easy:
        return Icons.school_outlined;
      case BotDifficulty.medium:
        return Icons.military_tech_outlined;
      case BotDifficulty.hard:
        return Icons.shield_outlined;
      case BotDifficulty.veryHard:
        return Icons.auto_awesome;
    }
  }

  @override
  Widget build(BuildContext context) {
    final mode = variant == 'cup' ? 'cupbot' : 'bot';
    return CChessCard(
      onTap: () => context.go(
        '${AppConstants.routeGame}?mode=$mode&level=${difficulty.name}',
      ),
      borderColor: _accent.withValues(alpha: 0.5),
      child: Row(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: _accent.withValues(alpha: 0.14),
              shape: BoxShape.circle,
              border: Border.all(color: _accent.withValues(alpha: 0.4)),
            ),
            alignment: Alignment.center,
            child: Icon(_icon, color: _accent, size: 26),
          ),
          AppSpacing.hGapMd,
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(difficulty.nameVi, style: AppTextStyles.headingMd),
                    AppSpacing.hGapSm,
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 1,
                      ),
                      decoration: BoxDecoration(
                        color: _accent.withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        '~ELO ${difficulty.estimatedElo}',
                        style: AppTextStyles.captionSm.copyWith(
                          color: _accent,
                          fontWeight: FontWeight.w700,
                          fontSize: 10,
                        ),
                      ),
                    ),
                  ],
                ),
                AppSpacing.vGapXs,
                Text(
                  difficulty.descriptionVi,
                  style: AppTextStyles.captionSm.copyWith(
                    color: AppColors.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const Icon(Icons.chevron_right, color: AppColors.parchmentTan),
        ],
      ),
    );
  }
}

class _GrandmasterCard extends StatelessWidget {
  const _GrandmasterCard();

  @override
  Widget build(BuildContext context) {
    return CChessCard(
      onTap: () => context.go(
        '${AppConstants.routeGame}?mode=bot&level=${EngineLevel.grandmaster.apiName}',
      ),
      borderColor: AppColors.accentGold.withValues(alpha: 0.65),
      child: Row(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: AppColors.accentGold.withValues(alpha: 0.16),
              shape: BoxShape.circle,
              border: Border.all(
                color: AppColors.accentGold.withValues(alpha: 0.5),
              ),
            ),
            alignment: Alignment.center,
            child: const Icon(
              Icons.workspace_premium,
              color: AppColors.accentGold,
              size: 26,
            ),
          ),
          AppSpacing.hGapMd,
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text('Đại Sư+', style: AppTextStyles.headingMd),
                    AppSpacing.hGapSm,
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 1,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.accentGold.withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        'Pikafish',
                        style: AppTextStyles.captionSm.copyWith(
                          color: AppColors.accentGold,
                          fontWeight: FontWeight.w700,
                          fontSize: 10,
                        ),
                      ),
                    ),
                  ],
                ),
                AppSpacing.vGapXs,
                Text(
                  'Dùng Pikafish server-side khi online; mất mạng sẽ tự hạ về Đại Sư offline.',
                  style: AppTextStyles.captionSm.copyWith(
                    color: AppColors.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const Icon(Icons.chevron_right, color: AppColors.parchmentTan),
        ],
      ),
    );
  }
}
