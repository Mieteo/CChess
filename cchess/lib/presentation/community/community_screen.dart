import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_text_styles.dart';
import '../../widgets/common/common.dart';

/// Cộng Đồng — leaderboard preview, news feed, nearby players.
class CommunityScreen extends StatelessWidget {
  const CommunityScreen({super.key});

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
        Text('Cộng Đồng Cờ Tướng', style: AppTextStyles.titleLg),
        AppSpacing.vGapXs,
        Text(
          'Kết nối kỳ thủ Việt khắp cả nước',
          style: AppTextStyles.captionSm.copyWith(
            color: AppColors.onSurfaceVariant,
          ),
        ),
        AppSpacing.vGapLg,
        const _QuickAccessRow(),
        AppSpacing.vGapLg,
        const SectionHeader(title: 'Top kỳ thủ tuần này'),
        AppSpacing.vGapMd,
        const _LeaderboardPodium(),
        AppSpacing.vGapLg,
        SectionHeader(
          title: 'Tàn Cục Thách Đấu',
          actionLabel: 'Xem thêm',
          onActionPressed: () {},
        ),
        AppSpacing.vGapMd,
        const _PuzzleChallengeCard(),
        AppSpacing.vGapLg,
        const SectionHeader(title: 'Kỳ thủ gần bạn'),
        AppSpacing.vGapMd,
        const _NearbyPlayersRow(),
      ],
    );
  }
}

class _QuickAccessRow extends StatelessWidget {
  const _QuickAccessRow();

  static const items = <(IconData, String)>[
    (Icons.people_outline, 'Bạn Bè'),
    (Icons.leaderboard_outlined, 'Bảng XH'),
    (Icons.workspace_premium_outlined, 'Kỳ Xã'),
    (Icons.emoji_events_outlined, 'Giải Đấu'),
    (Icons.live_tv_outlined, 'Live'),
  ];

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (final (icon, label) in items)
          Expanded(
            child: GestureDetector(
              onTap: () {},
              child: Column(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: AppColors.surfaceContainerHigh,
                      shape: BoxShape.circle,
                      border: Border.all(color: AppColors.outlineVariant),
                    ),
                    alignment: Alignment.center,
                    child: Icon(icon, color: AppColors.accentGold),
                  ),
                  AppSpacing.vGapXs,
                  Text(
                    label,
                    style: AppTextStyles.captionSm.copyWith(
                      color: AppColors.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _LeaderboardPodium extends StatelessWidget {
  const _LeaderboardPodium();

  @override
  Widget build(BuildContext context) {
    final players = <(String, int, int)>[
      ('Hồng Vương', 2284, 2),
      ('Lan Phương', 2410, 1),
      ('Hoàng Minh', 2198, 3),
    ];
    return CChessCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (final (name, elo, place) in players)
            Expanded(child: _PodiumPlayer(name: name, elo: elo, place: place)),
        ],
      ),
    );
  }
}

class _PodiumPlayer extends StatelessWidget {
  final String name;
  final int elo;
  final int place;

  const _PodiumPlayer({
    required this.name,
    required this.elo,
    required this.place,
  });

  @override
  Widget build(BuildContext context) {
    final (color, height) = switch (place) {
      1 => (AppColors.accentGold, 84.0),
      2 => (AppColors.outline, 64.0),
      _ => (AppColors.parchmentTan, 52.0),
    };
    return Column(
      children: [
        CChessAvatar(
          initials: name.split(' ').last.substring(0, 1),
          size: 44,
          elo: elo,
        ),
        AppSpacing.vGapXs,
        Text(
          name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: AppTextStyles.bodyMd.copyWith(fontWeight: FontWeight.w600),
        ),
        Text(
          'ELO $elo',
          style: AppTextStyles.captionSm.copyWith(
            color: AppColors.parchmentTan,
          ),
        ),
        AppSpacing.vGapXs,
        Container(
          height: height,
          width: 48,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.16),
            border: Border.all(color: color, width: 1.5),
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(8),
            ),
          ),
          alignment: Alignment.center,
          child: Text(
            '$place',
            style: AppTextStyles.titleLg.copyWith(color: color),
          ),
        ),
      ],
    );
  }
}

class _PuzzleChallengeCard extends StatelessWidget {
  const _PuzzleChallengeCard();

  @override
  Widget build(BuildContext context) {
    return CChessCard(
      onTap: () {},
      child: Row(
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: AppColors.woodLight,
              borderRadius: AppRadius.card,
            ),
            child: const Center(
              child: Icon(Icons.extension_outlined,
                  color: AppColors.woodDark, size: 32),
            ),
          ),
          AppSpacing.hGapMd,
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Chiếu hết trong 3 nước',
                  style: AppTextStyles.headingMd,
                ),
                AppSpacing.vGapXs,
                Text(
                  '488 kỳ thủ đã thử',
                  style: AppTextStyles.captionSm.copyWith(
                    color: AppColors.onSurfaceVariant,
                  ),
                ),
                AppSpacing.vGapXs,
                Row(
                  children: [
                    for (int i = 0; i < 3; i++)
                      const Icon(Icons.star, color: AppColors.accentGold, size: 14),
                    for (int i = 0; i < 2; i++)
                      const Icon(Icons.star_outline,
                          color: AppColors.parchmentTan, size: 14),
                  ],
                ),
              ],
            ),
          ),
          const Icon(Icons.chevron_right, color: AppColors.parchmentTan),
        ],
      ),
    );
  }
}

class _NearbyPlayersRow extends StatelessWidget {
  const _NearbyPlayersRow();

  static const _players = <(String, int, String)>[
    ('Quang Tâm', 1860, '2.4km'),
    ('Lan Phương', 1820, '5km'),
    ('Hoàng Minh', 1200, '8km'),
    ('Trần Khoa', 1480, '12km'),
  ];

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 168,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: _players.length,
        separatorBuilder: (_, _) => AppSpacing.hGapSm,
        itemBuilder: (_, i) {
          final (name, elo, distance) = _players[i];
          return Container(
            width: 128,
            padding: const EdgeInsets.all(AppSpacing.sm),
            decoration: BoxDecoration(
              color: AppColors.surfaceContainerHigh,
              border: Border.all(color: AppColors.outlineVariant),
              borderRadius: AppRadius.card,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    const Icon(
                      Icons.location_on,
                      size: 12,
                      color: AppColors.tealSuccess,
                    ),
                    Text(
                      distance,
                      style: AppTextStyles.captionSm.copyWith(fontSize: 10),
                    ),
                  ],
                ),
                AppSpacing.vGapXs,
                CChessAvatar(initials: name[0], size: 44, elo: elo),
                AppSpacing.vGapXs,
                Text(
                  name,
                  style: AppTextStyles.captionSm.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                ),
                Text(
                  'ELO $elo',
                  style: AppTextStyles.captionSm.copyWith(
                    color: AppColors.parchmentTan,
                  ),
                ),
                const Spacer(),
                CChessButton(
                  label: 'Kết bạn',
                  variant: CChessButtonVariant.outline,
                  icon: Icons.person_add_alt_1,
                  fullWidth: true,
                  height: 28,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 0,
                  ),
                  onPressed: () {},
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
