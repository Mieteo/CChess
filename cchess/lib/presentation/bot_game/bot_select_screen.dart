import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/chess_engine/chess_engine.dart';
import '../../core/constants/app_constants.dart';
import '../../core/constants/elo_constants.dart';
import '../../core/matchmaking/bot_matchmaker.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_text_styles.dart';
import '../../widgets/common/common.dart';
import '../profile/profile_controller.dart';

/// Entry screen for CPU games.
///
/// * `standard` Xiangqi → ELO matchmaking ("Tìm trận"): the player is paired
///   with a hidden-strength bot around their ELO; no difficulty tiers.
/// * `cup` (Cờ Úp) → keeps the offline difficulty cards, because the cup-aware
///   bot can't read hidden pieces (Pikafish / ELO matchmaking don't apply).
class BotSelectScreen extends ConsumerWidget {
  final String variant;

  const BotSelectScreen({super.key, this.variant = 'standard'});

  bool get _isCup => variant == 'cup';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.woodDark,
        title: Text(_isCup ? 'Cờ Úp với Máy' : 'Luyện tập với Bot'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go(AppConstants.routeHome),
        ),
      ),
      body: SafeArea(
        child: _isCup ? const _CupDifficultyList() : _Matchmaking(ref: ref),
      ),
    );
  }
}

/// Standard ELO matchmaking: shows the player's current ELO + a "Tìm trận"
/// button that pairs them with a hidden bot around their level.
class _Matchmaking extends StatelessWidget {
  const _Matchmaking({required this.ref});

  final WidgetRef ref;

  void _findMatch(BuildContext context, int playerElo) {
    final match = pickBot(playerElo);
    context.go(
      '${AppConstants.routeGame}?mode=bot'
      '&botElo=${match.botElo}&bracket=${match.bracket.name}',
    );
  }

  @override
  Widget build(BuildContext context) {
    final playerElo =
        ref.watch(profileControllerProvider).valueOrNull?.eloChess ??
        EloConstants.initialElo;

    return Padding(
      padding: const EdgeInsets.all(AppSpacing.base),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          CChessCard(
            child: Column(
              children: [
                Text(
                  'ELO của bạn',
                  style: AppTextStyles.bodyMd.copyWith(
                    color: AppColors.onSurfaceVariant,
                  ),
                ),
                AppSpacing.vGapXs,
                Text(
                  '$playerElo',
                  style: AppTextStyles.displayCalligraphy.copyWith(
                    fontSize: 48,
                    color: AppColors.accentGold,
                  ),
                ),
              ],
            ),
          ),
          AppSpacing.vGapLg,
          Text(
            'Ghép trận theo trình độ',
            style: AppTextStyles.titleLg,
          ),
          AppSpacing.vGapXs,
          Text(
            'Hệ thống sẽ ghép bạn với một Bot quanh ELO của bạn — có thể ngang '
            'sức, mạnh hơn hoặc yếu hơn một chút. Trình độ của Bot được giữ kín '
            'trong ván và chỉ lộ ở màn kết quả. Thắng Bot mạnh hơn được nhiều '
            'điểm hơn; thắng Bot yếu hơn được ít điểm hơn.',
            style: AppTextStyles.bodyMd.copyWith(
              color: AppColors.onSurfaceVariant,
            ),
          ),
          const Spacer(),
          CChessButton(
            label: 'Tìm trận',
            icon: Icons.search,
            fullWidth: true,
            onPressed: () => _findMatch(context, playerElo),
          ),
          AppSpacing.vGapMd,
        ],
      ),
    );
  }
}

/// Cờ Úp keeps the offline difficulty tiers (the cup bot is depth-based and
/// can't use Pikafish / ELO matchmaking).
class _CupDifficultyList extends StatelessWidget {
  const _CupDifficultyList();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.base),
      children: [
        Text('Bot Cờ Úp offline', style: AppTextStyles.titleLg),
        AppSpacing.vGapXs,
        Text(
          'Máy chỉ thấy mặt phủ và quân đã lộ như bạn — định giá quân úp theo '
          'kỳ vọng. Cấp càng cao tính càng sâu.',
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
        '${AppConstants.routeGame}?mode=cupbot&level=${difficulty.name}',
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
                Text(difficulty.nameVi, style: AppTextStyles.headingMd),
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
