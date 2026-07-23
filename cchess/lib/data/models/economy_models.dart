import 'package:equatable/equatable.dart';

import 'shop_item.dart';

/// Models for the S16 economy extension (D4 Hộp Thư / D5 Sự Kiện / D6 Phúc Lợi
/// / D7 Đúc Bàn Cờ). One file because they all revolve around the same
/// [RewardBundle] the backend credits into the wallet + inventory.

int _asInt(Object? value, [int fallback = 0]) {
  if (value is int) return value;
  if (value is num) return value.round();
  return fallback;
}

String _asString(Object? value) => value is String ? value : '';

/// One item grant inside a reward (mirrors the backend RewardItem).
class RewardItem extends Equatable {
  final String itemId;
  final ShopItemKind kind;
  final String payloadKey;
  final int qty;

  const RewardItem({
    required this.itemId,
    required this.kind,
    required this.payloadKey,
    this.qty = 1,
  });

  factory RewardItem.fromJson(Map<dynamic, dynamic> json) => RewardItem(
        itemId: _asString(json['itemId']),
        kind: ShopItemKind.fromName(json['kind'] as String?),
        payloadKey: _asString(json['payloadKey']),
        qty: _asInt(json['qty'], 1),
      );

  Map<String, dynamic> toJson() => {
        'itemId': itemId,
        'kind': kind.name,
        'payloadKey': payloadKey,
        'qty': qty,
      };

  @override
  List<Object?> get props => [itemId, kind, payloadKey, qty];
}

/// Coins + gems + item grants delivered by a claim.
class RewardBundle extends Equatable {
  final int coins;
  final int gems;
  final List<RewardItem> items;

  const RewardBundle({this.coins = 0, this.gems = 0, this.items = const []});

  bool get isEmpty => coins <= 0 && gems <= 0 && items.isEmpty;

  factory RewardBundle.fromJson(Map<dynamic, dynamic> json) => RewardBundle(
        coins: _asInt(json['coins']),
        gems: _asInt(json['gems']),
        items: json['items'] is List
            ? (json['items'] as List)
                .whereType<Map>()
                .map(RewardItem.fromJson)
                .toList(growable: false)
            : const [],
      );

  Map<String, dynamic> toJson() => {
        'coins': coins,
        'gems': gems,
        'items': items.map((i) => i.toJson()).toList(),
      };

  @override
  List<Object?> get props => [coins, gems, items];
}

/// One mailbox message from `GET /mail` (D4).
class MailMessage extends Equatable {
  final String id;
  final String title;
  final String body;

  /// null → pure notification, nothing to claim.
  final RewardBundle? reward;
  final bool read;
  final bool claimed;
  final int? createdAtMs;
  final int? expiresAtMs;

  const MailMessage({
    required this.id,
    required this.title,
    this.body = '',
    this.reward,
    this.read = false,
    this.claimed = false,
    this.createdAtMs,
    this.expiresAtMs,
  });

  /// True when there is still an attachment to collect.
  bool get hasUnclaimedReward =>
      reward != null && !reward!.isEmpty && !claimed;

  factory MailMessage.fromJson(Map<dynamic, dynamic> json) {
    final rewardRaw = json['reward'];
    final reward =
        rewardRaw is Map ? RewardBundle.fromJson(rewardRaw) : null;
    return MailMessage(
      id: _asString(json['id']),
      title: _asString(json['title']),
      body: _asString(json['body']),
      reward: reward == null || reward.isEmpty ? null : reward,
      read: json['read'] == true,
      claimed: json['claimed'] == true,
      createdAtMs: json['createdAtMs'] is num ? _asInt(json['createdAtMs']) : null,
      expiresAtMs: json['expiresAtMs'] is num ? _asInt(json['expiresAtMs']) : null,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'body': body,
        'reward': reward?.toJson(),
        'read': read,
        'claimed': claimed,
        'createdAtMs': createdAtMs,
        'expiresAtMs': expiresAtMs,
      };

  MailMessage copyWith({bool? read, bool? claimed}) => MailMessage(
        id: id,
        title: title,
        body: body,
        reward: reward,
        read: read ?? this.read,
        claimed: claimed ?? this.claimed,
        createdAtMs: createdAtMs,
        expiresAtMs: expiresAtMs,
      );

  @override
  List<Object?> get props =>
      [id, title, body, reward, read, claimed, createdAtMs, expiresAtMs];
}

/// One claimable gift inside an event (D5).
class EventGift extends Equatable {
  final String id;
  final String title;
  final RewardBundle reward;

  const EventGift({required this.id, required this.title, required this.reward});

  factory EventGift.fromJson(Map<dynamic, dynamic> json) => EventGift(
        id: _asString(json['id']),
        title: _asString(json['title']),
        reward: json['reward'] is Map
            ? RewardBundle.fromJson(json['reward'] as Map)
            : const RewardBundle(),
      );

  Map<String, dynamic> toJson() =>
      {'id': id, 'title': title, 'reward': reward.toJson()};

  @override
  List<Object?> get props => [id, title, reward];
}

/// A live seasonal event from `GET /events` (D5).
class EconEvent extends Equatable {
  final String id;
  final String title;
  final String descVi;
  final int startAtMs;
  final int endAtMs;
  final List<EventGift> gifts;

