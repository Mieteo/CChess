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
    this.founderId = '',
    this.createdAt,
    this.isMember = false,
  });

  final String id;
  final String name;
  final String region;
  final String description;
  final int memberCount;
  final int weeklyScore;
  final String founderId;
  final DateTime? createdAt;
  final bool isMember;

  CommunityClub copyWith({bool? isMember}) {
    return CommunityClub(
      id: id,
      name: name,
      region: region,
      description: description,
      memberCount: memberCount,
      weeklyScore: weeklyScore,
      founderId: founderId,
      createdAt: createdAt,
      isMember: isMember ?? this.isMember,
    );
  }

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
      founderId: communityStringFromValue(data['founderId'], ''),
      createdAt: communityDateFromValue(data['createdAtMs'] ?? data['createdAt']),
      isMember: data['isMember'] == true || data['isJoined'] == true,
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
    founderId,
    createdAt,
    isMember,
  ];
}

enum ClubRole {
  owner,
  member;

  static ClubRole fromValue(Object? value) {
    return value == 'owner' ? ClubRole.owner : ClubRole.member;
  }

  String get label => switch (this) {
    ClubRole.owner => 'Sáng lập',
    ClubRole.member => 'Thành viên',
  };
}

class ClubMember extends Equatable {
  const ClubMember({
    required this.uid,
    required this.role,
    required this.displayName,
    required this.eloChess,
    this.joinedAt,
  });

  final String uid;
  final ClubRole role;
  final String displayName;
  final int eloChess;
  final DateTime? joinedAt;

  factory ClubMember.fromMap(Map<String, dynamic> data) {
    return ClubMember(
      uid: communityStringFromValue(data['uid'], ''),
      role: ClubRole.fromValue(data['role']),
      displayName: communityStringFromValue(data['displayName'], 'Kỳ thủ'),
      eloChess: communityIntFromValue(data['eloChess'], 1000),
      joinedAt: communityDateFromValue(data['joinedAtMs'] ?? data['joinedAt']),
    );
  }

  @override
  List<Object?> get props => [uid, role, displayName, eloChess, joinedAt];
}

enum TournamentStatus {
  registering,
  inProgress,
  finished;

  static TournamentStatus fromValue(Object? value) {
    return switch (value) {
      'in_progress' => TournamentStatus.inProgress,
      'finished' => TournamentStatus.finished,
      _ => TournamentStatus.registering,
    };
  }

  String get label => switch (this) {
    TournamentStatus.registering => 'Đang đăng ký',
    TournamentStatus.inProgress => 'Đang diễn ra',
    TournamentStatus.finished => 'Đã kết thúc',
  };
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
    this.status = TournamentStatus.registering,
    this.createdBy = 'system',
    this.registrationDeadline,
    this.minElo,
    this.maxElo,
    this.winnerUid,
  });

  final String id;
  final String name;
  final String mode;
  final String statusLabel;
  final DateTime startsAt;
  final int registeredPlayers;
  final int capacity;
  final String prize;
  final TournamentStatus status;
  final String createdBy;
  final DateTime? registrationDeadline;
  final int? minElo;
  final int? maxElo;
  final String? winnerUid;

  double get fillRatio {
    if (capacity <= 0) return 0;
    return (registeredPlayers / capacity).clamp(0.0, 1.0);
  }

  factory CommunityTournament.fromMap(String id, Map<String, dynamic> data) {
    final status = TournamentStatus.fromValue(data['status']);
    return CommunityTournament(
      id: id,
      name: communityStringFromValue(data['name'], 'Giải đấu CChess'),
      // 'mode'/'statusLabel' are the legacy free-text display fields used by
      // the seed fallback; the backend-authoritative shape only sends
      // 'format'/'status', so derive matching Vietnamese labels from those.
      mode: communityStringFromValue(data['mode'], 'Loại trực tiếp'),
      statusLabel: communityStringFromValue(data['statusLabel'], status.label),
      startsAt:
          communityDateFromValue(data['startsAtMs'] ?? data['startsAt']) ??
          DateTime.now().add(const Duration(days: 1)),
      registeredPlayers: communityIntFromValue(
        data['participantCount'] ?? data['registeredPlayers'],
        0,
      ),
      capacity: communityIntFromValue(data['capacity'], 32),
      prize: communityStringFromValue(data['prize'], 'Huy chương Kỳ Xã'),
      status: status,
      createdBy: communityStringFromValue(data['createdBy'], 'system'),
      registrationDeadline: communityDateFromValue(data['registrationDeadlineMs']),
      minElo: data['minElo'] is num ? (data['minElo'] as num).toInt() : null,
      maxElo: data['maxElo'] is num ? (data['maxElo'] as num).toInt() : null,
      winnerUid: data['winnerUid'] as String?,
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
    status,
    createdBy,
    registrationDeadline,
    minElo,
    maxElo,
    winnerUid,
  ];
}

