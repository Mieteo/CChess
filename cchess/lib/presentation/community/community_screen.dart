import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants/app_constants.dart';
import '../../data/models/community_models.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_text_styles.dart';
import '../../widgets/common/common.dart';
import '../puzzle/puzzle_list_controller.dart';
import 'community_controller.dart';
import 'community_widgets.dart';

/// Cộng Đồng — friends, leaderboard, clubs, tournaments and daily feed.
class CommunityScreen extends ConsumerWidget {
  const CommunityScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dashboard = ref.watch(communityDashboardProvider);

    return dashboard.when(
      loading: () => const Center(child: BrushStrokeSpinner()),
      error: (error, _) => ListView(
        padding: const EdgeInsets.all(AppSpacing.base),
        children: [
          const CommunityPageHeader(
            title: 'Cộng Đồng Cờ Tướng',
            subtitle: 'Kết nối kỳ thủ Việt khắp cả nước',
            icon: Icons.groups_outlined,
          ),
          AppSpacing.vGapLg,
          CommunityEmptyState(
            icon: Icons.cloud_off_outlined,
            title: 'Chưa tải được cộng đồng',
            message: '$error',
          ),
        ],
      ),
      data: (data) {
        final onlineFriends = data.friends
            .where((friend) => friend.player.isOnline)
            .length;
        return RefreshIndicator(
          color: AppColors.accentGold,
          onRefresh: () => ref.refresh(communityDashboardProvider.future),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.base,
              AppSpacing.base,
              AppSpacing.base,
              96,
            ),
            children: [
              const CommunityPageHeader(
                title: 'Cộng Đồng Cờ Tướng',
                subtitle: 'Kết nối kỳ thủ Việt khắp cả nước',
                icon: Icons.groups_outlined,
              ),
              AppSpacing.vGapLg,
              Row(
                children: [
                  Expanded(
                    child: CommunityMetricChip(
                      icon: Icons.people_outline,
                      label: 'bạn online',
                      value: '$onlineFriends',
                      color: AppColors.tealSuccess,
                    ),
                  ),
                  AppSpacing.hGapSm,
                  Expanded(
                    child: CommunityMetricChip(
                      icon: Icons.leaderboard_outlined,
                      label: 'hạng của bạn',
                      value: data.myRank == null
                          ? '—'
                          : '#${data.myRank!.rank}',
                    ),
                  ),
                  AppSpacing.hGapSm,
                  Expanded(
                    child: CommunityMetricChip(
                      icon: Icons.mail_outline,
                      label: 'lời mời',
                      value: '${data.requests.length}',
                      color: AppColors.tertiary,
                    ),
                  ),
                ],
              ),
              AppSpacing.vGapLg,
              _QuickAccessRow(
                onFriends: () => context.go(AppConstants.routeCommunityFriends),
                onLeaderboard: () =>
                    context.go(AppConstants.routeCommunityLeaderboard),
                onClubs: () => context.go(AppConstants.routeCommunityClubs),
                onTournaments: () =>
                    context.go(AppConstants.routeCommunityTournaments),
                onLive: () => context.push(AppConstants.routeOnlineLobby),
              ),
              AppSpacing.vGapLg,
              SectionHeader(
                title: 'Bạn bè',
                actionLabel: 'Quản lý',
                onActionPressed: () =>
                    context.go(AppConstants.routeCommunityFriends),
              ),
              AppSpacing.vGapMd,
              _FriendSnapshot(friends: data.friends, requests: data.requests),
              AppSpacing.vGapLg,
              SectionHeader(
                title: 'Top kỳ thủ tuần này',
                actionLabel: 'Bảng XH',
                onActionPressed: () =>
                    context.go(AppConstants.routeCommunityLeaderboard),
              ),
              AppSpacing.vGapMd,
              _LeaderboardPreview(entries: data.leaderboard),
              AppSpacing.vGapLg,
              const SectionHeader(title: 'Tin cộng đồng'),
              AppSpacing.vGapMd,
              _FeedSection(items: data.feed),
              AppSpacing.vGapLg,
              SectionHeader(
                title: 'Kỳ Xã nổi bật',
                actionLabel: 'Xem CLB',
                onActionPressed: () =>
                    context.go(AppConstants.routeCommunityClubs),
              ),
              AppSpacing.vGapMd,
              _ClubPreview(clubs: data.clubs),
              AppSpacing.vGapLg,
              SectionHeader(
                title: 'Giải đấu sắp tới',
                actionLabel: 'Lịch đấu',
                onActionPressed: () =>
                    context.go(AppConstants.routeCommunityTournaments),
              ),
              AppSpacing.vGapMd,
              _TournamentPreview(tournaments: data.tournaments),
              AppSpacing.vGapLg,
              const SectionHeader(title: 'Kỳ thủ gần bạn'),
              AppSpacing.vGapMd,
              _NearbyPlayersRow(players: data.nearbyPlayers),
            ],
          ),
        );
      },
    );
  }
}

