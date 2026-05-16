import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/chess_engine/ai/bot_difficulty.dart';
import '../../core/constants/app_constants.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_text_styles.dart';
import '../../widgets/common/common.dart';

/// Screen where the user picks a bot difficulty before starting a CPU game.
class BotSelectScreen extends StatelessWidget {
  const BotSelectScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.woodDark,
        title: const Text('Chọn cấp độ Bot'),
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
              'Bot AI offline',
              style: AppTextStyles.titleLg,
            ),
            AppSpacing.vGapXs,
            Text(
              'Mỗi cấp độ tính trước số nước khác nhau. Càng cao càng chậm và khó.',
              style: AppTextStyles.bodyMd.copyWith(
                color: AppColors.onSurfaceVariant,
              ),
            ),
            AppSpacing.vGapLg,
            for (final difficulty in BotDifficulty.values) ...[
              _BotCard(difficulty: difficulty),
              AppSpacing.vGapMd,
            ],
          ],
        ),
      ),
    );
  }
}

class _BotCard extends StatelessWidget {
  final BotDifficulty difficulty;

  const _BotCard({required this.difficulty});

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
    return CChessCard(
      onTap: () => context.go(
        '${AppConstants.routeGame}?mode=bot&level=${difficulty.name}',
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
