import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants/app_constants.dart';
import '../../data/models/learning_lesson.dart';
import '../../data/repositories/learning_repository.dart';
import '../../data/repositories/puzzle_repository.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_text_styles.dart';
import '../../widgets/common/common.dart';

class BeginnerLessonDetailScreen extends ConsumerWidget {
  final String lessonId;

  const BeginnerLessonDetailScreen({super.key, required this.lessonId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final learningRepo = ref.watch(learningRepositoryProvider);
    final puzzleRepo = ref.watch(puzzleRepositoryProvider);
    final lesson = learningRepo.beginnerLessonById(lessonId);

    if (lesson == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Không tìm thấy bài học')),
        body: Center(
          child: Text(
            'Không tìm thấy bài học "$lessonId"',
            style: AppTextStyles.bodyMd,
          ),
        ),
      );
    }

    final nextLesson = learningRepo.nextBeginnerLesson(lesson.id);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.woodDark,
        title: Text(lesson.titleVi, overflow: TextOverflow.ellipsis),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go(AppConstants.routeBeginnerLessons),
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
            _LessonHeader(lesson: lesson),
            AppSpacing.vGapMd,
            for (final section in lesson.sections) ...[
              _LessonSectionCard(section: section),
              AppSpacing.vGapSm,
            ],
            _CheckpointCard(points: lesson.checkpoints),
            if (lesson.practicePuzzleIds.isNotEmpty) ...[
              AppSpacing.vGapSm,
              _PracticeCard(
                puzzleIds: lesson.practicePuzzleIds,
                puzzleTitleForId: (id) => puzzleRepo.puzzleById(id)?.titleVi,
              ),
            ],
            AppSpacing.vGapLg,
            _LessonActions(
              nextLesson: nextLesson,
              hasPractice: lesson.practicePuzzleIds.isNotEmpty,
            ),
          ],
        ),
      ),
    );
  }
}

class _LessonHeader extends StatelessWidget {
  final LearningLesson lesson;

  const _LessonHeader({required this.lesson});

  @override
  Widget build(BuildContext context) {
    return CChessCard(
      gradient: const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [AppColors.inkBlack, AppColors.woodDark],
      ),
      borderColor: AppColors.accentGold.withValues(alpha: 0.45),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: AppColors.accentGold.withValues(alpha: 0.16),
                  border: Border.all(color: AppColors.accentGold),
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: Text(
                  lesson.order.toString().padLeft(2, '0'),
                  style: AppTextStyles.monoTimer.copyWith(
                    color: AppColors.accentGold,
                    fontSize: 16,
                  ),
                ),
              ),
              AppSpacing.hGapMd,
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(lesson.titleVi, style: AppTextStyles.titleLg),
                    AppSpacing.vGapXs,
                    Text(
                      lesson.subtitleVi,
                      style: AppTextStyles.bodyMd.copyWith(
                        color: AppColors.onSurfaceVariant,
                        height: 1.5,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          AppSpacing.vGapMd,
          Wrap(
            spacing: AppSpacing.xs,
            runSpacing: AppSpacing.xs,
            children: [
              _MetaPill(
                Icons.timer_outlined,
                '${lesson.estimatedMinutes} phút',
              ),
              _MetaPill(Icons.signal_cellular_alt, lesson.levelLabel),
              for (final piece in lesson.focusPieces)
                _MetaPill(Icons.extension_outlined, piece),
            ],
          ),
        ],
      ),
    );
  }
}

class _LessonSectionCard extends StatelessWidget {
  final LessonSection section;

  const _LessonSectionCard({required this.section});

  @override
  Widget build(BuildContext context) {
    return CChessCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(section.title, style: AppTextStyles.headingMd),
          AppSpacing.vGapSm,
          Text(
            section.body,
            style: AppTextStyles.bodyMd.copyWith(
              color: AppColors.onSurface,
              height: 1.55,
            ),
          ),
          if (section.bullets.isNotEmpty) ...[
            AppSpacing.vGapMd,
            for (final bullet in section.bullets) ...[
              _BulletText(text: bullet),
              AppSpacing.vGapXs,
            ],
          ],
        ],
      ),
    );
  }
}

