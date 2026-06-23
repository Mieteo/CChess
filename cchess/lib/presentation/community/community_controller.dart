import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/community_models.dart';
import '../../data/models/user_profile.dart';
import '../../data/repositories/community_repository.dart';
import '../../data/repositories/friend_repository.dart';
import '../../data/repositories/leaderboard_repository.dart';
import '../profile/profile_controller.dart';

class CommunityDashboard {
  const CommunityDashboard({
    required this.profile,
    required this.friends,
    required this.requests,
    required this.leaderboard,
    required this.myRank,
    required this.nearbyPlayers,
    required this.clubs,
    required this.tournaments,
    required this.feed,
  });

  final UserProfile? profile;
  final List<FriendSummary> friends;
  final List<FriendSummary> requests;
  final List<LeaderboardEntry> leaderboard;
  final LeaderboardEntry? myRank;
  final List<CommunityPlayer> nearbyPlayers;
  final List<CommunityClub> clubs;
  final List<CommunityTournament> tournaments;
  final List<CommunityFeedItem> feed;
}

final communityDashboardProvider =
    FutureProvider.autoDispose<CommunityDashboard>((ref) async {
      final profile = ref.watch(profileControllerProvider).valueOrNull;
      final friendRepo = ref.watch(friendRepositoryProvider);
      final leaderboardRepo = ref.watch(leaderboardRepositoryProvider);
      final communityRepo = ref.watch(communityRepositoryProvider);

      final friends = await friendRepo.loadFriends(fallback: profile);
      final leaderboard = await leaderboardRepo.loadLeaderboard(
        profile: profile,
        limit: 10,
      );
      final myRank = profile == null
          ? null
          : await leaderboardRepo.myRank(
              profile: profile,
              boardType: CommunityBoardType.chess,
            );
      final clubs = await communityRepo.loadClubs(limit: 4);
      final tournaments = await communityRepo.loadTournaments(limit: 3);
      final requests = await friendRepo.loadIncomingRequests(fallback: profile);
      final nearbyPlayers = seedCommunityPlayers(
        profile: profile,
      ).where((player) => player.id != profile?.id).take(6).toList();

      return CommunityDashboard(
        profile: profile,
        friends: friends,
        requests: requests,
        leaderboard: leaderboard,
        myRank: myRank,
        nearbyPlayers: nearbyPlayers,
        clubs: clubs,
        tournaments: tournaments,
        feed: communityRepo.loadFeed(),
      );
    });

final friendsProvider = StreamProvider.autoDispose<List<FriendSummary>>((ref) {
  final profile = ref.watch(profileControllerProvider).valueOrNull;
  return ref.watch(friendRepositoryProvider).watchFriends(fallback: profile);
});

final incomingFriendRequestsProvider =
    StreamProvider.autoDispose<List<FriendSummary>>((ref) {
      final profile = ref.watch(profileControllerProvider).valueOrNull;
      return ref
          .watch(friendRepositoryProvider)
          .watchIncomingRequests(fallback: profile);
    });
