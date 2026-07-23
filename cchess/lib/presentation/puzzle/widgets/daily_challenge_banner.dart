import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/app_constants.dart';
import '../../../theme/app_colors.dart';
import '../../../theme/app_spacing.dart';
import '../../../theme/app_text_styles.dart';
import '../../../widgets/common/common.dart';
import '../puzzle_list_controller.dart';

/// Featured daily endgame puzzle with a live countdown to the next VN-midnight
/// reset. Watches [dailyPuzzleProvider] itself so it can sit anywhere — the
/// Home lobby, Học Cờ and the puzzle list all share this one banner instead of
/// each drawing its own (previously two of them were static mock-ups).
class DailyChallengeBanner extends ConsumerStatefulWidget {
  const DailyChallengeBanner({super.key});

  @override
  ConsumerState<DailyChallengeBanner> createState() =>
      _DailyChallengeBannerState();
}

class _DailyChallengeBannerState extends ConsumerState<DailyChallengeBanner> {
  Timer? _timer;
  Duration _remaining = Duration.zero;

  @override
  void initState() {
    super.initState();
    _remaining = _timeToVnReset();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _remaining = _timeToVnReset());
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  /// Time until the next daily reset (00:00 in Vietnam, UTC+7).
  static Duration _timeToVnReset() {
    final nowUtc = DateTime.now().toUtc();
    final vnNow = nowUtc.add(const Duration(hours: 7));
    final nextVnMidnight = DateTime.utc(
      vnNow.year,
      vnNow.month,
      vnNow.day,
    ).add(const Duration(days: 1));
    final nextResetUtc = nextVnMidnight.subtract(const Duration(hours: 7));
    final diff = nextResetUtc.difference(nowUtc);
    return diff.isNegative ? Duration.zero : diff;
  }

  String get _countdown {
    final h = _remaining.inHours.toString().padLeft(2, '0');
    final m = (_remaining.inMinutes % 60).toString().padLeft(2, '0');
    final s = (_remaining.inSeconds % 60).toString().padLeft(2, '0');
    return '$h:$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final daily = ref.watch(dailyPuzzleProvider);
    final puzzle = daily.valueOrNull;
    return CChessCard(
      gradient: const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [AppColors.charcoalDark, AppColors.woodDark],
      ),
      borderColor: AppColors.accentGold.withValues(alpha: 0.5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(
                Icons.local_fire_department,
                color: AppColors.accentGold,
                size: 20,
              ),
              AppSpacing.hGapSm,
              Expanded(
                child: Text(
                  'Thử thách hôm nay',
                  style: AppTextStyles.headingMd,
                ),
              ),
              const Icon(
                Icons.schedule,
                size: 14,
                color: AppColors.parchmentTan,
              ),
              AppSpacing.hGapXs,
              Text(
                _countdown,
                style: AppTextStyles.monoTimer.copyWith(
                  fontSize: 14,
                  color: AppColors.accentGold,
                ),
              ),
            ],
          ),
          AppSpacing.vGapSm,
          if (daily.isLoading)
            Text(
              'Đang tải thử thách…',
              style: AppTextStyles.captionSm.copyWith(
                color: AppColors.parchmentTan,
              ),
            )
          else if (puzzle == null)
            Text(
              'Hôm nay chưa có thử thách. Quay lại sau nhé!',
              style: AppTextStyles.captionSm.copyWith(
                color: AppColors.parchmentTan,
              ),
            )
          else ...[
            Text(
              puzzle.titleVi,
              style: AppTextStyles.titleLg.copyWith(
                color: AppColors.parchmentTan,
              ),
            ),
            AppSpacing.vGapMd,
            CChessButton(
              label: 'Vào giải ngay',
              icon: Icons.play_arrow,
              variant: CChessButtonVariant.danger,
              fullWidth: true,
              onPressed: () =>
                  context.go('${AppConstants.routePuzzle}/${puzzle.id}'),
            ),
          ],
        ],
      ),
    );
  }
}
