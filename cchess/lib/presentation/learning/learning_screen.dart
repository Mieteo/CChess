import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants/app_constants.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_text_styles.dart';
import '../../widgets/common/common.dart';

/// Học Tập (Học Cờ) hub screen.
class LearningScreen extends StatelessWidget {
  const LearningScreen({super.key});

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
        _Header(),
        AppSpacing.vGapLg,
        _DailyChallengeBanner(
          onTry: () => context.go('${AppConstants.routePuzzle}/p003'),
        ),
        AppSpacing.vGapLg,
        const _SectionGrid(),
        AppSpacing.vGapLg,
        const SectionHeader(title: 'Hoạt Động Gần Đây'),
        AppSpacing.vGapSm,
        const _RecentActivityList(),
      ],
    );
  }
}

class _Header extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Học Cờ', style: AppTextStyles.titleLg),
              AppSpacing.vGapXs,
              Text(
                'Nâng cao trình độ mỗi ngày',
                style: AppTextStyles.captionSm.copyWith(
                  color: AppColors.onSurfaceVariant,
                ),
              ),
              AppSpacing.vGapMd,
              CChessProgressBar(value: 0.66),
              AppSpacing.vGapXs,
              Text(
                'Nhiệm vụ học hôm nay: 2/3 hoàn thành',
                style: AppTextStyles.captionSm.copyWith(
                  color: AppColors.accentGold,
                ),
                textAlign: TextAlign.end,
              ),
            ],
          ),
        ),
        AppSpacing.hGapMd,
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: AppColors.surfaceContainerHigh,
            border: Border.all(color: AppColors.outlineVariant),
            shape: BoxShape.circle,
          ),
          child: const Icon(
            Icons.lightbulb_outline,
            color: AppColors.accentGold,
          ),
        ),
      ],
    );
  }
}

class _DailyChallengeBanner extends StatelessWidget {
  final VoidCallback onTry;
  const _DailyChallengeBanner({required this.onTry});

  @override
  Widget build(BuildContext context) {
    return CChessCard(
      gradient: const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [AppColors.inkBlack, AppColors.woodDark],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.sm,
              vertical: 2,
            ),
            decoration: BoxDecoration(
              color: AppColors.vermilionRed.withValues(alpha: 0.2),
              borderRadius: AppRadius.chip,
              border: Border.all(
                color: AppColors.vermilionRed.withValues(alpha: 0.5),
              ),
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
          AppSpacing.vGapSm,
          Text('Tàn Cục Thách Đấu Hôm Nay', style: AppTextStyles.titleLg),
          AppSpacing.vGapXs,
          Row(
            children: [
              const Icon(Icons.timer, size: 16, color: AppColors.parchmentTan),
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
            onPressed: onTry,
          ),
        ],
      ),
    );
  }
}

class _SectionGrid extends StatelessWidget {
  const _SectionGrid();

  @override
  Widget build(BuildContext context) {
    final items = <_LearningTile>[
      _LearningTile(
        title: 'Khóa Học\nVỡ Lòng',
        icon: Icons.menu_book_outlined,
        color: AppColors.tealSuccess,
        badge: 'MỚI',
        badgeColor: AppColors.tealSuccess,
        onTap: () => context.go(AppConstants.routeBeginnerLessons),
      ),
      _LearningTile(
        title: 'Bài Tập\nTàn Cục',
        icon: Icons.fort_outlined,
        color: AppColors.vermilionRed,
        onTap: () => context.go(AppConstants.routePuzzle),
      ),
      _LearningTile(
        title: 'Kỳ Phổ &\nPhục Bàn',
        icon: Icons.history_edu,
        color: AppColors.accentGold,
        onTap: () {},
      ),
      _LearningTile(
        title: 'AI Tư Vấn',
        icon: Icons.smart_toy_outlined,
        color: const Color(0xFFD8B4FE),
        badge: 'VIP',
        badgeColor: AppColors.accentGold,
        onTap: () => context.push(AppConstants.routeAiCoach),
      ),
      _LearningTile(
        title: 'Khai Cuộc\nĐại Sư',
        icon: Icons.map_outlined,
        color: const Color(0xFFFDBA74),
        onTap: () => context.go(AppConstants.routeOpenings),
      ),
      _LearningTile(
        title: 'Chụp Nhận\nDiện Cờ',
        icon: Icons.photo_camera_outlined,
        color: AppColors.onSurface,
        badge: 'HOT',
        badgeColor: AppColors.vermilionRed,
        onTap: () {},
      ),
    ];
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: AppSpacing.md,
        crossAxisSpacing: AppSpacing.md,
        childAspectRatio: 1.0,
      ),
      itemCount: items.length,
      itemBuilder: (_, i) => items[i],
    );
  }
}

class _LearningTile extends StatelessWidget {
  final String title;
  final IconData icon;
  final Color color;
  final String? badge;
  final Color? badgeColor;
  final VoidCallback onTap;

  const _LearningTile({
    required this.title,
    required this.icon,
    required this.color,
    this.badge,
    this.badgeColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return CChessCard(
      onTap: onTap,
      padding: const EdgeInsets.all(AppSpacing.base),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    border: Border.all(color: color.withValues(alpha: 0.3)),
                    shape: BoxShape.circle,
                  ),
                  alignment: Alignment.center,
                  child: Icon(icon, color: color, size: 24),
                ),
                AppSpacing.vGapSm,
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: AppTextStyles.headingMd,
                ),
              ],
            ),
          ),
          if (badge != null)
            Positioned(
              top: -8,
              right: -8,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: badgeColor ?? AppColors.accentGold,
                  borderRadius: const BorderRadius.only(
                    bottomLeft: Radius.circular(8),
                    topRight: Radius.circular(12),
                  ),
                ),
                child: Text(
                  badge!,
                  style: AppTextStyles.captionSm.copyWith(
                    color:
                        badgeColor == AppColors.vermilionRed ||
                            badgeColor == AppColors.tealSuccess
                        ? Colors.white
                        : AppColors.surfaceContainerLowest,
                    fontWeight: FontWeight.w700,
                    fontSize: 10,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _RecentActivityList extends StatelessWidget {
  const _RecentActivityList();

  @override
  Widget build(BuildContext context) {
    final items = <(String, bool, String)>[
      ('Bài vỡ lòng: Xe mở đường thẳng', true, 'Hôm nay'),
      ('Tàn cục: Chiếu hết trong 1 nước', true, 'Hôm qua'),
      ('Bài vỡ lòng: Pháo cần ngòi', false, 'Đang học'),
    ];
    return Column(
      children: [
        for (final (title, ok, ago) in items)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.xs),
            child: Container(
              padding: const EdgeInsets.all(AppSpacing.sm),
              decoration: BoxDecoration(
                color: AppColors.surfaceContainerHighest,
                border: Border.all(
                  color: AppColors.outlineVariant.withValues(alpha: 0.5),
                ),
                borderRadius: AppRadius.card,
              ),
              child: Row(
                children: [
                  Icon(
                    ok ? Icons.check_circle : Icons.cancel,
                    color: ok ? AppColors.tealSuccess : AppColors.error,
                    size: 20,
                  ),
                  AppSpacing.hGapSm,
                  Expanded(
                    child: Text(
                      title,
                      style: AppTextStyles.bodyMd.copyWith(
                        color: ok
                            ? AppColors.onSurface
                            : AppColors.onSurface.withValues(alpha: 0.8),
                      ),
                    ),
                  ),
                  Text(
                    ago,
                    style: AppTextStyles.captionSm.copyWith(
                      color: AppColors.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
