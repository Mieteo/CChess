import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/community_models.dart';
import '../models/user_profile.dart';

class FriendRepository {
  FriendRepository(this._db, this._auth);

  final FirebaseFirestore _db;
  final FirebaseAuth _auth;

  CollectionReference<Map<String, dynamic>> _friends(String uid) {
    return _db.collection('friendships').doc(uid).collection('friends');
  }

  CollectionReference<Map<String, dynamic>> get _publicProfiles {
    return _db.collection('public_profiles');
  }

  Stream<List<FriendSummary>> watchFriends({UserProfile? fallback}) {
    return _watchFriendDocs(
      fallback: _seedFriends(
        fallback,
      ).where((friend) => friend.status == FriendStatus.accepted).toList(),
      predicate: (friend) => friend.status == FriendStatus.accepted,
    );
  }

  Stream<List<FriendSummary>> watchIncomingRequests({UserProfile? fallback}) {
    return _watchFriendDocs(
      fallback: _seedFriends(
        fallback,
      ).where((friend) => friend.isIncomingRequest).toList(),
      predicate: (friend) => friend.isIncomingRequest,
    );
  }

  Future<List<FriendSummary>> loadFriends({UserProfile? fallback}) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) {
      return _seedFriends(
        fallback,
      ).where((friend) => friend.status == FriendStatus.accepted).toList();
    }

    try {
      final snap = await _friends(uid).get();
      final friends = snap.docs
          .map((doc) => FriendSummary.fromMap(doc.id, doc.data()))
          .where((friend) => friend.status == FriendStatus.accepted)
          .toList();
      friends.sort(_sortFriends);
      return friends.isEmpty
          ? _seedFriends(
              fallback,
            ).where((friend) => friend.status == FriendStatus.accepted).toList()
          : friends;
    } on FirebaseException {
      return _seedFriends(
        fallback,
      ).where((friend) => friend.status == FriendStatus.accepted).toList();
    }
  }

  Future<List<FriendSummary>> loadIncomingRequests({
    UserProfile? fallback,
  }) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) {
      return _seedFriends(
        fallback,
      ).where((friend) => friend.isIncomingRequest).toList();
    }

    try {
      final snap = await _friends(uid).get();
      final requests = snap.docs
          .map((doc) => FriendSummary.fromMap(doc.id, doc.data()))
          .where((friend) => friend.isIncomingRequest)
          .toList();
      requests.sort(_sortFriends);
      return requests;
    } on FirebaseException {
      return _seedFriends(
        fallback,
      ).where((friend) => friend.isIncomingRequest).toList();
    }
  }

  Stream<List<FriendSummary>> _watchFriendDocs({
    required List<FriendSummary> fallback,
    required bool Function(FriendSummary friend) predicate,
  }) async* {
    final uid = _auth.currentUser?.uid;
    if (uid == null) {
      yield fallback;
      return;
    }

    try {
      await for (final snap in _friends(uid).snapshots()) {
        final friends = snap.docs
            .map((doc) => FriendSummary.fromMap(doc.id, doc.data()))
            .where(predicate)
            .toList();
        friends.sort(_sortFriends);
        yield friends;
      }
    } on FirebaseException {
      yield fallback;
    }
  }

  Future<List<CommunityPlayer>> searchUsers(String query) async {
    final normalized = query.trim().toLowerCase();
    if (normalized.isEmpty) return _seedPlayers();

    try {
      final results = <CommunityPlayer>[];
      final exact = await _publicProfiles.doc(query.trim()).get();
      if (exact.exists && exact.data() != null) {
        results.add(CommunityPlayer.fromMap(exact.id, exact.data()!));
      }

      final prefix = await _publicProfiles
          .orderBy('displayNameLower')
          .startAt([normalized])
          .endAt(['$normalized\uf8ff'])
          .limit(20)
          .get();
      for (final doc in prefix.docs) {
        if (results.any((player) => player.id == doc.id)) continue;
        results.add(CommunityPlayer.fromMap(doc.id, doc.data()));
      }

      if (results.isNotEmpty) return results;
    } on FirebaseException {
      // Fall through to local seed search.
    }

    return _seedPlayers()
        .where(
          (player) =>
              player.displayName.toLowerCase().contains(normalized) ||
              player.region.toLowerCase().contains(normalized) ||
              player.shortId.toLowerCase().contains(normalized),
        )
        .toList();
  }

  Future<void> sendFriendRequest({
    required UserProfile me,
    required CommunityPlayer target,
  }) async {
    final uid = _requireUid();
    if (target.id == uid || target.id == me.id) {
      throw StateError('Không thể kết bạn với chính mình.');
    }

    final now = FieldValue.serverTimestamp();
    final mePlayer = _playerFromProfile(me, uid);
    final batch = _db.batch();
    batch.set(_friends(uid).doc(target.id), {
      ...target.toFriendPayload(),
      'status': FriendStatus.pending.firestoreValue,
      'direction': FriendDirection.outgoing.firestoreValue,
      'since': now,
      'updatedAt': now,
    });
    batch.set(_friends(target.id).doc(uid), {
      ...mePlayer.toFriendPayload(),
      'status': FriendStatus.pending.firestoreValue,
      'direction': FriendDirection.incoming.firestoreValue,
      'since': now,
      'updatedAt': now,
    });
    await batch.commit();
  }

  Future<void> acceptFriendRequest(String requesterUid) async {
    final uid = _requireUid();
    final now = FieldValue.serverTimestamp();
    final batch = _db.batch();
    batch.update(_friends(uid).doc(requesterUid), {
      'status': FriendStatus.accepted.firestoreValue,
      'direction': FriendDirection.accepted.firestoreValue,
      'updatedAt': now,
    });
    batch.update(_friends(requesterUid).doc(uid), {
      'status': FriendStatus.accepted.firestoreValue,
      'direction': FriendDirection.accepted.firestoreValue,
      'updatedAt': now,
    });
    await batch.commit();
  }

  Future<void> declineFriendRequest(String requesterUid) async {
    final uid = _requireUid();
    final batch = _db.batch();
    batch.delete(_friends(uid).doc(requesterUid));
    batch.delete(_friends(requesterUid).doc(uid));
    await batch.commit();
  }

  Future<void> removeFriend(String friendUid) async {
    final uid = _requireUid();
    final batch = _db.batch();
    batch.delete(_friends(uid).doc(friendUid));
    batch.delete(_friends(friendUid).doc(uid));
    await batch.commit();
  }

  String _requireUid() {
    final uid = _auth.currentUser?.uid;
    if (uid == null) {
      throw StateError('Cần đăng nhập để dùng tính năng bạn bè.');
    }
    return uid;
  }

  int _sortFriends(FriendSummary a, FriendSummary b) {
    final online = (b.player.isOnline ? 1 : 0) - (a.player.isOnline ? 1 : 0);
    if (online != 0) return online;
    return a.player.displayName.compareTo(b.player.displayName);
  }

  CommunityPlayer _playerFromProfile(UserProfile profile, String uid) {
    return CommunityPlayer(
      id: uid,
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

final friendRepositoryProvider = Provider<FriendRepository>((ref) {
  return FriendRepository(FirebaseFirestore.instance, FirebaseAuth.instance);
});

List<FriendSummary> seedFriendSummaries(UserProfile? profile) =>
    _seedFriends(profile);

List<CommunityPlayer> seedCommunityPlayers({UserProfile? profile}) {
  final players = _seedPlayers();
  if (profile == null) return players;
  return [
    CommunityPlayer(
      id: profile.id,
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
    ),
    ...players.where((player) => player.id != profile.id),
  ];
}

List<FriendSummary> _seedFriends(UserProfile? profile) {
  final now = DateTime.now();
  final players = seedCommunityPlayers(profile: profile);
  return [
    FriendSummary(
      player: players[1].copyWith(
        lastActiveAt: now.subtract(const Duration(minutes: 3)),
      ),
      status: FriendStatus.accepted,
      direction: FriendDirection.accepted,
      since: now.subtract(const Duration(days: 22)),
      updatedAt: now.subtract(const Duration(minutes: 3)),
    ),
    FriendSummary(
      player: players[2].copyWith(
        lastActiveAt: now.subtract(const Duration(hours: 2)),
      ),
      status: FriendStatus.accepted,
      direction: FriendDirection.accepted,
      since: now.subtract(const Duration(days: 15)),
      updatedAt: now.subtract(const Duration(hours: 2)),
    ),
    FriendSummary(
      player: players[3].copyWith(
        lastActiveAt: now.subtract(const Duration(minutes: 8)),
      ),
      status: FriendStatus.pending,
      direction: FriendDirection.incoming,
      since: now.subtract(const Duration(hours: 4)),
      updatedAt: now.subtract(const Duration(hours: 4)),
    ),
  ];
}

List<CommunityPlayer> _seedPlayers() {
  final now = DateTime.now();
  return [
    CommunityPlayer(
      id: 'seed-lan-phuong',
      displayName: 'Lan Phương',
      region: 'Hà Nội',
      eloChess: 2410,
      eloCup: 2188,
      totalGames: 620,
      wins: 398,
      losses: 169,
      draws: 53,
      lastActiveAt: now.subtract(const Duration(minutes: 3)),
    ),
    CommunityPlayer(
      id: 'seed-hong-vuong',
      displayName: 'Hồng Vương',
      region: 'Hồ Chí Minh',
      eloChess: 2284,
      eloCup: 2241,
      totalGames: 540,
      wins: 330,
      losses: 168,
      draws: 42,
      lastActiveAt: now.subtract(const Duration(hours: 2)),
    ),
    CommunityPlayer(
      id: 'seed-hoang-minh',
      displayName: 'Hoàng Minh',
      region: 'Đà Nẵng',
      eloChess: 2198,
      eloCup: 2302,
      totalGames: 492,
      wins: 301,
      losses: 148,
      draws: 43,
      lastActiveAt: now.subtract(const Duration(minutes: 8)),
    ),
    CommunityPlayer(
      id: 'seed-quang-tam',
      displayName: 'Quang Tâm',
      region: 'Cần Thơ',
      eloChess: 1860,
      eloCup: 1742,
      totalGames: 212,
      wins: 121,
      losses: 74,
      draws: 17,
      lastActiveAt: now.subtract(const Duration(minutes: 42)),
    ),
    CommunityPlayer(
      id: 'seed-tran-khoa',
      displayName: 'Trần Khoa',
      region: 'Hải Phòng',
      eloChess: 1480,
      eloCup: 1512,
      totalGames: 86,
      wins: 42,
      losses: 35,
      draws: 9,
      lastActiveAt: now.subtract(const Duration(days: 1)),
    ),
  ];
}
