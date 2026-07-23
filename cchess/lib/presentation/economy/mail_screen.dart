import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/economy_models.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_text_styles.dart';
import '../../widgets/common/common.dart';
import 'economy_controller.dart';
import 'economy_widgets.dart';

/// Hộp Thư (S16 D4). Personal mailbox: system notices + claimable gifts.
/// Tapping an unread mail marks it read; mails with an attachment show a
/// "Nhận quà" button; claimed/notification mails can be deleted.
class MailScreen extends ConsumerWidget {
  const MailScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mailAsync = ref.watch(mailProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.woodDark,
        title: const Text('Hộp Thư'),
      ),
      body: SafeArea(
        child: mailAsync.when(
          loading: () => const Center(child: BrushStrokeSpinner()),
          error: (e, _) => EconomyMessage(
            icon: Icons.cloud_off,
            title: 'Không tải được hộp thư',
            detail: 'Kiểm tra kết nối mạng rồi thử lại.',
            onRetry: () => ref.invalidate(mailProvider),
          ),
          data: (messages) {
            if (messages.isEmpty) {
              return const EconomyMessage(
                icon: Icons.mail_outline,
                title: 'Hộp thư trống',
                detail: 'Quà và thông báo từ hệ thống sẽ xuất hiện ở đây.',
              );
            }
            return RefreshIndicator(
              onRefresh: () async => ref.invalidate(mailProvider),
              child: ListView.builder(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.base,
                  AppSpacing.base,
                  AppSpacing.base,
                  96,
                ),
                itemCount: messages.length,
                itemBuilder: (context, i) => _MailCard(message: messages[i]),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _MailCard extends ConsumerWidget {
  final MailMessage message;
  const _MailCard({required this.message});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(economyControllerProvider);
    final reward = message.reward;

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: CChessCard(
        onTap: message.read
            ? null
            : () => controller
                .markMailRead(message.id)
                .catchError((Object e) {
                  if (context.mounted) showEconomyError(context, e);
                }),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                if (!message.read) ...[
                  Container(
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(
                      color: AppColors.accentGold,
                      shape: BoxShape.circle,
                    ),
                  ),
                  AppSpacing.hGapSm,
                ],
                Expanded(
                  child: Text(message.title, style: AppTextStyles.headingMd),
                ),
                if (!message.hasUnclaimedReward)
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(
                      Icons.delete_outline,
                      size: 20,
                      color: AppColors.onSurfaceVariant,
                    ),
                    onPressed: () async {
                      try {
                        await controller.deleteMail(message.id);
                      } catch (e) {
                        if (context.mounted) showEconomyError(context, e);
                      }
                    },
                  ),
              ],
            ),
            if (message.body.isNotEmpty) ...[
              AppSpacing.vGapXs,
              Text(
                message.body,
                style: AppTextStyles.captionSm
                    .copyWith(color: AppColors.onSurfaceVariant),
              ),
            ],
            if (reward != null && !reward.isEmpty) ...[
              AppSpacing.vGapSm,
              Row(
                children: [
                  Expanded(child: RewardChips(reward: reward)),
                  if (message.hasUnclaimedReward)
                    FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.accentGold,
                        foregroundColor: AppColors.inkBlack,
                        visualDensity: VisualDensity.compact,
                      ),
                      onPressed: () async {
                        try {
                          final outcome =
                              await controller.claimMail(message.id);
                          if (context.mounted) {
                            showRewardSnack(context, outcome.reward);
                          }
                        } catch (e) {
                          if (context.mounted) showEconomyError(context, e);
                        }
                      },
                      child: const Text('Nhận quà'),
                    )
                  else
                    Text(
                      'Đã nhận',
                      style: AppTextStyles.captionSm
                          .copyWith(color: AppColors.tealSuccess),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