class _QuickAccessRow extends StatelessWidget {
  const _QuickAccessRow({
    required this.onFriends,
    required this.onLeaderboard,
    required this.onClubs,
    required this.onTournaments,
    required this.onLive,
  });

  final VoidCallback onFriends;
  final VoidCallback onLeaderboard;
  final VoidCallback onClubs;
  final VoidCallback onTournaments;
  final VoidCallback onLive;

  @override
  Widget build(BuildContext context) {
    final items = <_QuickAccessItem>[
      _QuickAccessItem(Icons.people_outline, 'Bạn Bè', onFriends),
      _QuickAccessItem(Icons.leaderboard_outlined, 'Bảng XH', onLeaderboard),
      _QuickAccessItem(Icons.workspace_premium_outlined, 'Kỳ Xã', onClubs),
      _QuickAccessItem(Icons.emoji_events_outlined, 'Giải Đấu', onTournaments),
      _QuickAccessItem(Icons.live_tv_outlined, 'Live', onLive),
    ];
    return Row(
      children: [
        for (final item in items)
          Expanded(
            child: InkWell(
              borderRadius: BorderRadius.circular(AppRadius.lg),
              onTap: item.onTap,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
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
                      child: Icon(item.icon, color: AppColors.accentGold),
                    ),
                    AppSpacing.vGapXs,
                    Text(
                      item.label,
                      style: AppTextStyles.captionSm.copyWith(
                        color: AppColors.onSurfaceVariant,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
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

class _QuickAccessItem {
  const _QuickAccessItem(this.icon, this.label, this.onTap);
  final IconData icon;
  final String label;
  final VoidCallback onTap;
}

class _FriendSnapshot extends StatelessWidget {
  const _FriendSnapshot({required this.friends, required this.requests});

  final List<FriendSummary> friends;
  final List<FriendSummary> requests;

  @override
  Widget build(BuildContext context) {
    final visibleFriends = friends.take(3).toList();
    return Column(
      children: [
        if (requests.isNotEmpty) ...[
          CChessCard(
            child: Row(
              children: [
                const Icon(
                  Icons.mark_email_unread_outlined,
                  color: AppColors.tertiary,
                ),
                AppSpacing.hGapSm,
                Expanded(
                  child: Text(
                    '${requests.length} lời mời kết bạn đang chờ',
                    style: AppTextStyles.bodyMd.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: () =>
                      context.go(AppConstants.routeCommunityFriends),
                  child: const Text('Xử lý'),
                ),
              ],
            ),
          ),
          AppSpacing.vGapSm,
        ],
        if (visibleFriends.isEmpty)
          const CommunityEmptyState(
            icon: Icons.person_add_alt_1,
            title: 'Chưa có bạn bè',
            message: 'Tìm kỳ thủ theo tên hoặc ID để bắt đầu kết nối.',
          )
        else
          for (final friend in visibleFriends) ...[
            CommunityPlayerRow(
              player: friend.player,
              subtitle: friend.player.isOnline
                  ? 'Đang online • ELO ${friend.player.eloChess}'
                  : '${friend.player.region} • offline',
              trailing: IconButton(
                tooltip: 'Mời đấu',
                icon: const Icon(
                  Icons.sports_kabaddi,
                  color: AppColors.accentGold,
                ),
                onPressed: () =>
                    context.push('${AppConstants.routeOnlineLobby}?casual=1'),
              ),
            ),
            if (friend != visibleFriends.last) AppSpacing.vGapSm,
          ],
      ],
    );
  }
}

class _LeaderboardPreview extends StatelessWidget {
  const _LeaderboardPreview({required this.entries});

  final List<LeaderboardEntry> entries;

  @override
  Widget build(BuildContext context) {
    if (entries.isEmpty) {
      return const CommunityEmptyState(
        icon: Icons.leaderboard_outlined,
        title: 'Chưa có bảng xếp hạng',
        message: 'Bảng XH sẽ xuất hiện sau khi có dữ liệu ELO từ server.',
      );
    }
    final top = entries.take(3).toList();
    return CChessCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (final entry in top) Expanded(child: _PodiumPlayer(entry: entry)),
        ],
      ),
    );
  }
}

class _PodiumPlayer extends StatelessWidget {
  const _PodiumPlayer({required this.entry});

  final LeaderboardEntry entry;

  @override
  Widget build(BuildContext context) {
    final (color, height) = switch (entry.rank) {
      1 => (AppColors.accentGold, 84.0),
      2 => (AppColors.outline, 64.0),
      _ => (AppColors.parchmentTan, 52.0),
    };
    return Column(
      children: [
        CChessAvatar(initials: entry.player.initials, size: 44, elo: entry.elo),
        AppSpacing.vGapXs,
        Text(
          entry.player.displayName,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: AppTextStyles.bodyMd.copyWith(fontWeight: FontWeight.w600),
        ),
        Text(
          'ELO ${entry.elo}',
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
            borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
          ),
          alignment: Alignment.center,
          child: Text(
            '${entry.rank}',
            style: AppTextStyles.titleLg.copyWith(color: color),
          ),
        ),
      ],
    );
  }
}

class _FeedSection extends StatelessWidget {
  const _FeedSection({required this.items});

  final List<CommunityFeedItem> items;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (final item in items) ...[
          _FeedCard(item: item),
          if (item != items.last) AppSpacing.vGapSm,
        ],
      ],
    );
  }
}

class _FeedCard extends ConsumerWidget {
  const _FeedCard({required this.item});

