import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/economy_models.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_text_styles.dart';
import '../../widgets/common/common.dart';
import 'economy_controller.dart';
import 'economy_widgets.dart';

/// Phúc Lợi (S16 D6). Daily check-in over an escalating 7-day cycle (day 7
/// pays gems), plus the one-time newbie gift and the comeback gift after a
/// ≥7-day absence. Day boundary is Vietnam midnight (server-side).
class WelfareScreen extends ConsumerWidget {
  const WelfareScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final welfareAsync = ref.watch(welfareProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.woodDark,
        title: const Text('Phúc Lợi'),
      ),
      body: SafeArea(
        child: welfareAsync.when(
          loading: () => const Center(child: BrushStrokeSpinner()),
          error: (e, _) => EconomyMessage(
            icon: Icons.cloud_off,
            title: 'Không tải được phúc lợi',
            detail: 'Kiểm tra kết nối mạng rồi thử lại.',
            onRetry: () => ref.invalidate(welfareProvider),
          ),
          data: (status) => _WelfareBody(status: status),
        ),
      ),
    );
  }
}

class _WelfareBody extends ConsumerWidget {
  final WelfareStatus status;
  const _WelfareBody({required this.status});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(economyControllerProvider);

    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.base,
        AppSpacing.base,
        AppSpacing.base,
        96,
      ),
      children: [
        // ── Điểm danh 7 ngày ──
        CChessCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.event_available,
                      color: AppColors.tealSuccess, size: 20),
                  AppSpacing.hGapSm,
                  Expanded(
                    child:
                        Text('Điểm Danh Hàng Ngày', style: AppTextStyles.headingMd),
                  ),
                  Text(
                    'chuỗi ${status.streak} ngày',
                    style: AppTextStyles.captionSm
                        .copyWith(color: AppColors.accentGold),
                  ),
                ],
              ),
              AppSpacing.vGapSm,
              if (status.cycle.isNotEmpty) _CycleGrid(status: status),
              AppSpacing.vGapMd,
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: status.todayClaimed
                        ? AppColors.surfaceContainerHigh
                        : AppColors.tealSuccess,
                    foregroundColor: status.todayClaimed
                        ? AppColors.onSurfaceVariant
                        : Colors.white,
                    padding:
                        const EdgeInsets.symmetric(vertical: AppSpacing.sm),
                  ),
                  icon: Icon(
                    status.todayClaimed ? Icons.check : Icons.touch_app,
                  ),
                  label: Text(
                    status.todayClaimed
                        ? 'Hôm nay đã điểm danh'
                        : 'Điểm danh hôm nay',
                  ),
                  onPressed: status.todayClaimed
                      ? null
                      : () async {
                          try {
                            final outcome = await controller.checkin();
                            if (context.mounted) {
                              showRewardSnack(context, outcome.reward);
                            }
                          } catch (e) {
                            if (context.mounted) {
                              showEconomyError(context, e);
                            }
                          }
                        },
                ),
              ),
            ],
          ),
        ),
        AppSpacing.vGapMd,

        // ── Quà tân thủ ──
        if (!status.newbieClaimed)
          _GiftCard(
            icon: Icons.card_giftcard,
            color: AppColors.accentGold,
            title: 'Quà Tân Thủ',
            subtitle: 'Chào mừng kỳ thủ mới — nhận một lần duy nhất.',
            onClaim: () async {
              try {
                final outcome = await controller.claimNewbie();
                if (context.mounted) {
                  showRewardSnack(context, outcome.reward);
                }
              } catch (e) {
                if (context.mounted) showEconomyError(context, e);
              }
            },
          ),

        // ── Quà quay lại ──
        if (status.comebackAvailable)
          _GiftCard(
            icon: Icons.waving_hand,
            color: AppColors.vermilionRed,
            title: 'Quà Quay Lại',
            subtitle: 'Mừng bạn trở lại sau những ngày vắng bóng!',
            onClaim: () async {
              try {
                final outcome = await controller.claimComeback();
                if (context.mounted) {
                  showRewardSnack(context, outcome.reward);
                }
              } catch (e) {
                if (context.mounted) showEconomyError(context, e);
              }
            },
          ),
      ],
    );
  }
}

/// The 7-day reward strip. Days before today's slot show as collected when
/// the streak covers them; today's slot is highlighted.
class _CycleGrid extends StatelessWidget {
  final WelfareStatus status;
  const _CycleGrid({required this.status});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const spacing = 6.0;
        final tileWidth =
            (constraints.maxWidth - spacing * 6) / 7;
        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: [
            for (int i = 0; i < status.cycle.length; i++)
              SizedBox(
                width: tileWidth,
                child: _DayTile(
                  day: i + 1,
                  reward: status.cycle[i],
                  collected: status.todayClaimed
                      ? i <= status.todayIndex
                      : i < status.todayIndex,
                  isToday: i == status.todayIndex,
                ),
              ),
          ],
        );
      },
    );
  }
}

class _DayTile extends StatelessWidget {
  final int day;
  final RewardBundle reward;
  final bool collected;
  final bool isToday;

  const _DayTile({
    required this.day,
    required this.reward,
    required this.collected,
    required this.isToday,
  });

  @override
  Widget build(BuildContext context) {
    final highlight = isToday && !collected;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      decoration: BoxDecoration(
        color: collected
            ? AppColors.tealSuccess.withValues(alpha: 0.15)
            : highlight
                ? AppColors.accentGold.withValues(alpha: 0.15)
                : AppColors.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: collected
              ? AppColors.tealSuccess.withValues(alpha: 0.5)
              : highlight
                  ? AppColors.accentGold
                  : AppColors.outlineVariant.withValues(alpha: 0.3),
        ),
      ),
      child: Column(
        children: [
          Text(
            'N$day',
            style: AppTextStyles.captionSm.copyWith(
              fontWeight: FontWeight.w700,
              color: collected
                  ? AppColors.tealSuccess
                  : highlight
                      ? AppColors.accentGold
                      : AppColors.onSurfaceVariant,
            ),
          ),
          AppSpacing.vGapXs,
          if (collected)
            const Icon(Icons.check_circle,
                size: 16, color: AppColors.tealSuccess)
          else
            Text(
              reward.gems > 0 ? '💎${reward.gems}' : '${reward.coins}',
              style: AppTextStyles.captionSm.copyWith(fontSize: 10),
            ),
        ],
      ),
    );
  }
}

class _GiftCard extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final Future<void> Function() onClaim;

  const _GiftCard({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.onClaim,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: CChessCard(
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                shape: BoxShape.circle,
                border: Border.all(color: color.withValues(alpha: 0.3)),
              ),
              child: Icon(icon, color: color, size: 22),
            ),
            AppSpacing.hGapMd,
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: AppTextStyles.headingMd),
                  AppSpacing.vGapXs,
                  Text(
                    subtitle,
                    style: AppTextStyles.captionSm
                        .copyWith(color: AppColors.onSurfaceVariant),
                  ),
                ],
              ),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: color,
                foregroundColor:
                    color == AppColors.accentGold ? AppColors.inkBlack : Colors.white,
                visualDensity: VisualDensity.compact,
              ),
              onPressed: onClaim,
              child: const Text('Nhận'),
            ),
          ],
        ),
      ),
    );
  }
}
