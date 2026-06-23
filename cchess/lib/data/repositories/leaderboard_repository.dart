import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/community_models.dart';
import '../models/user_profile.dart';
import 'friend_repository.dart';

class LeaderboardRepository {
  LeaderboardRepository(this._db, this._auth);

  final FirebaseFirestore _db;
  final FirebaseAuth _auth;

  Future<List<LeaderboardEntry>> loadLeaderboard({
    CommunityBoardType boardType = CommunityBoardType.chess,
    LeaderboardScope scope = LeaderboardScope.national,
    String? region,
    List<FriendSummary> friends = const [],
    UserProfile? profile,
    int limit = 50,
  }) async {
    if (scope == LeaderboardScope.friends && friends.isNotEmpty) {
      final players = [
        if (profile != null) _playerFromProfile(profile),
        ...friends
            .where((friend) => friend.isAccepted)
            .map((friend) => friend.player),
      ];
      return _entriesFromPlayers(
        players,
        boardType: boardType,
        profile: profile,
        limit: limit,
      );
    }

    final aggregated = await _loadAggregated(
      boardType: boardType,
      scope: scope,
      region: region,
      profile: profile,
      limit: limit,
    );
    if (aggregated.isNotEmpty) return aggregated;

    final publicProfiles = await _loadPublicProfiles(
      boardType: boardType,
      scope: scope,
      region: region,
      profile: profile,
      limit: limit,
    );
    if (publicProfiles.isNotEmpty) return publicProfiles;

    return _seedLeaderboard(
      boardType: boardType,
      scope: scope,
      region: region,
      profile: profile,
      limit: limit,
    );
  }

  Future<LeaderboardEntry> myRank({
    required UserProfile profile,
    CommunityBoardType boardType = CommunityBoardType.chess,
    LeaderboardScope scope = LeaderboardScope.national,
  }) async {
    final entries = await loadLeaderboard(
      boardType: boardType,
      scope: scope,
      region: profile.region,
      profile: profile,
      limit: 100,
    );
    final uid = _auth.currentUser?.uid ?? profile.id;
    LeaderboardEntry? found;
    for (final entry in entries) {
      if (entry.player.id == uid) {
        found = entry;
        break;
      }
    }
    if (found != null) return found.copyWith(isCurrentUser: true);

    final player = _playerFromProfile(profile, uid: uid);
    final better = entries.where(
      (entry) => entry.elo > player.eloFor(boardType),
    );
    return LeaderboardEntry(
      player: player,
      rank: better.length + 1,
      boardType: boardType,
      elo: player.eloFor(boardType),
      updatedAt: profile.lastActiveAt,
      isCurrentUser: true,
    );
  }

  Future<List<LeaderboardEntry>> _loadAggregated({
    required CommunityBoardType boardType,
    required LeaderboardScope scope,
    required String? region,
    required UserProfile? profile,
    required int limit,
  }) async {
    if (scope == LeaderboardScope.friends) return const [];
    try {
      final period = _periodFor(scope, region ?? profile?.region);
      final snap = await _db
          .collection('leaderboards')
          .doc(boardType.firestoreKey)
          .collection(period)
          .orderBy('elo', descending: true)
          .limit(limit)
          .get();
      final uid = _auth.currentUser?.uid ?? profile?.id;
      return [
        for (var i = 0; i < snap.docs.length; i++)
          LeaderboardEntry.fromMap(
            id: snap.docs[i].id,
            rank: i + 1,
            boardType: boardType,
            data: snap.docs[i].data(),
            currentUid: uid,
          ),
      ];
    } on FirebaseException {
      return const [];
    }
  }

  Future<List<LeaderboardEntry>> _loadPublicProfiles({
    required CommunityBoardType boardType,
    required LeaderboardScope scope,
    required String? region,
    required UserProfile? profile,
    required int limit,
  }) async {
    try {
      Query<Map<String, dynamic>> query = _db.collection('public_profiles');
      if (scope == LeaderboardScope.regional) {
        final selectedRegion = region ?? profile?.region;
        if (selectedRegion != null && selectedRegion.isNotEmpty) {
          query = query.where('region', isEqualTo: selectedRegion);
        }
      } else {
        query = query.orderBy(boardType.eloField, descending: true);
      }

      final snap = await query.limit(limit).get();
      final players = snap.docs
          .map((doc) => CommunityPlayer.fromMap(doc.id, doc.data()))
          .toList();
      return _entriesFromPlayers(
        players,
        boardType: boardType,
        profile: profile,
        limit: limit,
      );
    } on FirebaseException {
      return const [];
    }
  }

  List<LeaderboardEntry> _seedLeaderboard({
    required CommunityBoardType boardType,
    required LeaderboardScope scope,
    required String? region,
    required UserProfile? profile,
    required int limit,
  }) {
    var players = seedCommunityPlayers(profile: profile);
    if (scope == LeaderboardScope.regional) {
      final selectedRegion = region ?? profile?.region;
      if (selectedRegion != null) {
        players = players
            .where(
              (player) =>
                  player.region == selectedRegion ||
                  player.id == (_auth.currentUser?.uid ?? profile?.id),
            )
            .toList();
      }
    }
    return _entriesFromPlayers(
      players,
      boardType: boardType,
      profile: profile,
      limit: limit,
    );
  }

  List<LeaderboardEntry> _entriesFromPlayers(
    List<CommunityPlayer> players, {
    required CommunityBoardType boardType,
    required UserProfile? profile,
    required int limit,
  }) {
    final uid = _auth.currentUser?.uid ?? profile?.id;
    final unique = <String, CommunityPlayer>{};
    for (final player in players) {
      unique[player.id] = player;
    }
    final sorted = unique.values.toList()
      ..sort((a, b) => b.eloFor(boardType).compareTo(a.eloFor(boardType)));
    return [
      for (var i = 0; i < sorted.take(limit).length; i++)
        LeaderboardEntry(
          player: sorted[i],
          rank: i + 1,
          boardType: boardType,
          elo: sorted[i].eloFor(boardType),
          updatedAt: sorted[i].lastActiveAt,
          isCurrentUser: uid != null && sorted[i].id == uid,
        ),
    ];
  }

  String _periodFor(LeaderboardScope scope, String? region) {
    return switch (scope) {
      LeaderboardScope.national => 'national',
      LeaderboardScope.regional =>
        'region_${Uri.encodeComponent(region ?? 'Khác')}',
      LeaderboardScope.friends => 'friends',
    };
  }

  CommunityPlayer _playerFromProfile(UserProfile profile, {String? uid}) {
    return CommunityPlayer(
      id: uid ?? profile.id,
      displayName: profile.displayName,
      region: profile.region,
      avatarUrl: profile.avatarUrl,
      eloChess: profile.eloChess,
      eloCup: profile.eloCup,
      totalGames: profile.totalGames,
      wins: profile.wins,
      losses: profile.losses,
      draws: profile.draws,
      lastActiveAt: profile.lastActiveAt,
    );
  }
}

final leaderboardRepositoryProvider = Provider<LeaderboardRepository>((ref) {
  return LeaderboardRepository(
    FirebaseFirestore.instance,
    FirebaseAuth.instance,
  );
});
