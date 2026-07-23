import 'package:cchess/data/models/economy_models.dart';
import 'package:cchess/presentation/economy/economy_controller.dart';
import 'package:cchess/presentation/economy/events_screen.dart';
import 'package:cchess/presentation/economy/mail_screen.dart';
import 'package:cchess/presentation/economy/welfare_screen.dart';
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
}
