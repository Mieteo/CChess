import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/chess_engine/chess_engine.dart';
import '../../core/constants/app_constants.dart';
import '../../data/models/game_record.dart';
import '../../data/repositories/game_history_repository.dart';
import '../../data/repositories/puzzle_repository.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_text_styles.dart';
import '../../widgets/common/common.dart';
import '../puzzle/widgets/daily_challenge_banner.dart';

/// Solved endgame-puzzle count — real progress for the header (which used to
/// show a hard-coded "2/3 hoàn thành" bar).
final _solvedPuzzlesProvider = FutureProvider.autoDispose<int>((ref) async {
  final progress = await ref.watch(puzzleRepositoryProvider).getAllProgress();
  return progress.values.where((p) => p.solved).length;
});

/// Three most recent saved games — real "Hoạt Động Gần Đây".
final _recentGamesProvider = FutureProvider.autoDispose<List<GameRecord>>((
  ref,
) async {
  final all = await ref.watch(gameHistoryRepositoryProvider).all();
  return all.take(3).toList();
});

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
        // Real daily endgame challenge (B4) — shared with Home + puzzle list.
        const DailyChallengeBanner(),
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

class _Header extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Real progress (the old bar was a hard-coded 2/3).
    final solved = ref.watch(_solvedPuzzlesProvider).valueOrNull;
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
              if (solved != null && solved > 0) ...[
                AppSpacing.vGapXs,
                Text(
                  'Đã giải $solved bài tàn cục',
                  style: AppTextStyles.captionSm.copyWith(
                    color: AppColors.accentGold,
                  ),
                ),
              ],
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
        onTap: () => context.go(AppConstants.routeHistory),
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
        // Not built yet — was badged "HOT" with a dead tap.
        badge: 'SẮP CÓ',
        badgeColor: AppColors.parchmentTan,
        onTap: () => ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Nhận diện bàn cờ qua ảnh đang được phát triển — sắp ra mắt!',
            ),
          ),
        ),
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

/// Real recent games (the old list was a hard-coded sample). Tapping a row
/// opens its replay.
class _RecentActivityList extends ConsumerWidget {
  const _RecentActivityList();

  String _resultLabel(GameRecord r) {
    if (r.result == GameStatus.draw) return 'Hòa';
    final hc = r.humanColor;
    if (hc == null) {
      return r.result == GameStatus.redWin ? 'Đỏ thắng' : 'Đen thắng';
    }
    final won =
        (r.result == GameStatus.redWin && hc == PieceColor.red) ||
        (r.result == GameStatus.blackWin && hc == PieceColor.black);
    return won ? 'Thắng' : 'Thua';
  }

  bool _isWinForHuman(GameRecord r) {
    final hc = r.humanColor;
    if (hc == null || r.result == GameStatus.draw) return false;
    return (r.result == GameStatus.redWin && hc == PieceColor.red) ||
        (r.result == GameStatus.blackWin && hc == PieceColor.black);
  }

  String _agoLabel(DateTime t) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(t.year, t.month, t.day);
    final diff = today.difference(day).inDays;
    if (diff <= 0) return 'Hôm nay';
    if (diff == 1) return 'Hôm qua';
    return '$diff ngày trước';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final recent = ref.watch(_recentGamesProvider);
    final games = recent.valueOrNull;

    if (games == null) {
      return const SizedBox(
        height: 56,
        child: Center(child: BrushStrokeSpinner(size: 24)),
      );
    }
    if (games.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(AppSpacing.sm),
        decoration: BoxDecoration(
          color: AppColors.surfaceContainerHighest,
          border: Border.all(
            color: AppColors.outlineVariant.withValues(alpha: 0.5),
          ),
          borderRadius: AppRadius.card,
        ),
        child: Text(
          'Chưa có hoạt động nào — đánh một ván hoặc giải một thế cờ nhé!',
          style: AppTextStyles.captionSm.copyWith(
            color: AppColors.onSurfaceVariant,
          ),
        ),
      );
    }

    return Column(
      children: [
        for (final r in games)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.xs),
            child: InkWell(
              borderRadius: AppRadius.card,
              onTap: () => context.go('${AppConstants.routeReplay}/${r.id}'),
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
                      r.result == GameStatus.draw
                          ? Icons.handshake_outlined
                          : _isWinForHuman(r)
                          ? Icons.check_circle
                          : Icons.cancel,
                      color: r.result == GameStatus.draw
                          ? AppColors.accentGold
                          : _isWinForHuman(r)
                          ? AppColors.tealSuccess
                          : AppColors.error,
                      size: 20,
                    ),
                    AppSpacing.hGapSm,
                    Expanded(
                      child: Text(
                        '${_resultLabel(r)} vs ${r.opponentLabel}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.bodyMd,
                      ),
                    ),
                    Text(
                      _agoLabel(r.endedAt),
                      style: AppTextStyles.captionSm.copyWith(
                        color: AppColors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}
