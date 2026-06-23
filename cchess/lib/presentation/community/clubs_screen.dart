import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/community_models.dart';
import '../../data/repositories/community_repository.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_text_styles.dart';
import '../../widgets/common/common.dart';
import 'community_widgets.dart';

class ClubsScreen extends ConsumerWidget {
  const ClubsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final future = ref.watch(communityRepositoryProvider).loadClubs(limit: 20);
    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.base,
        AppSpacing.base,
        AppSpacing.base,
        96,
      ),
      children: [
        const CommunityPageHeader(
          title: 'Kỳ Xã',
          subtitle: 'Câu lạc bộ theo địa phương, nhóm bạn và lối chơi',
          icon: Icons.workspace_premium_outlined,
          showBack: true,
        ),
        AppSpacing.vGapLg,
        FutureBuilder<List<CommunityClub>>(
          future: future,
          builder: (context, snapshot) {
            if (!snapshot.hasData) {
              return const Center(child: BrushStrokeSpinner());
            }
            final clubs = snapshot.data!;
            if (clubs.isEmpty) {
              return const CommunityEmptyState(
                icon: Icons.workspace_premium_outlined,
                title: 'Chưa có Kỳ Xã',
                message: 'Các câu lạc bộ công khai sẽ xuất hiện tại đây.',
              );
            }
            return Column(
              children: [
                for (final club in clubs) ...[
                  _ClubCard(club: club),
                  if (club != clubs.last) AppSpacing.vGapMd,
                ],
              ],
            );
          },
        ),
      ],
    );
  }
}

class _ClubCard extends StatelessWidget {
  const _ClubCard({required this.club});

  final CommunityClub club;

  @override
  Widget build(BuildContext context) {
    return CChessCard(
      borderColor: club.isJoined
          ? AppColors.accentGold.withValues(alpha: 0.5)
          : AppColors.outlineVariant,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: AppColors.accentGold.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(AppRadius.lg),
                ),
                alignment: Alignment.center,
                child: const Icon(
                  Icons.workspace_premium_outlined,
                  color: AppColors.accentGold,
                ),
              ),
              AppSpacing.hGapMd,
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(club.name, style: AppTextStyles.headingMd),
                    AppSpacing.vGapXs,
                    Text(
                      club.region,
                      style: AppTextStyles.captionSm.copyWith(
                        color: AppColors.parchmentTan,
                      ),
                    ),
                  ],
                ),
              ),
              if (club.isJoined)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.accentGold.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    'Đã vào',
                    style: AppTextStyles.captionSm.copyWith(
                      color: AppColors.accentGold,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
            ],
          ),
          AppSpacing.vGapMd,
          Text(
            club.description,
            style: AppTextStyles.bodyMd.copyWith(
              color: AppColors.onSurfaceVariant,
            ),
          ),
          AppSpacing.vGapMd,
          Row(
            children: [
              Expanded(
                child: _InlineMetric(
                  icon: Icons.people_outline,
                  label: 'thành viên',
                  value: '${club.memberCount}',
                  color: AppColors.tertiary,
                ),
              ),
              AppSpacing.hGapSm,
              Expanded(
                child: _InlineMetric(
                  icon: Icons.stacked_line_chart,
                  label: 'điểm tuần',
                  value: '${club.weeklyScore}',
                  color: AppColors.accentGold,
                ),
              ),
            ],
          ),
          AppSpacing.vGapMd,
          Row(
            children: [
              Expanded(
                child: CChessButton(
                  label: club.isJoined ? 'Phòng CLB' : 'Tham gia',
                  icon: club.isJoined
                      ? Icons.meeting_room_outlined
                      : Icons.group_add_outlined,
                  onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        club.isJoined
                            ? 'Phòng riêng CLB sẽ nối vào online lobby.'
                            : 'Yêu cầu tham gia Kỳ Xã đã được ghi nhận.',
                      ),
                    ),
                  ),
                ),
              ),
              AppSpacing.hGapSm,
              CChessButton(
                label: 'Bảng điểm',
                icon: Icons.leaderboard_outlined,
                variant: CChessButtonVariant.outline,
                onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Bảng điểm CLB đang chuẩn bị.')),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _InlineMetric extends StatelessWidget {
  const _InlineMetric({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        border: Border.all(color: color.withValues(alpha: 0.3)),
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 18),
          AppSpacing.hGapSm,
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  style: AppTextStyles.headingMd.copyWith(color: color),
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  label,
                  style: AppTextStyles.captionSm.copyWith(
                    color: AppColors.onSurfaceVariant,
                    fontSize: 11,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
