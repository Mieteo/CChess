import 'package:equatable/equatable.dart';

import 'shop_item.dart';

/// The player's wallet + active loadout, from `GET /wallet` (and updated by
/// purchase/equip). `equipped` maps a cosmetic kind name → equipped itemId.
class Wallet extends Equatable {
  final int coins;
  final int gems;
  final Map<String, String> equipped;

  const Wallet({
    this.coins = 0,
    this.gems = 0,
    this.equipped = const {},
  });

  /// The itemId equipped in [kind]'s slot, or null when nothing is equipped.
  String? equippedFor(ShopItemKind kind) => equipped[kind.name];

  Wallet copyWith({int? coins, int? gems, Map<String, String>? equipped}) {
    return Wallet(
      coins: coins ?? this.coins,
      gems: gems ?? this.gems,
      equipped: equipped ?? this.equipped,
    );
  }

  factory Wallet.fromJson(Map<dynamic, dynamic> json) {
    final raw = json['equipped'];
    final equipped = <String, String>{};
    if (raw is Map) {
      raw.forEach((k, v) {
        if (k is String && v is String && v.isNotEmpty) equipped[k] = v;
      });
    }
    return Wallet(
      coins: _asInt(json['coins']),
      gems: _asInt(json['gems']),
      equipped: equipped,
    );
  }

  Map<String, dynamic> toJson() => {
        'coins': coins,
        'gems': gems,
        'equipped': equipped,
      };

  @override
  List<Object?> get props => [coins, gems, equipped];
}

int _asInt(Object? value, [int fallback = 0]) {
  if (value is int) return value;
  if (value is num) return value.round();
  return fallback;
}
