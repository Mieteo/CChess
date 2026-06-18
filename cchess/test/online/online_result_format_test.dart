import 'package:cchess/core/chess_engine/chess_engine.dart';
import 'package:cchess/presentation/online/online_match_controller.dart';
import 'package:cchess/presentation/online/online_result_format.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('B4/G4 — result dialog title', () {
    test('draw is "Hòa" regardless of my colour', () {
      expect(onlineResultTitle('draw', PieceColor.red), 'Hòa');
      expect(onlineResultTitle('draw', PieceColor.black), 'Hòa');
      expect(onlineResultTitle('draw', null), 'Hòa');
    });

    test('player sees Bạn thắng / Bạn thua from their own colour', () {
      expect(onlineResultTitle('red-win', PieceColor.red), 'Bạn thắng!');
      expect(onlineResultTitle('red-win', PieceColor.black), 'Bạn thua');
      expect(onlineResultTitle('black-win', PieceColor.black), 'Bạn thắng!');
      expect(onlineResultTitle('black-win', PieceColor.red), 'Bạn thua');
    });

    test('spectator (no colour) sees neutral side labels', () {
      expect(onlineResultTitle('red-win', null), 'Đỏ thắng');
      expect(onlineResultTitle('black-win', null), 'Đen thắng');
    });
  });

  group('B4/G4 — reason label (Vietnamese)', () {
    test('known reasons map to Vietnamese', () {
      expect(onlineReasonLabel('timeout'), 'Hết giờ');
      expect(onlineReasonLabel('resign'), 'Xin thua');
      expect(onlineReasonLabel('checkmate'), 'Chiếu bí');
      expect(onlineReasonLabel('disconnect'), 'Đối thủ mất kết nối');
      expect(onlineReasonLabel('stalemate'), 'Hết nước đi (thua)');
    });

    test('null reason renders an em dash, unknown codes pass through', () {
      expect(onlineReasonLabel(null), '—');
      expect(onlineReasonLabel('weird-code'), 'weird-code');
    });
  });

  group('B4/G4 — ELO delta sign + direction', () {
    Map<String, dynamic> elo({required int redDelta, required int blackDelta}) =>
        {
          'red': {'old': 1000, 'new': 1000 + redDelta, 'delta': redDelta},
          'black': {
            'old': 1000,
            'new': 1000 + blackDelta,
            'delta': blackDelta,
          },
        };

    test('a gain is up with a "+" sign', () {
      final d = OnlineEloDelta.fromUpdate(
        elo(redDelta: 16, blackDelta: -16),
        PieceColor.red,
      )!;
      expect(d.direction, EloDeltaDirection.up);
      expect(d.delta, 16);
      expect(d.newElo, 1016);
      expect(d.sign, '+');
    });

    test('a loss is down, the minus stays inside the delta', () {
      final d = OnlineEloDelta.fromUpdate(
        elo(redDelta: 16, blackDelta: -16),
        PieceColor.black,
      )!;
      expect(d.direction, EloDeltaDirection.down);
      expect(d.delta, -16);
      expect(d.sign, '');
    });

    test('a zero delta (draw between equals) is flat', () {
      final d = OnlineEloDelta.fromUpdate(
        elo(redDelta: 0, blackDelta: 0),
        PieceColor.red,
      )!;
      expect(d.direction, EloDeltaDirection.flat);
      expect(d.sign, '');
    });

    test('picks the side that matches my colour', () {
      final update = elo(redDelta: 8, blackDelta: -8);
      expect(
        OnlineEloDelta.fromUpdate(update, PieceColor.red)!.delta,
        8,
      );
      expect(
        OnlineEloDelta.fromUpdate(update, PieceColor.black)!.delta,
        -8,
      );
    });

    test('null when no ELO, no colour (spectator), or my side missing', () {
      expect(OnlineEloDelta.fromUpdate(null, PieceColor.red), isNull);
      expect(
        OnlineEloDelta.fromUpdate(elo(redDelta: 8, blackDelta: -8), null),
        isNull,
      );
      expect(
        OnlineEloDelta.fromUpdate({'red': null}, PieceColor.black),
        isNull,
      );
    });
  });

  group('B2/D — grace countdown formula', () {
    OnlineMatchState waiting({int? atMs, int? graceMs}) => OnlineMatchState(
      phase: OnlineMatchPhase.peerDisconnected,
      peerDisconnectedAtMs: atMs,
      peerDisconnectGraceMs: graceMs,
    );

    test('null when not waiting for a peer', () {
      const playing = OnlineMatchState(phase: OnlineMatchPhase.playing);
      expect(onlineRemainingGraceSec(playing, 1000), isNull);
    });

    test('rounds the remaining window up to whole seconds', () {
      final s = waiting(atMs: 0, graceMs: 60000);
      expect(onlineRemainingGraceSec(s, 0), 60);
      expect(onlineRemainingGraceSec(s, 1500), 59); // 58.5s → ceil 59
    });

    test('clamps to 0 once the deadline has passed', () {
      final s = waiting(atMs: 0, graceMs: 60000);
      expect(onlineRemainingGraceSec(s, 60000), 0);
      expect(onlineRemainingGraceSec(s, 70000), 0);
    });

    test('null when the timing fields are missing', () {
      expect(onlineRemainingGraceSec(waiting(graceMs: 60000), 0), isNull);
      expect(onlineRemainingGraceSec(waiting(atMs: 0), 0), isNull);
    });
  });

  group('B4/G5 — post-game profile refresh', () {
    test('refreshes cloud then profile when still mounted', () async {
      final calls = <String>[];
      await refreshProfileAfterRankedGame(
        refreshFromCloud: () async => calls.add('cloud'),
        refreshProfile: () async => calls.add('profile'),
        stillMounted: () => true,
      );
      expect(calls, ['cloud', 'profile']);
    });

    test('skips the profile refresh if the screen unmounted mid-flight',
        () async {
      final calls = <String>[];
      await refreshProfileAfterRankedGame(
        refreshFromCloud: () async => calls.add('cloud'),
        refreshProfile: () async => calls.add('profile'),
        stillMounted: () => false,
      );
      expect(calls, ['cloud']);
    });
  });
}
