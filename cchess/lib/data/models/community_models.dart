import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:equatable/equatable.dart';

enum CommunityBoardType {
  chess,
  cup;

  String get label => switch (this) {
    CommunityBoardType.chess => 'Cờ Tướng',
    CommunityBoardType.cup => 'Cờ Úp',
  };

  String get firestoreKey => switch (this) {
    CommunityBoardType.chess => 'chess',
    CommunityBoardType.cup => 'cup',
  };

  String get eloField => switch (this) {
    CommunityBoardType.chess => 'eloChess',
    CommunityBoardType.cup => 'eloCup',
  };
}

enum LeaderboardScope {
  national,
  regional,
  friends;

  String get label => switch (this) {
    LeaderboardScope.national => 'Toàn quốc',
    LeaderboardScope.regional => 'Khu vực',
    LeaderboardScope.friends => 'Bạn bè',
  };
}

enum FriendStatus {
  pending,
  accepted;

  static FriendStatus fromValue(Object? value) {
    return value == 'accepted' ? FriendStatus.accepted : FriendStatus.pending;
  }

  String get firestoreValue => switch (this) {
    FriendStatus.pending => 'pending',
    FriendStatus.accepted => 'accepted',
  };
}

enum FriendDirection {
  incoming,
  outgoing,
  accepted;

  static FriendDirection fromValue(Object? value) {
    return switch (value) {
      'incoming' => FriendDirection.incoming,
      'outgoing' => FriendDirection.outgoing,
      _ => FriendDirection.accepted,
    };
  }

  String get firestoreValue => switch (this) {
    FriendDirection.incoming => 'incoming',
    FriendDirection.outgoing => 'outgoing',
    FriendDirection.accepted => 'accepted',
  };
}

DateTime? communityDateFromValue(Object? value) {
  if (value == null) return null;
  if (value is Timestamp) return value.toDate();
  if (value is DateTime) return value;
  if (value is num) return DateTime.fromMillisecondsSinceEpoch(value.toInt());
  if (value is String) return DateTime.tryParse(value);
  return null;
}

int communityIntFromValue(Object? value, int fallback) {
  return value is num ? value.toInt() : fallback;
}

String communityStringFromValue(Object? value, String fallback) {
  final text = value as String?;
  if (text == null || text.trim().isEmpty) return fallback;
  return text.trim();
}

class CommunityPlayer extends Equatable {
  const CommunityPlayer({
    required this.id,
    required this.displayName,
    required this.region,
    this.avatarUrl,
    required this.eloChess,
    required this.eloCup,
    required this.totalGames,
    required this.wins,
    required this.losses,
    required this.draws,
    this.lastActiveAt,
  });

  final String id;
  final String displayName;
  final String region;
  final String? avatarUrl;
  final int eloChess;
  final int eloCup;
  final int totalGames;
  final int wins;
  final int losses;
  final int draws;
  final DateTime? lastActiveAt;

  String get initials {
    final parts = displayName.trim().split(RegExp(r'\s+'));
    final last = parts.isEmpty ? displayName : parts.last;
    return last.isEmpty ? '?' : last.substring(0, 1).toUpperCase();
  }

  String get shortId => '#${id.hashCode.abs().toString().padLeft(9, '0')}';

  bool get isOnline {
    final seen = lastActiveAt;
    if (seen == null) return false;
    return DateTime.now().difference(seen).inMinutes < 10;
  }

  double get winRate => totalGames == 0 ? 0 : wins / totalGames;

  int eloFor(CommunityBoardType boardType) {
    return boardType == CommunityBoardType.cup ? eloCup : eloChess;
  }

  CommunityPlayer copyWith({
    String? displayName,
    String? region,
    String? avatarUrl,
    int? eloChess,
    int? eloCup,
    int? totalGames,
    int? wins,
    int? losses,
    int? draws,
    DateTime? lastActiveAt,
  }) {
    return CommunityPlayer(
      id: id,
      displayName: displayName ?? this.displayName,
      region: region ?? this.region,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      eloChess: eloChess ?? this.eloChess,
      eloCup: eloCup ?? this.eloCup,
      totalGames: totalGames ?? this.totalGames,
      wins: wins ?? this.wins,
      losses: losses ?? this.losses,
      draws: draws ?? this.draws,
      lastActiveAt: lastActiveAt ?? this.lastActiveAt,
    );
  }

  factory CommunityPlayer.fromMap(String id, Map<String, dynamic> data) {
    return CommunityPlayer(
      id: id,
      displayName: communityStringFromValue(data['displayName'], 'Kỳ thủ'),
      region: communityStringFromValue(data['region'], 'Khác'),
      avatarUrl: data['avatarUrl'] as String?,
      eloChess: communityIntFromValue(data['eloChess'], 1000),
      eloCup: communityIntFromValue(data['eloCup'], 1000),
      totalGames: communityIntFromValue(data['totalGames'], 0),
      wins: communityIntFromValue(data['wins'], 0),
      losses: communityIntFromValue(data['losses'], 0),
      draws: communityIntFromValue(data['draws'], 0),
      lastActiveAt: communityDateFromValue(data['lastActiveAt']),
    );
  }

  Map<String, dynamic> toFriendPayload() => {
    'uid': id,
    'displayName': displayName,
    'region': region,
    'avatarUrl': avatarUrl,
    'eloChess': eloChess,
    'eloCup': eloCup,
    'totalGames': totalGames,
    'wins': wins,
    'losses': losses,
    'draws': draws,
    'lastActiveAt': lastActiveAt,
  };

  @override
  List<Object?> get props => [
    id,
    displayName,
    region,
    avatarUrl,
    eloChess,
    eloCup,
    totalGames,
    wins,
    losses,
    draws,
    lastActiveAt,
  ];
}

