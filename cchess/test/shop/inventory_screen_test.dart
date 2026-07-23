import 'package:cchess/data/models/inventory_item.dart';
import 'package:cchess/data/models/shop_item.dart';
import 'package:cchess/data/models/wallet.dart';
import 'package:cchess/presentation/shop/inventory_screen.dart';
import 'package:cchess/presentation/shop/shop_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Rendering tests for Balo Vật Phẩm — especially pretty-name resolution
/// against the shop catalog (QA 23/7 polish: raw ids like "hint_pack_5"
/// leaked into the item rows).

ShopItem _catalogItem(
  String id,
  String nameVi, {
  ShopItemKind kind = ShopItemKind.consumable,
  String payloadKey = 'p',
}) =>
    ShopItem(
      id: id,
      kind: kind,
      nameVi: nameVi,
      descVi: '',
      priceCoins: 10,
      priceGems: 0,
      rarity: Rarity.common,
      payloadKey: payloadKey,
      consumable: kind == ShopItemKind.consumable,
      consumableQty: 1,
      sortOrder: 0,
    );

Widget _balo({
  required List<InventoryItem> inventory,
  List<ShopItem> catalog = const [],
  Wallet wallet = const Wallet(),
  Object? catalogError,
}) =>
    ProviderScope(
      overrides: [
        inventoryProvider.overrideWith((ref) async => inventory),
        walletProvider.overrideWith((ref) async => wallet),
        shopCatalogProvider.overrideWith(
          (ref) async =>
              catalogError != null ? throw catalogError : catalog,
        ),
      ],
      child: const MaterialApp(home: InventoryScreen()),
    );

void main() {
  testWidgets('consumable shows its pretty catalog name, not the raw id',
      (tester) async {
    await tester.pumpWidget(_balo(
      inventory: const [
        InventoryItem(
          itemId: 'hint_pack_5',
          kind: ShopItemKind.consumable,
          payloadKey: 'hint_pack',
          qty: 7,
        ),
      ],
      catalog: [_catalogItem('hint_pack_5', 'Gói 5 Gợi Ý')],
    ));
    await tester.pumpAndSettle();

    expect(find.text('Gói 5 Gợi Ý'), findsOneWidget);
    expect(find.text('Số lượng: 7'), findsOneWidget);
    expect(find.textContaining('hint_pack'), findsNothing);
  });

  testWidgets(
      'crafted board theme outside the catalog falls back to Bàn <tên>',
      (tester) async {
    await tester.pumpWidget(_balo(
      inventory: const [
        InventoryItem(
          itemId: 'jade-board',
          kind: ShopItemKind.boardTheme,
          payloadKey: 'jade',
          qty: 1,
        ),
      ],
      wallet: const Wallet(equipped: {'boardTheme': 'jade-board'}),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Bàn Ngọc Bích'), findsOneWidget);
    expect(find.text('Đang dùng'), findsOneWidget);
  });

  testWidgets('unknown consumable falls back to slot label • payloadKey',
      (tester) async {
    await tester.pumpWidget(_balo(
      inventory: const [
        InventoryItem(
          itemId: 'mystery-juice',
          kind: ShopItemKind.consumable,
          payloadKey: 'mystery',
          qty: 2,
        ),
      ],
    ));
    await tester.pumpAndSettle();

    expect(find.text('Công cụ • mystery'), findsOneWidget);
  });

  testWidgets('catalog fetch failure still renders rows with fallback names',
      (tester) async {
    await tester.pumpWidget(_balo(
      inventory: const [
        InventoryItem(
          itemId: 'jade-board',
          kind: ShopItemKind.boardTheme,
          payloadKey: 'jade',
          qty: 1,
        ),
      ],
      catalogError: Exception('offline'),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Bàn Ngọc Bích'), findsOneWidget);
    expect(find.text('Chưa trang bị'), findsOneWidget);
  });
}