class _CheckpointCard extends StatelessWidget {
  final List<String> points;

  const _CheckpointCard({required this.points});

  @override
  Widget build(BuildContext context) {
    return CChessCard(
      borderColor: AppColors.tealSuccess.withValues(alpha: 0.45),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.fact_check_outlined,
                color: AppColors.tealSuccess,
                size: 18,
              ),
              AppSpacing.hGapSm,
              Text('Cần nắm sau bài này', style: AppTextStyles.headingMd),
            ],
          ),
          AppSpacing.vGapSm,
          for (final point in points) ...[
            _BulletText(
              text: point,
              color: AppColors.tealSuccess,
              icon: Icons.check_circle,
            ),
            AppSpacing.vGapXs,
          ],
        ],
      ),
    );
  }
}

class _PracticeCard extends StatelessWidget {
  final List<String> puzzleIds;
  final String? Function(String id) puzzleTitleForId;

  const _PracticeCard({
    required this.puzzleIds,
    required this.puzzleTitleForId,
  });

  @override
  Widget build(BuildContext context) {
    return CChessCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.extension_outlined,
                color: AppColors.vermilionRed,
                size: 18,
              ),
              AppSpacing.hGapSm,
              Text('Bài luyện gợi ý', style: AppTextStyles.headingMd),
            ],
          ),
          AppSpacing.vGapSm,
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              for (final id in puzzleIds)
                _PracticeChip(
                  label: puzzleTitleForId(id) ?? id,
                  onTap: () => context.go('${AppConstants.routePuzzle}/$id'),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _LessonActions extends StatelessWidget {
  final LearningLesson? nextLesson;
  final bool hasPractice;

  const _LessonActions({required this.nextLesson, required this.hasPractice});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: CChessButton(
            label: hasPractice ? 'Luyện tàn cục' : 'Kho tàn cục',
            variant: CChessButtonVariant.outline,
            icon: Icons.fort_outlined,
            fullWidth: true,
            onPressed: () => context.go(AppConstants.routePuzzle),
          ),
        ),
        AppSpacing.hGapMd,
        Expanded(
          child: CChessButton(
            label: nextLesson == null ? 'Về khóa học' : 'Bài tiếp',
            icon: nextLesson == null ? Icons.list_alt : Icons.skip_next,
            fullWidth: true,
            onPressed: () {
              final next = nextLesson;
              if (next == null) {
                context.go(AppConstants.routeBeginnerLessons);
              } else {
                context.go('${AppConstants.routeBeginnerLessons}/${next.id}');
              }
            },
          ),
        ),
      ],
    );
  }
}

class _BulletText extends StatelessWidget {
  final String text;
  final Color color;
  final IconData icon;

  const _BulletText({
    required this.text,
    this.color = AppColors.accentGold,
    this.icon = Icons.circle,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 5),
          child: Icon(icon, color: color, size: icon == Icons.circle ? 7 : 14),
        ),
        AppSpacing.hGapSm,
        Expanded(
          child: Text(text, style: AppTextStyles.bodyMd.copyWith(height: 1.45)),
        ),
      ],
    );
  }
}

class _MetaPill extends StatelessWidget {
  final IconData icon;
  final String label;

  const _MetaPill(this.icon, this.label);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: 4,
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

class _PracticeChip extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _PracticeChip({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      borderRadius: AppRadius.chip,
      child: InkWell(
        borderRadius: AppRadius.chip,
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(maxWidth: 220),
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.sm,
            vertical: 6,
          ),
          decoration: BoxDecoration(
            color: AppColors.vermilionRed.withValues(alpha: 0.12),
            borderRadius: AppRadius.chip,
            border: Border.all(
              color: AppColors.vermilionRed.withValues(alpha: 0.45),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.play_arrow,
                color: AppColors.vermilionRed,
                size: 14,
              ),
              AppSpacing.hGapXs,
              Flexible(
                child: Text(
                  label,
                  style: AppTextStyles.captionSm.copyWith(
                    color: AppColors.onSurface,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
