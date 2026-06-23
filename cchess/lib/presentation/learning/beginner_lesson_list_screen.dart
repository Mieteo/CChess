import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants/app_constants.dart';
import '../../data/models/learning_lesson.dart';
import '../../data/repositories/learning_repository.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_text_styles.dart';
import '../../widgets/common/common.dart';

class BeginnerLessonListScreen extends ConsumerWidget {
  const BeginnerLessonListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.watch(learningRepositoryProvider);
    final lessons = repo.beginnerLessons();
    final totalMinutes = lessons.fold<int>(
      0,
      (sum, lesson) => sum + lesson.estimatedMinutes,
    );

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.woodDark,
        title: const Text('Khóa Học Vỡ Lòng'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go(AppConstants.routeLearning),
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.base,
            AppSpacing.base,
            AppSpacing.base,
            AppSpacing.xl,
          ),
          children: [
            _CourseHeader(
              lessonCount: lessons.length,
              totalMinutes: totalMinutes,
            ),
            AppSpacing.vGapLg,
            const SectionHeader(title: 'Lộ Trình Khai Tâm'),
            AppSpacing.vGapMd,
            for (final lesson in lessons) ...[
              _LessonCard(lesson: lesson),
              AppSpacing.vGapSm,
            ],
          ],
        ),
      ),
    );
  }
}

class _CourseHeader extends StatelessWidget {
  final int lessonCount;
  final int totalMinutes;

  const _CourseHeader({required this.lessonCount, required this.totalMinutes});

  @override
  Widget build(BuildContext context) {
    return CChessCard(
      gradient: const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [AppColors.charcoalDark, AppColors.woodDark],
      ),
      borderColor: AppColors.tealSuccess.withValues(alpha: 0.45),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: AppColors.tealSuccess.withValues(alpha: 0.16),
                  border: Border.all(color: AppColors.tealSuccess),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.school_outlined,
                  color: AppColors.tealSuccess,
                ),
              ),
              AppSpacing.hGapMd,
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Vỡ lòng Cờ Tướng', style: AppTextStyles.titleLg),
                    AppSpacing.vGapXs,
                    Text(
                      '$lessonCount bài • khoảng $totalMinutes phút',
                      style: AppTextStyles.captionSm.copyWith(
                        color: AppColors.parchmentTan,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          AppSpacing.vGapMd,
          Text(
            'Học luật đi quân, chống Tướng, chiếu bí và thói quen đọc thế cờ trước khi luyện tàn cục.',
            style: AppTextStyles.bodyMd.copyWith(
              color: AppColors.onSurface,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}

class _LessonCard extends StatelessWidget {
  final LearningLesson lesson;

  const _LessonCard({required this.lesson});

  @override
  Widget build(BuildContext context) {
    return CChessCard(
      onTap: () =>
          context.go('${AppConstants.routeBeginnerLessons}/${lesson.id}'),
      borderColor: lesson.order == 1
          ? AppColors.tealSuccess.withValues(alpha: 0.55)
          : AppColors.outlineVariant,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: AppColors.surfaceContainerHigh,
              border: Border.all(color: AppColors.accentGold),
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: Text(
              lesson.order.toString().padLeft(2, '0'),
              style: AppTextStyles.monoSm.copyWith(color: AppColors.accentGold),
            ),
          ),
          AppSpacing.hGapMd,
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        lesson.titleVi,
                        style: AppTextStyles.headingMd,
                      ),
                    ),
                    const Icon(
                      Icons.chevron_right,
                      color: AppColors.parchmentTan,
                    ),
                  ],
                ),
                AppSpacing.vGapXs,
                Text(
                  lesson.subtitleVi,
                  style: AppTextStyles.captionSm.copyWith(
                    color: AppColors.onSurfaceVariant,
                    height: 1.45,
                  ),
                ),
                AppSpacing.vGapSm,
                Wrap(
                  spacing: AppSpacing.xs,
                  runSpacing: AppSpacing.xs,
                  children: [
                    _InfoChip(
                      icon: Icons.timer_outlined,
                      label: '${lesson.estimatedMinutes} phút',
                    ),
                    _InfoChip(
                      icon: Icons.signal_cellular_alt,
                      label: lesson.levelLabel,
                    ),
                    for (final piece in lesson.focusPieces.take(2))
                      _InfoChip(icon: Icons.extension_outlined, label: piece),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  final IconData icon;
  final String label;

  const _InfoChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: 3,
      ),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerHighest,
        borderRadius: AppRadius.chip,
        border: Border.all(color: AppColors.outlineVariant),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: AppColors.accentGold),
          AppSpacing.hGapXs,
          Text(label, style: AppTextStyles.captionSm.copyWith(fontSize: 11)),
        ],
      ),
    );
  }
}