  final CommunityFeedItem item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final (icon, color, action) = switch (item.type) {
      CommunityFeedType.puzzle => (
        Icons.extension_outlined,
        AppColors.woodLight,
        'Thử ngay',
      ),
      CommunityFeedType.match => (
        Icons.visibility_outlined,
        AppColors.tertiary,
        'Xem',
      ),
      CommunityFeedType.news => (
        Icons.article_outlined,
        AppColors.tealSuccess,
        'Đọc',
      ),
    };
    return CChessCard(
      onTap: () => _handleFeedTap(context, ref),
      child: Row(
        children: [
          Container(
            width: 58,
            height: 58,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.16),
              borderRadius: AppRadius.card,
              border: Border.all(color: color.withValues(alpha: 0.38)),
            ),
            child: Icon(icon, color: color, size: 30),
          ),
          AppSpacing.hGapMd,
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item.title, style: AppTextStyles.headingMd),
                AppSpacing.vGapXs,
                Text(
                  item.subtitle,
                  style: AppTextStyles.captionSm.copyWith(
                    color: AppColors.onSurfaceVariant,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                AppSpacing.vGapXs,
                Text(
                  item.meta,
                  style: AppTextStyles.captionSm.copyWith(
                    color: AppColors.parchmentTan,
                  ),
                ),
              ],
            ),
          ),
          AppSpacing.hGapSm,
          Text(
            action,
            style: AppTextStyles.captionSm.copyWith(
              color: AppColors.accentGold,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _handleFeedTap(BuildContext context, WidgetRef ref) async {
    if (item.route == 'daily_puzzle') {
      final puzzle = await ref.read(dailyPuzzleProvider.future);
      if (!context.mounted) return;
      if (puzzle != null) {
        context.push('${AppConstants.routePuzzle}/${puzzle.id}');
      } else {
        context.go(AppConstants.routePuzzle);
      }
      return;
    }
    if (item.linkUrl != null) {
      _showLinkDialog(context, item.linkUrl!);
      return;
    }
    switch (item.type) {
      case CommunityFeedType.puzzle:
        context.go(AppConstants.routePuzzle);
      case CommunityFeedType.match:
        context.push(AppConstants.routeOnlineLobby);
      case CommunityFeedType.news:
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Tin cộng đồng sẽ mở ở bản kế tiếp.')),
        );
    }
  }

  void _showLinkDialog(BuildContext context, String url) {
    showDialog<void>(
      context: context,
      builder: (ctx) => CChessDialog(
        title: item.title,
        leadingIcon: Icons.article_outlined,
        content: Text(url, style: AppTextStyles.bodyMd),
        actions: [
          CChessButton(
            label: 'Đóng',
            variant: CChessButtonVariant.outline,
            onPressed: () => Navigator.of(ctx).pop(),
          ),
          AppSpacing.hGapMd,
          CChessButton(
            label: 'Sao chép liên kết',
            onPressed: () {
              Clipboard.setData(ClipboardData(text: url));
              Navigator.of(ctx).pop();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Đã sao chép liên kết')),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _ClubPreview extends StatelessWidget {
  const _ClubPreview({required this.clubs});

  final List<CommunityClub> clubs;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 142,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: clubs.length,
        separatorBuilder: (_, _) => AppSpacing.hGapSm,
        itemBuilder: (_, index) {
          final club = clubs[index];
          return SizedBox(
            width: 224,
            child: CChessCard(
              onTap: () => context.go(AppConstants.routeCommunityClubs),
              borderColor: club.isMember
                  ? AppColors.accentGold.withValues(alpha: 0.45)
                  : AppColors.outlineVariant,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(
                        Icons.workspace_premium_outlined,
                        color: AppColors.accentGold,
                      ),
                      AppSpacing.hGapSm,
                      Expanded(
                        child: Text(
                          club.name,
                          style: AppTextStyles.headingMd,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  AppSpacing.vGapXs,
                  Text(
                    club.region,
                    style: AppTextStyles.captionSm.copyWith(
                      color: AppColors.parchmentTan,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    '${club.memberCount} thành viên • ${club.weeklyScore} điểm',
                    style: AppTextStyles.captionSm.copyWith(
                      color: AppColors.onSurfaceVariant,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _TournamentPreview extends StatelessWidget {
  const _TournamentPreview({required this.tournaments});

  final List<CommunityTournament> tournaments;

  @override
  Widget build(BuildContext context) {
    if (tournaments.isEmpty) {
      return const CommunityEmptyState(
        icon: Icons.emoji_events_outlined,
        title: 'Chưa có giải đấu',
        message: 'Các giải định kỳ sẽ xuất hiện tại đây.',
      );
    }
    final next = tournaments.first;
    return CChessCard(
      onTap: () => context.go(AppConstants.routeCommunityTournaments),
      borderColor: AppColors.accentGold.withValues(alpha: 0.35),
      child: Row(
        children: [
          const Icon(Icons.emoji_events, color: AppColors.accentGold, size: 34),
          AppSpacing.hGapMd,
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(next.name, style: AppTextStyles.headingMd),
                AppSpacing.vGapXs,
                Text(
                  '${next.mode} • ${next.statusLabel}',
                  style: AppTextStyles.captionSm.copyWith(
                    color: AppColors.onSurfaceVariant,
                  ),
                ),
                AppSpacing.vGapSm,
                CChessProgressBar(value: next.fillRatio),
                AppSpacing.vGapXs,
                Text(
                  '${next.registeredPlayers}/${next.capacity} kỳ thủ',
                  style: AppTextStyles.captionSm.copyWith(
                    color: AppColors.parchmentTan,
                  ),
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
  const _NearbyPlayersRow({required this.players});

  final List<CommunityPlayer> players;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 170,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: players.length,
        separatorBuilder: (_, _) => AppSpacing.hGapSm,
        itemBuilder: (_, index) {
          final player = players[index];
          return Container(
            width: 132,
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
                      '${(index + 1) * 2}km',
                      style: AppTextStyles.captionSm.copyWith(fontSize: 10),
                    ),
                  ],
                ),
                AppSpacing.vGapXs,
                CChessAvatar(
                  initials: player.initials,
                  size: 44,
                  elo: player.eloChess,
                ),
                AppSpacing.vGapXs,
                Text(
                  player.displayName,
                  style: AppTextStyles.captionSm.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                ),
                Text(
                  'ELO ${player.eloChess}',
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
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  onPressed: () =>
                      context.go(AppConstants.routeCommunityFriends),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
