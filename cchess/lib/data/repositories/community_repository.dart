import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/community_models.dart';

class CommunityRepository {
  CommunityRepository(this._db);

  final FirebaseFirestore _db;

  Future<List<CommunityClub>> loadClubs({int limit = 8}) async {
    try {
      final snap = await _db
          .collection('clubs')
          .orderBy('weeklyScore', descending: true)
          .limit(limit)
          .get();
      final clubs = snap.docs
          .map((doc) => CommunityClub.fromMap(doc.id, doc.data()))
          .toList();
      return clubs.isEmpty ? seedCommunityClubs() : clubs;
    } on FirebaseException {
      return seedCommunityClubs();
    }
  }

  Future<List<CommunityTournament>> loadTournaments({int limit = 6}) async {
    try {
      final snap = await _db
          .collection('tournaments')
          .orderBy('startsAt')
          .limit(limit)
          .get();
      final tournaments = snap.docs
          .map((doc) => CommunityTournament.fromMap(doc.id, doc.data()))
          .toList();
      return tournaments.isEmpty ? seedCommunityTournaments() : tournaments;
    } on FirebaseException {
      return seedCommunityTournaments();
    }
  }

  List<CommunityFeedItem> loadFeed() {
    return const [
      CommunityFeedItem(
        id: 'daily-endgame',
        type: CommunityFeedType.puzzle,
        title: 'Tàn Cục Thách Đấu',
        subtitle: 'Chiếu hết trong 3 nước, thế xe pháo phối hợp.',
        meta: '488 kỳ thủ đã thử',
      ),
      CommunityFeedItem(
        id: 'featured-match',
        type: CommunityFeedType.match,
        title: 'Ván Đấu Nổi Bật',
        subtitle: 'Lan Phương vs Hồng Vương, trung cuộc căng sau 28 nước.',
        meta: 'Đang có 42 người xem',
      ),
      CommunityFeedItem(
        id: 'news-open-cup',
        type: CommunityFeedType.news,
        title: 'CChess Open cuối tuần',
        subtitle: 'Vòng Swiss 5 ván mở đăng ký cho mọi ELO.',
        meta: 'Tin cộng đồng',
      ),
    ];
  }
}

final communityRepositoryProvider = Provider<CommunityRepository>((ref) {
  return CommunityRepository(FirebaseFirestore.instance);
});

List<CommunityClub> seedCommunityClubs() {
  return const [
    CommunityClub(
      id: 'club-ha-noi',
      name: 'Kỳ Xã Thăng Long',
      region: 'Hà Nội',
      description: 'Luyện khai cuộc, giao lưu cuối tuần và đấu đội nội bộ.',
      memberCount: 128,
      weeklyScore: 8420,
      isJoined: true,
    ),
    CommunityClub(
      id: 'club-sai-gon',
      name: 'Sài Gòn Pháo Đầu',
      region: 'Hồ Chí Minh',
      description: 'Nhóm kỳ thủ thích lối đánh công sát và bình cờ nhanh.',
      memberCount: 96,
      weeklyScore: 7310,
    ),
    CommunityClub(
      id: 'club-da-nang',
      name: 'Sông Hàn Tượng Kỳ',
      region: 'Đà Nẵng',
      description: 'Kỳ xã thân thiện cho người mới và trung cấp.',
      memberCount: 74,
      weeklyScore: 6105,
    ),
  ];
}

List<CommunityTournament> seedCommunityTournaments() {
  final now = DateTime.now();
  return [
    CommunityTournament(
      id: 'tour-weekend-open',
      name: 'CChess Weekend Open',
      mode: 'Swiss 5 ván',
      statusLabel: 'Đang đăng ký',
      startsAt: now.add(const Duration(days: 2, hours: 3)),
      registeredPlayers: 46,
      capacity: 64,
      prize: '1.500 xu + huy chương',
    ),
    CommunityTournament(
      id: 'tour-cup-night',
      name: 'Đêm Cờ Úp',
      mode: 'Loại trực tiếp',
      statusLabel: 'Sắp mở',
      startsAt: now.add(const Duration(days: 5, hours: 1)),
      registeredPlayers: 18,
      capacity: 32,
      prize: 'Khung avatar Cờ Úp',
    ),
    CommunityTournament(
      id: 'tour-rook-school',
      name: 'Tân Thủ Kỳ Đài',
      mode: 'Round robin',
      statusLabel: 'Ưu tiên ELO < 1300',
      startsAt: now.add(const Duration(days: 7, hours: 4)),
      registeredPlayers: 22,
      capacity: 24,
      prize: 'Gói bài học nhập môn',
    ),
  ];
}
