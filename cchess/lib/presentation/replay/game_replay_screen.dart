import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/chess_engine/chess_engine.dart';
import '../../core/constants/app_constants.dart';
import '../../data/models/game_record.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_text_styles.dart';
import '../../widgets/chess/chess_board.dart';
import '../../widgets/common/common.dart';
import 'replay_controller.dart';

class GameReplayScreen extends ConsumerWidget {
  final String recordId;

  const GameReplayScreen({super.key, required this.recordId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncRecord = ref.watch(replayRecordProvider(recordId));
    return asyncRecord.when(
      loading: () => _wrap(context, child: const Center(child: BrushStrokeSpinner())),
      error: (e, _) => _wrap(context, child: Center(child: Text('Lỗi: $e'))),
      data: (record) {
        if (record == null) {
          return _wrap(
            context,
            child: Center(
              child: Text(
                'Không tìm thấy kỳ phổ "$recordId"',
                style: AppTextStyles.bodyMd,
              ),
            ),
          );
        }
        return _ReplayBody(record: record);
      },
    );
  }

  Widget _wrap(BuildContext context, {required Widget child}) => Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          backgroundColor: AppColors.woodDark,
          title: const Text('Phục Bàn'),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => context.go(AppConstants.routeHistory),
          ),
        ),
        body: SafeArea(child: child),
      );
}

class _ReplayBody extends ConsumerWidget {
  final GameRecord record;
  const _ReplayBody({required this.record});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(replayControllerProvider(record));
    final controller = ref.read(replayControllerProvider(record).notifier);

    final currentAnalysis = state.analysis != null && state.currentPly > 0
        ? _findMoveAnalysis(state.analysis!, state.currentPly - 1)
        : null;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.woodDark,
        title: const Text('Phục Bàn'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go(AppConstants.routeHistory),
        ),
        actions: [
          IconButton(
            icon: Icon(
              state.coachMode
                  ? Icons.smart_toy
                  : Icons.smart_toy_outlined,
              color: state.coachMode ? AppColors.accentGold : null,
            ),
            tooltip: 'Bật / tắt AI Coach',
            onPressed: controller.toggleCoachMode,
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.sm),
          child: Column(
            children: [
              _ReplayHeader(record: state.record),
              AppSpacing.vGapSm,
              Expanded(
                child: AspectRatio(
                  aspectRatio: 9 / 10,
                  child: ChessBoard(
                    board: state.board,
                    lastMove: state.lastMove,
                  ),
                ),
              ),
              AppSpacing.vGapSm,
              if (state.coachMode)
                _CoachStrip(
                  state: state,
                  currentMoveAnalysis: currentAnalysis,
                ),
              if (state.coachMode) AppSpacing.vGapSm,
              _TransportBar(state: state, controller: controller),
              AppSpacing.vGapSm,
              SizedBox(
                height: 70,
                child: _MoveList(state: state, controller: controller),
              ),
            ],
          ),
        ),
      ),
    );
  }

  MoveAnalysis? _findMoveAnalysis(GameAnalysis analysis, int moveIndex) {
    for (final m in analysis.moves) {
      if (m.moveIndex == moveIndex) return m;
    }
    return null;
  }
}

class _ReplayHeader extends StatelessWidget {
  final GameRecord record;
  const _ReplayHeader({required this.record});

