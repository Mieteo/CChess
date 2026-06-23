import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/chess_engine/chess_engine.dart';
import '../../core/constants/app_constants.dart';
import '../../data/models/game_record.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_text_styles.dart';
import '../../widgets/common/common.dart';
import '../replay/replay_controller.dart' show replayRecordProvider;
import 'ai_coach_controller.dart';

/// AI Coach (spec B3): grades a saved game and gives the player phase-by-phase
/// feedback plus what to practise next.
///
/// Opened either for a specific game (`/ai-coach/:id`) or generically
/// (`/ai-coach`), in which case it coaches the most recent finished game.
class AiCoachScreen extends ConsumerWidget {
  final String? recordId;
  const AiCoachScreen({super.key, this.recordId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final id = recordId;
    final recordAsync = id != null
        ? ref.watch(replayRecordProvider(id))
        : ref.watch(latestCoachGameProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.woodDark,
        title: const Text('Gia Sư AI'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.canPop()
              ? context.pop()
              : context.go(AppConstants.routeLearning),
        ),
      ),
      body: SafeArea(
        child: recordAsync.when(
          loading: () => const Center(child: BrushStrokeSpinner()),
          error: (e, _) => _CenteredMessage(
            icon: Icons.error_outline,
            color: AppColors.error,
            title: 'Không tải được ván đấu',
            detail: '$e',
          ),
          data: (record) {
            if (record == null) {
              return const _CenteredMessage(
                icon: Icons.psychology_alt_outlined,
                color: AppColors.parchmentTan,
                title: 'Chưa có ván để phân tích',
                detail:
                    'Hãy chơi xong một ván (với bot hoặc online) rồi quay lại — '
                    'Gia Sư AI sẽ chỉ ra điểm mạnh, điểm yếu của bạn.',
              );
            }
            return _CoachBody(record: record);
          },
        ),
      ),
    );
  }
}

class _CoachBody extends ConsumerWidget {
  final GameRecord record;
  const _CoachBody({required this.record});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(aiCoachControllerProvider(record));

    if (state.loading) {
      return Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const BrushStrokeSpinner(),
          AppSpacing.vGapMd,
          Text(
            'Đang phân tích ${record.moves.length} nước đi…',
            style: AppTextStyles.bodyMd
                .copyWith(color: AppColors.onSurfaceVariant),
          ),
        ],
      );
    }

    if (state.error != null) {
      return _CenteredMessage(
        icon: Icons.cloud_off,
        color: AppColors.error,
        title: 'Phân tích thất bại',
        detail: 'Đã xảy ra lỗi khi phân tích ván đấu.',
        action: FilledButton.icon(
          onPressed: () =>
              ref.read(aiCoachControllerProvider(record).notifier).retry(),
          icon: const Icon(Icons.refresh),
          label: const Text('Thử lại'),
        ),
      );
    }

    final report = state.report!;
    if (report.isEmpty) {
      return const _CenteredMessage(
        icon: Icons.psychology_alt_outlined,
        color: AppColors.parchmentTan,
        title: 'Không có nước nào của bạn để chấm',
        detail: 'Ván này không có nước đi nào thuộc về bạn để phân tích.',
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.base,
        AppSpacing.base,
        AppSpacing.base,
        96,
      ),
      children: [
        _OverviewCard(record: record, report: report),
        AppSpacing.vGapLg,
        const SectionHeader(title: 'Theo Giai Đoạn'),
        AppSpacing.vGapSm,
        for (final phase in GamePhase.values)
          _PhaseRow(
            report: report.phaseReport(phase),
            isWeakest: report.weakestPhase == phase,
          ),
        AppSpacing.vGapLg,
        const SectionHeader(title: 'Nhận Xét & Gợi Ý'),
        AppSpacing.vGapSm,
        for (final insight in report.insights)
          _InsightCard(insight: insight, record: record),
        if (report.criticalMoments.isNotEmpty) ...[
          AppSpacing.vGapLg,
          const SectionHeader(title: 'Nước Bước Ngoặt'),
          AppSpacing.vGapSm,
          for (final m in report.criticalMoments) _CriticalMomentRow(move: m),
          AppSpacing.vGapMd,
          CChessButton(
            label: 'Xem lại toàn ván',
            onPressed: () =>
                context.push('${AppConstants.routeReplay}/${record.id}'),
          ),
        ],
      ],
    );
  }
}

