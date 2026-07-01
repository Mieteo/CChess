import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../../core/constants/app_constants.dart';
import '../datasources/remote/clubs_api_source.dart';
import '../models/community_models.dart';
import 'community_repository.dart' show seedCommunityClubs;

/// Repository for clubs (S14 C3 — Kỳ Xã). Server-authoritative: the backend
/// owns membership + memberCount; this layer fetches through [ClubsApiSource]
/// and keeps a Hive cache of the last successful club list + the caller's own
/// memberships so Cộng Đồng → Kỳ Xã still renders offline.
class ClubRepository {
  ClubRepository({ClubsApiSource? remote}) : _remote = remote;

  final ClubsApiSource? _remote;

  static const String _boxName = AppConstants.boxClubs;
  static const String _kClubs = 'clubs';
  static const String _kMine = 'mine';

  Box<dynamic>? _box;

  Future<Box<dynamic>> _openBox() async {
    final existing = _box;
    if (existing != null && existing.isOpen) return existing;
    final box = await Hive.openBox<dynamic>(_boxName);
    _box = box;
    return box;
  }

  /// The club list with `isMember` resolved against the caller's own
  /// memberships (best-effort — if the auth call fails, membership just shows
  /// as unknown/false rather than blocking the whole list).
  Future<List<CommunityClub>> listClubs() async {
    final remote = _remote;
    if (remote != null) {
      try {
        final clubs = await remote.listClubs();
        final mine = await _tryListMine(remote);
        final mineIds = mine.map((m) => m.clubId).toSet();
        final resolved = clubs.map((c) => c.copyWith(isMember: mineIds.contains(c.id))).toList();
        await _cacheClubs(resolved);
        await _cacheMine(mine);
        return resolved;
      } on ClubApiException {
        // fall through to cache
      }
    }
    return cachedClubs();
  }

  Future<List<MyClubEntry>> _tryListMine(ClubsApiSource remote) async {
    try {
      return await remote.listMine();
    } on ClubApiException {
      return const [];
    }
  }

  Future<List<CommunityClub>> cachedClubs() async {
    final box = await _openBox();
    final raw = box.get(_kClubs);
    if (raw is List) {
      return raw
          .whereType<Map>()
          .map((m) => CommunityClub.fromMap(m['id'] as String? ?? '', m.cast<String, dynamic>()))
          .toList(growable: false);
    }
    return seedCommunityClubs();
  }

  Future<void> _cacheClubs(List<CommunityClub> clubs) async {
    final box = await _openBox();
    await box.put(_kClubs, clubs.map(_clubToJson).toList());
  }

  Future<void> _cacheMine(List<MyClubEntry> mine) async {
    final box = await _openBox();
    await box.put(_kMine, mine.map((m) => m.clubId).toList());
  }

  Map<String, dynamic> _clubToJson(CommunityClub c) => {
    'id': c.id,
    'name': c.name,
    'region': c.region,
    'description': c.description,
    'memberCount': c.memberCount,
    'weeklyScore': c.weeklyScore,
    'founderId': c.founderId,
    'isMember': c.isMember,
  };

  Future<List<ClubMember>> members(String clubId) async {
    final remote = _remote;
    if (remote == null) return const [];
    try {
      return await remote.listMembers(clubId);
    } on ClubApiException {
      return const [];
    }
  }

  Future<CommunityClub> create({
    required String name,
    required String region,
    required String description,
  }) async {
    final remote = _remote;
    if (remote == null) {
      throw const ClubApiException(code: 'offline', message: 'Không thể tạo Kỳ Xã khi ngoại tuyến');
    }
    return remote.create(name: name, region: region, description: description);
  }

  Future<CommunityClub> join(String clubId) async {
    final remote = _remote;
    if (remote == null) {
      throw const ClubApiException(code: 'offline', message: 'Không thể tham gia khi ngoại tuyến');
    }
    return remote.join(clubId);
  }

  Future<void> leave(String clubId) async {
    final remote = _remote;
    if (remote == null) {
      throw const ClubApiException(code: 'offline', message: 'Không thể rời Kỳ Xã khi ngoại tuyến');
    }
    await remote.leave(clubId);
  }
}

final clubRepositoryProvider = Provider<ClubRepository>((ref) {
  return ClubRepository(remote: ref.watch(clubsApiSourceProvider));
});
