// Phase B widget tests for the "visual" online pieces extracted from
// OnlineGameScreen into online_game_widgets.dart: the chat button badge (C2),
// the reconnect banner (D), and the result dialog (G4). These pump the widgets
// in isolation (MaterialApp + Scaffold) — no go_router / connectivity_plus /
// Firebase — so the rendering wiring is asserted directly, complementing the
// pure-logic coverage in online_result_format_test.dart.

import 'package:cchess/core/chess_engine/chess_engine.dart';
import 'package:cchess/presentation/online/online_game_widgets.dart';
import 'package:cchess/presentation/online/online_match_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> pump(WidgetTester tester, Widget child) {
    return tester.pumpWidget(MaterialApp(home: Scaffold(body: child)));
  }

  group('C2 — OnlineChatButton', () {
    testWidgets('shows no count when there are no messages', (tester) async {
      await pump(
        tester,
        OnlineChatButton(messageCount: 0, canChat: true, onPressed: () {}),
      );
      expect(find.text('Chat'), findsOneWidget);
    });

    testWidgets('shows the (n) badge once messages arrive', (tester) async {
      await pump(
        tester,
        OnlineChatButton(messageCount: 3, canChat: true, onPressed: () {}),
      );
      expect(find.text('Chat (3)'), findsOneWidget);
    });

    testWidgets('is tappable when chat is allowed', (tester) async {
      var taps = 0;
      await pump(
        tester,
        OnlineChatButton(messageCount: 1, canChat: true, onPressed: () => taps++),
      );
      await tester.tap(find.byType(OutlinedButton));
      expect(taps, 1);
    });

    testWidgets('is disabled when chat is not allowed', (tester) async {
      var taps = 0;
      await pump(
        tester,
        OnlineChatButton(
          messageCount: 1,
          canChat: false,
          onPressed: () => taps++,
        ),
      );
      final button = tester.widget<OutlinedButton>(find.byType(OutlinedButton));
      expect(button.onPressed, isNull, reason: 'disabled when !canChat');
      await tester.tap(find.byType(OutlinedButton), warnIfMissed: false);
      expect(taps, 0);
    });
  });

  group('D — OnlineReconnectBanner', () {
    testWidgets('peerDisconnected with seconds shows the countdown', (
      tester,
    ) async {
      await pump(
        tester,
        const OnlineReconnectBanner(
          phase: OnlineMatchPhase.peerDisconnected,
          remainingGraceSec: 42,
        ),
      );
      expect(
        find.text('Đối thủ mất kết nối — còn 42s để reconnect'),
        findsOneWidget,
      );
      expect(find.byIcon(Icons.wifi_off), findsOneWidget);
    });

    testWidgets('peerDisconnected with null grace shows the waiting label', (
      tester,
    ) async {
      await pump(
        tester,
        const OnlineReconnectBanner(
          phase: OnlineMatchPhase.peerDisconnected,
          remainingGraceSec: null,
        ),
      );
      expect(find.text('Đối thủ mất kết nối — chờ reconnect…'), findsOneWidget);
    });

    testWidgets('peerDisconnected at 0 shows the confirming label', (
      tester,
    ) async {
      await pump(
        tester,
        const OnlineReconnectBanner(
          phase: OnlineMatchPhase.peerDisconnected,
          remainingGraceSec: 0,
        ),
      );
      expect(
        find.text('Hết thời gian chờ — đang xác nhận kết quả…'),
        findsOneWidget,
      );
    });

    testWidgets('reconnecting shows a spinner banner', (tester) async {
      await pump(
        tester,
        const OnlineReconnectBanner(
          phase: OnlineMatchPhase.reconnecting,
          remainingGraceSec: null,
        ),
      );
      expect(find.text('Mất kết nối — đang kết nối lại…'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('renders nothing during a normal playing phase', (tester) async {
      await pump(
        tester,
        const OnlineReconnectBanner(
          phase: OnlineMatchPhase.playing,
          remainingGraceSec: null,
        ),
      );
      expect(find.byIcon(Icons.wifi_off), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.textContaining('kết nối'), findsNothing);
    });
  });

  group('G4 — OnlineResultDialog', () {
    OnlineMatchState ended({
      String result = 'red-win',
      String? endReason = 'checkmate',
      PieceColor? myColor = PieceColor.red,
      Map<String, dynamic>? eloUpdate,
      bool meOffered = false,
      bool oppOffered = false,
      bool opponentLeft = false,
      String? errorMessage,
      String roomMode = 'ranked',
    }) {
      return OnlineMatchState(
        phase: OnlineMatchPhase.ended,
        result: result,
        endReason: endReason,
        myColor: myColor,
        eloUpdate: eloUpdate,
        rematchOfferedByMe: meOffered,
        rematchOfferedByOpponent: oppOffered,
        opponentLeftRoom: opponentLeft,
        errorMessage: errorMessage,
        roomMode: roomMode,
      );
    }

    Widget dialog(
      OnlineMatchState state, {
      VoidCallback? onLeave,
      VoidCallback? onOffer,
      VoidCallback? onDecline,
    }) {
      return OnlineResultDialog(
        state: state,
        onLeave: onLeave ?? () {},
        onOfferRematch: onOffer ?? () {},
        onDeclineRematch: onDecline ?? () {},
      );
    }

    // Shape mirrors the JSON-decoded game-ended.elo map.
    final eloRedGains = <String, dynamic>{
      'red': <String, dynamic>{'old': 1000, 'new': 1016, 'delta': 16},
      'black': <String, dynamic>{'old': 1000, 'new': 984, 'delta': -16},
    };
    final eloRedLoses = <String, dynamic>{
      'red': <String, dynamic>{'old': 1000, 'new': 984, 'delta': -16},
      'black': <String, dynamic>{'old': 1000, 'new': 1016, 'delta': 16},
    };

    testWidgets('win + ranked ELO shows title, reason, +delta, default actions', (
      tester,
    ) async {
      await pump(tester, dialog(ended(eloUpdate: eloRedGains)));
      expect(find.text('Bạn thắng!'), findsOneWidget);
      expect(find.text('Lý do: Chiếu bí'), findsOneWidget);
      expect(find.textContaining('ELO: +16'), findsOneWidget);
      expect(find.byIcon(Icons.trending_up), findsOneWidget);
      expect(find.text('Về Đối Đầu'), findsOneWidget);
      expect(find.text('Đấu lại'), findsOneWidget);
    });

    testWidgets('loss shows Bạn thua + a down arrow for the negative delta', (
      tester,
    ) async {
      await pump(
        tester,
        dialog(ended(result: 'black-win', eloUpdate: eloRedLoses)),
      );
      expect(find.text('Bạn thua'), findsOneWidget);
      expect(find.byIcon(Icons.trending_down), findsOneWidget);
    });

    testWidgets('draw shows Hòa', (tester) async {
      await pump(tester, dialog(ended(result: 'draw', endReason: 'stalemate')));
      expect(find.text('Hòa'), findsOneWidget);
    });

    testWidgets('no ELO row when the server sent no elo', (tester) async {
      await pump(tester, dialog(ended()));
      expect(find.textContaining('ELO:'), findsNothing);
    });

    testWidgets('A2 — casual game shows the "không tính ELO" note, no ELO', (
      tester,
    ) async {
      // A casual room ends with elo:null; the dialog must say WHY there is no
      // ELO rather than silently dropping the row.
      await pump(tester, dialog(ended(roomMode: 'casual')));
      expect(find.text('Cờ giao hữu — không tính ELO.'), findsOneWidget);
      expect(find.textContaining('ELO:'), findsNothing);
    });

    testWidgets('A2 — casual hides ELO even if a stray delta is present', (
      tester,
    ) async {
      // Defensive: even if the server somehow sent an elo map for a casual
      // room, the casual note wins and no ELO delta is rendered.
      await pump(
        tester,
        dialog(ended(roomMode: 'casual', eloUpdate: eloRedGains)),
      );
      expect(find.text('Cờ giao hữu — không tính ELO.'), findsOneWidget);
      expect(find.textContaining('ELO:'), findsNothing);
    });

    testWidgets('tapping Đấu lại offers a rematch', (tester) async {
      var offers = 0;
      await pump(tester, dialog(ended(), onOffer: () => offers++));
      await tester.tap(find.text('Đấu lại'));
      expect(offers, 1);
    });

    testWidgets('tapping Về Đối Đầu leaves', (tester) async {
      var leaves = 0;
      await pump(tester, dialog(ended(), onLeave: () => leaves++));
      await tester.tap(find.text('Về Đối Đầu'));
      expect(leaves, 1);
    });

    testWidgets('after I offered: waiting tile + Hủy/Về Đối Đầu, no Đấu lại', (
      tester,
    ) async {
      var declines = 0;
      await pump(
        tester,
        dialog(ended(meOffered: true), onDecline: () => declines++),
      );
      expect(find.text('Đang chờ đối thủ đồng ý đấu lại…'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('Đấu lại'), findsNothing);
      await tester.tap(find.text('Hủy'));
      expect(declines, 1);
    });

    testWidgets('opponent offered: prompt + Từ chối/Đồng ý wired up', (
      tester,
    ) async {
      var offers = 0;
      var declines = 0;
      await pump(
        tester,
        dialog(
          ended(oppOffered: true),
          onOffer: () => offers++,
          onDecline: () => declines++,
        ),
      );
      expect(find.text('Đối thủ muốn đấu lại!'), findsOneWidget);
      await tester.tap(find.text('Đồng ý'));
      expect(offers, 1);
      await tester.tap(find.text('Từ chối'));
      expect(declines, 1);
    });

    testWidgets('opponent gone (disconnect) → no rematch, only Về Đối Đầu', (
      tester,
    ) async {
      await pump(tester, dialog(ended(endReason: 'disconnect')));
      expect(find.text('Đối thủ đã rời — không thể đấu lại.'), findsOneWidget);
      expect(find.text('Đấu lại'), findsNothing);
      expect(find.text('Về Đối Đầu'), findsOneWidget);
    });

    testWidgets('spectator sees a neutral title + a single Thoát button', (
      tester,
    ) async {
      var leaves = 0;
      await pump(tester, dialog(ended(myColor: null), onLeave: () => leaves++));
      expect(find.text('Đỏ thắng'), findsOneWidget); // neutral, not "Bạn..."
      expect(
        find.text('Nếu hai kỳ thủ đấu lại, ván mới sẽ tự mở.'),
        findsOneWidget,
      );
      expect(find.text('Thoát'), findsOneWidget);
      expect(find.text('Đấu lại'), findsNothing);
      await tester.tap(find.text('Thoát'));
      expect(leaves, 1);
    });

    testWidgets('spectator with a player gone shows the closed-match note', (
      tester,
    ) async {
      await pump(tester, dialog(ended(myColor: null, opponentLeft: true)));
      expect(
        find.text('Một kỳ thủ đã rời — trận đấu khép lại.'),
        findsOneWidget,
      );
    });

    testWidgets('an error message is surfaced inside the dialog', (
      tester,
    ) async {
      await pump(
        tester,
        dialog(ended(errorMessage: 'Không thể đấu lại — đối thủ đã rời phòng')),
      );
      expect(
        find.text('Không thể đấu lại — đối thủ đã rời phòng'),
        findsOneWidget,
      );
    });
  });
}
