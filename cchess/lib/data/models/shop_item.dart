import 'package:equatable/equatable.dart';

/// Cosmetic / consumable categories. Mirrors the backend `ShopItemKind`.
enum ShopItemKind {
  boardTheme,
  pieceSet,
  avatarFrame,
  chatBubble,
  nameplate,
  soundPack,
  consumable;

  static ShopItemKind fromName(String? name) {
    for (final k in ShopItemKind.values) {
      if (k.name == name) return k;
    }
    return ShopItemKind.consumable;
  }

  /// Whether this kind is a cosmetic slot that can be equipped (one at a time).
  bool get isEquippable => this != ShopItemKind.consumable;

  String get labelVi {
    switch (this) {
      case ShopItemKind.boardTheme:
        return 'Bàn cờ';
      case ShopItemKind.pieceSet:
        return 'Quân cờ';
      case ShopItemKind.avatarFrame:
        return 'Khung avatar';
      case ShopItemKind.chatBubble:
        return 'Bong bóng chat';
      case ShopItemKind.nameplate:
        return 'Biển hiệu';
      case ShopItemKind.soundPack:
        return 'Âm hiệu';
      case ShopItemKind.consumable:
        return 'Công cụ';
    }
  }
}

/// Rarity tier — drives the accent color of a shop tile.
enum Rarity {
  common,
  rare,
  epic,
  legendary;

  static Rarity fromName(String? name) {
    for (final r in Rarity.values) {
      if (r.name == name) return r;
    }
    return Rarity.common;
  }

  String get labelVi {
    switch (this) {
      case Rarity.common:
        return 'Thường';
      case Rarity.rare:
        return 'Hiếm';
      case Rarity.epic:
        return 'Sử thi';
      case Rarity.legendary:
        return 'Huyền thoại';
    }
  }
}

/// A purchasable catalog item from `GET /shop`.
class ShopItem extends Equatable {
  final String id;
  final ShopItemKind kind;
  final String nameVi;
  final String descVi;

  /// Price in each currency; 0 means "not purchasable with this currency".
  final int priceCoins;
  final int priceGems;
  final Rarity rarity;

  /// Key the client maps to a concrete asset/theme (e.g. a board-theme key).
  final String payloadKey;
  final bool consumable;
  final int consumableQty;
  final int sortOrder;

  const ShopItem({
    required this.id,
    required this.kind,
    required this.nameVi,
    required this.descVi,
    required this.priceCoins,
    required this.priceGems,
    required this.rarity,
    required this.payloadKey,
    required this.consumable,
    required this.consumableQty,
    required this.sortOrder,
  });

  bool get sellsForCoins => priceCoins > 0;
  bool get sellsForGems => priceGems > 0;

  factory ShopItem.fromJson(Map<dynamic, dynamic> json) {
    return ShopItem(
      id: (json['id'] as String?) ?? '',
      kind: ShopItemKind.fromName(json['kind'] as String?),
      nameVi: (json['nameVi'] as String?) ?? '',
      descVi: (json['descVi'] as String?) ?? '',
      priceCoins: _asInt(json['priceCoins']),
      priceGems: _asInt(json['priceGems']),
      rarity: Rarity.fromName(json['rarity'] as String?),
      payloadKey: (json['payloadKey'] as String?) ?? '',
      consumable: json['consumable'] == true,
      consumableQty: _asInt(json['consumableQty'], 1),
      sortOrder: _asInt(json['sortOrder']),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'kind': kind.name,
        'nameVi': nameVi,
        'descVi': descVi,
        'priceCoins': priceCoins,
        'priceGems': priceGems,
        'rarity': rarity.name,
        'payloadKey': payloadKey,
        'consumable': consumable,
        'consumableQty': consumableQty,
        'sortOrder': sortOrder,
      };

  @override
  List<Object?> get props => [
        id,
        kind,
        nameVi,
        descVi,
        priceCoins,
        priceGems,
        rarity,
        payloadKey,
        consumable,
        consumableQty,
        sortOrder,
      ];
}

int _asInt(Object? value, [int fallback = 0]) {
  if (value is int) return value;
  if (value is num) return value.round();
  return fallback;
}
