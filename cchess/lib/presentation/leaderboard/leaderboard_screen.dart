import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/community_models.dart';
import '../../data/repositories/leaderboard_repository.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_text_styles.dart';
import '../../widgets/common/common.dart';
import '../community/community_controller.dart';
import '../community/community_widgets.dart';
import '../profile/profile_controller.dart';

class LeaderboardScreen extends ConsumerStatefulWidget {
  const LeaderboardScreen({super.key});

  @override
  ConsumerState<LeaderboardScreen> createState() => _LeaderboardScreenState();
}

class _LeaderboardScreenState extends ConsumerState<LeaderboardScreen> {
  CommunityBoardType _boardType = CommunityBoardType.chess;
  LeaderboardScope _scope = LeaderboardScope.national;

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(profileControllerProvider).valueOrNull;
    final friends = ref.watch(friendsProvider).valueOrNull ?? const [];
    final repo = ref.watch(leaderboardRepositoryProvider);
    final future = repo.loadLeaderboard(
      boardType: _boardType,
      scope: _scope,
      region: profile?.region,
      friends: friends,
      profile: profile,
      limit: 100,
    );

    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.base,
        AppSpacing.base,
        AppSpacing.base,
        96,
      ),
      children: [
        const CommunityPageHeader(
          title: 'Bảng Xếp Hạng',
          subtitle: 'Theo ELO toàn quốc, khu vực và bạn bè',
          icon: Icons.leaderboard_outlined,
          showBack: true,
        ),
        AppSpacing.vGapLg,
        _SegmentPanel(
          boardType: _boardType,
          scope: _scope,
          onBoardChanged: (value) => setState(() => _boardType = value),
          onScopeChanged: (value) => setState(() => _scope = value),
        ),
        AppSpacing.vGapLg,
        FutureBuilder<List<LeaderboardEntry>>(
          future: future,
          builder: (context, snapshot) {
            if (!snapshot.hasData) {
              return const Center(child: BrushStrokeSpinner());
            }
            final entries = snapshot.data!;
            if (entries.isEmpty) {
              return const CommunityEmptyState(
                icon: Icons.leaderboard_outlined,
                title: 'Chưa có dữ liệu',
                message: 'Hãy hoàn thành vài ván xếp hạng để mở bảng XH.',
              );
            }
            final current = entries
                .where((entry) => entry.isCurrentUser)
                .toList();
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (current.isNotEmpty) ...[
                  _MyRankCard(entry: current.first),
                  AppSpacing.vGapLg,
                ],
                _Podium(entries: entries.take(3).toList()),
                AppSpacing.vGapLg,
                SectionHeader(title: _scope.label),
                AppSpacing.vGapMd,
                for (final entry in entries) ...[
                  CommunityPlayerRow(
                    player: entry.player,
                    rank: entry.rank,
                    boardType: _boardType,
                    highlight: entry.isCurrentUser,
                    subtitle:
                        '${entry.player.region} • ELO ${entry.elo} • ${entry.player.totalGames} ván',
                  ),
                  if (entry != entries.last) AppSpacing.vGapSm,
                ],
              ],
            );
          },
        ),
      ],
    );
  }
}

class _SegmentPanel extends StatelessWidget {
  const _SegmentPanel({
    required this.boardType,
    required this.scope,
    required this.onBoardChanged,
    required this.onScopeChanged,
  });

  final CommunityBoardType boardType;
  final LeaderboardScope scope;
  final ValueChanged<CommunityBoardType> onBoardChanged;
  final ValueChanged<LeaderboardScope> onScopeChanged;

  @override
  Widget build(BuildContext context) {
    return CChessCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Biến thể', style: AppTextStyles.captionSm),
          AppSpacing.vGapXs,
          SegmentedButton<CommunityBoardType>(
            segments: [
              for (final type in CommunityBoardType.values)
                ButtonSegment(value: type, label: Text(type.label)),
            ],
            selected: {boardType},
            onSelectionChanged: (values) => onBoardChanged(values.first),
          ),
          AppSpacing.vGapMd,
          Text('Phạm vi', style: AppTextStyles.captionSm),
          AppSpacing.vGapXs,
          SegmentedButton<LeaderboardScope>(
            segments: [
              for (final item in LeaderboardScope.values)
                ButtonSegment(value: item, label: Text(item.label)),
            ],
            selected: {scope},
            onSelectionChanged: (values) => onScopeChanged(values.first),
          ),
        ],
      ),
    );
  }
}

class _MyRankCard extends StatelessWidget {
  const _MyRankCard({required this.entry});

  final LeaderboardEntry entry;

  @override
  Widget build(BuildContext context) {
    return CChessCard(
      borderColor: AppColors.accentGold.withValues(alpha: 0.45),
      child: Row(
        children: [
          const Icon(
            Icons.military_tech,
            color: AppColors.accentGold,
            size: 32,
          ),
          AppSpacing.hGapMd,
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Thứ hạng của bạn', style: AppTextStyles.headingMd),
                AppSpacing.vGapXs,
                Text(
                  '#${entry.rank} • ELO ${entry.elo}',
                  style: AppTextStyles.captionSm.copyWith(
                    color: AppColors.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          CChessRankBadge(elo: entry.elo),
        ],
      ),
    );
  }
}

class _Podium extends StatelessWidget {
  const _Podium({required this.entries});

  final List<LeaderboardEntry> entries;

  @override
  Widget build(BuildContext context) {
    return CChessCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (final entry in entries)
            Expanded(
              child: Column(
                children: [
                  CChessAvatar(
                    initials: entry.player.initials,
                    size: entry.rank == 1 ? 58 : 48,
                    elo: entry.elo,
                  ),
                  AppSpacing.vGapXs,
                  Text(
                    entry.player.displayName,
                    style: AppTextStyles.captionSm.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    '#${entry.rank}',
                    style: AppTextStyles.titleLg.copyWith(
                      color: entry.rank == 1
                          ? AppColors.accentGold
                          : AppColors.parchmentTan,
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