class FriendSummary extends Equatable {
  const FriendSummary({
    required this.player,
    required this.status,
    required this.direction,
    this.since,
    this.updatedAt,
  });

  final CommunityPlayer player;
  final FriendStatus status;
  final FriendDirection direction;
  final DateTime? since;
  final DateTime? updatedAt;

  bool get isAccepted => status == FriendStatus.accepted;
  bool get isIncomingRequest =>
      status == FriendStatus.pending && direction == FriendDirection.incoming;
  bool get isOutgoingRequest =>
      status == FriendStatus.pending && direction == FriendDirection.outgoing;

  factory FriendSummary.fromMap(String id, Map<String, dynamic> data) {
    final player = CommunityPlayer.fromMap(
      (data['uid'] as String?) ?? id,
      data,
    );
    return FriendSummary(
      player: player,
      status: FriendStatus.fromValue(data['status']),
      direction: FriendDirection.fromValue(data['direction']),
      since: communityDateFromValue(data['since']),
      updatedAt: communityDateFromValue(data['updatedAt']),
    );
  }

  @override
  List<Object?> get props => [player, status, direction, since, updatedAt];
}

class LeaderboardEntry extends Equatable {
  const LeaderboardEntry({
    required this.player,
    required this.rank,
    required this.boardType,
    required this.elo,
    this.updatedAt,
    this.isCurrentUser = false,
  });

  final CommunityPlayer player;
  final int rank;
  final CommunityBoardType boardType;
  final int elo;
  final DateTime? updatedAt;
  final bool isCurrentUser;

  factory LeaderboardEntry.fromMap({
    required String id,
    required int rank,
    required CommunityBoardType boardType,
    required Map<String, dynamic> data,
    String? currentUid,
  }) {
    final player = CommunityPlayer.fromMap(
      (data['uid'] as String?) ?? id,
      data,
    );
    return LeaderboardEntry(
      player: player,
      rank: communityIntFromValue(data['rank'], rank),
      boardType: boardType,
      elo: communityIntFromValue(
        data['elo'] ?? data[boardType.eloField],
        player.eloFor(boardType),
      ),
      updatedAt: communityDateFromValue(data['updatedAt']),
      isCurrentUser: currentUid != null && player.id == currentUid,
    );
  }

  LeaderboardEntry copyWith({int? rank, bool? isCurrentUser}) {
    return LeaderboardEntry(
      player: player,
      rank: rank ?? this.rank,
      boardType: boardType,
      elo: elo,
      updatedAt: updatedAt,
      isCurrentUser: isCurrentUser ?? this.isCurrentUser,
    );
  }

  @override
  List<Object?> get props => [
    player,
    rank,
    boardType,
    elo,
    updatedAt,
    isCurrentUser,
  ];
}

class CommunityClub extends Equatable {
  const CommunityClub({
    required this.id,
    required this.name,
    required this.region,
    required this.description,
    required this.memberCount,
    required this.weeklyScore,
    this.isJoined = false,
  });

  final String id;
  final String name;
  final String region;
  final String description;
  final int memberCount;
  final int weeklyScore;
  final bool isJoined;

  factory CommunityClub.fromMap(String id, Map<String, dynamic> data) {
    return CommunityClub(
      id: id,
      name: communityStringFromValue(data['name'], 'Kỳ Xã'),
      region: communityStringFromValue(data['region'], 'Toàn quốc'),
      description: communityStringFromValue(
        data['description'],
        'Sinh hoạt, luyện cờ và thi đấu nội bộ.',
      ),
      memberCount: communityIntFromValue(data['memberCount'], 0),
      weeklyScore: communityIntFromValue(data['weeklyScore'], 0),
      isJoined: data['isJoined'] == true,
    );
  }

  @override
  List<Object?> get props => [
    id,
    name,
    region,
    description,
    memberCount,
    weeklyScore,
    isJoined,
  ];
}

class CommunityTournament extends Equatable {
  const CommunityTournament({
    required this.id,
    required this.name,
    required this.mode,
    required this.statusLabel,
    required this.startsAt,
    required this.registeredPlayers,
    required this.capacity,
    required this.prize,
  });

  final String id;
  final String name;
  final String mode;
  final String statusLabel;
  final DateTime startsAt;
  final int registeredPlayers;
  final int capacity;
  final String prize;

  double get fillRatio {
    if (capacity <= 0) return 0;
    return (registeredPlayers / capacity).clamp(0.0, 1.0);
  }

  factory CommunityTournament.fromMap(String id, Map<String, dynamic> data) {
    return CommunityTournament(
      id: id,
      name: communityStringFromValue(data['name'], 'Giải đấu CChess'),
      mode: communityStringFromValue(data['mode'], 'Swiss'),
      statusLabel: communityStringFromValue(data['statusLabel'], 'Sắp mở'),
      startsAt:
          communityDateFromValue(data['startsAt']) ??
          DateTime.now().add(const Duration(days: 1)),
      registeredPlayers: communityIntFromValue(data['registeredPlayers'], 0),
      capacity: communityIntFromValue(data['capacity'], 32),
      prize: communityStringFromValue(data['prize'], 'Huy chương Kỳ Xã'),
    );
  }

  @override
  List<Object?> get props => [
    id,
    name,
    mode,
    statusLabel,
    startsAt,
    registeredPlayers,
    capacity,
    prize,
  ];
}

enum CommunityFeedType { puzzle, match, news }

class CommunityFeedItem extends Equatable {
  const CommunityFeedItem({
    required this.id,
    required this.type,
    required this.title,
    required this.subtitle,
    required this.meta,
  });

  final String id;
  final CommunityFeedType type;
  final String title;
  final String subtitle;
  final String meta;

  @override
  List<Object?> get props => [id, type, title, subtitle, meta];
}
