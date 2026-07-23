import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/economy_models.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_text_styles.dart';
import '../../widgets/common/common.dart';
import 'economy_controller.dart';
import 'economy_widgets.dart';

/// Sự Kiện (S16 D5). Live seasonal events, each with claim-once gifts. The
/// claimed set comes from the backend so it survives reinstalls.
class EventsScreen extends ConsumerWidget {
  const EventsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final eventsAsync = ref.watch(eventsProvider);
    final claims = ref.watch(eventClaimsProvider).valueOrNull ?? const {};

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.woodDark,
        title: const Text('Sự Kiện'),
      ),
      body: SafeArea(
        child: eventsAsync.when(
          loading: () => const Center(child: BrushStrokeSpinner()),
          error: (e, _) => EconomyMessage(
            icon: Icons.cloud_off,
            title: 'Không tải được sự kiện',
            detail: 'Kiểm tra kết nối mạng rồi thử lại.',
            onRetry: () => ref.invalidate(eventsProvider),
          ),
          data: (events) {
            if (events.isEmpty) {
              return const EconomyMessage(
                icon: Icons.celebration_outlined,
                title: 'Chưa có sự kiện',
                detail:
                    'Sự kiện theo mùa (Tết, 30/4, 2/9…) sẽ xuất hiện ở đây.',
              );
            }
            return RefreshIndicator(
              onRefresh: () async {
                ref.invalidate(eventsProvider);
                ref.invalidate(eventClaimsProvider);
              },
              child: ListView.builder(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.base,
                  AppSpacing.base,
                  AppSpacing.base,
                  96,
                ),
                itemCount: events.length,
                itemBuilder: (context, i) =>
                    _EventCard(event: events[i], claims: claims),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _EventCard extends ConsumerWidget {
  final EconEvent event;
  final Set<String> claims;
  const _EventCard({required this.event, required this.claims});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(economyControllerProvider);

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: CChessCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.celebration,
                  color: AppColors.vermilionRed,
                  size: 20,
                ),
                AppSpacing.hGapSm,
                Expanded(
                  child: Text(event.title, style: AppTextStyles.headingMd),
                ),
                Text(
                  _remaining(event.endAtMs),
                  style: AppTextStyles.captionSm
                      .copyWith(color: AppColors.onSurfaceVariant),
                ),
              ],
            ),
            if (event.descVi.isNotEmpty) ...[
              AppSpacing.vGapXs,
              Text(
                event.descVi,
                style: AppTextStyles.captionSm
                    .copyWith(color: AppColors.onSurfaceVariant),
              ),
            ],
            AppSpacing.vGapSm,
            for (final gift in event.gifts)
              _GiftRow(
                gift: gift,
                claimed: claims.contains('${event.id}__${gift.id}'),
                onClaim: () async {
                  try {
                    final outcome =
                        await controller.claimEventGift(event.id, gift.id);
                    if (context.mounted) {
                      showRewardSnack(context, outcome.reward);
                    }
                  } catch (e) {
                    if (context.mounted) showEconomyError(context, e);
                  }
                },
              ),
          ],
        ),
      ),
    );
  }

  String _remaining(int endAtMs) {
    final left = DateTime.fromMillisecondsSinceEpoch(endAtMs)
        .difference(DateTime.now());
    if (left.isNegative) return 'đã kết thúc';
    if (left.inDays >= 1) return 'còn ${left.inDays} ngày';
    if (left.inHours >= 1) return 'còn ${left.inHours} giờ';
    return 'còn ${left.inMinutes} phút';
  }
}

class _GiftRow extends StatelessWidget {
  final EventGift gift;
  final bool claimed;
  final Future<void> Function() onClaim;

  const _GiftRow({
    required this.gift,
    required this.claimed,
    required this.onClaim,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.xs),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(gift.title, style: AppTextStyles.bodyMd),
                AppSpacing.vGapXs,
                RewardChips(reward: gift.reward),
              ],
            ),
          ),
          if (claimed)
            const Icon(Icons.check_circle, color: AppColors.tealSuccess)
          else
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.vermilionRed,
                foregroundColor: Colors.white,
                visualDensity: VisualDensity.compact,
              ),
              onPressed: onClaim,
              child: const Text('Nhận'),
            ),
        ],
      ),
    );
  }
}