enum TournamentParticipantStatus {
  registered,
  active,
  eliminated,
  champion;

  static TournamentParticipantStatus fromValue(Object? value) {
    return switch (value) {
      'active' => TournamentParticipantStatus.active,
      'eliminated' => TournamentParticipantStatus.eliminated,
      'champion' => TournamentParticipantStatus.champion,
      _ => TournamentParticipantStatus.registered,
    };
  }
}

class TournamentParticipant extends Equatable {
  const TournamentParticipant({
    required this.uid,
    required this.displayName,
    required this.eloAtRegistration,
    required this.status,
  });

  final String uid;
  final String displayName;
  final int eloAtRegistration;
  final TournamentParticipantStatus status;

  factory TournamentParticipant.fromMap(Map<String, dynamic> data) {
    return TournamentParticipant(
      uid: communityStringFromValue(data['uid'], ''),
      displayName: communityStringFromValue(data['displayName'], 'Kỳ thủ'),
      eloAtRegistration: communityIntFromValue(data['eloAtRegistration'], 1000),
      status: TournamentParticipantStatus.fromValue(data['status']),
    );
  }

  @override
  List<Object?> get props => [uid, displayName, eloAtRegistration, status];
}

enum TournamentMatchStatus {
  pending,
  ready,
  inProgress,
  finished;

  static TournamentMatchStatus fromValue(Object? value) {
    return switch (value) {
      'ready' => TournamentMatchStatus.ready,
      'in_progress' => TournamentMatchStatus.inProgress,
      'finished' => TournamentMatchStatus.finished,
      _ => TournamentMatchStatus.pending,
    };
  }
}

class TournamentMatch extends Equatable {
  const TournamentMatch({
    required this.id,
    required this.round,
    required this.slotIndex,
    required this.player1Id,
    required this.player2Id,
    required this.result,
    required this.roomId,
    required this.status,
  });

  final String id;
  final int round;
  final int slotIndex;
  final String? player1Id;
  final String? player2Id;
  final String? result; // 'player1' | 'player2' | 'bye' | null
  final String? roomId;
  final TournamentMatchStatus status;

  /// The uid of the winner, if this match has a decided result. A 'bye'
  /// result has exactly one real player present — they're the winner.
  String? get winnerUid {
    if (result == 'player1') return player1Id;
    if (result == 'player2') return player2Id;
    if (result == 'bye') return player1Id ?? player2Id;
    return null;
  }

  bool isPlayer(String? uid) =>
      uid != null && (player1Id == uid || player2Id == uid);

  factory TournamentMatch.fromMap(Map<String, dynamic> data) {
    return TournamentMatch(
      id: communityStringFromValue(data['id'], ''),
      round: communityIntFromValue(data['round'], 1),
      slotIndex: communityIntFromValue(data['slotIndex'], 0),
      player1Id: data['player1Id'] as String?,
      player2Id: data['player2Id'] as String?,
      result: data['result'] as String?,
      roomId: data['roomId'] as String?,
      status: TournamentMatchStatus.fromValue(data['status']),
    );
  }

  @override
  List<Object?> get props => [
    id,
    round,
    slotIndex,
    player1Id,
    player2Id,
    result,
    roomId,
    status,
  ];
}

enum CommunityFeedType {
  puzzle,
  match,
  news;

  static CommunityFeedType fromValue(Object? value) {
    return switch (value) {
      'puzzle' => CommunityFeedType.puzzle,
      'match' => CommunityFeedType.match,
      _ => CommunityFeedType.news,
    };
  }
}

class CommunityFeedItem extends Equatable {
  const CommunityFeedItem({
    required this.id,
    required this.type,
    required this.title,
    required this.subtitle,
    required this.meta,
    this.route,
    this.linkUrl,
  });

  final String id;
  final CommunityFeedType type;
  final String title;
  final String subtitle;
  final String meta;
  /// Stable marker deciding what tapping the card does (e.g. 'daily_puzzle').
  /// Null means the card has no special tap action beyond its [type].
  final String? route;
  /// External article URL for plain news items. Null for puzzle/match cards.
  final String? linkUrl;

  factory CommunityFeedItem.fromMap(Map<String, dynamic> data) {
    return CommunityFeedItem(
      id: communityStringFromValue(data['id'], ''),
      type: CommunityFeedType.fromValue(data['type']),
      title: communityStringFromValue(data['title'], ''),
      subtitle: communityStringFromValue(data['subtitle'], ''),
      meta: communityStringFromValue(data['meta'], ''),
      route: (data['route'] as String?)?.trim().isEmpty ?? true ? null : data['route'] as String?,
      linkUrl: (data['linkUrl'] as String?)?.trim().isEmpty ?? true ? null : data['linkUrl'] as String?,
    );
  }

  @override
  List<Object?> get props => [id, type, title, subtitle, meta, route, linkUrl];
}
