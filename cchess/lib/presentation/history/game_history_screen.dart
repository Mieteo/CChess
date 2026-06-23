import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/chess_engine/chess_engine.dart';
import '../../core/constants/app_constants.dart';
import '../../data/models/game_record.dart';
import '../../data/repositories/game_history_repository.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_text_styles.dart';
import '../../widgets/common/common.dart';

class GameHistoryScreen extends ConsumerStatefulWidget {
  const GameHistoryScreen({super.key});

  @override
  ConsumerState<GameHistoryScreen> createState() => _GameHistoryScreenState();
}

class _GameHistoryScreenState extends ConsumerState<GameHistoryScreen> {
  late Future<List<GameRecord>> _recordsFuture;

  @override
  void initState() {
    super.initState();
    _recordsFuture = ref.read(gameHistoryRepositoryProvider).all();
  }

  Future<void> _refresh() async {
    setState(() {
      _recordsFuture = ref.read(gameHistoryRepositoryProvider).all();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.woodDark,
        title: const Text('Kỳ Phổ Của Tôi'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go(AppConstants.routeProfile),
        ),
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _refresh,
          color: AppColors.accentGold,
          child: FutureBuilder<List<GameRecord>>(
            future: _recordsFuture,
            builder: (context, snap) {
              if (!snap.hasData) {
                return const Center(child: BrushStrokeSpinner());
              }
              final records = snap.data!;
              if (records.isEmpty) {
                return ListView(
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  children: [
                    AppSpacing.vGapXl,
                    const Icon(
                      Icons.history_edu,
                      color: AppColors.parchmentTan,
                      size: 56,
                    ),
                    AppSpacing.vGapMd,
                    Text(
                      'Chưa có kỳ phổ nào',
                      style: AppTextStyles.titleLg,
                      textAlign: TextAlign.center,
                    ),
                    AppSpacing.vGapSm,
                    Text(
                      'Sau mỗi ván đấu hoàn thành, kỳ phổ sẽ được lưu tại đây '
                      'để bạn ôn lại nước đi.',
                      style: AppTextStyles.bodyMd.copyWith(
                        color: AppColors.onSurfaceVariant,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                );
              }
              return ListView.separated(
                padding: const EdgeInsets.all(AppSpacing.base),
                itemCount: records.length,
                separatorBuilder: (_, _) => AppSpacing.vGapSm,
                itemBuilder: (_, i) => _GameRow(record: records[i]),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _GameRow extends StatelessWidget {
  final GameRecord record;
  const _GameRow({required this.record});

  (IconData, Color, String) get _resultBadge {
    if (record.humanColor == null) {
      // Local 2-player: report which color won instead of "you".
      if (record.result == GameStatus.draw) {
        return (Icons.handshake_outlined, AppColors.accentGold, 'Hòa');
      }
      if (record.result == GameStatus.redWin) {
        return (Icons.flag, AppColors.vermilionRed, 'Đỏ thắng');
      }
      return (Icons.flag, AppColors.deepNavyBlack, 'Đen thắng');
    }
    if (record.isDraw) {
      return (Icons.handshake_outlined, AppColors.accentGold, 'Hòa');
    }
    if (record.humanWon) {
      return (Icons.emoji_events, AppColors.tealSuccess, 'Thắng');
    }
    return (Icons.sentiment_dissatisfied, AppColors.error, 'Thua');
  }

  @override
  Widget build(BuildContext context) {
    final (icon, color, label) = _resultBadge;
    final dateFmt = DateFormat('dd/MM HH:mm');
    return CChessCard(
      onTap: () => context.go('${AppConstants.routeReplay}/${record.id}'),
      borderColor: color.withValues(alpha: 0.4),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color.withValues(alpha: 0.16),
              border: Border.all(color: color),
            ),
            child: Icon(icon, color: color, size: 22),
          ),
          AppSpacing.hGapMd,
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(label, style: AppTextStyles.headingMd),
                    AppSpacing.hGapSm,
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 1,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.surfaceContainerHigh,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        record.mode.nameVi,
                        style: AppTextStyles.captionSm.copyWith(
                          color: AppColors.parchmentTan,
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
                AppSpacing.vGapXs,
                Text(
                  'vs ${record.opponentLabel}',
                  style: AppTextStyles.bodyMd.copyWith(
                    color: AppColors.onSurfaceVariant,
                  ),
                ),
                AppSpacing.vGapXs,
                Row(
                  children: [
                    const Icon(
                      Icons.schedule,
                      size: 12,
                      color: AppColors.parchmentTan,
                    ),
                    AppSpacing.hGapXs,
                    Text(
                      '${dateFmt.format(record.endedAt)}  •  '
                      '${record.moves.length} nước  •  '
                      '${_fmtDuration(record.duration)}',
                      style: AppTextStyles.captionSm.copyWith(
                        color: AppColors.parchmentTan,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            tooltip: 'Gia sư AI',
            icon: const Icon(
              Icons.psychology_outlined,
              color: AppColors.accentGold,
              size: 22,
            ),
            onPressed: () =>
                context.push('${AppConstants.routeAiCoach}/${record.id}'),
          ),
          if (record.eloDelta != 0) ...[
            AppSpacing.hGapSm,
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 6,
                vertical: 2,
              ),
              decoration: BoxDecoration(
                color: (record.eloDelta > 0
                        ? AppColors.tealSuccess
                        : AppColors.error)
                    .withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                record.eloDelta > 0
                    ? '+${record.eloDelta}'
                    : '${record.eloDelta}',
                style: AppTextStyles.captionSm.copyWith(
                  color: record.eloDelta > 0
                      ? AppColors.tealSuccess
                      : AppColors.error,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _fmtDuration(Duration d) {
    final m = d.inMinutes;
    final s = d.inSeconds.remainder(60);
    if (m == 0) return '${s}s';
    return '${m}p ${s}s';
  }
}