  const EconEvent({
    required this.id,
    required this.title,
    this.descVi = '',
    this.startAtMs = 0,
    this.endAtMs = 0,
    this.gifts = const [],
  });

  factory EconEvent.fromJson(Map<dynamic, dynamic> json) => EconEvent(
        id: _asString(json['id']),
        title: _asString(json['title']),
        descVi: _asString(json['descVi']),
        startAtMs: _asInt(json['startAtMs']),
        endAtMs: _asInt(json['endAtMs']),
        gifts: json['gifts'] is List
            ? (json['gifts'] as List)
                .whereType<Map>()
                .map(EventGift.fromJson)
                .toList(growable: false)
            : const [],
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'descVi': descVi,
        'startAtMs': startAtMs,
        'endAtMs': endAtMs,
        'gifts': gifts.map((g) => g.toJson()).toList(),
      };

  @override
  List<Object?> get props => [id, title, descVi, startAtMs, endAtMs, gifts];
}

/// Welfare status from `GET /welfare` (D6): streak + derived claim flags +
/// the 7-day reward cycle to render.
class WelfareStatus extends Equatable {
  final int streak;
  final int totalCheckins;
  final String? lastCheckinDate;
  final bool todayClaimed;

  /// 0-based cycle slot today's (next) check-in pays out.
  final int todayIndex;
  final bool newbieClaimed;
  final bool comebackAvailable;
  final List<RewardBundle> cycle;

  const WelfareStatus({
    this.streak = 0,
    this.totalCheckins = 0,
    this.lastCheckinDate,
    this.todayClaimed = false,
    this.todayIndex = 0,
    this.newbieClaimed = false,
    this.comebackAvailable = false,
    this.cycle = const [],
  });

  factory WelfareStatus.fromJson(Map<dynamic, dynamic> json) => WelfareStatus(
        streak: _asInt(json['streak']),
        totalCheckins: _asInt(json['totalCheckins']),
        lastCheckinDate: json['lastCheckinDate'] as String?,
        todayClaimed: json['todayClaimed'] == true,
        todayIndex: _asInt(json['todayIndex']),
        newbieClaimed: json['newbieClaimed'] == true,
        comebackAvailable: json['comebackAvailable'] == true,
        cycle: json['cycle'] is List
            ? (json['cycle'] as List)
                .whereType<Map>()
                .map(RewardBundle.fromJson)
                .toList(growable: false)
            : const [],
      );

  Map<String, dynamic> toJson() => {
        'streak': streak,
        'totalCheckins': totalCheckins,
        'lastCheckinDate': lastCheckinDate,
        'todayClaimed': todayClaimed,
        'todayIndex': todayIndex,
        'newbieClaimed': newbieClaimed,
        'comebackAvailable': comebackAvailable,
        'cycle': cycle.map((c) => c.toJson()).toList(),
      };

  @override
  List<Object?> get props => [
        streak,
        totalCheckins,
        lastCheckinDate,
        todayClaimed,
        todayIndex,
        newbieClaimed,
        comebackAvailable,
        cycle,
      ];
}

/// One ingredient requirement of a craft recipe (D7).
class CraftIngredient extends Equatable {
  final String itemId;
  final int qty;

  const CraftIngredient({required this.itemId, required this.qty});

  factory CraftIngredient.fromJson(Map<dynamic, dynamic> json) =>
      CraftIngredient(
        itemId: _asString(json['itemId']),
        qty: _asInt(json['qty'], 1),
      );

  Map<String, dynamic> toJson() => {'itemId': itemId, 'qty': qty};

  @override
  List<Object?> get props => [itemId, qty];
}

/// One craftable recipe from `GET /crafting` (D7).
class CraftRecipe extends Equatable {
  final String id;
  final String nameVi;
  final String descVi;
  final List<CraftIngredient> ingredients;
  final int costCoins;
  final RewardItem output;

  const CraftRecipe({
    required this.id,
    required this.nameVi,
    this.descVi = '',
    this.ingredients = const [],
    this.costCoins = 0,
    required this.output,
  });

  factory CraftRecipe.fromJson(Map<dynamic, dynamic> json) => CraftRecipe(
        id: _asString(json['id']),
        nameVi: _asString(json['nameVi']),
        descVi: _asString(json['descVi']),
        ingredients: json['ingredients'] is List
            ? (json['ingredients'] as List)
                .whereType<Map>()
                .map(CraftIngredient.fromJson)
                .toList(growable: false)
            : const [],
        costCoins: _asInt(json['costCoins']),
        output: json['output'] is Map
            ? RewardItem.fromJson(json['output'] as Map)
            : const RewardItem(
                itemId: '', kind: ShopItemKind.boardTheme, payloadKey: ''),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'nameVi': nameVi,
        'descVi': descVi,
        'ingredients': ingredients.map((i) => i.toJson()).toList(),
        'costCoins': costCoins,
        'output': output.toJson(),
      };

  @override
  List<Object?> get props =>
      [id, nameVi, descVi, ingredients, costCoins, output];
}
