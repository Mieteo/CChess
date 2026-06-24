import 'package:equatable/equatable.dart';

import 'shop_item.dart';

/// One owned item from `GET /inventory` (under users/{uid}/inventory/{itemId}).
class InventoryItem extends Equatable {
  final String itemId;
  final ShopItemKind kind;
  final String payloadKey;

  /// Units owned (cosmetics: 1; consumables: running total).
  final int qty;

  const InventoryItem({
    required this.itemId,
    required this.kind,
    required this.payloadKey,
    required this.qty,
  });

  factory InventoryItem.fromJson(Map<dynamic, dynamic> json) {
    return InventoryItem(
      itemId: (json['itemId'] as String?) ?? '',
      kind: ShopItemKind.fromName(json['kind'] as String?),
      payloadKey: (json['payloadKey'] as String?) ?? '',
      qty: _asInt(json['qty'], 1),
    );
  }

  Map<String, dynamic> toJson() => {
        'itemId': itemId,
        'kind': kind.name,
        'payloadKey': payloadKey,
        'qty': qty,
      };

  @override
  List<Object?> get props => [itemId, kind, payloadKey, qty];
}

int _asInt(Object? value, [int fallback = 0]) {
  if (value is int) return value;
  if (value is num) return value.round();
  return fallback;
}