  @override
  Widget build(BuildContext context) {
    return CChessCard(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      child: Row(
        children: [
          Icon(
            record.isDraw
                ? Icons.handshake_outlined
                : record.humanWon
                    ? Icons.emoji_events
                    : Icons.sentiment_dissatisfied,
            color: record.humanWon
                ? AppColors.tealSuccess
                : record.isDraw
                    ? AppColors.accentGold
                    : AppColors.parchmentTan,
          ),
          AppSpacing.hGapSm,
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'vs ${record.opponentLabel}',
                  style: AppTextStyles.headingMd,
                ),
                Text(
                  '${record.moves.length} nước  •  ${record.mode.nameVi}',
                  style: AppTextStyles.captionSm.copyWith(
                    color: AppColors.parchmentTan,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CoachStrip extends StatelessWidget {
  final ReplayUiState state;
  final MoveAnalysis? currentMoveAnalysis;

  const _CoachStrip({
    required this.state,
    required this.currentMoveAnalysis,
  });

  @override
  Widget build(BuildContext context) {
    final analysis = state.analysis;
    if (analysis == null) {
      return CChessCard(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm,
        ),
        borderColor: AppColors.accentGold.withValues(alpha: 0.5),
        child: Row(
          children: [
            const SizedBox(
              width: 18,
              height: 18,
              child: BrushStrokeSpinner(size: 18),
            ),
            AppSpacing.hGapSm,
            Expanded(
              child: Text(
                'AI đang phân tích ván đấu… ${(state.analysisProgress * 100).round()}%',
                style: AppTextStyles.bodyMd,
              ),
            ),
          ],
        ),
      );
    }

    final m = currentMoveAnalysis;
    if (m == null) {
      return CChessCard(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm,
        ),
        borderColor: AppColors.accentGold.withValues(alpha: 0.5),
        child: Row(
          children: [
            _AccuracyChip(
              label: 'Đỏ',
              value: analysis.redAccuracy,
              tint: AppColors.vermilionRed,
            ),
            AppSpacing.hGapMd,
            _AccuracyChip(
              label: 'Đen',
              value: analysis.blackAccuracy,
              tint: AppColors.deepNavyBlack,
            ),
            const Spacer(),
            Text(
              '⌐ ${analysis.redBlunders + analysis.blackBlunders} sai lầm lớn',
              style: AppTextStyles.captionSm.copyWith(
                color: AppColors.error,
              ),
            ),
          ],
        ),
      );
    }

    return CChessCard(
      padding: const EdgeInsets.all(AppSpacing.sm),
      borderColor: m.quality.color.withValues(alpha: 0.5),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: m.quality.color.withValues(alpha: 0.15),
              shape: BoxShape.circle,
              border: Border.all(color: m.quality.color),
            ),
            alignment: Alignment.center,
            child: Icon(m.quality.icon, color: m.quality.color, size: 18),
          ),
          AppSpacing.hGapSm,
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${_moveLabel(m)} — ${m.quality.nameVi}',
                  style: AppTextStyles.bodyMd.copyWith(
                    color: m.quality.color,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (m.recommendedMove != null &&
                    !(m.move.from == m.recommendedMove!.from &&
                        m.move.to == m.recommendedMove!.to))
                  Text(
                    'Gợi ý: ${m.recommendedMove!.toUci()}  •  '
                    'Mất ${m.centipawnLoss}cp',
                    style: AppTextStyles.captionSm.copyWith(
                      color: AppColors.onSurfaceVariant,
                    ),
                  )
                else
                  Text(
                    'Bạn đã chọn nước tốt nhất.',
                    style: AppTextStyles.captionSm.copyWith(
                      color: AppColors.tealSuccess,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _moveLabel(MoveAnalysis m) {
    final num = (m.moveIndex ~/ 2) + 1;
    final dot = m.mover == PieceColor.red ? '.' : '...';
    return '$num$dot ${m.move.toUci()}';
  }
}

class _AccuracyChip extends StatelessWidget {
  final String label;
  final double value;
  final Color tint;

  const _AccuracyChip({
    required this.label,
    required this.value,
    required this.tint,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: 2,
      ),
      decoration: BoxDecoration(
        color: tint.withValues(alpha: 0.14),
        border: Border.all(color: tint.withValues(alpha: 0.5)),
        borderRadius: AppRadius.chip,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: AppTextStyles.captionSm.copyWith(
              color: AppColors.onSurface,
              fontWeight: FontWeight.w700,
            ),
          ),
          AppSpacing.hGapXs,
          Text(
            '${value.toStringAsFixed(0)}%',
            style: AppTextStyles.captionSm.copyWith(
              color: AppColors.accentGold,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _TransportBar extends StatelessWidget {
  final ReplayUiState state;
  final ReplayController controller;

  const _TransportBar({required this.state, required this.controller});

  @override
  Widget build(BuildContext context) {
    return CChessCard(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xs,
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              IconButton(
                onPressed: state.atStart ? null : controller.goToStart,
                icon: const Icon(Icons.first_page),
                color: AppColors.primary,
              ),
              IconButton(
                onPressed: state.atStart ? null : controller.stepBackward,
                icon: const Icon(Icons.chevron_left),
                color: AppColors.primary,
              ),
              Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.accentGold.withValues(alpha: 0.18),
                  border: Border.all(color: AppColors.accentGold),
                ),
                child: IconButton(
                  onPressed: state.atEnd ? null : controller.toggleAutoPlay,
                  icon: Icon(
                    state.isPlaying ? Icons.pause : Icons.play_arrow,
                    color: AppColors.accentGold,
                  ),
                ),
              ),
              IconButton(
                onPressed: state.atEnd ? null : controller.stepForward,
                icon: const Icon(Icons.chevron_right),
                color: AppColors.primary,
              ),
              IconButton(
                onPressed: state.atEnd ? null : controller.goToEnd,
                icon: const Icon(Icons.last_page),
                color: AppColors.primary,
              ),
            ],
          ),
          Row(
            children: [
              Text(
                '${state.currentPly} / ${state.totalPly}',
                style: AppTextStyles.captionSm.copyWith(
                  color: AppColors.parchmentTan,
                ),
              ),
              Expanded(
                child: SliderTheme(
                  data: SliderThemeData(
                    activeTrackColor: AppColors.accentGold,
                    inactiveTrackColor: AppColors.surfaceContainerHigh,
                    thumbColor: AppColors.accentGold,
                    overlayColor: AppColors.accentGold.withValues(alpha: 0.16),
                  ),
                  child: Slider(
                    value: state.currentPly.toDouble(),
                    min: 0,
                    max: state.totalPly.toDouble().clamp(1, double.infinity),
                    divisions:
                        state.totalPly == 0 ? 1 : state.totalPly,
                    onChanged: (v) => controller.seek(v.round()),
                  ),
                ),
              ),
              // Speed picker
              PopupMenuButton<double>(
                tooltip: 'Tốc độ',
                initialValue: state.speed,
                onSelected: controller.setSpeed,
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 0.5, child: Text('0.5×')),
                  PopupMenuItem(value: 1.0, child: Text('1×')),
                  PopupMenuItem(value: 2.0, child: Text('2×')),
                  PopupMenuItem(value: 4.0, child: Text('4×')),
                ],
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.sm,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceContainerHigh,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: AppColors.outlineVariant),
                  ),
                  child: Text(
                    '${state.speed.toStringAsFixed(state.speed == state.speed.roundToDouble() ? 0 : 1)}×',
                    style: AppTextStyles.captionSm.copyWith(
                      color: AppColors.accentGold,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MoveList extends StatelessWidget {
  final ReplayUiState state;
  final ReplayController controller;

  const _MoveList({required this.state, required this.controller});

  @override
  Widget build(BuildContext context) {
    final moves = state.record.moves;
    return ListView.separated(
      scrollDirection: Axis.horizontal,
      itemCount: moves.length,
      separatorBuilder: (_, _) => AppSpacing.hGapXs,
      itemBuilder: (_, i) {
        final selected = state.currentPly == i + 1;
        final isRed = i.isEven;
        MoveQuality? quality;
        if (state.coachMode && state.analysis != null) {
          for (final m in state.analysis!.moves) {
            if (m.moveIndex == i) {
              quality = m.quality;
              break;
            }
          }
        }
        final qualityColor = quality?.color;
        return GestureDetector(
          onTap: () => controller.seek(i + 1),
          child: Container(
            width: 78,
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.xs,
              vertical: AppSpacing.xs,
            ),
            decoration: BoxDecoration(
              color: selected
                  ? AppColors.accentGold.withValues(alpha: 0.18)
                  : AppColors.surfaceContainerHigh,
              borderRadius: AppRadius.card,
              border: Border.all(
                color: selected
                    ? AppColors.accentGold
                    : (qualityColor ?? AppColors.outlineVariant),
                width: selected ? 1.5 : 1,
              ),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  '${(i ~/ 2) + 1}${isRed ? '.' : '...'}',
                  style: AppTextStyles.captionSm.copyWith(
                    color: AppColors.parchmentTan,
                    fontSize: 10,
                  ),
                ),
                Text(
                  moves[i],
                  style: AppTextStyles.bodyMd.copyWith(
                    color: isRed
                        ? AppColors.vermilionRed
                        : AppColors.onSurface,
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
                if (quality != null)
                  Icon(quality.icon, color: quality.color, size: 12),
              ],
            ),
          ),
        );
      },
    );
  }
}
