import 'package:equatable/equatable.dart';

import '../../core/constants/elo_constants.dart';

/// Local user profile. Mirrors the spec's UserModel but lives entirely
/// in Hive for now; an online sync layer can promote it to Firestore later.
class UserProfile extends Equatable {
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
  final int coins;
  final int gems;
  final int creditScore;
  final bool isVip;
  final DateTime? vipExpiresAt;
  final DateTime createdAt;
  final DateTime lastActiveAt;
  final bool onboardingCompleted;

  const UserProfile({
    required this.id,
    required this.displayName,
    required this.region,
    this.avatarUrl,
    this.eloChess = EloConstants.initialElo,
    this.eloCup = EloConstants.initialElo,
    this.totalGames = 0,
    this.wins = 0,
    this.losses = 0,
    this.draws = 0,
    this.coins = 100,
    this.gems = 10,
    this.creditScore = 100,
    this.isVip = false,
    this.vipExpiresAt,
    required this.createdAt,
    required this.lastActiveAt,
    this.onboardingCompleted = false,
  });

  factory UserProfile.fresh({
    String? id,
    String displayName = 'Kỳ Thủ',
    String region = 'Hà Nội',
  }) {
    final now = DateTime.now();
    return UserProfile(
      id: id ?? 'local-${now.microsecondsSinceEpoch}',
      displayName: displayName,
      region: region,
      createdAt: now,
      lastActiveAt: now,
    );
  }

  /// Vietnamese-style abbreviated id, e.g. "#A12345678".
  String get shortId => '#${id.hashCode.abs().toString().padLeft(9, '0')}';

  double get winRate => totalGames == 0 ? 0.0 : wins / totalGames;

  UserProfile copyWith({
    String? displayName,
    String? region,
    String? avatarUrl,
    int? eloChess,
    int? eloCup,
    int? totalGames,
    int? wins,
    int? losses,
    int? draws,
    int? coins,
    int? gems,
    int? creditScore,
    bool? isVip,
    DateTime? vipExpiresAt,
    bool clearVipExpiry = false,
    DateTime? lastActiveAt,
    bool? onboardingCompleted,
  }) {
    return UserProfile(
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
      coins: coins ?? this.coins,
      gems: gems ?? this.gems,
      creditScore: creditScore ?? this.creditScore,
      isVip: isVip ?? this.isVip,
      vipExpiresAt:
          clearVipExpiry ? null : (vipExpiresAt ?? this.vipExpiresAt),
      createdAt: createdAt,
      lastActiveAt: lastActiveAt ?? this.lastActiveAt,
      onboardingCompleted: onboardingCompleted ?? this.onboardingCompleted,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'displayName': displayName,
        'region': region,
        'avatarUrl': avatarUrl,
        'eloChess': eloChess,
        'eloCup': eloCup,
        'totalGames': totalGames,
        'wins': wins,
        'losses': losses,
        'draws': draws,
        'coins': coins,
        'gems': gems,
        'creditScore': creditScore,
        'isVip': isVip,
        'vipExpiresAt': vipExpiresAt?.toIso8601String(),
        'createdAt': createdAt.toIso8601String(),
        'lastActiveAt': lastActiveAt.toIso8601String(),
        'onboardingCompleted': onboardingCompleted,
      };

  factory UserProfile.fromJson(Map<dynamic, dynamic> json) {
    return UserProfile(
      id: json['id'] as String,
      displayName: json['displayName'] as String,
      region: json['region'] as String,
      avatarUrl: json['avatarUrl'] as String?,
      eloChess: json['eloChess'] as int? ?? EloConstants.initialElo,
      eloCup: json['eloCup'] as int? ?? EloConstants.initialElo,
      totalGames: json['totalGames'] as int? ?? 0,
      wins: json['wins'] as int? ?? 0,
      losses: json['losses'] as int? ?? 0,
      draws: json['draws'] as int? ?? 0,
      coins: json['coins'] as int? ?? 0,
      gems: json['gems'] as int? ?? 0,
      creditScore: json['creditScore'] as int? ?? 100,
      isVip: json['isVip'] as bool? ?? false,
      vipExpiresAt: (json['vipExpiresAt'] as String?) == null
          ? null
          : DateTime.tryParse(json['vipExpiresAt'] as String),
      createdAt: DateTime.parse(json['createdAt'] as String),
      lastActiveAt: DateTime.parse(json['lastActiveAt'] as String),
      onboardingCompleted: json['onboardingCompleted'] as bool? ?? false,
    );
  }

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
        coins,
        gems,
        creditScore,
        isVip,
        vipExpiresAt,
        createdAt,
        lastActiveAt,
        onboardingCompleted,
      ];
}

/// Vietnamese regions used in onboarding / profile.
const List<String> kVietnamRegions = [
  'Hà Nội',
  'Hồ Chí Minh',
  'Hải Phòng',
  'Đà Nẵng',
  'Cần Thơ',
  'An Giang',
  'Bà Rịa - Vũng Tàu',
  'Bắc Giang',
  'Bắc Kạn',
  'Bạc Liêu',
  'Bắc Ninh',
  'Bến Tre',
  'Bình Định',
  'Bình Dương',
  'Bình Phước',
  'Bình Thuận',
  'Cà Mau',
  'Cao Bằng',
  'Đắk Lắk',
  'Đắk Nông',
  'Điện Biên',
  'Đồng Nai',
  'Đồng Tháp',
  'Gia Lai',
  'Hà Giang',
  'Hà Nam',
  'Hà Tĩnh',
  'Hải Dương',
  'Hậu Giang',
  'Hòa Bình',
  'Hưng Yên',
  'Khánh Hòa',
  'Kiên Giang',
  'Kon Tum',
  'Lai Châu',
  'Lâm Đồng',
  'Lạng Sơn',
  'Lào Cai',
  'Long An',
  'Nam Định',
  'Nghệ An',
  'Ninh Bình',
  'Ninh Thuận',
  'Phú Thọ',
  'Phú Yên',
  'Quảng Bình',
  'Quảng Nam',
  'Quảng Ngãi',
  'Quảng Ninh',
  'Quảng Trị',
  'Sóc Trăng',
  'Sơn La',
  'Tây Ninh',
  'Thái Bình',
  'Thái Nguyên',
  'Thanh Hóa',
  'Thừa Thiên Huế',
  'Tiền Giang',
  'Trà Vinh',
  'Tuyên Quang',
  'Vĩnh Long',
  'Vĩnh Phúc',
  'Yên Bái',
  'Khác',
];
