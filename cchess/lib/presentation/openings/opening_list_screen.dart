import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants/app_constants.dart';
import '../../data/models/opening.dart';
import '../../data/repositories/opening_repository.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_text_styles.dart';
import '../../widgets/common/common.dart';

class OpeningListScreen extends ConsumerWidget {
  const OpeningListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.watch(openingRepositoryProvider);
    final openings = repo.sortedByPopularity();

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.woodDark,
        title: const Text('Khai Cuộc Đại Sư'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go(AppConstants.routeLearning),
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.base),
          children: [
            CChessCard(
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [AppColors.charcoalDark, AppColors.woodDark],
              ),
              borderColor: AppColors.accentGold.withValues(alpha: 0.4),
              child: Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppColors.accentGold.withValues(alpha: 0.18),
                      border: Border.all(color: AppColors.accentGold),
                    ),
                    child: const Icon(Icons.map_outlined,
                        color: AppColors.accentGold),
                  ),
                  AppSpacing.hGapMd,
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Học khai cuộc kinh điển',
                          style: AppTextStyles.headingMd,
                        ),
                        AppSpacing.vGapXs,
                        Text(
                          '${openings.length} thế khai cuộc — đi từng nước, '
                          'đọc ý đồ chiến lược.',
                          style: AppTextStyles.captionSm.copyWith(
                            color: AppColors.parchmentTan,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            AppSpacing.vGapLg,
            const SectionHeader(title: 'Khai cuộc phổ biến'),
            AppSpacing.vGapMd,
            for (final o in openings) ...[
              _OpeningCard(opening: o),
              AppSpacing.vGapSm,
            ],
          ],
        ),
      ),
    );
  }
}

class _OpeningCard extends StatelessWidget {
  final Opening opening;
  const _OpeningCard({required this.opening});

  @override
  Widget build(BuildContext context) {
    return CChessCard(
      onTap: () =>
          context.go('${AppConstants.routeOpenings}/${opening.id}'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(opening.nameVi, style: AppTextStyles.headingMd),
                    Text(
                      opening.nameHan,
                      style: AppTextStyles.captionSm.copyWith(
                        color: AppColors.accentGold,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.sm,
                  vertical: 2,
                ),
                decoration: BoxDecoration(
                  color: AppColors.surfaceContainerHigh,
                  borderRadius: AppRadius.chip,
                  border: Border.all(color: AppColors.outlineVariant),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (int i = 1; i <= 5; i++)
                      Icon(
                        Icons.local_fire_department,
                        size: 11,
                        color: i <= opening.popularity
                            ? AppColors.vermilionRed
                            : AppColors.parchmentTan
                                .withValues(alpha: 0.4),
                      ),
                  ],
                ),
              ),
            ],
          ),
          AppSpacing.vGapXs,
          Text(
            opening.tagline,
            style: AppTextStyles.captionSm.copyWith(
              color: AppColors.parchmentTan,
              fontStyle: FontStyle.italic,
            ),
          ),
          AppSpacing.vGapSm,
          Row(
            children: [
              for (int i = 1; i <= 5; i++)
                Icon(
                  i <= opening.difficulty ? Icons.star : Icons.star_outline,
                  size: 14,
                  color: AppColors.accentGold,
                ),
              AppSpacing.hGapSm,
              Text(
                '${opening.moveCount} nước',
                style: AppTextStyles.captionSm.copyWith(
                  color: AppColors.onSurfaceVariant,
                ),
              ),
              const Spacer(),
              const Icon(Icons.chevron_right, color: AppColors.parchmentTan),
            ],
          ),
        ],
      ),
    );
  }
}
