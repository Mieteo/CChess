import 'package:cchess/data/models/economy_models.dart';
import 'package:cchess/data/models/inventory_item.dart';
import 'package:cchess/data/models/shop_item.dart';
import 'package:cchess/data/models/wallet.dart';
import 'package:cchess/presentation/economy/crafting_screen.dart';
import 'package:cchess/presentation/economy/economy_controller.dart';
import 'package:cchess/presentation/economy/events_screen.dart';
import 'package:cchess/presentation/economy/mail_screen.dart';
import 'package:cchess/presentation/economy/welfare_screen.dart';
import 'package:cchess/presentation/shop/shop_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Rendering-state tests for the S16 economy screens: provider overrides feed
/// fixed data, assertions check what the player sees. Claim flows (server +
/// cache) are covered by economy_repository_test.dart.

Widget _wrap(List<Override> overrides, Widget child) => ProviderScope(
      overrides: overrides,
      child: MaterialApp(home: child),
    );

const _cycle = [
  RewardBundle(coins: 20),
  RewardBundle(coins: 30),
  RewardBundle(coins: 40),
  RewardBundle(coins: 50),
  RewardBundle(coins: 60),
  RewardBundle(coins: 80),
  RewardBundle(coins: 100, gems: 5),
];

void main() {
  group('WelfareScreen', () {
    testWidgets('renders streak, highlights today, enables check-in',
        (tester) async {
      const status = WelfareStatus(
        streak: 2,
        totalCheckins: 2,
        lastCheckinDate: '2026-07-22',
        todayClaimed: false,
        todayIndex: 2,
        newbieClaimed: true,
        comebackAvailable: false,
        cycle: _cycle,
      );
      await tester.pumpWidget(_wrap(
        [welfareProvider.overrideWith((ref) async => status)],
        const WelfareScreen(),
      ));
      await tester.pumpAndSettle();

      expect(find.text('chuỗi 2 ngày'), findsOneWidget);
      expect(find.text('Điểm danh hôm nay'), findsOneWidget);
      // Days 1-2 collected (< todayIndex), shown as check icons.
      expect(find.byIcon(Icons.check_circle), findsNWidgets(2));
      // Newbie gift already claimed → card hidden.
      expect(find.text('Quà Tân Thủ'), findsNothing);
      expect(find.text('Quà Quay Lại'), findsNothing);
      // Check-in button is tappable.
      final button = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Điểm danh hôm nay'),
      );
      expect(button.onPressed, isNotNull);
    });

    testWidgets('after today’s check-in the button disables', (tester) async {
      const status = WelfareStatus(
        streak: 3,
        totalCheckins: 3,
        lastCheckinDate: '2026-07-23',
        todayClaimed: true,
        todayIndex: 2,
        newbieClaimed: true,
        cycle: _cycle,
      );
      await tester.pumpWidget(_wrap(
        [welfareProvider.overrideWith((ref) async => status)],
        const WelfareScreen(),
      ));
      await tester.pumpAndSettle();

      final button = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Hôm nay đã điểm danh'),
      );
      expect(button.onPressed, isNull);
      // Days 1-3 collected (<= todayIndex when claimed).
      expect(find.byIcon(Icons.check_circle), findsNWidgets(3));
    });

    testWidgets('newbie + comeback cards appear when available',
        (tester) async {
      const status = WelfareStatus(
        streak: 0,
        newbieClaimed: false,
        comebackAvailable: true,
        cycle: _cycle,
      );
      await tester.pumpWidget(_wrap(
        [welfareProvider.overrideWith((ref) async => status)],
        const WelfareScreen(),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Quà Tân Thủ'), findsOneWidget);
      expect(find.text('Quà Quay Lại'), findsOneWidget);
    });
  });

  group('MailScreen', () {
    testWidgets('unclaimed gift shows claim button; claimed shows Đã nhận',
        (tester) async {
      final messages = [
        const MailMessage(
          id: 'm1',
          title: 'Quà sự kiện',
          body: 'Cảm ơn bạn đã tham gia!',
          reward: RewardBundle(coins: 50),
        ),
        const MailMessage(
          id: 'm2',
          title: 'Quà đã nhận',
          reward: RewardBundle(coins: 10),
          read: true,
          claimed: true,
        ),
        const MailMessage(id: 'm3', title: 'Bảo trì máy chủ', read: true),
      ];
      await tester.pumpWidget(_wrap(
        [mailProvider.overrideWith((ref) async => messages)],
        const MailScreen(),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Nhận quà'), findsOneWidget);
      expect(find.text('Đã nhận'), findsOneWidget);
      // Notification mail renders without any reward row.
      expect(find.text('Bảo trì máy chủ'), findsOneWidget);
    });

    testWidgets('empty mailbox shows the empty state', (tester) async {
      await tester.pumpWidget(_wrap(
        [mailProvider.overrideWith((ref) async => <MailMessage>[])],
        const MailScreen(),
      ));
      await tester.pumpAndSettle();
      expect(find.text('Hộp thư trống'), findsOneWidget);
    });
  });

  group('EventsScreen', () {
    testWidgets('claimed gift shows a check, unclaimed offers Nhận',
        (tester) async {
      final events = [
        EconEvent(
          id: 'tet',
          title: 'Tết 2026',
          descVi: 'Mừng xuân',
          startAtMs: DateTime.now().millisecondsSinceEpoch - 1000,
          endAtMs: DateTime.now().millisecondsSinceEpoch + 86_400_000,
          gifts: const [
            EventGift(id: 'lixi', title: 'Lì xì', reward: RewardBundle(coins: 88)),
            EventGift(id: 'phao', title: 'Pháo hoa', reward: RewardBundle(gems: 2)),
          ],
        ),
      ];
      await tester.pumpWidget(_wrap(
        [
          eventsProvider.overrideWith((ref) async => events),
          eventClaimsProvider.overrideWith((ref) async => {'tet__lixi'}),
        ],
        const EventsScreen(),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Tết 2026'), findsOneWidget);
      expect(find.byIcon(Icons.check_circle), findsOneWidget); // lixi claimed
      expect(find.text('Nhận'), findsOneWidget); // phao still claimable
    });
  });

  group('CraftingScreen', () {
    const recipe = CraftRecipe(
      id: 'jade',
      nameVi: 'Bàn Ngọc Bích',
      ingredients: [CraftIngredient(itemId: 'shard', qty: 3)],
      costCoins: 100,
      output: RewardItem(
        itemId: 'jade-board',
        kind: ShopItemKind.boardTheme,
        payloadKey: 'jade',
      ),
    );

    InventoryItem shard(int qty) => InventoryItem(
          itemId: 'shard',
          kind: ShopItemKind.consumable,
          payloadKey: 'shard',
          qty: qty,
        );

    Widget crafting({
      required int coins,
      List<InventoryItem> owned = const [],
      List<CraftRecipe> recipes = const [recipe],
    }) =>
        _wrap(
          [
            craftRecipesProvider.overrideWith((ref) async => recipes),
            walletProvider.overrideWith((ref) async => Wallet(coins: coins)),
            inventoryProvider.overrideWith((ref) async => owned),
          ],
          const CraftingScreen(),
        );

    FilledButton buttonWithText(WidgetTester tester, String label) =>
        tester.widget<FilledButton>(find.widgetWithText(FilledButton, label));

    testWidgets('enabled when ingredients + coins suffice', (tester) async {
      await tester.pumpWidget(crafting(coins: 150, owned: [shard(4)]));
      await tester.pumpAndSettle();

      expect(find.text('Bàn Ngọc Bích'), findsOneWidget);
      expect(find.text('shard 4/3'), findsOneWidget);
      expect(find.text('100 đồng'), findsOneWidget);
      expect(buttonWithText(tester, 'Đúc ngay').onPressed, isNotNull);
    });

    testWidgets('missing ingredients disables the button with the reason',
        (tester) async {
      await tester.pumpWidget(crafting(coins: 150, owned: [shard(1)]));
      await tester.pumpAndSettle();

      expect(find.text('shard 1/3'), findsOneWidget);
      expect(buttonWithText(tester, 'Chưa đủ nguyên liệu').onPressed, isNull);
    });

    testWidgets('not enough coins disables the button', (tester) async {
      await tester.pumpWidget(crafting(coins: 10, owned: [shard(3)]));
      await tester.pumpAndSettle();

      expect(buttonWithText(tester, 'Chưa đủ đồng').onPressed, isNull);
    });

    testWidgets('already-owned output shows Đã sở hữu + check', (tester) async {
      await tester.pumpWidget(crafting(
        coins: 500,
        owned: [
          shard(9),
          const InventoryItem(
            itemId: 'jade-board',
            kind: ShopItemKind.boardTheme,
            payloadKey: 'jade',
            qty: 1,
          ),
        ],
      ));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.check_circle), findsOneWidget);
      expect(buttonWithText(tester, 'Đã sở hữu').onPressed, isNull);
    });

    testWidgets('empty catalog shows the empty state', (tester) async {
      await tester.pumpWidget(crafting(coins: 0, recipes: const []));
      await tester.pumpAndSettle();

      expect(find.text('Chưa có công thức'), findsOneWidget);
    });
  });

  group('unreadMailCountProvider', () {
    test('counts unread + unclaimed messages for the Explore badge', () async {
      final container = ProviderContainer(overrides: [
        mailProvider.overrideWith((ref) async => const [
              MailMessage(id: 'a', title: 'Chưa đọc'), // unread
              MailMessage(
                id: 'b',
                title: 'Đọc rồi nhưng còn quà',
                read: true,
                reward: RewardBundle(coins: 5), // unclaimed reward
              ),
              MailMessage(
                id: 'c',
                title: 'Xong',
                read: true,
                reward: RewardBundle(coins: 5),
                claimed: true,
              ),
            ]),
      ]);
      addTearDown(container.dispose);

      // Loading → badge hidden (0), then counts once the mail resolves.
      expect(container.read(unreadMailCountProvider), 0);
      await container.read(mailProvider.future);
      expect(container.read(unreadMailCountProvider), 2);
    });
  });
}
