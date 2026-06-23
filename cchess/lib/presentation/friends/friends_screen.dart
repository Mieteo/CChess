import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants/app_constants.dart';
import '../../data/models/community_models.dart';
import '../../data/repositories/friend_repository.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_text_styles.dart';
import '../../widgets/common/common.dart';
import '../community/community_controller.dart';
import '../community/community_widgets.dart';
import '../profile/profile_controller.dart';

class FriendsScreen extends ConsumerStatefulWidget {
  const FriendsScreen({super.key});

  @override
  ConsumerState<FriendsScreen> createState() => _FriendsScreenState();
}

class _FriendsScreenState extends ConsumerState<FriendsScreen> {
  final _searchCtrl = TextEditingController();
  Future<List<CommunityPlayer>>? _searchFuture;

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  void _search() {
    final query = _searchCtrl.text.trim();
    setState(() {
      _searchFuture = query.isEmpty
          ? null
          : ref.read(friendRepositoryProvider).searchUsers(query);
    });
  }

  Future<void> _runAction(
    Future<void> Function() action,
    String success,
  ) async {
    try {
      await action();
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(success)));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  @override
  Widget build(BuildContext context) {
    final friends = ref.watch(friendsProvider);
    final requests = ref.watch(incomingFriendRequestsProvider);
    final profile = ref.watch(profileControllerProvider).valueOrNull;

    return DefaultTabController(
      length: 2,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.base,
          AppSpacing.base,
          AppSpacing.base,
          96,
        ),
        child: Column(
          children: [
            const CommunityPageHeader(
              title: 'Bạn Bè',
              subtitle: 'Tìm kỳ thủ, nhận lời mời và rủ bạn đấu casual',
              icon: Icons.people_outline,
              showBack: true,
            ),
            AppSpacing.vGapLg,
            Container(
              decoration: BoxDecoration(
                color: AppColors.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(AppRadius.lg),
                border: Border.all(color: AppColors.outlineVariant),
              ),
              child: const TabBar(
                indicatorColor: AppColors.accentGold,
                labelColor: AppColors.accentGold,
                unselectedLabelColor: AppColors.onSurfaceVariant,
                tabs: [
                  Tab(text: 'Danh sách'),
                  Tab(text: 'Tìm bạn'),
                ],
              ),
            ),
            AppSpacing.vGapMd,
            Expanded(
              child: TabBarView(
                children: [
                  _FriendListTab(
                    friends: friends,
                    requests: requests,
                    onAccept: (uid) => _runAction(
                      () => ref
                          .read(friendRepositoryProvider)
                          .acceptFriendRequest(uid),
                      'Đã chấp nhận lời mời.',
                    ),
                    onDecline: (uid) => _runAction(
                      () => ref
                          .read(friendRepositoryProvider)
                          .declineFriendRequest(uid),
                      'Đã bỏ qua lời mời.',
                    ),
                    onRemove: (uid) => _runAction(
                      () =>
                          ref.read(friendRepositoryProvider).removeFriend(uid),
                      'Đã xoá khỏi danh sách bạn.',
                    ),
                  ),
                  _SearchFriendTab(
                    controller: _searchCtrl,
                    searchFuture: _searchFuture,
                    onSearch: _search,
                    onSendRequest: (player) {
                      if (profile == null) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Hồ sơ chưa sẵn sàng, thử lại sau.'),
                          ),
                        );
                        return;
                      }
                      _runAction(
                        () => ref
                            .read(friendRepositoryProvider)
                            .sendFriendRequest(me: profile, target: player),
                        'Đã gửi lời mời kết bạn.',
                      );
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FriendListTab extends StatelessWidget {
  const _FriendListTab({
    required this.friends,
    required this.requests,
    required this.onAccept,
    required this.onDecline,
    required this.onRemove,
  });

  final AsyncValue<List<FriendSummary>> friends;
  final AsyncValue<List<FriendSummary>> requests;
  final ValueChanged<String> onAccept;
  final ValueChanged<String> onDecline;
  final ValueChanged<String> onRemove;

  @override
  Widget build(BuildContext context) {
    return ListView(
      children: [
        requests.when(
          loading: () => const Center(child: BrushStrokeSpinner()),
          error: (error, _) => Text('Lỗi lời mời: $error'),
          data: (items) => _RequestsSection(
            requests: items,
            onAccept: onAccept,
            onDecline: onDecline,
          ),
        ),
        AppSpacing.vGapLg,
        SectionHeader(title: 'Bạn bè của tôi'),
        AppSpacing.vGapMd,
        friends.when(
          loading: () => const Center(child: BrushStrokeSpinner()),
          error: (error, _) => Text('Lỗi danh sách bạn: $error'),
          data: (items) {
            if (items.isEmpty) {
              return const CommunityEmptyState(
                icon: Icons.person_add_alt_1,
                title: 'Chưa có bạn bè',
                message: 'Sang tab Tìm bạn để kết nối với kỳ thủ khác.',
              );
            }
            return Column(
              children: [
                for (final friend in items) ...[
                  CommunityPlayerRow(
                    player: friend.player,
                    subtitle: friend.player.isOnline
                        ? 'Đang online • ${friend.player.region}'
                        : '${friend.player.region} • vừa offline',
                    trailing: Wrap(
                      spacing: 4,
                      children: [
                        IconButton(
                          tooltip: 'Mời đấu',
                          icon: const Icon(
                            Icons.sports_kabaddi,
                            color: AppColors.accentGold,
                          ),
                          onPressed: () => context.push(
                            '${AppConstants.routeOnlineLobby}?casual=1',
                          ),
                        ),
                        IconButton(
                          tooltip: 'Xoá bạn',
                          icon: const Icon(
                            Icons.person_remove_outlined,
                            color: AppColors.parchmentTan,
                          ),
                          onPressed: () => onRemove(friend.player.id),
                        ),
                      ],
                    ),
                  ),
                  if (friend != items.last) AppSpacing.vGapSm,
                ],
              ],
            );
          },
        ),
      ],
    );
  }
}

class _RequestsSection extends StatelessWidget {
  const _RequestsSection({
    required this.requests,
    required this.onAccept,
    required this.onDecline,
  });

  final List<FriendSummary> requests;
  final ValueChanged<String> onAccept;
  final ValueChanged<String> onDecline;

  @override
  Widget build(BuildContext context) {
    if (requests.isEmpty) {
      return CChessCard(
        child: Row(
          children: [
            const Icon(
              Icons.mark_email_read_outlined,
              color: AppColors.tealSuccess,
            ),
            AppSpacing.hGapSm,
            Expanded(
              child: Text(
                'Không có lời mời mới',
                style: AppTextStyles.bodyMd.copyWith(
                  color: AppColors.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(title: 'Lời mời kết bạn'),
        AppSpacing.vGapMd,
        for (final request in requests) ...[
          CommunityPlayerRow(
            player: request.player,
            subtitle:
                '${request.player.region} • ELO ${request.player.eloChess}',
            trailing: Wrap(
              spacing: 4,
              children: [
                IconButton(
                  tooltip: 'Chấp nhận',
                  icon: const Icon(
                    Icons.check_circle,
                    color: AppColors.tealSuccess,
                  ),
                  onPressed: () => onAccept(request.player.id),
                ),
                IconButton(
                  tooltip: 'Từ chối',
                  icon: const Icon(
                    Icons.cancel_outlined,
                    color: AppColors.error,
                  ),
                  onPressed: () => onDecline(request.player.id),
                ),
              ],
            ),
          ),
          if (request != requests.last) AppSpacing.vGapSm,
        ],
      ],
    );
  }
}

class _SearchFriendTab extends StatelessWidget {
  const _SearchFriendTab({
    required this.controller,
    required this.searchFuture,
    required this.onSearch,
    required this.onSendRequest,
  });

  final TextEditingController controller;
  final Future<List<CommunityPlayer>>? searchFuture;
  final VoidCallback onSearch;
  final ValueChanged<CommunityPlayer> onSendRequest;

  @override
  Widget build(BuildContext context) {
    return ListView(
      children: [
        TextField(
          controller: controller,
          textInputAction: TextInputAction.search,
          onSubmitted: (_) => onSearch(),
          decoration: InputDecoration(
            labelText: 'Tên kỳ thủ hoặc UID',
            prefixIcon: const Icon(Icons.search),
            suffixIcon: IconButton(
              tooltip: 'Tìm',
              icon: const Icon(Icons.arrow_forward),
              onPressed: onSearch,
            ),
          ),
        ),
        AppSpacing.vGapMd,
        if (searchFuture == null)
          const CommunityEmptyState(
            icon: Icons.manage_search,
            title: 'Tìm bạn theo tên hoặc ID',
            message: 'Nhập ít nhất một phần tên kỳ thủ để tìm public profile.',
          )
        else
          FutureBuilder<List<CommunityPlayer>>(
            future: searchFuture,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const Center(child: BrushStrokeSpinner());
              }
              final players = snapshot.data ?? const <CommunityPlayer>[];
              if (players.isEmpty) {
                return const CommunityEmptyState(
                  icon: Icons.search_off,
                  title: 'Không tìm thấy kỳ thủ',
                  message: 'Thử tên khác hoặc nhập UID đầy đủ.',
                );
              }
              return Column(
                children: [
                  for (final player in players) ...[
                    CommunityPlayerRow(
                      player: player,
                      subtitle:
                          '${player.shortId} • ${player.region} • ELO ${player.eloChess}',
                      trailing: CChessButton(
                        label: 'Kết bạn',
                        icon: Icons.person_add_alt_1,
                        variant: CChessButtonVariant.outline,
                        height: 34,
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        onPressed: () => onSendRequest(player),
                      ),
                    ),
                    if (player != players.last) AppSpacing.vGapSm,
                  ],
                ],
              );
            },
          ),
      ],
    );
  }
}