class _OverviewCard extends StatelessWidget {
  final GameRecord record;
  final CoachReport report;
  const _OverviewCard({required this.record, required this.report});

  @override
  Widget build(BuildContext context) {
    final acc = report.overallAccuracy;
    final color = _accuracyColor(acc);
    final sideVi =
        report.playerColor == PieceColor.red ? 'Bên Đỏ' : 'Bên Đen';
    return CChessCard(
      gradient: const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [AppColors.inkBlack, AppColors.woodDark],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Phân tích cho $sideVi  •  vs ${record.opponentLabel}',
            style: AppTextStyles.captionSm
                .copyWith(color: AppColors.parchmentTan),
          ),
          AppSpacing.vGapMd,
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                acc.toStringAsFixed(0),
                style: AppTextStyles.titleLg.copyWith(
                  color: color,
                  fontSize: 48,
                  height: 1.0,
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(bottom: 8, left: 2),
                child: Text('%',
                    style: AppTextStyles.titleLg.copyWith(color: color)),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.sm, vertical: 4),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.16),
                  borderRadius: AppRadius.chip,
                  border: Border.all(color: color.withValues(alpha: 0.5)),
                ),
                child: Text(
                  report.gradeVi,
                  style: AppTextStyles.headingMd.copyWith(color: color),
                ),
              ),
            ],
          ),
          AppSpacing.vGapXs,
          Text(
            'Độ chính xác tổng thể',
            style: AppTextStyles.captionSm
                .copyWith(color: AppColors.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

class _PhaseRow extends StatelessWidget {
  final PhaseReport report;
  final bool isWeakest;
  const _PhaseRow({required this.report, required this.isWeakest});

  @override
  Widget build(BuildContext context) {
    final hasData = report.hasData;
    final color = hasData ? _accuracyColor(report.accuracy) : AppColors.outlineVariant;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: CChessCard(
        borderColor: isWeakest ? AppColors.accentGold.withValues(alpha: 0.6) : null,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(report.phase.nameVi, style: AppTextStyles.headingMd),
                if (isWeakest) ...[
                  AppSpacing.hGapSm,
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                    decoration: BoxDecoration(
                      color: AppColors.accentGold.withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      'CẦN LUYỆN',
                      style: AppTextStyles.captionSm.copyWith(
                        color: AppColors.accentGold,
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
                const Spacer(),
                Text(
                  hasData ? '${report.accuracy.toStringAsFixed(0)}%' : '—',
                  style: AppTextStyles.headingMd.copyWith(color: color),
                ),
              ],
            ),
            AppSpacing.vGapSm,
            _Bar(fraction: hasData ? report.accuracy / 100 : 0, color: color),
            AppSpacing.vGapXs,
            Text(
              hasData
                  ? '${report.moveCount} nước • ${report.errorCount} nước chưa tối ưu'
                  : 'Không có nước nào trong giai đoạn này',
              style: AppTextStyles.captionSm
                  .copyWith(color: AppColors.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}

class _Bar extends StatelessWidget {
  final double fraction;
  final Color color;
  const _Bar({required this.fraction, required this.color});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: Container(
        height: 8,
        color: AppColors.surfaceContainerHighest,
        child: FractionallySizedBox(
          alignment: Alignment.centerLeft,
          widthFactor: fraction.clamp(0.0, 1.0),
          child: Container(color: color),
        ),
      ),
    );
  }
}

class _InsightCard extends StatelessWidget {
  final CoachInsight insight;
  final GameRecord record;
  const _InsightCard({required this.insight, required this.record});

  @override
  Widget build(BuildContext context) {
    final (icon, color) = _toneVisual(insight.tone);
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: CChessCard(
        borderColor: color.withValues(alpha: 0.4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon, color: color, size: 20),
                AppSpacing.hGapSm,
                Expanded(
                  child: Text(insight.title, style: AppTextStyles.headingMd),
                ),
              ],
            ),
            AppSpacing.vGapXs,
            Text(
              insight.detail,
              style: AppTextStyles.bodyMd
                  .copyWith(color: AppColors.onSurfaceVariant),
            ),
            if (insight.action != null) ...[
              AppSpacing.vGapSm,
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  style: TextButton.styleFrom(foregroundColor: color),
                  onPressed: () => _runAction(context, insight.action!),
                  icon: Icon(_actionIcon(insight.action!), size: 18),
                  label: Text(_actionLabel(insight.action!)),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  void _runAction(BuildContext context, CoachActionKind action) {
    switch (action) {
      case CoachActionKind.reviewMoves:
        context.push('${AppConstants.routeReplay}/${record.id}');
        break;
      case CoachActionKind.practicePuzzles:
        context.go(AppConstants.routePuzzle);
        break;
      case CoachActionKind.studyOpenings:
        context.go(AppConstants.routeOpenings);
        break;
      case CoachActionKind.takeLessons:
        context.go(AppConstants.routeLearning);
        break;
    }
  }
}

class _CriticalMomentRow extends StatelessWidget {
  final MoveAnalysis move;
  const _CriticalMomentRow({required this.move});

  @override
  Widget build(BuildContext context) {
    final sideVi = move.mover == PieceColor.red ? 'Đỏ' : 'Đen';
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xs),
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.sm),
        decoration: BoxDecoration(
          color: AppColors.surfaceContainerHighest,
          border: Border.all(color: move.quality.color.withValues(alpha: 0.5)),
          borderRadius: AppRadius.card,
        ),
        child: Row(
          children: [
            Icon(move.quality.icon, color: move.quality.color, size: 20),
            AppSpacing.hGapSm,
            Expanded(
              child: Text(
                'Nước ${move.moveIndex + 1} ($sideVi) — ${move.quality.nameVi}',
                style: AppTextStyles.bodyMd,
              ),
            ),
            Text(
              'mất ~${move.centipawnLoss} điểm',
              style: AppTextStyles.captionSm
                  .copyWith(color: AppColors.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}

class _CenteredMessage extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String detail;
  final Widget? action;
  const _CenteredMessage({
    required this.icon,
    required this.color,
    required this.title,
    required this.detail,
    this.action,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 56),
            AppSpacing.vGapMd,
            Text(title, style: AppTextStyles.titleLg, textAlign: TextAlign.center),
            AppSpacing.vGapSm,
            Text(
              detail,
              style: AppTextStyles.bodyMd
                  .copyWith(color: AppColors.onSurfaceVariant),
              textAlign: TextAlign.center,
            ),
            if (action != null) ...[AppSpacing.vGapMd, action!],
          ],
        ),
      ),
    );
  }
}

Color _accuracyColor(double acc) {
  if (acc >= 80) return AppColors.tealSuccess;
  if (acc >= 65) return AppColors.accentGold;
  return AppColors.error;
}

(IconData, Color) _toneVisual(CoachTone tone) {
  switch (tone) {
    case CoachTone.praise:
      return (Icons.verified_outlined, AppColors.tealSuccess);
    case CoachTone.tip:
      return (Icons.lightbulb_outline, AppColors.accentGold);
    case CoachTone.warning:
      return (Icons.warning_amber_rounded, AppColors.error);
  }
}

IconData _actionIcon(CoachActionKind action) {
  switch (action) {
    case CoachActionKind.reviewMoves:
      return Icons.replay;
    case CoachActionKind.practicePuzzles:
      return Icons.extension;
    case CoachActionKind.studyOpenings:
      return Icons.map_outlined;
    case CoachActionKind.takeLessons:
      return Icons.menu_book_outlined;
  }
}

String _actionLabel(CoachActionKind action) {
  switch (action) {
    case CoachActionKind.reviewMoves:
      return 'Xem lại các nước';
    case CoachActionKind.practicePuzzles:
      return 'Luyện bài tập';
    case CoachActionKind.studyOpenings:
      return 'Học khai cuộc';
    case CoachActionKind.takeLessons:
      return 'Vào khóa học';
  }
}
